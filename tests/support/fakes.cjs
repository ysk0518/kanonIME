const assert = require('node:assert/strict');

function response(preedit = '', options = {}) {
  const candidates = options.candidates ?? [];
  return JSON.stringify({ ok: true, preedit_len: Buffer.byteLength(preedit), preedit,
    ncand: candidates.length, candidates, result: '', segcount: preedit ? 1 : 0, ...options });
}

// Fixed protocol responses, not a second implementation of roman conversion.
class ScriptedBridge {
  constructor(steps = [], ready = true) { this.steps = [...steps]; this.calls = []; this.ready = ready; }
  async prepare() { return this.ready; }
  async executeAsync(operation, text, candidateId) {
    const call = { operation, text, candidateId };
    this.calls.push(call);
    const step = this.steps.shift();
    assert.ok(step, `Unexpected bridge operation: ${operation}`);
    assert.equal(operation, step.operation);
    if (step.text !== undefined) { assert.equal(text, step.text); }
    if (step.candidateId !== undefined) { assert.equal(candidateId, step.candidateId); }
    if (step.error) { throw step.error; }
    return typeof step.output === 'function' ? step.output(call) : step.output;
  }
  assertDone() { assert.equal(this.steps.length, 0, 'Bridge script was not fully consumed'); }
}

// Editor contract model. Preview text is visible inside text, but remains uncommitted.
class FakeEditor {
  constructor(text = '', cursor = text.length) {
    this.text = text; this.cursor = cursor; this.epoch = 1;
    this.preview = null; this.selection = null; this.calls = [];
    this.supported = true; this.failInsert = false; this.caretMatches = true;
    this.beforeResult = undefined;
  }
  getEpoch() { return this.epoch; }
  hasSelection() { return this.selection !== null && this.selection.start !== this.selection.end; }
  async queryPreviewSupported() { return this.supported; }
  async queryCursor() { return this.cursor; }
  async queryBefore(length) { return this.text.slice(Math.max(0, this.cursor - length), this.cursor); }
  async queryBeforeResult(length) {
    return this.beforeResult ?? { ok: true, code: 0, value: await this.queryBefore(length) };
  }
  async setPreview(text, start, end) {
    this.calls.push({ operation: 'setPreview', text, start, end });
    assert.deepEqual([start, end], [-1, -1]);
    const from = this.preview?.start ?? (this.hasSelection() ? Math.min(this.selection.start,this.selection.end) : this.cursor);
    const to = this.preview?.end ?? (this.hasSelection() ? Math.max(this.selection.start,this.selection.end) : this.cursor);
    this.text = this.text.slice(0, from) + text + this.text.slice(to);
    this.cursor = from + text.length; this.selection = null;
    // An empty preview still has a session until finishPreview/insert closes it.
    this.preview = { start: from, end: this.cursor };
    return { ok: true, code: 0 };
  }
  async insert(text) {
    this.calls.push({ operation: 'insert', text });
    if (this.failInsert) { return { ok: false, code: 12800003 }; }
    const from = this.preview?.start ?? this.cursor;
    const to = this.preview?.end ?? this.cursor;
    this.text = this.text.slice(0, from) + text + this.text.slice(to);
    this.cursor = from + text.length; this.preview = null;
    return { ok: true, code: 0 };
  }
  async finishPreview() { this.calls.push({ operation: 'finishPreview' }); this.preview = null; return { ok: true, code: 0 }; }
  async previewCaret(position) {
    this.calls.push({ operation: 'previewCaret', position });
    if (!this.caretMatches) { return { ok: false, code: -7 }; }
    this.cursor = position; return { ok: true, code: 0 };
  }
  async selectRange(start, end) {
    this.calls.push({ operation: 'selectRange', start, end });
    this.selection = { start, end }; this.cursor = end; return { ok: true, code: 0 };
  }
  async moveCursor(direction) { this.calls.push({ operation: 'moveCursor', direction }); return { ok: true, code: 0 }; }
  async selectByMovement(direction) { this.calls.push({ operation: 'selectByMovement', direction }); return { ok: true, code: 0 }; }
  async selectAll() { return this.selectRange(0, this.text.length); }
  async deleteForward(length) {
    this.calls.push({ operation: 'deleteForward', length });
    const from = this.hasSelection() ? this.selection.start : Math.max(0, this.cursor - length);
    const to = this.hasSelection() ? this.selection.end : this.cursor;
    this.text = this.text.slice(0, from) + this.text.slice(to); this.cursor = from; this.selection = null;
    return { ok: true, code: 0 };
  }
  async deleteBackward(length) {
    this.calls.push({ operation: 'deleteBackward', length });
    this.text = this.text.slice(0, this.cursor) + this.text.slice(this.cursor + length);
    return { ok: true, code: 0 };
  }
  count(operation) { return this.calls.filter(call => call.operation === operation).length; }
}

function update(sessionId, epoch, sequence, options = {}) {
  const preeditLen = options.preeditLen ?? 0;
  return { sessionId, editorEpoch: epoch, sequence, revision: sequence, consumed: true,
    phase: preeditLen > 0 ? 'composing' : 'empty',
    hasPreedit: preeditLen > 0, preeditLen, caretUtf16: preeditLen,
    segCount: preeditLen ? 1 : 0, candidateCount: 0, candidateRevision: sequence,
    candidates: [], effects: [], errorCode: 0, errorRecoverable: true, ...options };
}

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

module.exports = { response, ScriptedBridge, FakeEditor, update, deferred };
