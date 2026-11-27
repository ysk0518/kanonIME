/*
 * Kanon IME: MozcEngine (M4)
 * libkanon_bridge.soをCoordinatorのEnginePort面へ包む。IPC不使用・同一プロセス。
 * - 通常入力の履歴を保持し、削除・カーソル移動後はMozcのセッションを継続する。
 * - Spaceは空欄で半角空白効果、未確定ありで変換開始、変換中で次候補。
 * - 候補タップ(select)は選択＋確定を合成する（AT-16のSpaceなし確定用）。
 * - 効果テキスト・候補labelはメモリ内のみ。ログに出さない（REQ-07）。
 */

import { CandidateLabel, CommitEffect, CompositionPhase, EnginePort, EngineUpdate } from './ImeCoordinator';
import { CandidateInputEvent, CompositionCursorEvent, InputEvent, KanaModifier, ModifyKanaInputEvent,
  ReplaceToggleEvent, TextInputEvent } from './InputEventTypes';
import { kanaRoman, modifiedKana } from './KanaInput';
import { CompositionInput, literalInputs } from './CompositionInput';
import { MozcBridgePort } from './MozcBridgePort';
import { MozcEditState } from './MozcEditState';
import { compositionCaretPath } from './CompositionCursorSync';

class Cand {
  id: number = -1;
  value: string = '';
  deletable?: boolean;
}

class ConvOut {
  ok: boolean = false;
  candidate_not_learned: boolean = false;
  preedit_len: number = 0;
  preedit: string = '';
  focused_reading: string = '';
  focused_id: number | undefined = undefined;
  caret_utf16: number | undefined = undefined;
  ncand: number = 0;
  candidates: Cand[] = [];
  result: string = '';
  deletion_offset: number | undefined = undefined;
  deletion_length: number | undefined = undefined;
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
    out.candidate_not_learned = o.candidate_not_learned === true;
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
    out.deletion_offset = o.deletion_offset;
    out.deletion_length = o.deletion_length;
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

/** Hiragana, katakana or the long vowel mark: no roman key is pending before the caret. */
function endsWithKana(s: string): boolean {
  if (s.length === 0) { return false; }
  const c: number = s.charCodeAt(s.length - 1);
  return (c >= 0x3041 && c <= 0x3096) || (c >= 0x30A1 && c <= 0x30FA) || c === 0x30FC;
}

/** The preedit ends with the roman letter last typed, half or full width. */
function endsWithRomanKey(s: string, key: string): boolean {
  if (s.length === 0 || key.length !== 1) { return false; }
  let c: number = s.charCodeAt(s.length - 1);
  if (c >= 0xFF21 && c <= 0xFF5A) { c -= 0xFEE0; }
  return String.fromCharCode(c).toLowerCase() === key;
}

/** Mozc cursor positions count Unicode characters, not UTF-16 units. */
function codePointLength(s: string): number {
  let count: number = 0;
  for (let i: number = 0; i < s.length; i++) {
    const c: number = s.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) { i++; }
    count++;
  }
  return count;
}

/** One or more lowercase roman letters; several arrive together when fast keys were merged. */
function isRomanLower(s: string): boolean {
  if (s.length === 0) { return false; }
  for (let i: number = 0; i < s.length; i++) {
    const c: string = s.charAt(i);
    if (c < 'a' || c > 'z') { return false; }
  }
  return true;
}

export class MozcEngine implements EnginePort {
  private bridge: MozcBridgePort;
  private buffer: string = '';
  private inputUnits: CompositionInput[] = [];
  // Each Mozc key with suggestions costs 20-30 ms, and 100-200 ms for the first
  // consonant of a new word. With deferral a key only updates the preedit; the
  // session asks for candidates ("suggest") when no newer key is queued.
  private deferSuggestions: boolean = false;
  private suggestPending: boolean = false;
  /** The pending roman letter "suggest" deletes and retypes; empty to move the cursor. */
  private retypeKey: string = '';
  private lastLabels: CandidateLabel[] = [];
  private lastCandidateRevision: number = 0;
  private revision: number = 0;
  private lastIds: number[] = [];
  private selIdx: number = 0;
  private lastPreedit: string = '';
  private lastOut: ConvOut = new ConvOut();
  private lastLens: string = '';
  /** mozcセッションの相。候補の有無とは独立。 */
  private phase: CompositionPhase = 'empty';
  /** Replay ownership and candidate commit scope are independent editing policies. */
  private editing: MozcEditState = new MozcEditState();

  constructor(bridge: MozcBridgePort, deferSuggestions: boolean = false) {
    this.bridge = bridge;
    this.deferSuggestions = deferSuggestions;
  }

  /** True when the shown preedit is newer than its candidates; see suggestLater. */
  needsSuggestion(): boolean {
    return this.suggestPending && this.phase === 'composing';
  }

  /** 強調中の候補位置（診断表示用）。 */
  getSelIdx(): number {
    return this.phase === 'converting' ? this.selIdx : -1;
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

  private async ensure(): Promise<boolean> {
    try {
      return await this.bridge.prepare();
    } catch (e) {
      return false;
    }
  }

  async prepare(): Promise<boolean> {
    return this.ensure();
  }

  private errUpdate(sessionId: string, epoch: number, seq: number, recoverable: boolean): EngineUpdate {
    return {
      sessionId: sessionId, editorEpoch: epoch, sequence: seq, revision: this.revision,
      consumed: false, phase: 'empty', hasPreedit: false, preeditLen: 0, caretUtf16: 0, segCount: 0,
      candidateCount: 0, candidateRevision: this.revision, candidates: [], effects: [],
      errorCode: 1, errorRecoverable: recoverable
    };
  }

  private emptyUpdate(sessionId: string, epoch: number, seq: number): EngineUpdate {
    return {
      sessionId: sessionId, editorEpoch: epoch, sequence: seq, revision: this.revision,
      consumed: true, phase: 'empty', hasPreedit: false, preeditLen: 0, caretUtf16: 0, segCount: 0,
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
    this.lastLabels = labels;
    this.lastCandidateRevision = this.revision;
    const hasPre: boolean = out.preedit_len > 0;
    return {
      sessionId: sessionId, editorEpoch: epoch, sequence: seq, revision: this.revision,
      consumed: true, phase: hasPre ? this.phase : 'empty', hasPreedit: hasPre, preeditLen: hasPre ? out.preedit.length : 0,
      caretUtf16: hasPre ? this.caretPosition(out) : 0,
      segCount: hasPre ? (out.segcount > 0 ? out.segcount : 1) : 0,
      candidateCount: out.ncand, candidateRevision: this.revision, candidates: labels,
      effects: effects, errorCode: 0, errorRecoverable: true
    };
  }

  // A key typed with deferred suggestions. Keep showing the previous candidates
  // (stale: their revision no longer matches, so a tap on one is rejected)
  // until "suggest" replaces them. A pending roman letter cannot be suggested
  // by moving the cursor without breaking the next key, so "suggest" deletes
  // and retypes that letter instead; any other tail shows no candidates.
  private deferredUpdate(sessionId: string, epoch: number, seq: number, out: ConvOut,
    romanKey: string): EngineUpdate {
    const previousLabels: CandidateLabel[] = this.lastLabels;
    const previousRevision: number = this.lastCandidateRevision;
    const update: EngineUpdate = this.fromOut(sessionId, epoch, seq, out, []);
    const caret: number = this.caretPosition(out);
    if (caret !== out.preedit.length) { return update; }
    if (endsWithKana(out.preedit)) {
      this.retypeKey = '';
    } else if (romanKey.length > 0 && endsWithRomanKey(out.preedit, romanKey)) {
      this.retypeKey = romanKey;
    } else {
      return update;
    }
    this.suggestPending = true;
    this.lastIds = [];
    this.lastLabels = previousLabels;
    this.lastCandidateRevision = previousRevision;
    update.candidates = previousLabels;
    update.candidateCount = previousLabels.length;
    update.candidateRevision = previousRevision;
    return update;
  }

  private async suggest(sessionId: string, epoch: number, seq: number): Promise<EngineUpdate> {
    if (!this.needsSuggestion()) { return this.currentUpdate(sessionId, epoch, seq); }
    this.suggestPending = false;
    let out: ConvOut;
    try {
      out = parseOut(await this.bridge.executeAsync('suggest', this.retypeKey, codePointLength(this.lastPreedit)));
    } catch (e) {
      out = new ConvOut();
      out.ok = false;
    }
    const retyped: boolean = this.retypeKey.length > 0;
    this.retypeKey = '';
    // Moving the cursor leaves the composition as shown, so keep it on any
    // mismatch. A retype has already changed Mozc: show whatever it holds now.
    if (!out.ok) {
      return retyped ? this.errUpdate(sessionId, epoch, seq, true) : this.currentUpdate(sessionId, epoch, seq);
    }
    if (!retyped && out.preedit !== this.lastPreedit) { return this.currentUpdate(sessionId, epoch, seq); }
    if (out.preedit_len === 0) { this.phase = 'empty'; }
    this.revision++;
    return this.fromOut(sessionId, epoch, seq, out, []);
  }

  // The state as last shown, for a suggestion that no longer applies.
  private currentUpdate(sessionId: string, epoch: number, seq: number): EngineUpdate {
    const hasPre: boolean = this.phase !== 'empty' && this.lastPreedit.length > 0;
    return {
      sessionId: sessionId, editorEpoch: epoch, sequence: seq, revision: this.revision,
      consumed: true, phase: hasPre ? this.phase : 'empty', hasPreedit: hasPre,
      preeditLen: hasPre ? this.lastPreedit.length : 0, caretUtf16: hasPre ? this.caretPosition(this.lastOut) : 0,
      segCount: hasPre ? (this.lastOut.segcount > 0 ? this.lastOut.segcount : 1) : 0,
      candidateCount: this.lastLabels.length, candidateRevision: this.lastCandidateRevision,
      candidates: this.lastLabels, effects: [], errorCode: 0, errorRecoverable: true
    };
  }

  private acceptComposingOutput(sessionId: string, epoch: number, seq: number, out: ConvOut): EngineUpdate {
    this.inputUnits = [];
    this.buffer = out.preedit;
    this.editing.afterBackspace(out.preedit_len > 0);
    this.selIdx = 0;
    this.phase = out.preedit_len > 0 ? 'composing' : 'empty';
    this.revision++;
    return this.fromOut(sessionId, epoch, seq, out, []);
  }

  private async callConvert(keys: string, deferSuggestion: boolean = false): Promise<ConvOut> {
    const api: MozcBridgePort = this.bridge;
    try {
      return parseOut(await api.executeAsync('convert', keys, deferSuggestion ? 1 : 0));
    } catch (e) {
      const out = new ConvOut();
      out.ok = false;
      return out;
    }
  }

  private async callLiteral(text: string): Promise<ConvOut> {
    const api: MozcBridgePort = this.bridge;
    try {
      return parseOut(await api.executeAsync('literal', text, 0));
    } catch (e) {
      return new ConvOut();
    }
  }

  /** Replay typed units; UTF-8 literals must never go through the roman byte path. */
  private async replay(units: CompositionInput[]): Promise<ConvOut> {
    const api: MozcBridgePort = this.bridge;
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

  private async replaceToggle(event: ReplaceToggleEvent): Promise<ConvOut> {
    if (this.phase !== 'composing' || this.lastPreedit.length === 0) { return new ConvOut(); }
    const roman: string = kanaRoman(event.text);
    const unit: CompositionInput = new CompositionInput(roman || event.text, event.text, roman.length === 0);
    if (this.editing.canReplay()) {
      const last: CompositionInput | undefined = this.inputUnits[this.inputUnits.length - 1];
      if (last === undefined || (last.literal ? last.text : last.kana) !== event.previous) { return new ConvOut(); }
      const units: CompositionInput[] = this.inputUnits.slice(0, -1);
      units.push(unit);
      const out: ConvOut = await this.replay(units);
      if (out.ok) { this.setInputUnits(units); }
      else { await this.replay(this.inputUnits); }
      return out;
    }
    // After a caret move or deletion, the live composer owns the history.
    const caret: number = this.caretPosition(this.lastOut);
    if (caret === 0 || this.lastPreedit.charAt(caret - 1) !== event.previous) { return new ConvOut(); }
    const deleted: ConvOut = parseOut(await this.bridge.executeAsync('backspace', '', 0));
    if (!deleted.ok) { return deleted; }
    const out: ConvOut = unit.literal ? await this.callLiteral(unit.text) : await this.callConvert(unit.text);
    if (out.ok && out.result.length === 0) { this.buffer = out.preedit; return out; }
    if (!out.ok) {
      const original: string = kanaRoman(event.previous);
      if (original.length === 0) { await this.callLiteral(event.previous); }
      else { await this.callConvert(original); }
    }
    return new ConvOut();
  }

  /** 純粋Spaceキー（special_key=SPACE）。変換開始に使う。key_codeの空白では変換しない。 */
  private async callSpace(): Promise<ConvOut> {
    const api: MozcBridgePort = this.bridge;
    try {
      return parseOut(await api.executeAsync('space', '', 0));
    } catch (e) {
      const out = new ConvOut();
      out.ok = false;
      return out;
    }
  }

  async dispatch(sessionId: string, editorEpoch: number, sequence: number, event: InputEvent): Promise<EngineUpdate> {
    const ready: boolean = await this.ensure();
    if (!ready || this.bridge === null) {
      return this.errUpdate(sessionId, editorEpoch, sequence, event.kind === 'deleteCandidate');
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
        const api: MozcBridgePort = this.bridge;
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
    this.editing.reset();
  }

  private async dispatchInner(sessionId: string, epoch: number, seq: number, event: InputEvent): Promise<EngineUpdate> {
    const api: MozcBridgePort = this.bridge;
    const kind: string = event.kind;
    if (kind === 'suggest') { return await this.suggest(sessionId, epoch, seq); }
    // Any other operation replaces the composition the deferred candidates were for.
    this.suggestPending = false;
    this.retypeKey = '';
    if (kind === 'undo') {
      const out: ConvOut = parseOut(await api.undo());
      if (!out.ok) { return this.errUpdate(sessionId, epoch, seq, true); }
      if (out.deletion_offset === undefined && out.deletion_length === undefined) {
        // Echo-back and REWIND do not undo a commit.
        const unchanged: EngineUpdate = this.emptyUpdate(sessionId, epoch, seq);
        unchanged.consumed = false;
        return unchanged;
      }
      this.buffer = out.preedit;
      this.inputUnits = [];
      this.phase = out.preedit_len === 0 ? 'empty' : out.focused_id === undefined ? 'composing' : 'converting';
      this.editing.afterBackspace(out.preedit_len > 0);
      this.selIdx = 0;
      this.revision++;
      const restored: EngineUpdate = this.fromOut(sessionId, epoch, seq, out, []);
      restored.deletionOffset = out.deletion_offset;
      restored.deletionLength = out.deletion_length;
      return restored;
    }
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
      this.editing.reset();
      if (kind === 'reset') {
        this.revision = 0;
      } else {
        this.revision++;
      }
      this.phase = 'empty';
      return this.emptyUpdate(sessionId, epoch, seq);
    }
    if (kind === 'replaceToggle') {
      const out: ConvOut = await this.replaceToggle(event as ReplaceToggleEvent);
      if (!out.ok) { return this.errUpdate(sessionId, epoch, seq, true); }
      this.revision++;
      return this.fromOut(sessionId, epoch, seq, out, []);
    }
    if (kind === 'modifyKana') {
      const modifier: KanaModifier | undefined = (event as ModifyKanaInputEvent).text;
      if (this.buffer.length === 0 && this.lastPreedit.length === 0) {
        return this.emptyUpdate(sessionId, epoch, seq);
      }
      // Partial commit makes the old replay history unusable, but it does not
      // forbid editing kana in the remaining live composition.
      if (this.phase !== 'composing') {
        return this.fromOut(sessionId, epoch, seq, this.lastOut, []);
      }
      if (!this.editing.canReplay()) {
        const caret: number = this.caretPosition(this.lastOut);
        const previous: string = this.lastPreedit.slice(Math.max(0, caret - 1), caret);
        const kana: string = modifiedKana(previous, modifier);
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
      const previous: string = this.inputUnits[last].kana;
      const kana: string = modifiedKana(previous, modifier);
      const roman: string = kanaRoman(kana);
      if (kana !== previous && roman.length > 0) {
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
      const t: string = (event as TextInputEvent).text;
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
      // Defer candidates only for keys typed at the end of a composition.
      const atEnd: boolean = this.phase === 'empty' ||
        (this.phase === 'composing' && this.caretPosition(this.lastOut) === this.lastPreedit.length);
      const deferred: boolean = this.deferSuggestions && !literal && !retainConversion && atEnd;
      const out: ConvOut = literal ? await this.callLiteral(t) : await this.callConvert(unit, deferred);
      if (!out.ok) { return this.errUpdate(sessionId, epoch, seq, true); }
      const effects: CommitEffect[] = [];
      if (out.result.length > 0) {
        // Mozc may commit an existing conversion when ordinary roman input
        // starts the next composition. Never silently discard that result.
        effects.push({ effectId: `t${seq}`, text: out.result });
        units = [];
      }
      this.editing.afterInput(retainConversion, out.result.length > 0, out.preedit_len > 0);
      if (literal) {
        units = units.concat(literalInputs(t));
      } else if (kind === 'text') {
        // Keep one replayable unit per key, also for keys merged into one call.
        for (let i: number = 0; i < unit.length; i++) { units.push(new CompositionInput(unit.charAt(i), '')); }
      } else {
        units.push(new CompositionInput(unit, kind === 'kana' ? t : ''));
      }
      this.setInputUnits(units);
      if (!this.editing.canReplay()) {
        this.inputUnits = [];
        this.buffer = out.preedit;
      }
      this.selIdx = 0;
      this.phase = out.preedit_len > 0 ? 'composing' : 'empty';
      if (this.phase === 'empty') { this.setInputUnits([]); }
      this.revision++;
      if (!deferred || this.phase !== 'composing' || effects.length > 0) {
        return this.fromOut(sessionId, epoch, seq, out, effects);
      }
      return this.deferredUpdate(sessionId, epoch, seq, out, kind === 'text' ? unit.charAt(unit.length - 1) : '');
    }
    if (kind === 'deleteCandidate') {
      const id: number = (event as CandidateInputEvent).candidateId;
      if (this.phase === 'empty' || !this.lastIds.includes(id)) {
        return this.errUpdate(sessionId, epoch, seq, true);
      }
      // Mozc clears conversion learning for the segment's top candidate (id 0) whichever id is sent,
      // so only the top candidate or a learned prediction may be deleted without touching another word.
      const target: Cand | undefined = this.lastOut.candidates.find((c: Cand): boolean => c.id === id);
      if (id !== 0 && target?.deletable !== true) {
        const skipped: EngineUpdate = this.errUpdate(sessionId, epoch, seq, true);
        skipped.candidateNotLearned = true;
        return skipped;
      }
      const out: ConvOut = parseOut(await api.executeAsync('deleteCandidate', '', id));
      if (out.candidate_not_learned) {
        const update: EngineUpdate = this.errUpdate(sessionId, epoch, seq, true);
        update.candidateNotLearned = true;
        return update;
      }
      if (!out.ok || out.preedit_len === 0 || out.result.length > 0) {
        return this.errUpdate(sessionId, epoch, seq, true);
      }
      return this.acceptComposingOutput(sessionId, epoch, seq, out);
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
      return this.acceptComposingOutput(sessionId, epoch, seq, out);
    }
    if (kind === 'compositionCursor') {
      const text: string = this.lastPreedit;
      const caret: number = this.caretPosition(this.lastOut);
      const path: number[] | undefined = compositionCaretPath(text, caret, (event as CompositionCursorEvent).cursor);
      if (this.phase !== 'composing' || text.length === 0 || path === undefined) {
        return this.errUpdate(sessionId, epoch, seq, true);
      }
      if (path.length === 0) { return this.fromOut(sessionId, epoch, seq, this.lastOut, []); }
      const operation: string = (event as CompositionCursorEvent).cursor < caret ? 'arrowLeft' : 'arrowRight';
      let out: ConvOut = this.lastOut;
      for (const position of path) {
        try { out = parseOut(await api.executeAsync(operation, '', 0)); }
        catch (error) { return this.errUpdate(sessionId, epoch, seq, false); }
        if (!out.ok || out.result.length > 0 || out.preedit_len === 0 ||
          out.preedit !== text || this.caretPosition(out) !== position) {
          // A command was issued, so an unverified native cursor must not accept the next key.
          return this.errUpdate(sessionId, epoch, seq, false);
        }
        this.lastOut = out;
      }
      this.editing.afterArrow(this.phase);
      this.inputUnits = [];
      this.buffer = out.preedit;
      this.selIdx = 0;
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
      this.editing.afterArrow(this.phase);
      if (this.phase !== 'converting') {
        // An insertion cursor makes the original append-only history obsolete.
        this.inputUnits = [];
        this.buffer = out.preedit;
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
    const scopedSelection: boolean = kind === 'select' && this.editing.scopesCandidate(this.phase);
    if (kind === 'select' && !scopedSelection) {
      let id: number = (event as CandidateInputEvent).candidateId;
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
      this.editing.reset();
      this.revision++;
      const effects: CommitEffect[] = [];
      if (done.ok && done.result.length > 0) {
        effects.push({ effectId: `s${this.revision}`, text: done.result, undoable: true });
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
      const id: number = scopedSelection ?
        (event as CandidateInputEvent).candidateId : this.lastIds[this.selIdx];
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
      const hasRemaining: boolean = remaining.preedit_len > 0;
      this.editing.afterPartialCommit(hasRemaining);
      // Suggestions for the remaining reading do not imply conversion state.
      this.phase = !hasRemaining ? 'empty' : remaining.focused_id !== undefined ? 'converting' : 'composing';
      this.selIdx = 0;
      this.revision++;
      const effects: CommitEffect[] = [];
      if (part.result.length > 0) {
        effects.push({ effectId: `p${this.revision}`, text: part.result, undoable: true });
      }
      return this.fromOut(sessionId, epoch, seq, remaining, effects);
    }
    if (kind === 'submit' || kind === 'enter') {
      if (this.buffer.length === 0 && this.lastPreedit.length === 0) {
        return this.emptyUpdate(sessionId, epoch, seq);
      }
      if (this.phase === 'composing' && this.buffer.length > 0) {
        // Use the session command to keep the undo context. The Enter key
        // path for unconverted input previously crashed on device.
        let done: ConvOut = new ConvOut();
        try { done = parseOut(await api.executeAsync('submitReading', '', 0)); } catch (error) { }
        const effects: CommitEffect[] = [];
        if (this.lastPreedit.length > 0) {
          // Keep the exact displayed reading, including pending roman input.
          effects.push({ effectId: `k${this.revision + 1}`, text: this.lastPreedit,
            undoable: done.ok && done.result === this.lastPreedit });
        }
        this.buffer = '';
        this.inputUnits = [];
        this.lastIds = [];
        this.selIdx = 0;
        this.lastPreedit = '';
        this.phase = 'empty';
        this.editing.reset();
        if (!done.ok || effects.length === 0 || !effects[0].undoable) {
          try { await api.executeAsync('reset', '', 0); } catch (error) { }
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
      this.editing.reset();
      this.revision++;
      const effects: CommitEffect[] = [];
      if (done.ok && done.result.length > 0) {
        effects.push({ effectId: `c${this.revision}`, text: done.result, undoable: true });
      }
      const u: EngineUpdate = this.emptyUpdate(sessionId, epoch, seq);
      u.effects = effects;
      return u;
    }
    return this.emptyUpdate(sessionId, epoch, seq);
  }
}
