/*
 * Kanon IME: ImeCoordinator (M3)
 * SPEC KANON_SPEC.md §4/§5/§6: 単一dispatch応答モデル。
 * - KeyboardViewは触らない。UI状態の読み出しはgetSnapshot()のみ（文字列内容を持たない）。
 * - EditorPort / EnginePort へは本ファイルだけが触る。M4で実EditorAdapter・実Engineへ接続する。
 * - REQ-07: 効果テキストはメモリ内でのみ受け渡し、ログ・snapshot・履歴に出さない。
 */

export interface OpResult {
  ok: boolean;
  code: number;
}

/** Coordinatorが必要とする編集側の最小面。実EditorAdapterはM4で包む。 */
export interface EditorPort {
  getEpoch(): number;
  setPreview(text: string, start: number, end: number): Promise<OpResult>;
  finishPreview(): Promise<OpResult>;
  insert(text: string): Promise<OpResult>;
  deleteForward(length: number): Promise<OpResult>;
  moveCursor(direction: number): Promise<OpResult>;
  selectRange(start: number, end: number): Promise<OpResult>;
  queryPreviewSupported(): Promise<boolean>;
  /** カーソル位置（UTF-16）。失敗時は-1。 */
  queryCursor(): Promise<number>;
  /**
   * カーソル直前の最大length単位を返す。サロゲートペア判定専用。
   * 内容の保持・記録はしないこと（REQ-07）。失敗時は''。
   */
  queryBefore(length: number): Promise<string>;
}

/** UIイベント。1イベント→1 EngineUpdateが契約。 */
export interface UiEvent {
  kind: string; // 'text' | 'paste' | 'backspace' | 'convert' | 'submit' | 'cancel' | 'move' | 'select' | 'reset' | 'mode'
  text?: string;
  candidateId?: number;
  expectedRevision?: number;
  direction?: number;
  /** 'begin' | 'end'。カーソル行頭・行末移動（selectRangeで表現）。 */
  edge?: string;
  /** 英語補完取り消し用。照合したカーソル位置と入力済み接頭辞の長さ。 */
  cursor?: number;
  prefixLength?: number;
}

export interface CommitEffect {
  effectId: string;
  text: string; // メモリ内のみ。ログ・snapshotに出さない。
}

/** 候補1件。labelは表示用メモリ保持（ログ・snapshotに出さない）。 */
export interface CandidateLabel {
  id: number;
  label: string;
}

export interface EngineUpdate {
  sessionId: string;
  editorEpoch: number;
  sequence: number;
  revision: number;
  consumed: boolean;
  hasPreedit: boolean;
  preeditLen: number;
  caretUtf16: number;
  segCount: number;
  candidateCount: number;
  candidateRevision: number;
  candidates: CandidateLabel[];
  effects: CommitEffect[];
  errorCode: number; // 0=なし。非0はエンジン側失敗。
  errorRecoverable: boolean;
}

export interface EnginePort {
  dispatch(sessionId: string, editorEpoch: number, sequence: number, event: UiEvent): Promise<EngineUpdate>;
}

/** 文字列内容を持たないUIスナップショット。 */
export interface ImeSnapshot {
  mode: string; // 'EN' | 'JP'
  state: string; // 'DIRECT_EN' | 'JP_EMPTY' | 'JP_COMPOSING' | 'JP_CONVERTING' | 'ENGINE_ERROR'
  preeditLen: number;
  caretUtf16: number;
  segCount: number;
  candidateCount: number;
  revision: number;
  sequence: number;
  needsRecovery: boolean;
  lastError: string; // 'ok' または符号のみ
  droppedStale: number;
  droppedLate: number;
  dupSuppressed: number;
  /** 直近applyCommitの確定文字数。部分確定後の再アンカー用（内容は持たない）。 */
  commitLength: number;
}

let sessionCounter: number = 0;

function newSessionId(): string {
  sessionCounter++;
  return `s${sessionCounter}`;
}

export class ImeCoordinator {
  private editor: EditorPort;
  private engine: EnginePort | undefined = undefined;
  private tail: Promise<void> = Promise.resolve();

  private mode: string = 'JP';
  private state: string = 'JP_EMPTY';
  private sessionId: string = newSessionId();
  private sequence: number = 0;
  private revision: number = 0;
  private lastAppliedSequence: number = 0;
  private appliedEffects: string[] = [];
  private previewShown: boolean = false;
  private previewSupported: boolean = false;
  private previewStart: number = -1;
  private previewEnd: number = -1;
  private needsRecovery: boolean = false;
  private lastError: string = 'ok';
  private preeditLen: number = 0;
  private caretUtf16: number = 0;
  private segCount: number = 0;
  private candidateCount: number = 0;
  private candidateRevision: number = 0;
  private candidateItems: CandidateLabel[] = [];
  private droppedStale: number = 0;
  private droppedLate: number = 0;
  private dupSuppressed: number = 0;
  private lastCommitLength: number = 0;

  constructor(editor: EditorPort) {
    this.editor = editor;
  }

  setEngine(engine: EnginePort): void {
    this.engine = engine;
  }

  getSnapshot(): ImeSnapshot {
    return {
      mode: this.mode,
      state: this.state,
      preeditLen: this.preeditLen,
      caretUtf16: this.caretUtf16,
      segCount: this.segCount,
      candidateCount: this.candidateCount,
      revision: this.revision,
      sequence: this.sequence,
      needsRecovery: this.needsRecovery,
      lastError: this.lastError,
      droppedStale: this.droppedStale,
      droppedLate: this.droppedLate,
      dupSuppressed: this.dupSuppressed,
      commitLength: this.lastCommitLength
    };
  }

  /** 候補バー表示用。メモリ内のみ。ログに出さないこと。 */
  getCandidateView(): CandidateLabel[] {
    return this.candidateItems;
  }

  getCandidateRevision(): number {
    return this.candidateRevision;
  }

  /** preview書込が非対応と判明した通知。以降はinsert確定のみにする。 */
  setPreviewUnsupported(): void {
    this.previewSupported = false;
    this.previewShown = false;
    this.previewStart = -1;
    this.previewEnd = -1;
  }
  snapLine(): string {
    const s: ImeSnapshot = this.getSnapshot();
    return `${s.mode}/${s.state} rev=${s.revision} seq=${s.sequence} pre=${s.preeditLen} cand=${s.candidateCount} rec=${s.needsRecovery ? 1 : 0} err=${s.lastError}`;
  }

  /** イベント受付。FIFO直列化し、UIスレッドを塞がない（REQ-05/09）。世代は受付時点で確定する。 */
  postEvent(event: UiEvent): Promise<void> {
    const epoch: number = this.editor.getEpoch();
    const run: Promise<void> = this.tail.then(async (): Promise<void> => {
      await this.handleSerial(epoch, event);
    });
    this.tail = run.then((): void => undefined).catch((): void => undefined);
    return run;
  }

  /** 入力先が変わった通知。旧世代の保留は破棄し、新世代で作り直す（REQ-02/10）。 */
  onEditorChanged(): void {
    this.sessionId = newSessionId();
    this.sequence = 0;
    this.revision = 0;
    this.lastAppliedSequence = 0;
    this.appliedEffects = [];
    this.previewShown = false;
    this.previewStart = -1;
    this.previewEnd = -1;
    this.preeditLen = 0;
    this.caretUtf16 = 0;
    this.segCount = 0;
    this.candidateCount = 0;
    this.candidateRevision = 0;
    this.candidateItems = [];
    this.needsRecovery = false;
    this.lastError = 'ok';
    if (this.mode === 'JP') {
      this.state = 'JP_EMPTY';
    } else {
      this.state = 'DIRECT_EN';
    }
  }

  private effectKey(epoch: number, effectId: string): string {
    return `${epoch}:${effectId}`;
  }

  private async handleSerial(epoch: number, event: UiEvent): Promise<void> {
    if (epoch !== this.editor.getEpoch()) { this.lastError = 'stale-epoch'; return; }
    if (event.kind === 'reset') {
      await this.doReset(epoch);
      return;
    }
    if (this.needsRecovery) {
      // 整合性未確認のまま後続を流さない（REQ-06）。reset/cancelのみ受付。
      if (event.kind === 'cancel') {
        await this.doReset(epoch);
        return;
      }
      this.lastError = 'recovery-hold';
      return;
    }
    if (this.state === 'ENGINE_ERROR') {
      if (event.kind === 'mode') {
        this.mode = 'EN';
        this.state = 'DIRECT_EN';
        this.lastError = 'ok';
        return;
      }
      this.lastError = 'engine-error-hold';
      return;
    }
    if (event.kind === 'mode') {
      await this.doModeSwitch(epoch, event);
      return;
    }
    if (event.kind === 'move') {
      await this.doMove(epoch, event);
      return;
    }
    if (event.kind === 'undoCompletion') {
      await this.undoEnglishCompletion(epoch, event);
      return;
    }
    if (event.kind === 'paste') {
      if (this.mode === 'JP' && this.state !== 'JP_EMPTY') {
        this.lastError = 'paste-needs-submit';
        return;
      }
      const value: string = event.text ?? '';
      if (value.length === 0) { this.lastError = 'paste-empty'; return; }
      const result: OpResult = await this.editor.insert(value);
      this.lastError = result.ok ? 'ok' : `edit-${result.code}`;
      if (!result.ok) { this.needsRecovery = true; }
      return;
    }
    if (this.mode === 'EN') {
      await this.doDirectEn(epoch, event);
      return;
    }
    await this.doEngineEvent(epoch, event);
  }

  /** 補完された末尾だけを取り消す。入力先と単語を照合してから編集する。 */
  private async undoEnglishCompletion(epoch: number, event: UiEvent): Promise<void> {
    const word: string = event.text ?? '';
    const cursor: number = event.cursor ?? -1;
    const prefixLength: number = event.prefixLength ?? 0;
    if (this.mode !== 'EN' || cursor < word.length || cursor > 4096 ||
      word.length > 40 || prefixLength <= 0 || prefixLength >= word.length) {
      this.lastError = 'undo-stale';
      return;
    }
    const actual: number = await this.editor.queryCursor();
    const before: string = await this.editor.queryBefore(cursor);
    if (epoch !== this.editor.getEpoch() || actual !== cursor || before.length !== cursor || !before.endsWith(word)) {
      this.lastError = 'undo-stale';
      return;
    }
    // 追加されたASCII文字だけを1文字ずつ削除する。各削除の反映を見てから次へ進む。
    for (let remaining: number = word.length; remaining > prefixLength; remaining--) {
      if (epoch !== this.editor.getEpoch()) { this.lastError = 'stale-epoch'; return; }
      const result: OpResult = await this.editor.deleteForward(1);
      if (!result.ok) { this.lastError = `edit-${result.code}`; this.needsRecovery = true; return; }
      const expected: number = cursor - (word.length - remaining) - 1;
      let applied: boolean = false;
      for (let attempt: number = 0; attempt < 7; attempt++) {
        const index: number = await this.editor.queryCursor();
        const text: string = await this.editor.queryBefore(expected);
        if (epoch !== this.editor.getEpoch()) { this.lastError = 'stale-epoch'; return; }
        if (index === expected && text.length === expected && text.endsWith(word.substring(0, remaining - 1))) {
          applied = true;
          break;
        }
        await this.sleepMs(50);
      }
      if (!applied) { this.lastError = 'undo-edit-unconfirmed'; this.needsRecovery = true; return; }
    }
    this.lastError = 'ok';
  }

  /** EN直書き。エンジンを通さないがFIFO順序は守る（REQ-05）。 */
  private async doDirectEn(epoch: number, event: UiEvent): Promise<void> {
    this.state = 'DIRECT_EN';
    if (event.kind === 'cancel') { this.lastError = 'ok'; return; }
    if (event.kind === 'text') {
      const t: string = event.text ? event.text as string : '';
      if (t.length === 0) {
        return;
      }
      const r: OpResult = await this.editor.insert(t);
      this.lastError = r.ok ? 'ok' : `edit-${r.code}`;
      if (!r.ok) {
        this.needsRecovery = true;
      }
      return;
    }
    if (event.kind === 'backspace') {
      // deleteForwardは複数単位を一度に消せない実機挙動のため1単位ずつ。
      // 連続削除は適用確認しながら進める（直列・二重標的の取りこぼし防止）。
      if (!(await this.directDelete(await this.backspaceUnits()))) {
        this.lastError = 'edit-fail';
        this.needsRecovery = true;
      } else {
        this.lastError = 'ok';
      }
      return;
    }
    this.lastError = 'en-ignore';
  }

  /** Backspaceの削除単位。直前がサロゲートペアなら2、通常1（AT-11）。 */
  private async backspaceUnits(): Promise<number> {
    try {
      // getForward(n)は先頭側n単位を返す実機挙動のため、100単位取りの
      // 末尾2で判定する。100で打ち切られる長文は判定不能で1とする。
      const t: string = await this.editor.queryBefore(100);
      if (t.length >= 100) {
        return 1;
      }
      // 末尾2がペアでもカーソルが末尾になければ対象がずれる。
      // カーソル照会が末尾一致のときのみ2単位にする。
      try {
        const cur: number = await this.editor.queryCursor();
        if (cur >= 0 && cur === t.length && t.length >= 2) {
          const hi: number = t.charCodeAt(t.length - 2);
          const lo: number = t.charCodeAt(t.length - 1);
          if (hi >= 0xD800 && hi <= 0xDBFF && lo >= 0xDC00 && lo <= 0xDFFF) {
            return 2;
          }
        }
        return 1;
      } catch (e) {
        return 1;
      }
    } catch (e) {
    }
    return 1;
  }

  private sleepMs(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout((): void => {
        resolve();
      }, ms);
    });
  }

  private async beforeLength(): Promise<number> {
    try {
      const b: string = await this.editor.queryBefore(100);
      return b.length;
    } catch (e) {
      return -1;
    }
  }

  /**
   * 直接削除n単位。空欄は何もせず成功。1単位ずつ消し、
   * 縮小確認後に次へ進む（適用遅延による二重標的を防ぐ）。
   */
  private async directDelete(n: number): Promise<boolean> {
    for (let i: number = 0; i < n; i++) {
      const before: number = await this.beforeLength();
      if (before === 0) {
        return true;
      }
      const r: OpResult = await this.editor.deleteForward(1);
      if (!r.ok) {
        return false;
      }
      if (before < 0) {
        continue;
      }
      let shrunk: boolean = false;
      for (let t: number = 0; t < 7; t++) {
        const now: number = await this.beforeLength();
        if (now >= 0 && now < before) {
          shrunk = true;
          break;
        }
        await this.sleepMs(50);
      }
      if (!shrunk) {
        return false;
      }
    }
    return true;
  }

  private async doEngineEvent(epoch: number, event: UiEvent): Promise<void> {
    // 未確定なしのBackspaceは確定済み本文への直接削除（G-01: Backspace=deleteForward）。
    // 直前がサロゲートペアなら2単位で消す（AT-11: 壊れた半分を残さない）。
    // 複数単位の一括削除は効かないため1単位ずつ直列に消す。
    // 連続削除は適用確認しながら進める（直列・二重標的の取りこぼし防止）。
    if (event.kind === 'backspace' && this.state === 'JP_EMPTY') {
      if (!(await this.directDelete(await this.backspaceUnits()))) {
        this.lastError = 'edit-fail';
        this.needsRecovery = true;
      } else {
        this.lastError = 'ok';
      }
      return;
    }
    // 未確定なしのEnterは欄のアクション側へ返す。エンジンを空振りさせない。
    if (event.kind === 'submit' && this.state === 'JP_EMPTY') {
      this.lastError = 'empty-submit';
      return;
    }
    // 候補タップ・文節確定は手元のrevisionで先にふるい落とす（REQ-08）。
    if (event.kind === 'select' || event.kind === 'partial') {
      const exp: number = event.expectedRevision === undefined ? -1 : event.expectedRevision as number;
      if (exp !== this.revision) {
        this.lastError = 'stale-revision';
        return;
      }
    }
    // 未確定中のBackspaceはエンジンへ回し、確定済み本文に触れない（REQ-03）。
    const eng: EnginePort | undefined = this.engine;
    if (eng === undefined) {
      this.lastError = 'no-engine';
      return;
    }
    this.sequence++;
    const seq: number = this.sequence;
    let update: EngineUpdate;
    try {
      update = await eng.dispatch(this.sessionId, epoch, seq, event);
    } catch (e) {
      this.lastError = 'engine-throw';
      this.enterEngineError();
      return;
    }
    await this.applyUpdate(epoch, seq, update);
  }

  private async applyUpdate(epoch: number, seq: number, update: EngineUpdate): Promise<void> {
    // 確定長の報告は今回の更新分のみ。効果なしなら0のまま（古い値を使わない）。
    this.lastCommitLength = 0;
    // 世代ずれは破棄（REQ-02）。新しい入力先へ持ち越さない。
    const nowEpoch: number = this.editor.getEpoch();
    if (update.editorEpoch !== nowEpoch) {
      this.droppedStale++;
      this.lastError = 'stale-epoch';
      return;
    }
    // 遅延した古い応答の誤適用を防ぐ。表示更新の合流は新しい方のみ。
    if (update.sequence < this.lastAppliedSequence) {
      this.droppedLate++;
      this.lastError = 'late-seq';
      return;
    }
    this.lastAppliedSequence = update.sequence;
    if (update.errorCode !== 0) {
      this.lastError = `engine-${update.errorCode}`;
      if (!update.errorRecoverable) {
        this.enterEngineError();
      }
      return;
    }
    if (update.revision < this.revision) {
      this.droppedLate++;
      this.lastError = 'late-rev';
      return;
    }
    this.revision = update.revision;
    // 効果の適用。成功済みは重複適用しない（REQ-01）。epochと組で扱う。
    for (let i: number = 0; i < update.effects.length; i++) {
      const ef: CommitEffect = update.effects[i];
      const key: string = this.effectKey(nowEpoch, ef.effectId);
      if (this.appliedEffects.indexOf(key) >= 0) {
        this.dupSuppressed++;
        continue;
      }
      const ok: boolean = await this.applyCommit(nowEpoch, ef.text);
      if (!ok) {
        // 再送せず整合性回復へ。失敗を入力済みと表示しない（REQ-06）。
        this.needsRecovery = true;
        this.lastError = 'commit-fail';
        return;
      }
      this.appliedEffects.push(key);
    }
    // 表示スナップショット更新。
    this.preeditLen = update.hasPreedit ? update.preeditLen : 0;
    this.caretUtf16 = update.caretUtf16;
    this.segCount = update.segCount;
    this.candidateCount = update.candidateCount;
    this.candidateRevision = update.candidateRevision;
    this.candidateItems = update.candidates;
    this.previewShown = update.hasPreedit && this.previewSupported;
    if (this.candidateCount > 0) {
      this.state = 'JP_CONVERTING';
    } else if (this.preeditLen > 0) {
      this.state = 'JP_COMPOSING';
    } else {
      this.state = 'JP_EMPTY';
    }
    this.lastError = 'ok';
  }

  /**
   * 確定効果の適用。プレビュー表示中はその範囲の確定として処理し、
   * 同じ文字のinsertTextを重ねない（REQ-04・G-01順序に準拠）。
   */
  private async applyCommit(epoch: number, text: string): Promise<boolean> {
    if (epoch !== this.editor.getEpoch()) { return false; }
    if (this.previewShown) {
      if (this.previewStart >= 0) {
        // 確立済みpreviewは効果テキストで置換してから確定し、insertは重ねない。
        // 置換なしにfinish＋insertすると二重に入る。
        if (text.length > 0) {
          const rep: OpResult = await this.editor.setPreview(text, -1, -1);
          if (!rep.ok) {
            return false;
          }
        }
        if (epoch !== this.editor.getEpoch()) { return false; }
        const fin: OpResult = await this.editor.finishPreview();
        if (!fin.ok) {
          return false;
        }
        this.previewShown = false;
        this.preeditLen = 0;
        this.previewStart = -1;
        this.previewEnd = -1;
        this.lastCommitLength = text.length;
        return true;
      }
      // 未確立のpreviewShown（fake等でrangeなし）はfinishしてinsertへ落とす。
      const fin0: OpResult = await this.editor.finishPreview();
      if (!fin0.ok) {
        return false;
      }
      this.previewShown = false;
      this.preeditLen = 0;
    }
    if (text.length === 0) {
      this.lastCommitLength = 0;
      return true;
    }
    if (epoch !== this.editor.getEpoch()) { return false; }
    const ins: OpResult = await this.editor.insert(text);
    if (ins.ok) {
      this.lastCommitLength = text.length;
    }
    return ins.ok;
  }

  /** 未確定プレビューの表示更新（エンジン応答のpreedit反映）。失敗は符号のみ残す。 */
  async refreshPreview(text: string, start: number, end: number): Promise<boolean> {
    if (!this.previewSupported) {
      return false;
    }
    // Once a preview exists, replace the editor's current preview region.
    // A host field can report success while its visible text length lags behind
    // our tracked range, so an absolute range can silently target stale text.
    const replacing: boolean = this.previewShown && this.previewStart >= 0;
    const r: OpResult = await this.editor.setPreview(text, replacing ? -1 : start, replacing ? -1 : end);
    if (r.ok) {
      this.previewShown = true;
      this.previewStart = start;
      // endは置換前の範囲。確定置換用には結果の範囲を保持する。
      this.previewEnd = start + text.length;
    }
    return r.ok;
  }

  async loadPreviewSupport(): Promise<void> {
    try {
      this.previewSupported = await this.editor.queryPreviewSupported();
    } catch (e) {
      this.previewSupported = false;
    }
  }

  /** モード切替。表示中の未確定を先に確定し、成功後にモードを反映する（REQ-10/D-03）。 */
  private async doModeSwitch(epoch: number, event: UiEvent): Promise<void> {
    const target: string = event.text ? event.text as string : 'EN';
    if (this.mode === 'JP' && (this.state === 'JP_COMPOSING' || this.state === 'JP_CONVERTING')) {
      const eng: EnginePort | undefined = this.engine;
      if (eng === undefined) {
        this.lastError = 'no-engine';
        return;
      }
      this.sequence++;
      const seq: number = this.sequence;
      let update: EngineUpdate;
      try {
        const submit: UiEvent = { kind: 'submit' };
        update = await eng.dispatch(this.sessionId, epoch, seq, submit);
      } catch (e) {
        this.lastError = 'engine-throw';
        this.enterEngineError();
        return;
      }
      await this.applyUpdate(epoch, seq, update);
      if (this.needsRecovery || this.lastError !== 'ok') {
        // 確定が完了しなければ切替成功を表示しない（§12）。
        return;
      }
    }
    this.mode = target;
    if (target === 'EN') {
      this.state = 'DIRECT_EN';
    } else {
      this.state = 'JP_EMPTY';
    }
    this.preeditLen = 0;
    this.candidateCount = 0;
    this.previewShown = false;
    this.previewStart = -1;
    this.previewEnd = -1;
    this.lastError = 'ok';
  }

  /** カーソル移動。未確定があれば先に確定し、成功後に欄カーソルを動かす。 */
  private async doMove(epoch: number, event: UiEvent): Promise<void> {
    if (this.mode === 'JP' && (this.state === 'JP_COMPOSING' || this.state === 'JP_CONVERTING')) {
      const eng: EnginePort | undefined = this.engine;
      if (eng === undefined) {
        this.lastError = 'no-engine';
        return;
      }
      this.sequence++;
      const seq: number = this.sequence;
      let update: EngineUpdate;
      try {
        const submit: UiEvent = { kind: 'submit' };
        update = await eng.dispatch(this.sessionId, epoch, seq, submit);
      } catch (e) {
        this.lastError = 'engine-throw';
        this.enterEngineError();
        return;
      }
      await this.applyUpdate(epoch, seq, update);
      if (this.needsRecovery || this.lastError !== 'ok') {
        // 確定が完了しなければカーソルを動かさない。
        return;
      }
    }
    const edge: string = event.edge ? event.edge as string : '';
    let r: OpResult;
    if (edge === 'begin') {
      r = await this.editor.selectRange(0, 0);
    } else if (edge === 'end') {
      r = await this.editor.selectRange(1000, 1000);
    } else {
      const dir: number = event.direction === undefined ? 0 : event.direction as number;
      r = await this.editor.moveCursor(dir);
    }
    this.lastError = r.ok ? 'ok' : `edit-${r.code}`;
    if (!r.ok) {
      this.needsRecovery = true;
    }
  }

  private async doReset(epoch: number): Promise<void> {
    const eng: EnginePort | undefined = this.engine;
    if (eng !== undefined) {
      this.sequence++;
      try {
        const reset: UiEvent = { kind: 'reset' };
        await eng.dispatch(this.sessionId, epoch, this.sequence, reset);
      } catch (e) {
        // reset自体の失敗は符号のみ残し、こちら側は作り直す。
        this.lastError = 'reset-engine-fail';
      }
    }
    this.sessionId = newSessionId();
    this.revision = 0;
    this.lastAppliedSequence = this.sequence;
    this.appliedEffects = [];
    this.previewShown = false;
    this.previewStart = -1;
    this.previewEnd = -1;
    this.preeditLen = 0;
    this.caretUtf16 = 0;
    this.segCount = 0;
    this.candidateCount = 0;
    this.candidateRevision = 0;
    this.candidateItems = [];
    this.needsRecovery = false;
    if (this.lastError === 'ok' || this.lastError === 'reset-engine-fail') {
      // engine-fail由来のlastErrorはENGINE_ERROR側で保持する。
    }
    if (this.state !== 'ENGINE_ERROR') {
      this.lastError = 'ok';
      this.state = this.mode === 'EN' ? 'DIRECT_EN' : 'JP_EMPTY';
    }
  }

  private enterEngineError(): void {
    this.state = 'ENGINE_ERROR';
    this.preeditLen = 0;
    this.candidateCount = 0;
    this.candidateRevision = 0;
    this.candidateItems = [];
    this.previewShown = false;
    this.previewStart = -1;
    this.previewEnd = -1;
  }
}
