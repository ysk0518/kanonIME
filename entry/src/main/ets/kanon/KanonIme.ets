/*
 * Kanon IME: KanonIme (M4)
 * 実キーボードとCoordinatorの接続点。KeyboardViewは意味のあるイベントだけを投げる（§6）。
 * - 入力先の世代変化を検出してonEditorChangedする。旧欄への書込はCoordinatorが遮断する。
 * - 未確定previewは全体置換で更新し、候補確定時は1回だけinsertする。
 * - ログは符号・件数・長さのみ。本文・候補は扱わない（REQ-07）。
 */

import { CandidateLabel, ImeCoordinator, ImeSnapshot, UiEvent } from './ImeCoordinator';
import { realEditorPort } from './RealEditorPort';
import { MozcEngine } from './MozcEngine';
import { EnglishEngine } from './EnglishEngine';
import { editorAdapter } from './EditorAdapter';
import { EnglishCompletionUndo, englishPrediction } from './EnglishPrediction';
import { DEFAULT_LAYOUT_ORDER, layoutLanguage, languageLayouts, nextLanguageLayout,
  readSharedFlickEnabled } from '../common/KeyboardConfig';
import { keyboardSettingsSync } from '../common/KeyboardSettingsSync';
import { keyboardHaptics } from '../common/KeyboardHaptics';

class KanonIme {
  private coord: ImeCoordinator = new ImeCoordinator(realEditorPort);
  private engine: MozcEngine = new MozcEngine();
  private englishEngine: EnglishEngine = new EnglishEngine();
  private ready: boolean = false;
  private lastEpoch: number = -1;
  private mode: string = 'JP';
  private compIdx: number = -1;
  private compLen: number = 0;
  private tick: number = 0;
  private postTail: Promise<void> = Promise.resolve();

  configureProfile(filesDirectory: string): void {
    this.engine.configureProfile(filesDirectory);
  }

  private async ensure(): Promise<void> {
    if (this.ready) {
      return;
    }
    this.coord.setEngine(this.engine);
    this.coord.setEnglishEngine(this.englishEngine);
    await this.engine.prepare();
    await this.coord.loadPreviewSupport();
    const layout: string = AppStorage.get<string>('kanonLayout') ?? 'jp_flick';
    await this.coord.postEvent({ kind: 'mode', text: layoutLanguage(layout) });
    this.mode = this.coord.getSnapshot().mode;
    this.lastEpoch = realEditorPort.getEpoch();
    this.ready = true;
  }

  private async syncEpoch(): Promise<void> {
    const e: number = realEditorPort.getEpoch();
    if (this.lastEpoch !== e) {
      this.coord.onEditorChanged();
      await this.engine.resetLocal();
      this.englishEngine.resetLocal();
      englishPrediction.clear();
      await this.coord.loadPreviewSupport();
      this.lastEpoch = e;
      this.compIdx = -1;
      this.compLen = 0;
    }
  }

  private publish(s: ImeSnapshot): void {
    this.mode = s.mode;
    this.tick++;
    kanonRevTick++;
    AppStorage.setOrCreate('kanonTick', this.tick);
    AppStorage.setOrCreate('kanonMode', s.mode);
    AppStorage.setOrCreate('kanonState', s.state);
    AppStorage.setOrCreate('kanonEnglishComposing', s.mode === 'EN' && (this.coord.usesEnglishComposition() ? s.preeditLen > 0 : englishPrediction.getPrefix().length > 0));
    AppStorage.setOrCreate('kanonErr', s.lastError);
    AppStorage.setOrCreate('kanonNeedsRecovery', s.needsRecovery);
    AppStorage.setOrCreate('kanonCand', s.mode === 'EN' && !this.coord.usesEnglishComposition() ? englishPrediction.getItems().length : s.candidateCount);
    AppStorage.setOrCreate('kanonRev', s.mode === 'EN' && !this.coord.usesEnglishComposition() ? englishPrediction.getRevision() : this.coord.getCandidateRevision());
    try {
      const items = s.mode === 'EN' && !this.coord.usesEnglishComposition() ? englishPrediction.getItems() : this.coord.getCandidateView();
      const labels: string[] = [];
      const ids: number[] = [];
      for (let i: number = 0; i < items.length && i < 20; i++) {
        labels.push(items[i].label);
        ids.push(items[i].id);
      }
      AppStorage.setOrCreate('kanonList', labels);
      AppStorage.setOrCreate('kanonIdList', ids);
    } catch (e) {
    }
    try {
      AppStorage.setOrCreate('kanonLens', this.engine.getLastLens());
      AppStorage.setOrCreate('kanonIds', this.getCandidateIds());
      AppStorage.setOrCreate('kanonLens2', this.getCandidateLens2());
      AppStorage.setOrCreate('kanonSeg', s.segCount);
      AppStorage.setOrCreate('kanonSel', s.mode === 'EN' ? englishPrediction.getSelectedIndex() : this.engine.getSelIdx());
    } catch (e) {
    }
  }

  private async post(kind: string, text?: string, candidateId?: number,
    expectedRevision?: number, direction?: number, edge?: string): Promise<ImeSnapshot> {
    // プレビュー更新も含めて直列化する。次の打鍵が前の表示・確定へ割り込まない。
    const epoch: number = realEditorPort.getEpoch();
    const run: Promise<ImeSnapshot> = this.postTail.then((): Promise<ImeSnapshot> => {
      if (epoch !== realEditorPort.getEpoch()) {
        return Promise.resolve(this.coord.getSnapshot());
      }
      return this.postSerial(kind, text, candidateId, expectedRevision, direction, edge);
    });
    this.postTail = run.then((): void => undefined).catch((): void => undefined);
    return run;
  }

  private async postSerial(kind: string, text?: string, candidateId?: number,
    expectedRevision?: number, direction?: number, edge?: string): Promise<ImeSnapshot> {
    try {
      const requestEpoch: number = realEditorPort.getEpoch();
      await this.ensure();
      await this.syncEpoch();
      if (requestEpoch !== realEditorPort.getEpoch()) { return this.coord.getSnapshot(); }
      this.coord.setEnglishCompositionEnabled(this.predictionAllowed());
      if (this.mode === 'EN' && englishPrediction.takeCompositionAbandoned()) {
        this.englishEngine.resetLocal();
        this.coord.onEditorChanged();
        this.compIdx = -1;
        this.compLen = 0;
      }
      if (kind === 'prepare') {
        const configured: string = AppStorage.get<string>('kanonLayoutOrder') ?? DEFAULT_LAYOUT_ORDER;
        const current: string = AppStorage.get<string>('kanonLayout') ?? 'jp_flick';
        const selected: string[] = languageLayouts(configured);
        const preferred: string = selected.find((id: string) => layoutLanguage(id) === layoutLanguage(current)) ?? selected[0];
        if (preferred !== current || this.coord.getSnapshot().mode !== layoutLanguage(preferred)) {
          return await this.changeLayout('config', configured, requestEpoch);
        }
        return this.coord.getSnapshot();
      }
      if (kind !== 'backspace' && kind !== 'select' && kind !== 'undoEnglish') { englishPrediction.dropUndo(); }
      if (kind === 'cycle' || kind === 'config') {
        return await this.changeLayout(kind, text ?? '', requestEpoch);
      }
      if (this.mode === 'EN' && !this.coord.usesEnglishComposition() && kind === 'convert') {
        if (this.predictionAllowed() && englishPrediction.getItems().length > 0) {
          const expected: number = englishPrediction.getCursor();
          const cursor: number = await realEditorPort.queryCursor();
          const before: string = cursor >= 0 && cursor <= 4096 ? await realEditorPort.queryBefore(cursor) : '';
          if (requestEpoch !== realEditorPort.getEpoch()) { englishPrediction.clear(); return this.coord.getSnapshot(); }
          if (cursor === expected && before.endsWith(englishPrediction.getPrefix())) {
            englishPrediction.selectNext();
          } else { englishPrediction.clear(); }
        } else {
          return await this.postSerial('text', ' ');
        }
        const snapshot: ImeSnapshot = this.coord.getSnapshot();
        this.publish(snapshot);
        return snapshot;
      }
      if (kind === 'paste' && this.coord.getSnapshot().preeditLen > 0) {
        const committed: ImeSnapshot = await this.postSerial('submit');
        if (committed.lastError !== 'ok' || requestEpoch !== realEditorPort.getEpoch()) { return committed; }
      }
      if (this.mode === 'EN' && (kind === 'backspace' || kind === 'undoEnglish')) {
        const undo: EnglishCompletionUndo | undefined = englishPrediction.takeUndo();
        if (undo !== undefined && undo.epoch === requestEpoch && this.predictionAllowed()) {
          englishPrediction.editing = true;
          try {
            await this.coord.postEvent({ kind: 'undoCompletion', text: undo.word,
              cursor: undo.cursor, prefixLength: undo.prefix.length });
          } finally { englishPrediction.editing = false; }
          const snapshot: ImeSnapshot = this.coord.getSnapshot();
          if (requestEpoch !== realEditorPort.getEpoch()) { englishPrediction.clear(); return snapshot; }
          if (snapshot.lastError === 'ok') {
            if (this.coord.usesEnglishComposition()) {
              this.compIdx = undo.cursor - undo.word.length;
              this.compLen = 0;
              englishPrediction.editing = true;
              try { await this.refreshPreview(snapshot); }
              finally { englishPrediction.editing = false; }
            } else {
              englishPrediction.restorePrefix(undo.prefix, undo.cursor - undo.word.length + undo.prefix.length);
            }
          }
          if (snapshot.lastError !== 'undo-stale') {
            const restored: ImeSnapshot = this.coord.getSnapshot();
            this.publish(restored);
            return restored;
          }
        }
      }
      // 明示的な「戻す」は照合が失敗しても通常削除へ置き換えない。
      if (kind === 'undoEnglish') {
        if (this.mode === 'EN' && this.coord.getSnapshot().lastError === 'undo-stale') {
          await this.coord.postEvent({ kind: 'cancel' });
        }
        const snapshot: ImeSnapshot = this.coord.getSnapshot();
        this.publish(snapshot);
        return snapshot;
      }
      if (this.mode === 'EN' && !this.coord.usesEnglishComposition() && (kind === 'select' || kind === 'cancel' || kind === 'enter')) {
        if (kind === 'select') { await this.completeEnglish(candidateId ?? -1, expectedRevision ?? -1); }
        else if (kind === 'enter' && englishPrediction.getPrefix().length > 0) {
          const selected: CandidateLabel | undefined = englishPrediction.getSelectedItem();
          if (selected !== undefined) {
            await this.completeEnglish(selected.id, englishPrediction.getRevision());
          } else { englishPrediction.clear(); }
        }
        else {
          englishPrediction.clear();
          if (kind === 'cancel') { await this.coord.postEvent({ kind: 'cancel' }); }
          if (kind === 'enter') {
            const epoch: number = realEditorPort.getEpoch();
            const attr = await editorAdapter.queryAttribute();
            if (attr.ok && attr.value !== undefined && epoch === realEditorPort.getEpoch()) {
              await editorAdapter.sendEnterAction(attr.value.enterKeyType);
            }
          }
        }
        const snapshot: ImeSnapshot = this.coord.getSnapshot();
        this.publish(snapshot);
        return snapshot;
      }
      const english: boolean = this.mode === 'EN';
      const directEnglish: boolean = english && !this.coord.usesEnglishComposition();
      const epoch: number = realEditorPort.getEpoch();
      const cursor: number = directEnglish && kind === 'text' && englishPrediction.getPrefix().length === 0 ?
        await realEditorPort.queryCursor() : englishPrediction.getCursor();
      if (directEnglish && kind === 'text' && /^[A-Za-z]+$/.test(text ?? '') && this.predictionAllowed() &&
        englishPrediction.getPrefix().length === 0 && englishPrediction.canSeed() && cursor > 0 && cursor <= 4096) {
        const before: string = await realEditorPort.queryBefore(cursor);
        const word: RegExpMatchArray | null = before.match(/[A-Za-z]+$/);
        if (word !== null && epoch === realEditorPort.getEpoch()) { englishPrediction.seed(word[0], cursor); }
      }
      if (epoch !== realEditorPort.getEpoch()) { englishPrediction.clear(); return this.coord.getSnapshot(); }
      const ev: UiEvent = { kind: kind };
      if (text !== undefined) {
        ev.text = text;
      }
      if (candidateId !== undefined) {
        ev.candidateId = candidateId;
      }
      if (expectedRevision !== undefined) {
        ev.expectedRevision = expectedRevision;
      }
      if (direction !== undefined) {
        ev.direction = direction;
      }
      if (edge !== undefined) {
        ev.edge = edge;
      }
      const completionPrefix: string = english && !directEnglish ? this.englishEngine.getTypedText() : '';
      const completionItem: CandidateLabel | undefined = kind === 'select' ?
        englishPrediction.getItems().find((item: CandidateLabel) => item.id === candidateId) :
        englishPrediction.getSelectedItem();
      const completionStart: number = this.compIdx;
      englishPrediction.editing = english;
      try { await this.coord.postEvent(ev); }
      finally { englishPrediction.editing = false; }
      const s: ImeSnapshot = this.coord.getSnapshot();
      if (epoch !== realEditorPort.getEpoch()) { englishPrediction.clear(); return s; }
      if ((!english || !directEnglish) && (kind === 'submit' || kind === 'enter') && s.lastError === 'empty-submit') {
        const attr = await editorAdapter.queryAttribute();
        if (attr.ok && attr.value !== undefined && epoch === realEditorPort.getEpoch()) {
          await editorAdapter.sendEnterAction(attr.value.enterKeyType);
        }
      }
      if (directEnglish && s.lastError === 'ok' && this.predictionAllowed()) {
        if (kind === 'text') { englishPrediction.text(text ?? '', cursor); }
        else if (kind === 'backspace') { englishPrediction.backspace(); }
        else { englishPrediction.clear(); }
      } else if (directEnglish || kind === 'mode') { englishPrediction.clear(); }
      if (english && !directEnglish && (kind === 'enter' || kind === 'select') &&
        s.lastError === 'ok' && s.commitLength > 0 && completionStart >= 0 &&
        /^[A-Za-z]+$/.test(completionPrefix) && completionItem !== undefined &&
        completionItem.label.startsWith(completionPrefix) && completionItem.label.length > completionPrefix.length) {
        englishPrediction.rememberCompletion(completionPrefix, completionItem.label,
          completionStart + s.commitLength, epoch);
      }
      if ((kind === 'partial' || kind === 'enter') && s.lastError === 'ok' && s.commitLength > 0) {
        // 部分確定は確定済み＋残り読みの構成が変わる。カーソル再問合せは
        // 確定直後の位置を返さない実機挙動があるため、追跡中の旧起点に
        // 今回確定文字数を足して再アンカーする（決定的）。
        const base: number = this.compIdx >= 0 ? this.compIdx : await realEditorPort.queryCursor();
        this.compIdx = (base >= 0 ? base : 0) + s.commitLength;
        this.compLen = 0;
      }
      if (s.preeditLen === 0 && this.compIdx >= 0) {
        if ((s.lastError === 'ok' && s.commitLength > 0) ||
          kind === 'submit' || kind === 'enter' || kind === 'select' || kind === 'move' ||
          kind === 'selectMove' || kind === 'selectEdge' || kind === 'selectAll' || kind === 'forwardDelete' ||
          kind === 'partial' ||
          (kind === 'mode' && s.mode !== this.mode)) {
          // 確定時はapplyCommitがpreviewを確定済み。範囲追跡だけ閉じる。
          // 切替成功時もsubmit確定済みのため同じ。
          this.compIdx = -1;
          this.compLen = 0;
        } else {
          // 空遷移（未確定消滅・取消・切替）で欄に残ったpreview全体を消す。
          try {
            await realEditorPort.setPreview('', -1, -1);
          } catch (e) {
          }
          this.compIdx = -1;
          this.compLen = 0;
        }
      }
      englishPrediction.editing = english;
      try { await this.refreshPreview(s); }
      finally { englishPrediction.editing = false; }
      const updated: ImeSnapshot = this.coord.getSnapshot();
      this.publish(updated);
      return updated;
    } catch (e) {
      const s: ImeSnapshot = this.coord.getSnapshot();
      this.publish(s);
      return s;
    }
  }

  /** 未確定previewの表示更新。前回範囲を置換する（G-01置換順序）。失敗時はinsert確定のみへ落とす。 */
  private async refreshPreview(s: ImeSnapshot): Promise<void> {
    if ((s.mode !== 'JP' && !this.coord.usesEnglishComposition()) || s.preeditLen === 0) {
      this.compIdx = -1;
      this.compLen = 0;
      return;
    }
    if (s.state !== 'JP_COMPOSING' && s.state !== 'JP_CONVERTING' && s.state !== 'EN_COMPOSING' && s.state !== 'EN_CONVERTING') {
      return;
    }
    const pre: string = s.mode === 'EN' ? this.englishEngine.getPreedit() : this.engine.getPreedit();
    if (pre.length === 0) {
      return;
    }
    if (this.compIdx < 0) {
      this.compIdx = await realEditorPort.queryCursor();
      this.compLen = 0;
    }
    if (this.compIdx < 0) {
      return;
    }
    if (s.mode === 'EN') { englishPrediction.setCompositionCursor(this.compIdx + pre.length); }
    const ok: boolean = await this.coord.refreshPreview(pre, this.compIdx, this.compIdx + this.compLen);
    if (ok) {
      this.compLen = pre.length;
    }
    if (!ok && s.mode === 'JP') {
      this.coord.setPreviewUnsupported();
    }
  }

  async keyText(ch: string, feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.post('text', ch);
  }

  async keyPaste(value: string): Promise<boolean> {
    if (value.length === 0) { return false; }
    const snapshot: ImeSnapshot = await this.post('paste', value);
    return snapshot.lastError === 'ok';
  }

  async keyKana(kana: string): Promise<void> {
    keyboardHaptics.key();
    await this.post('kana', kana);
  }

  async modifyKana(): Promise<void> {
    keyboardHaptics.key();
    await this.post('modifyKana');
  }

  private predictionAllowed(): boolean {
    const pattern: number = AppStorage.get<number>('inputPattern') ?? InputType.Normal;
    return pattern !== InputType.Password && pattern !== InputType.NUMBER_PASSWORD && pattern !== InputType.NEW_PASSWORD;
  }

  private async completeEnglish(id: number, revision: number): Promise<void> {
    if (!this.predictionAllowed() || revision !== englishPrediction.getRevision()) { return; }
    const items: CandidateLabel[] = englishPrediction.getItems();
    const item: CandidateLabel | undefined = items.find((candidate: CandidateLabel) => candidate.id === id);
    if (item === undefined) { return; }
    const prefix: string = englishPrediction.getPrefix();
    const expected: number = englishPrediction.getCursor();
    const epoch: number = realEditorPort.getEpoch();
    const cursor: number = await realEditorPort.queryCursor();
    if (cursor !== expected || cursor < 0 || cursor > 4096) { englishPrediction.clear(); return; }
    const before: string = await realEditorPort.queryBefore(cursor);
    if (epoch !== realEditorPort.getEpoch() || !before.endsWith(prefix)) { englishPrediction.clear(); return; }
    // Prefix matches the editor: insert only the remaining letters, without destructive replacement.
    englishPrediction.editing = true;
    let completed: boolean = false;
    try {
      await this.coord.postEvent({ kind: 'text', text: item.label.substring(prefix.length) });
      completed = this.coord.getSnapshot().lastError === 'ok' && epoch === realEditorPort.getEpoch();
    }
    finally {
      englishPrediction.editing = false;
      englishPrediction.clear();
    }
    if (completed && expected + item.label.length - prefix.length <= 4096) {
      englishPrediction.rememberCompletion(prefix, item.label, expected + item.label.length - prefix.length, epoch);
    }
  }

  async keySpace(feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.post('convert');
  }

  async keyReturn(feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.post('enter');
  }

  async keyDelete(feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.post('backspace');
    await this.updateCursor();
  }

  async keyDeleteForward(feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.post('forwardDelete');
    await this.updateCursor();
  }

  async keyUndoEnglish(): Promise<void> {
    await this.post('undoEnglish');
    await this.updateCursor();
  }

  /** カーソル移動（EditViewの矢印・行頭・行末）。単一キュー経由。 */
  async keyMove(direction: number, feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.post('move', undefined, undefined, undefined, direction);
    await this.updateCursor();
  }

  async keySelectMove(direction: number): Promise<void> {
    keyboardHaptics.key();
    await this.post('selectMove', undefined, undefined, undefined, direction);
    await this.updateCursor();
  }

  async keySelectEdge(edge: string): Promise<void> {
    keyboardHaptics.key();
    await this.post('selectEdge', undefined, undefined, undefined, undefined, edge);
    await this.updateCursor();
  }

  async keySelectAll(): Promise<void> {
    keyboardHaptics.key();
    await this.post('selectAll');
    await this.updateCursor();
  }

  async keyMoveBegin(): Promise<void> {
    keyboardHaptics.key();
    await this.post('move', undefined, undefined, undefined, undefined, 'begin');
    await this.updateCursor();
  }

  async keyMoveEnd(): Promise<void> {
    keyboardHaptics.key();
    await this.post('move', undefined, undefined, undefined, undefined, 'end');
    await this.updateCursor();
  }

  /** 欄カーソル位置の表示更新。移動・削除操作時のみ問い合わせる。 */
  private async updateCursor(): Promise<void> {
    try {
      const pos: number = await realEditorPort.queryCursor();
      AppStorage.setOrCreate('kanonCursor', pos);
    } catch (e) {
    }
  }

  async selectCandidate(id: number): Promise<void> {
    keyboardHaptics.key();
    const rev: number = this.mode === 'EN' && !this.coord.usesEnglishComposition() ? englishPrediction.getRevision() : this.coord.getCandidateRevision();
    await this.post('select', undefined, id, rev);
  }

  /** 先頭文節のみ確定（残りは未確定継続）。現行revを添える。 */
  async partialCommit(): Promise<void> {
    keyboardHaptics.key();
    const rev: number = this.coord.getCandidateRevision();
    await this.post('partial', undefined, undefined, rev);
  }

  async cancelCompose(): Promise<void> {
    await this.post('cancel');
  }

  async switchMode(): Promise<void> {
    await this.post('cycle');
  }

  async toggleLayout(): Promise<boolean> {
    if (!readSharedFlickEnabled()) { return false; }
    keyboardHaptics.key();
    const configured: string = AppStorage.get<string>('kanonLayoutOrder') ?? DEFAULT_LAYOUT_ORDER;
    const current: string = AppStorage.get<string>('kanonLayout') ?? 'jp_flick';
    const next: string = current === 'jp_flick' ? 'jp_qwerty' :
      current === 'jp_qwerty' ? 'jp_flick' :
      current === 'en_flick' ? 'en_qwerty' : 'en_flick';
    const flick: boolean = next.endsWith('_flick');
    const order: string[] = languageLayouts(configured).map((id: string) =>
      `${id.startsWith('en_') ? 'en' : 'jp'}_${flick ? 'flick' : 'qwerty'}`);
    return this.applyLayoutConfig(order.join(','));
  }

  async prepare(): Promise<void> {
    await this.post('prepare');
  }

  async applyLayoutConfig(value: string): Promise<boolean> {
    const normalized: string = languageLayouts(value).join(',');
    const epoch: number = realEditorPort.getEpoch();
    const snapshot: ImeSnapshot = await this.post('config', normalized);
    return epoch === realEditorPort.getEpoch() && snapshot.lastError === 'ok' &&
      AppStorage.get<string>('kanonLayoutOrder') === normalized;
  }

  private async changeLayout(kind: string, value: string, epoch: number): Promise<ImeSnapshot> {
    const configured: string = AppStorage.get<string>('kanonLayoutOrder') ?? DEFAULT_LAYOUT_ORDER;
    const current: string = AppStorage.get<string>('kanonLayout') ?? 'jp_flick';
    const order: string[] = languageLayouts(kind === 'config' ? value : configured).map((id: string) =>
      readSharedFlickEnabled() ? id : `${layoutLanguage(id) === 'EN' ? 'en' : 'jp'}_qwerty`);
    const target: string = kind === 'config' ?
      (order.find((id: string) => layoutLanguage(id) === layoutLanguage(current)) ?? order[0]) :
      nextLanguageLayout(configured, current);
    if (target !== current || this.coord.getSnapshot().mode !== layoutLanguage(target)) {
      await this.coord.postEvent({ kind: 'mode', text: layoutLanguage(target) });
      const snapshot: ImeSnapshot = this.coord.getSnapshot();
      if (epoch !== realEditorPort.getEpoch() || snapshot.lastError !== 'ok' || snapshot.mode !== layoutLanguage(target)) {
        this.publish(snapshot);
        return snapshot;
      }
      this.compIdx = -1;
      this.compLen = 0;
      englishPrediction.clear();
      AppStorage.setOrCreate('kanonLayout', target);
      AppStorage.setOrCreate('kanonLastLayout', target);
      AppStorage.setOrCreate('kanonCandidatesExpanded', false);
    }
    if (kind === 'config' && epoch === realEditorPort.getEpoch()) {
      if (AppStorage.get<string>('kanonLayoutOrder') !== order.join(',')) {
        await keyboardSettingsSync.save({ layoutOrder: order.join(',') }, false);
      }
    }
    const snapshot: ImeSnapshot = this.coord.getSnapshot();
    this.publish(snapshot);
    return snapshot;
  }

  getCandidates(): CandidateLabel[] {
    try {
      return this.mode === 'EN' && !this.coord.usesEnglishComposition() ? englishPrediction.getItems() : this.coord.getCandidateView();
    } catch (e) {
      return [];
    }
  }

  /** 候補スロット表示用。範囲外は空文字。 */
  getCandidateLabelAt(index: number): string {
    try {
      const items: CandidateLabel[] = this.coord.getCandidateView();
      if (index < 0 || index >= items.length) {
        return '';
      }
      return items[index].label;
    } catch (e) {
      return '';
    }
  }

  /** 候補スロットのid。範囲外は-1。 */
  getCandidateIdAt(index: number): number {
    try {
      const items: CandidateLabel[] = this.coord.getCandidateView();
      if (index < 0 || index >= items.length) {
        return -1;
      }
      return items[index].id;
    } catch (e) {
      return -1;
    }
  }

  /** 候補スロット数（表示上限20・横スクロールで辿る）。 */
  getCandidateSlotCount(): number {
    try {
      const n: number = this.coord.getCandidateView().length;
      return n > 20 ? 20 : n;
    } catch (e) {
      return 0;
    }
  }
  getCandidateIds(): string {
    try {
      const items: CandidateLabel[] = this.coord.getCandidateView();
      const parts: string[] = [];
      for (let i: number = 0; i < items.length; i++) {
        parts.push(items[i].id.toString());
      }
      return parts.join(',');
    } catch (e) {
      return '';
    }
  }

  /** 候補label長列（診断用・数値のみ）。 */
  getCandidateLens2(): string {
    try {
      const items: CandidateLabel[] = this.coord.getCandidateView();
      const parts: string[] = [];
      for (let i: number = 0; i < items.length; i++) {
        parts.push(items[i].label.length.toString());
      }
      return `${items.length}:${parts.join(',')}`;
    } catch (e) {
      return 'e';
    }
  }

  getMode(): string {
    return AppStorage.get<string>('kanonMode') ?? this.mode;
  }
}

export const kanonIme: KanonIme = new KanonIme();

/** 候補更新ごとに単調増加する表示用 tick。ForEachのキー空間切替に使う。 */
export let kanonRevTick: number = 0;
