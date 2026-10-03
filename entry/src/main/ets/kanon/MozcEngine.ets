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
  private inputUnits: string[] = [];
  private kanaUnits: string[] = [];
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
    this.kanaUnits = [];
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
      this.kanaUnits = [];
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
      if (this.phase !== 'composing' || this.partial || this.kanaUnits.length === 0) {
        return this.fromOut(sessionId, epoch, seq, this.lastOut, []);
      }
      const last: number = this.kanaUnits.length - 1;
      const kana: string = modifiedKana(this.kanaUnits[last]);
      const roman: string = kanaRoman(kana);
      if (roman.length > 0) {
        this.kanaUnits[last] = kana;
        this.inputUnits[last] = roman;
        this.buffer = this.inputUnits.join('');
        await api.executeAsync('reset', '', 0);
        this.revision++;
        return this.fromOut(sessionId, epoch, seq, await this.callConvert(this.buffer), []);
      }
      return this.fromOut(sessionId, epoch, seq, this.lastOut, []);
    }
    if (kind === 'text' || kind === 'kana') {
      const t: string = event.text ? event.text as string : '';
      if (t.length === 0) {
        return this.emptyUpdate(sessionId, epoch, seq);
      }
      const roman: string = kind === 'kana' ? kanaRoman(t) : '';
      if (!isRomanLower(t) && roman.length === 0) {
        // 数字・記号・大文字は未確定へ混ぜず直接効果にする。保留があれば先に確定する。
        const effects: CommitEffect[] = [];
        if (this.buffer.length > 0) {
          let committed: string = '';
          if (this.phase === 'composing' && this.lastPreedit.length > 0) {
            committed = this.lastPreedit;
            await api.executeAsync('reset', '', 0);
          } else {
            const flushed: ConvOut = parseOut(await api.executeAsync('submit', '', 0));
            if (flushed.ok) { committed = flushed.result; }
          }
          // An empty commit must not discard the pending reading when punctuation is entered.
          if (committed.length === 0) { return this.errUpdate(sessionId, epoch, seq, true); }
          effects.push({ effectId: `f${this.revision}`, text: committed });
          this.buffer = '';
          this.inputUnits = [];
          this.kanaUnits = [];
          this.lastIds = [];
          this.selIdx = 0;
          this.lastPreedit = '';
          this.partial = false;
        }
        effects.push({ effectId: `d${seq}`, text: t });
        this.revision++;
        this.phase = 'empty';
        const u: EngineUpdate = this.emptyUpdate(sessionId, epoch, seq);
        u.effects = effects;
        return u;
      }
      const unit: string = roman.length > 0 ? roman : t;
      this.inputUnits.push(unit);
      this.kanaUnits.push(kind === 'kana' ? t : '');
      this.buffer += unit;
      const out: ConvOut = await this.callConvert(unit);
      this.selIdx = 0;
      this.phase = this.buffer.length > 0 ? 'composing' : 'empty';
      this.revision++;
      return this.fromOut(sessionId, epoch, seq, out, []);
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
          this.kanaUnits = [];
          this.partial = false;
          this.phase = 'empty';
        }
        this.selIdx = 0;
        this.revision++;
        return this.fromOut(sessionId, epoch, seq, out, []);
      }
      this.inputUnits.pop();
      this.kanaUnits.pop();
      this.buffer = this.inputUnits.join('');
      try {
        await api.executeAsync('reset', '', 0);
      } catch (e) {
      }
      let out: ConvOut = new ConvOut();
      out.ok = true;
      if (this.buffer.length > 0) {
        out = await this.callConvert(this.buffer);
      } else {
        this.lastPreedit = '';
        this.lastIds = [];
      }
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
        // SELECT_CANDIDATE は Mozc 側で候補欄を閉じるため、巡回中は呼ばない。
        this.selIdx = (this.selIdx + 1) % this.lastIds.length;
        this.revision++;
        const u: EngineUpdate = this.fromOut(sessionId, epoch, seq, this.lastOut, []);
        const selected: string = this.lastOut.candidates[this.selIdx].value;
        this.lastPreedit = selected;
        u.hasPreedit = selected.length > 0;
        u.preeditLen = selected.length;
        u.caretUtf16 = selected.length;
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
      this.kanaUnits = [];
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
    if (kind === 'partial') {
      // 先頭文節のみ確定し、残り読みは未確定のまま続ける（AT-10）。
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
      if (!part.ok) {
        this.revision++;
        return this.errUpdate(sessionId, epoch, seq, true);
      }
      this.partial = true;
      this.phase = part.ncand > 0 ? 'converting' : 'composing';
      this.selIdx = 0;
      this.revision++;
      const effects: CommitEffect[] = [];
      if (part.result.length > 0) {
        effects.push({ effectId: `p${this.revision}`, text: part.result });
      }
      return this.fromOut(sessionId, epoch, seq, part, effects);
    }
    if (kind === 'submit') {
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
        this.kanaUnits = [];
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
      this.kanaUnits = [];
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
