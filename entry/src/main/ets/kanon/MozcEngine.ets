/*
 * Kanon IME: MozcEngine (M4)
 * libkanon_bridge.soをCoordinatorのEnginePort面へ包む。IPC不使用・同一プロセス。
 * - ローマ字バッファを自前で保持し、Backspaceはreset＋再送で実現する。
 * - Spaceは空欄で半角空白効果、未確定ありで変換開始、変換中で次候補。
 * - 候補タップ(select)は選択＋確定を合成する（AT-16のSpaceなし確定用）。
 * - 効果テキスト・候補labelはメモリ内のみ。ログに出さない（REQ-07）。
 */

import { CandidateLabel, CommitEffect, EnginePort, EngineUpdate, UiEvent } from './ImeCoordinator';
import { kanaRoman, modifiedKana } from './KanaInput';
import { CompositionInput, literalInputs } from './CompositionInput';

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

  /** 強調中の候補位置（診断表示用）。 */
  getSelIdx(): number {
    return this.selIdx;
  }

  /** 予測表示用。メモリ内のみ。 */
  getPreedit(): string {
    return this.lastPreedit;
  }

  /** 直近の候補長さ列（診断用・数値のみ）。 */
  getLastLens(): string {
    return this.lastLens;
  }

  private async ensure(): Promise<boolean> {
    if (this.bridge !== null) {
      return true;
    }
    if (this.initFailed) {
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
        ok = parseOut(await api.executeAsync('init', '', 0)).ok;
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
    this.lastPreedit = out.preedit;
    this.lastLens = out.candlens.join(',');
    const hasPre: boolean = out.preedit_len > 0;
    return {
      sessionId: sessionId, editorEpoch: epoch, sequence: seq, revision: this.revision,
      consumed: true, hasPreedit: hasPre, preeditLen: hasPre ? out.preedit.length : 0,
      caretUtf16: hasPre ? out.preedit.length : 0,
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
      if (this.phase !== 'composing' || this.partial || this.inputUnits.length === 0) {
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
      }
      if (literal) {
        units = units.concat(literalInputs(t));
      } else {
        units.push(new CompositionInput(unit, kind === 'kana' ? t : ''));
      }
      this.setInputUnits(units);
      if (retainConversion) { this.partial = false; }
      this.selIdx = 0;
      this.phase = out.preedit_len > 0 ? 'composing' : 'empty';
      if (this.phase === 'empty') { this.setInputUnits([]); }
      this.revision++;
      return this.fromOut(sessionId, epoch, seq, out, effects);
    }
    if (kind === 'backspace') {
      if (this.buffer.length === 0) {
        return this.emptyUpdate(sessionId, epoch, seq);
      }
      if (this.partial) {
        // 部分確定後の残り読みはbuffer再送できない。セッション内削除に回す。
        const bapi: BridgeApi = this.bridge as BridgeApi;
        let out: ConvOut = new ConvOut();
        out.ok = false;
        try {
          out = parseOut(await bapi.executeAsync('backspace', '', 0));
        } catch (e) {
          out.ok = false;
        }
        if (!out.ok) {
          this.revision++;
          return this.errUpdate(sessionId, epoch, seq, true);
        }
        if (out.preedit_len === 0) {
          this.buffer = '';
          this.inputUnits = [];
          this.partial = false;
          this.phase = 'empty';
        }
        this.selIdx = 0;
        this.revision++;
        return this.fromOut(sessionId, epoch, seq, out, []);
      }
      const units: CompositionInput[] = this.inputUnits.slice(0, -1);
      const out: ConvOut = await this.replay(units);
      if (!out.ok) {
        await this.replay(this.inputUnits);
        return this.errUpdate(sessionId, epoch, seq, true);
      }
      this.setInputUnits(units);
      this.selIdx = 0;
      this.phase = this.buffer.length > 0 ? 'composing' : 'empty';
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
    if (kind === 'select') {
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
    if (kind === 'partial' || (kind === 'enter' && this.phase === 'converting')) {
      // Enter during conversion shares the segment-commit path. Submit is
      // still the full commit used by layout changes, paste and cursor moves.
      if (this.phase !== 'converting' || this.lastIds.length === 0 ||
        this.selIdx >= this.lastIds.length) {
        this.revision++;
        return this.emptyUpdate(sessionId, epoch, seq);
      }
      const id: number = this.lastIds[this.selIdx];
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
      // Discard consumed input history: only Mozc owns the remaining reading.
      this.inputUnits = [];
      this.buffer = part.preedit;
      this.partial = part.preedit_len > 0;
      this.phase = !this.partial ? 'empty' : part.ncand > 0 ? 'converting' : 'composing';
      this.selIdx = 0;
      this.revision++;
      const effects: CommitEffect[] = [];
      if (part.result.length > 0) {
        effects.push({ effectId: `p${this.revision}`, text: part.result });
      }
      return this.fromOut(sessionId, epoch, seq, part, effects);
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
