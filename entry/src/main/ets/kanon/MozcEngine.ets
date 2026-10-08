/*
 * Kanon IME: MozcEngine (M4)
 * libkanon_bridge.soをCoordinatorのEnginePort面へ包む。IPC不使用・同一プロセス。
 * - 通常入力の履歴を保持し、削除・カーソル移動後はMozcのセッションを継続する。
 * - Spaceは空欄で半角空白効果、未確定ありで変換開始、変換中で次候補。
 * - 候補タップ(select)は選択＋確定を合成する（AT-16のSpaceなし確定用）。
 * - 効果テキスト・候補labelはメモリ内のみ。ログに出さない（REQ-07）。
 */

import { CandidateLabel, CommitEffect, EnginePort, EngineUpdate, UiEvent } from './ImeCoordinator';
import { kanaRoman, modifiedKana } from './KanaInput';
import { CompositionInput, literalInputs } from './CompositionInput';
import fs from '@ohos.file.fs';
import { debugLog, debugErrorCode } from '../common/DebugLog';

interface BridgeApi {
  executeAsync(operation: string, text: string, candidateId: number): Promise<string>;
}

class Cand {
  id: number = -1;
  value: string = '';
}

class ConvOut {
  ok: boolean = false;
  preedit_len: number = 0;
  preedit: string = '';
  focused_reading: string = '';
  focused_id: number | undefined = undefined;
  caret_utf16: number | undefined = undefined;
  ncand: number = 0;
  candidates: Cand[] = [];
  result: string = '';
  /** 候補値の長さ列（診断用・REQ-07適合）。 */
  candlens: number[] = [];
  /** 未確定の文節数。旧soは送らないため0=不明（1扱い）。 */
  segcount: number = 0;
}

function parseOut(json: string): ConvOut {
  const out = new ConvOut();
  try {
    const o = JSON.parse(json) as ConvOut;
    out.ok = o.ok === true;
    out.preedit_len = o.preedit_len ?? 0;
    out.preedit = o.preedit ?? '';
    out.focused_reading = o.focused_reading ?? '';
    out.focused_id = o.focused_id;
    out.caret_utf16 = o.caret_utf16;
    out.ncand = o.ncand ?? 0;
    if (o.candidates instanceof Array) {
      out.candidates = o.candidates as Cand[];
    }
    out.result = o.result ?? '';
    const sg = o.segcount as number | undefined;
    out.segcount = (typeof sg === 'number') ? sg : 0;
    const cl = o.candlens as number[] | undefined;
    if (cl instanceof Array) {
      out.candlens = cl;
    }
  } catch (e) {
  }
  return out;
}

function isRomanLower(s: string): boolean {
  return s.length === 1 && s >= 'a' && s <= 'z';
}

export class MozcEngine implements EnginePort {
  private bridge: BridgeApi | null = null;
  private initFailed: boolean = false;
  private profileDirectory: string = '';
  private buffer: string = '';
  private inputUnits: CompositionInput[] = [];
  private revision: number = 0;
  private lastIds: number[] = [];
  private selIdx: number = 0;
  private lastPreedit: string = '';
  private lastOut: ConvOut = new ConvOut();
  private lastLens: string = '';
  /** mozcセッションの相。composing=入力中、converting=変換表示中（候補あり）。 */
  private phase: string = 'empty';
  /**
   * 部分確定後の残り読み。trueの間はbuffer（消費済みローマ字を含む）を
   * 再送に使わず、Backspaceはセッション内削除に回す。
   */
  private partial: boolean = false;
  /** Native deletion changes the composer; the original key history is no longer replayable. */
  private sessionOwned: boolean = false;
  /** A manually adjusted boundary makes candidate taps commit only that segment. */
  private rangeAdjusted: boolean = false;

  /** 強調中の候補位置（診断表示用）。 */
  getSelIdx(): number {
    return this.selIdx;
  }

  /** 予測表示用。メモリ内のみ。 */
  getPreedit(): string {
    return this.lastPreedit;
  }

  getConversionReading(): string {
    return this.phase === 'converting' ? this.lastOut.focused_reading : '';
  }

  private caretPosition(out: ConvOut): number {
    return Math.max(0, Math.min(out.preedit.length, out.caret_utf16 ?? out.preedit.length));
  }

  getCursorPreview(): string {
    const caret: number = this.caretPosition(this.lastOut);
    if (this.phase !== 'composing' || this.lastPreedit.length === 0 || caret === this.lastPreedit.length) { return ''; }
    return `${this.lastPreedit.slice(0, caret)}│${this.lastPreedit.slice(caret)}`;
  }

  /** 直近の候補長さ列（診断用・数値のみ）。 */
  getLastLens(): string {
    return this.lastLens;
  }

  /** Must run before loading Mozc, whose character-form storage is a singleton. */
  configureProfile(filesDirectory: string): void {
    if (this.bridge !== null || this.profileDirectory.length > 0) { return; }
    const directory: string = `${filesDirectory}/mozc`;
    try {
      if (filesDirectory.length === 0) { return; }
      if (!fs.accessSync(directory)) { fs.mkdirSync(directory, true); }
      // Do not start the engine with an unavailable learning-storage directory.
      const probe: fs.File = fs.openSync(`${directory}/.writable`,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.closeSync(probe);
      fs.unlinkSync(`${directory}/.writable`);
      this.profileDirectory = directory;
      this.initFailed = false;
      debugLog.record('engine', 'profile ready=true');
    } catch (error) {
      debugLog.record('engine', `profile ready=false code=${debugErrorCode(error)}`);
    }
  }

  private async ensure(): Promise<boolean> {
    if (this.bridge !== null) {
      return true;
    }
    if (this.initFailed || this.profileDirectory.length === 0) {
      return false;
    }
    try {
      const m: ESObject = await import('libkanon_bridge.so');
      const ns: ESObject = m as ESObject;
      const d: ESObject = ns.default as ESObject;
      const api = (d ?? ns) as BridgeApi;
      if (api === null || api === undefined) {
        this.initFailed = true;
        return false;
      }
      let ok: boolean = false;
      try {
        ok = parseOut(await api.executeAsync('init', this.profileDirectory, 0)).ok;
      } catch (e) {
        ok = false;
      }
      if (!ok) {
        this.initFailed = true;
        return false;
      }
      this.bridge = api;
      return true;
    } catch (e) {
      this.initFailed = true;
      return false;
    }
  }

  async prepare(): Promise<boolean> {
    return this.ensure();
  }

  private errUpdate(sessionId: string, epoch: number, seq: number, recoverable: boolean): EngineUpdate {
    return {
      sessionId: sessionId, editorEpoch: epoch, sequence: seq, revision: this.revision,
      consumed: false, hasPreedit: false, preeditLen: 0, caretUtf16: 0, segCount: 0,
      candidateCount: 0, candidateRevision: this.revision, candidates: [], effects: [],
      errorCode: 1, errorRecoverable: recoverable
    };
  }

  private emptyUpdate(sessionId: string, epoch: number, seq: number): EngineUpdate {
    return {
      sessionId: sessionId, editorEpoch: epoch, sequence: seq, revision: this.revision,
      consumed: true, hasPreedit: false, preeditLen: 0, caretUtf16: 0, segCount: 0,
      candidateCount: 0, candidateRevision: this.revision, candidates: [], effects: [],
      errorCode: 0, errorRecoverable: true
    };
  }

  private fromOut(sessionId: string, epoch: number, seq: number, out: ConvOut,
    effects: CommitEffect[]): EngineUpdate {
    if (!out.ok) {
      return this.errUpdate(sessionId, epoch, seq, true);
    }
    this.lastOut = out;
    const ordered: Cand[] = out.candidates.slice();
    if (this.phase === 'composing' && out.preedit.length > 0) {
      const exact: number = ordered.findIndex((c: Cand): boolean => c.value === out.preedit);
      if (exact > 0) {
        const raw: Cand = ordered.splice(exact, 1)[0];
        ordered.unshift(raw);
      }
    }
    const labels: CandidateLabel[] = [];
    for (let i: number = 0; i < ordered.length; i++) {
      const c: Cand = ordered[i];
      labels.push({ id: c.id, label: c.value ?? '' });
    }
    this.lastIds = [];
    for (let i: number = 0; i < ordered.length; i++) {
      this.lastIds.push(ordered[i].id);
    }
    if (this.phase === 'converting' && out.focused_id !== undefined) {
      const selected: number = this.lastIds.indexOf(out.focused_id);
      this.selIdx = selected >= 0 ? selected : 0;
    }
    this.lastPreedit = out.preedit;
    this.lastLens = out.candlens.join(',');
    const hasPre: boolean = out.preedit_len > 0;
    return {
      sessionId: sessionId, editorEpoch: epoch, sequence: seq, revision: this.revision,
      consumed: true, hasPreedit: hasPre, preeditLen: hasPre ? out.preedit.length : 0,
      caretUtf16: hasPre ? this.caretPosition(out) : 0,
      segCount: hasPre ? (out.segcount > 0 ? out.segcount : 1) : 0,
      candidateCount: out.ncand, candidateRevision: this.revision, candidates: labels,
      effects: effects, errorCode: 0, errorRecoverable: true
    };
  }

  private async callConvert(keys: string): Promise<ConvOut> {
    const api: BridgeApi = this.bridge as BridgeApi;
    try {
      return parseOut(await api.executeAsync('convert', keys, 0));
    } catch (e) {
      const out = new ConvOut();
      out.ok = false;
      return out;
    }
  }

  private async callLiteral(text: string): Promise<ConvOut> {
    const api: BridgeApi = this.bridge as BridgeApi;
    try {
      return parseOut(await api.executeAsync('literal', text, 0));
    } catch (e) {
      return new ConvOut();
    }
  }

  /** Replay typed units; UTF-8 literals must never go through the roman byte path. */
  private async replay(units: CompositionInput[]): Promise<ConvOut> {
    const api: BridgeApi = this.bridge as BridgeApi;
    let out: ConvOut = parseOut(await api.executeAsync('reset', '', 0));
    if (!out.ok) { return out; }
    for (let i: number = 0; i < units.length; i++) {
      const literal: boolean = units[i].literal;
      let text: string = units[i].text;
      while (i + 1 < units.length && units[i + 1].literal === literal) {
        text += units[++i].text;
      }
      out = literal ? await this.callLiteral(text) : await this.callConvert(text);
      if (!out.ok || out.result.length > 0) { return new ConvOut(); }
    }
    return out;
  }

  private setInputUnits(units: CompositionInput[]): void {
    this.inputUnits = units;
    this.buffer = units.map((unit: CompositionInput): string => unit.text).join('');
  }

  /** 純粋Spaceキー（special_key=SPACE）。変換開始に使う。key_codeの空白では変換しない。 */
  private async callSpace(): Promise<ConvOut> {
    const api: BridgeApi = this.bridge as BridgeApi;
    try {
      return parseOut(await api.executeAsync('space', '', 0));
    } catch (e) {
      const out = new ConvOut();
      out.ok = false;
      return out;
    }
  }

  async dispatch(sessionId: string, editorEpoch: number, sequence: number, event: UiEvent): Promise<EngineUpdate> {
    const ready: boolean = await this.ensure();
    if (!ready || this.bridge === null) {
      return this.errUpdate(sessionId, editorEpoch, sequence, false);
    }
    try {
      return await this.dispatchInner(sessionId, editorEpoch, sequence, event);
    } catch (e) {
      return this.errUpdate(sessionId, editorEpoch, sequence, true);
    }
  }

  /** 入力先変更時の engine 側破棄。Coordinator.onEditorChanged と対で呼ぶ。 */
  async resetLocal(): Promise<void> {
    try {
      if (this.bridge !== null) {
        const api: BridgeApi = this.bridge as BridgeApi;
        await api.executeAsync('reset', '', 0);
      }
    } catch (e) {
    }
    this.buffer = '';
    this.inputUnits = [];
    this.lastIds = [];
    this.selIdx = 0;
    this.lastPreedit = '';
    this.lastLens = '';
    this.revision = 0;
    this.phase = 'empty';
    this.partial = false;
    this.sessionOwned = false;
    this.rangeAdjusted = false;
  }

  private async dispatchInner(sessionId: string, epoch: number, seq: number, event: UiEvent): Promise<EngineUpdate> {
    const api: BridgeApi = this.bridge as BridgeApi;
    const kind: string = event.kind;
    if (kind === 'reset' || kind === 'cancel') {
      try {
        await api.executeAsync('reset', '', 0);
      } catch (e) {
      }
      this.buffer = '';
      this.inputUnits = [];
      this.lastIds = [];
      this.selIdx = 0;
      this.lastPreedit = '';
      this.lastLens = '';
      this.partial = false;
      this.sessionOwned = false;
      this.rangeAdjusted = false;
      if (kind === 'reset') {
        this.revision = 0;
      } else {
        this.revision++;
      }
      this.phase = 'empty';
      return this.emptyUpdate(sessionId, epoch, seq);
    }
    if (kind === 'modifyKana') {
      if (this.buffer.length === 0 && this.lastPreedit.length === 0) {
        return this.emptyUpdate(sessionId, epoch, seq);
      }
      // Partial commit makes the old replay history unusable, but it does not
      // forbid editing kana in the remaining live composition.
      if (this.phase !== 'composing') {
        return this.fromOut(sessionId, epoch, seq, this.lastOut, []);
      }
      if (this.sessionOwned) {
        const caret: number = this.caretPosition(this.lastOut);
        const previous: string = this.lastPreedit.slice(Math.max(0, caret - 1), caret);
        const kana: string = modifiedKana(previous);
        const roman: string = kanaRoman(kana);
        if (kana === previous || roman.length === 0) {
          return this.fromOut(sessionId, epoch, seq, this.lastOut, []);
        }
        const deleted: ConvOut = parseOut(await api.executeAsync('backspace', '', 0));
        if (!deleted.ok) { return this.errUpdate(sessionId, epoch, seq, true); }
        const out: ConvOut = await this.callConvert(roman);
        if (!out.ok) { return this.errUpdate(sessionId, epoch, seq, true); }
        this.buffer = out.preedit;
        this.revision++;
        return this.fromOut(sessionId, epoch, seq, out, []);
      }
      if (this.inputUnits.length === 0) {
        return this.fromOut(sessionId, epoch, seq, this.lastOut, []);
      }
      const last: number = this.inputUnits.length - 1;
      const kana: string = modifiedKana(this.inputUnits[last].kana);
      const roman: string = kanaRoman(kana);
      if (roman.length > 0) {
        const units: CompositionInput[] = this.inputUnits.slice();
        units[last] = new CompositionInput(roman, kana);
        const out: ConvOut = await this.replay(units);
        if (!out.ok) {
          await this.replay(this.inputUnits);
          return this.errUpdate(sessionId, epoch, seq, true);
        }
        this.setInputUnits(units);
        this.revision++;
        return this.fromOut(sessionId, epoch, seq, out, []);
      }
      return this.fromOut(sessionId, epoch, seq, this.lastOut, []);
    }
    if (kind === 'text' || kind === 'kana') {
      const t: string = event.text ? event.text as string : '';
      if (t.length === 0) {
        return this.emptyUpdate(sessionId, epoch, seq);
      }
      const roman: string = kind === 'kana' ? kanaRoman(t) : '';
      const literal: boolean = !isRomanLower(t) && roman.length === 0;
      const unit: string = roman.length > 0 ? roman : t;
      let units: CompositionInput[] = this.inputUnits.slice();
      // Continue the displayed conversion for every input kind. Rebuild it as
      // literal input before appending kana, roman keys or symbols, so starting
      // a new composition cannot replace the highlighted text or commit it.
      const retainConversion: boolean = this.phase === 'converting';
      if (retainConversion) {
        units = literalInputs(this.lastPreedit);
        const restored: ConvOut = await this.replay(units);
        if (!restored.ok) { return this.errUpdate(sessionId, epoch, seq, true); }
      }
      const out: ConvOut = literal ? await this.callLiteral(t) : await this.callConvert(unit);
      if (!out.ok) { return this.errUpdate(sessionId, epoch, seq, true); }
      const effects: CommitEffect[] = [];
      if (out.result.length > 0) {
        // Mozc may commit an existing conversion when ordinary roman input
        // starts the next composition. Never silently discard that result.
        effects.push({ effectId: `t${seq}`, text: out.result });
        units = [];
        this.partial = false;
        this.sessionOwned = false;
      }
      if (literal) {
        units = units.concat(literalInputs(t));
      } else {
        units.push(new CompositionInput(unit, kind === 'kana' ? t : ''));
      }
      this.setInputUnits(units);
      if (retainConversion) {
        this.partial = false;
        this.sessionOwned = false;
      }
      if (this.sessionOwned) {
        this.inputUnits = [];
        this.buffer = out.preedit;
      }
      this.selIdx = 0;
      this.rangeAdjusted = false;
      this.phase = out.preedit_len > 0 ? 'composing' : 'empty';
      if (this.phase === 'empty') { this.setInputUnits([]); }
      this.revision++;
      return this.fromOut(sessionId, epoch, seq, out, effects);
    }
    if (kind === 'backspace') {
      if (this.lastPreedit.length === 0) {
        return this.emptyUpdate(sessionId, epoch, seq);
      }
      // Delete in the live composer, rather than undoing a roman keystroke:
      // replaying k after ki would turn the displayed き back into ｋ.
      const out: ConvOut = parseOut(await api.executeAsync('backspace', '', 0));
      if (!out.ok) {
        return this.errUpdate(sessionId, epoch, seq, true);
      }
      this.inputUnits = [];
      this.buffer = out.preedit;
      this.sessionOwned = out.preedit_len > 0;
      this.rangeAdjusted = false;
      if (!this.sessionOwned) { this.partial = false; }
      this.selIdx = 0;
      this.phase = this.sessionOwned ? 'composing' : 'empty';
      this.revision++;
      return this.fromOut(sessionId, epoch, seq, out, []);
    }
    if (kind === 'compositionArrow') {
      if (this.lastPreedit.length === 0) {
        return this.emptyUpdate(sessionId, epoch, seq);
      }
      const out: ConvOut = parseOut(await api.executeAsync(
        event.text === 'left' ? 'arrowLeft' : 'arrowRight', '', 0));
      if (!out.ok || out.result.length > 0 || out.preedit_len === 0) {
        return this.errUpdate(sessionId, epoch, seq, true);
      }
      this.selIdx = 0;
      if (this.phase === 'converting') {
        this.rangeAdjusted = true;
      } else {
        // An insertion cursor makes the original append-only history obsolete.
        this.inputUnits = [];
        this.buffer = out.preedit;
        this.sessionOwned = true;
      }
      this.revision++;
      return this.fromOut(sessionId, epoch, seq, out, []);
    }
    if (kind === 'convert') {
      if (this.buffer.length === 0) {
        // 空欄のSpaceは半角空白（エンジンを触らない）。
        this.revision++;
        const u: EngineUpdate = this.emptyUpdate(sessionId, epoch, seq);
        u.effects = [{ effectId: `sp${seq}`, text: ' ' }];
        return u;
      }
      if (this.phase === 'converting' && this.lastIds.length > 0) {
        // Highlight without committing or hiding the candidate window. Mozc's
        // complete preedit retains every other segment, including punctuation.
        const next: number = (this.selIdx + 1) % this.lastIds.length;
        const id: number = this.lastIds[next];
        const out: ConvOut = parseOut(await api.executeAsync('highlightCandidate', '', id));
        if (!out.ok || out.result.length > 0 || out.preedit_len === 0) {
          return this.errUpdate(sessionId, epoch, seq, true);
        }
        this.revision++;
        const u: EngineUpdate = this.fromOut(sessionId, epoch, seq, out, []);
        const selected: number = this.lastIds.indexOf(id);
        this.selIdx = selected >= 0 ? selected : 0;
        return u;
      }
      const out: ConvOut = await this.callSpace();
      if (out.ok && out.ncand > 0) {
        this.phase = 'converting';
      } else {
        this.phase = 'composing';
      }
      this.selIdx = 0;
      this.revision++;
      return this.fromOut(sessionId, epoch, seq, out, []);
    }
    // A composing candidate may consume only the prefix before the cursor.
    // Commit it in the original suggestion state: selecting it first changes
    // the native state to conversion and loses the partial-suggestion contract.
    const scopedSelection: boolean = kind === 'select' &&
      (this.phase === 'composing' || (this.rangeAdjusted && this.phase === 'converting'));
    if (kind === 'select' && !scopedSelection) {
      let id: number = event.candidateId === undefined ? -1 : event.candidateId as number;
      if (id < 0 && this.phase === 'converting' && this.selIdx < this.lastIds.length) {
        // Enter相当：強調中の候補を確定する。
        id = this.lastIds[this.selIdx];
      }
      let sel: ConvOut = new ConvOut();
      sel.ok = false;
      try {
        sel = parseOut(await api.executeAsync('selectCandidate', '', id));
      } catch (e) {
        sel.ok = false;
      }
      if (!sel.ok) {
        this.revision++;
        return this.errUpdate(sessionId, epoch, seq, true);
      }
      let done: ConvOut = sel;
      if (done.result.length === 0) {
        try {
          done = parseOut(await api.executeAsync('submit', '', 0));
        } catch (e) {
          done.ok = false;
        }
      }
      this.buffer = '';
      this.inputUnits = [];
      this.lastIds = [];
      this.selIdx = 0;
      this.lastPreedit = '';
      this.phase = 'empty';
      this.partial = false;
      this.sessionOwned = false;
      this.rangeAdjusted = false;
      this.revision++;
      const effects: CommitEffect[] = [];
      if (done.ok && done.result.length > 0) {
        effects.push({ effectId: `s${this.revision}`, text: done.result });
      }
      const u: EngineUpdate = this.emptyUpdate(sessionId, epoch, seq);
      u.effects = effects;
      if (effects.length === 0) {
        u.errorCode = 2;
      }
      return u;
    }
    if (kind === 'partial' || scopedSelection || (kind === 'enter' && this.phase === 'converting')) {
      // Enter during conversion shares the segment-commit path. Submit is
      // still the full commit used by layout changes, paste and cursor moves.
      if ((this.phase !== 'converting' && !scopedSelection) || this.lastIds.length === 0 ||
        this.selIdx >= this.lastIds.length) {
        this.revision++;
        return this.emptyUpdate(sessionId, epoch, seq);
      }
      const id: number = scopedSelection && event.candidateId !== undefined ?
        event.candidateId : this.lastIds[this.selIdx];
      if (this.lastIds.indexOf(id) < 0) {
        return this.errUpdate(sessionId, epoch, seq, true);
      }
      let part: ConvOut = new ConvOut();
      part.ok = false;
      try {
        part = parseOut(await api.executeAsync('submitCandidate', '', id));
      } catch (e) {
        part.ok = false;
      }
      if (!part.ok || part.result.length === 0) {
        this.revision++;
        return this.errUpdate(sessionId, epoch, seq, true);
      }
      let remaining: ConvOut = part;
      // Segment commit also hides the native window. Keep the committed result
      // separately while refreshing candidates for the remaining composition.
      if (part.preedit_len > 0 && part.focused_id !== undefined) {
        try {
          const shown: ConvOut = parseOut(await api.executeAsync('highlightCandidate', '', part.focused_id));
          if (shown.ok && shown.result.length === 0 && shown.preedit_len > 0) { remaining = shown; }
        } catch (error) {
          // Candidate refresh failure must not discard a successful commit.
        }
      }
      // Discard consumed input history: only Mozc owns the remaining reading.
      this.inputUnits = [];
      this.buffer = remaining.preedit;
      this.partial = remaining.preedit_len > 0;
      this.sessionOwned = this.partial;
      if (!this.partial) { this.rangeAdjusted = false; }
      // Suggestions for the remaining reading do not imply conversion state.
      this.phase = !this.partial ? 'empty' : remaining.focused_id !== undefined ? 'converting' : 'composing';
      this.selIdx = 0;
      this.revision++;
      const effects: CommitEffect[] = [];
      if (part.result.length > 0) {
        effects.push({ effectId: `p${this.revision}`, text: part.result });
      }
      return this.fromOut(sessionId, epoch, seq, remaining, effects);
    }
    if (kind === 'submit' || kind === 'enter') {
      if (this.buffer.length === 0 && this.lastPreedit.length === 0) {
        return this.emptyUpdate(sessionId, epoch, seq);
      }
      if (this.phase === 'composing' && this.buffer.length > 0) {
        // 未変換の確定は素のEnterを送らない（実機で落ちる）。表示中の読みを
        // そのまま1回確定し、エンジンは揃えて空に戻す（AT-03初回は確定のみ）。
        const effects: CommitEffect[] = [];
        if (this.lastPreedit.length > 0) {
          effects.push({ effectId: `k${this.revision + 1}`, text: this.lastPreedit });
        }
        this.buffer = '';
        this.inputUnits = [];
        this.lastIds = [];
        this.selIdx = 0;
        this.lastPreedit = '';
        this.phase = 'empty';
        this.partial = false;
        this.sessionOwned = false;
        this.rangeAdjusted = false;
        try {
          await api.executeAsync('reset', '', 0);
        } catch (e) {
        }
        this.revision++;
        const u: EngineUpdate = this.emptyUpdate(sessionId, epoch, seq);
        u.effects = effects;
        return u;
      }
      let selected: ConvOut = new ConvOut();
      if (this.phase === 'converting' && this.selIdx < this.lastIds.length) {
        // 変換表示中のEnterは強調中の候補を選んでから確定する。
        try {
          selected = parseOut(await api.executeAsync('selectCandidate', '', this.lastIds[this.selIdx]));
        } catch (e) {
        }
      }
      let done: ConvOut = selected;
      if (done.result.length === 0) {
        try {
          done = parseOut(await api.executeAsync('submit', '', 0));
        } catch (e) {
          done.ok = false;
        }
      }
      this.buffer = '';
      this.inputUnits = [];
      this.lastIds = [];
      this.selIdx = 0;
      this.lastPreedit = '';
      this.phase = 'empty';
      this.partial = false;
      this.sessionOwned = false;
      this.rangeAdjusted = false;
      this.revision++;
      const effects: CommitEffect[] = [];
      if (done.ok && done.result.length > 0) {
        effects.push({ effectId: `c${this.revision}`, text: done.result });
      }
      const u: EngineUpdate = this.emptyUpdate(sessionId, epoch, seq);
      u.effects = effects;
      return u;
    }
    return this.emptyUpdate(sessionId, epoch, seq);
  }
}
