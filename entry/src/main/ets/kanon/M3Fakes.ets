/*
 * Kanon IME: FakeEditor / FakeEngine (M3)
 * SPEC §10-4: 順序・失敗・入力先変更の試験用偽物。変換結果の単体試験とは別物。
 * - 記録するのは操作名・長さ・符号のみ。本文・候補内容は保持も記録もしない（REQ-07）。
 * - 固定fixtureの文字（'あ'等）を使う。端末内の実文章は使わない。
 */

import { CommitEffect, EditorPort, EnginePort, EngineUpdate, OpResult, UiEvent } from './ImeCoordinator';

export class FakeEditor implements EditorPort {
  private epoch: number = 1;
  /** 'op' または 'op:len' 形式の操作記録。本文なし。 */
  ops: string[] = [];
  /** 次の書き込み系操作を失敗させる回数。 */
  failNextWrites: number = 0;
  failCode: number = 12800001;
  /** trueでクライアント不在扱い（全操作no-client）。 */
  noClient: boolean = false;
  previewSupported: boolean = true;
  /** 書き込み系の前に挟む遅延ms。順序試験用。 */
  writeDelayMs: number = 0;
  /** カーソル直前の仮の本文（固定fixtureのみ。件数・末尾判定用）。 */
  beforeText: string = 'x';
  /** 仮のカーソル位置（UTF-16）。 */
  cursorPos: number = 0;

  getEpoch(): number {
    return this.epoch;
  }

  /** 入力先変更の模擬。世代を進める（REQ-02）。 */
  bumpEpoch(): number {
    this.epoch++;
    return this.epoch;
  }

  count(opPrefix: string): number {
    let n: number = 0;
    for (let i: number = 0; i < this.ops.length; i++) {
      if (this.ops[i] === opPrefix || this.ops[i].indexOf(opPrefix + ':') === 0) {
        n++;
      }
    }
    return n;
  }

  clear(): void {
    this.ops = [];
  }

  private async delay(): Promise<void> {
    if (this.writeDelayMs > 0) {
      await new Promise<void>((resolve: () => void) => {
        setTimeout((): void => {
          resolve();
        }, this.writeDelayMs);
      });
    }
  }

  private async writeOp(op: string, len: number): Promise<OpResult> {
    await this.delay();
    if (this.noClient) {
      this.ops.push(`${op}:no-client`);
      return { ok: false, code: -1 };
    }
    if (this.failNextWrites > 0) {
      this.failNextWrites--;
      this.ops.push(`${op}:fail-${this.failCode}`);
      return { ok: false, code: this.failCode };
    }
    this.ops.push(`${op}:${len}`);
    return { ok: true, code: 0 };
  }

  async setPreview(text: string, start: number, end: number): Promise<OpResult> {
    return this.writeOp('setPreview', text.length);
  }

  async finishPreview(): Promise<OpResult> {
    return this.writeOp('finish', 0);
  }

  async insert(text: string): Promise<OpResult> {
    return this.writeOp('insert', text.length);
  }

  async deleteForward(length: number): Promise<OpResult> {
    const r: OpResult = await this.writeOp('deleteFwd', length);
    if (r.ok && this.beforeText.length > 0) {
      const n: number = length > this.beforeText.length ? this.beforeText.length : length;
      this.beforeText = this.beforeText.substring(0, this.beforeText.length - n);
      this.cursorPos = this.beforeText.length;
    }
    return r;
  }

  async moveCursor(direction: number): Promise<OpResult> {
    return this.writeOp('moveCursor', direction);
  }

  async selectRange(start: number, end: number): Promise<OpResult> {
    this.ops.push(`selectRange:${start}-${end}`);
    return { ok: true, code: 0 };
  }

  async queryPreviewSupported(): Promise<boolean> {
    return this.previewSupported;
  }

  async queryCursor(): Promise<number> {
    return this.cursorPos;
  }

  async queryBefore(length: number): Promise<string> {
    if (this.beforeText.length <= length) {
      return this.beforeText;
    }
    return this.beforeText.substring(this.beforeText.length - length);
  }
}

/** FakeEngineの応答スクリプト1件。 */
export interface ScriptedReply {
  /** 応答前の遅延ms。 */
  delayMs: number;
  revision: number;
  hasPreedit: boolean;
  preeditLen: number;
  candidateCount: number;
  /** 効果のID列。テキストは固定fixture（'あ'×len相当の長さのみ使う）。 */
  effectIds: string[];
  effectTextLen: number;
  errorCode: number;
  errorRecoverable: boolean;
  /** trueでdispatch自体がthrow（到達不能エンジンの模擬）。 */
  throws: boolean;
}

export function reply(revision: number, hasPreedit: boolean, preeditLen: number,
  candidateCount: number, effectIds: string[], effectTextLen: number): ScriptedReply {
  return {
    delayMs: 0, revision: revision, hasPreedit: hasPreedit, preeditLen: preeditLen,
    candidateCount: candidateCount, effectIds: effectIds, effectTextLen: effectTextLen,
    errorCode: 0, errorRecoverable: true, throws: false
  };
}

export function replyError(code: number, recoverable: boolean): ScriptedReply {
  return {
    delayMs: 0, revision: 0, hasPreedit: false, preeditLen: 0, candidateCount: 0,
    effectIds: [], effectTextLen: 0, errorCode: code, errorRecoverable: recoverable, throws: false
  };
}

/** 固定fixtureの効果テキスト。長さだけが意味を持つ。 */
const FIX_EFFECT_TEXT: string = 'あいうえおかきくけこ';

function effectText(len: number): string {
  if (len <= 0) {
    return '';
  }
  let s: string = '';
  while (s.length < len) {
    s += FIX_EFFECT_TEXT;
  }
  return s.substring(0, len);
}

export class FakeEngine implements EnginePort {
  /** 受信イベントの記録。'seq:kind'形式。順序検証用（REQ-05）。 */
  received: string[] = [];
  /** dispatch呼び出しごとに消費する応答キュー。空なら最終応答を繰り返す。 */
  script: ScriptedReply[] = [];
  lastReply: ScriptedReply = reply(0, false, 0, 0, [], 0);

  setScript(items: ScriptedReply[]): void {
    this.script = items.slice(0, items.length);
  }

  /** 閉じている間dispatchが返らないゲート。古い応答の遅延到着を再現する。 */
  private gate: Promise<void> | undefined = undefined;
  private gateResolve: (() => void) | undefined = undefined;

  /** ゲートを閉じる。releaseHeld()までdispatchが返らない。 */
  hold(): void {
    if (this.gate === undefined) {
      this.gate = new Promise<void>((resolve: () => void) => {
        this.gateResolve = resolve;
      });
    }
  }

  releaseHeld(): void {
    if (this.gateResolve !== undefined) {
      const r: () => void = this.gateResolve as () => void;
      this.gate = undefined;
      this.gateResolve = undefined;
      r();
    }
  }

  async dispatch(sessionId: string, editorEpoch: number, sequence: number, event: UiEvent): Promise<EngineUpdate> {
    this.received.push(`${sequence}:${event.kind}`);
    let rep: ScriptedReply;
    if (this.script.length > 0) {
      const first: ScriptedReply | undefined = this.script.shift();
      rep = first === undefined ? this.lastReply : first;
      this.lastReply = rep;
    } else {
      rep = this.lastReply;
    }
    if (rep.throws) {
      throw new Error('fake-engine-throw');
    }
    if (rep.delayMs > 0) {
      await new Promise<void>((resolve: () => void) => {
        setTimeout((): void => {
          resolve();
        }, rep.delayMs);
      });
    }
    if (this.gate !== undefined) {
      const g: Promise<void> = this.gate as Promise<void>;
      await g;
    }
    const effects: CommitEffect[] = [];
    for (let i: number = 0; i < rep.effectIds.length; i++) {
      effects.push({ effectId: rep.effectIds[i], text: effectText(rep.effectTextLen) });
    }
    return {
      sessionId: sessionId,
      editorEpoch: editorEpoch,
      sequence: sequence,
      revision: rep.revision,
      consumed: true,
      hasPreedit: rep.hasPreedit,
      preeditLen: rep.preeditLen,
      caretUtf16: rep.preeditLen,
      segCount: rep.hasPreedit ? 1 : 0,
      candidateCount: rep.candidateCount,
      candidateRevision: rep.revision,
      candidates: [],
      effects: effects,
      errorCode: rep.errorCode,
      errorRecoverable: rep.errorRecoverable
    };
  }
}
