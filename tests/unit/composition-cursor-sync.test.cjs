const test = require('node:test');
const assert = require('node:assert/strict');
const { CompositionCursorSync, compositionCaretPath } = require('../../entry/src/main/ets/kanon/CompositionCursorSync.ets');
const { MozcEngine } = require('../../entry/src/main/ets/kanon/MozcEngine.ets');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { CompositionPreview } = require('../../entry/src/main/ets/kanon/CompositionPreview.ets');
const { validInputEvent } = require('../../entry/src/main/ets/kanon/InputEventContract.ets');
const { InputOperationQueue } = require('../../entry/src/main/ets/kanon/InputOperationQueue.ets');
const { ScriptedBridge, FakeEditor, response, deferred } = require('../support/fakes.cjs');

const context = { composing: true, cursorAligned: true, start: 0, previewLength: 2, text: 'かき', caret: 2 };
function rig() {
  const state = { epoch: 1, selected: false, position: 2, reads: 0, moves: [], ok: true };
  const port = { getEpoch: () => state.epoch, hasSelection: () => state.selected,
    queryCursor: async () => { state.reads++; return state.position; },
    alignCursor: async position => { state.moves.push(position); return state.ok; } };
  const sync = new CompositionCursorSync(port);
  return { state, port, sync };
}

test('P20: caret paths use UTF-16 boundaries in both directions', () => {
  assert.deepEqual(compositionCaretPath('かきく', 3, 0), [2, 1, 0]);
  assert.deepEqual(compositionCaretPath('かきく', 0, 3), [1, 2, 3]);
  assert.deepEqual(compositionCaretPath('かき', 1, 1), []);
});
test('P20: one supplementary character requires one native arrow', () => {
  assert.deepEqual(compositionCaretPath('a😀b', 4, 0), [3, 1, 0]);
  assert.deepEqual(compositionCaretPath('a😀b', 0, 4), [1, 3, 4]);
});
test('P20: invalid and surrogate-interior positions are rejected', () => {
  for (const position of [-1, 5, 2, NaN, Infinity, 0.5]) {
    assert.equal(compositionCaretPath('a😀b', 4, position), undefined);
    assert.equal(compositionCaretPath('a😀b', position, 4), undefined);
  }
});
test('P20: composition cursor events require a nonnegative integer payload', () => {
  for (const cursor of [0, 1, 4]) { assert.equal(validInputEvent({ kind: 'compositionCursor', cursor }), true); }
  for (const cursor of [undefined, -1, NaN, Infinity, 1.5]) {
    assert.equal(validInputEvent({ kind: 'compositionCursor', cursor }), false);
  }
});
test('P20: no notification performs no editor read or engine operation', async () => {
  const { sync, state } = rig();
  assert.equal(await sync.reconcile(context), 'ignored');
  assert.equal(state.reads, 0); assert.deepEqual(state.moves, []);
});
test('P20: selection hint for an empty field is not applied to the next new composition', async () => {
  const { sync, state } = rig(); sync.notify(1); state.position = 0;
  assert.equal(await sync.reconcile({ ...context, composing: false, previewLength: 0 }), 'ignored');
  assert.equal(await sync.reconcile(context), 'ignored');
  assert.equal(state.reads, 0); assert.deepEqual(state.moves, []);
});
test('P20: conversion, unknown preview and range selections are excluded', async () => {
  for (const patch of [{ composing: false }, { start: -1 }, { previewLength: 0 }, { previewLength: 1 }]) {
    const { sync, state } = rig(); sync.notify(1);
    assert.equal(await sync.reconcile({ ...context, ...patch }), 'ignored');
    assert.equal(state.reads, 0);
  }
  const { sync, state } = rig(); sync.notify(1); state.selected = true;
  assert.equal(await sync.reconcile(context), 'ignored'); assert.equal(state.reads, 0);
});
test('P20: delayed own notification with matching readback does not move the engine', async () => {
  const { sync, state } = rig(); sync.notify(1);
  assert.equal(await sync.reconcile(context), 'unchanged');
  assert.equal(await sync.reconcile(context), 'ignored');
  assert.equal(state.reads, 1); assert.deepEqual(state.moves, []);
});

test('P21: an unconfirmed own caret placement cannot move the engine to the editor end', async () => {
  const { sync, state } = rig(); sync.notify(1); state.position = 3;
  assert.equal(await sync.reconcile({ ...context, text: 'かｓき', previewLength: 3,
    caret: 2, cursorAligned: false }), 'ignored');
  assert.equal(state.reads, 0); assert.deepEqual(state.moves, []);
  // Do not carry the ignored hint into a later successful preview.
  assert.equal(await sync.reconcile(context), 'ignored');
});

test('P21: a fresh hint after confirmed caret placement resumes external tap synchronization', async () => {
  const { sync, state } = rig(); sync.notify(1);
  assert.equal(await sync.reconcile({ ...context, cursorAligned: false }), 'ignored');
  sync.notify(1); state.position = 0;
  assert.equal(await sync.reconcile(context), 'aligned');
  assert.deepEqual(state.moves, [0]);
});
test('P20: external tap is aligned from current readback, including position zero', async () => {
  const { sync, state } = rig(); sync.notify(1); state.position = 0;
  assert.equal(await sync.reconcile(context), 'aligned');
  assert.deepEqual(state.moves, [0]);
});
test('P20: partial commit document origin is subtracted from UTF-16 cursor', async () => {
  const { sync, state } = rig(); sync.notify(1); state.position = 6;
  assert.equal(await sync.reconcile({ ...context, start: 5 }), 'aligned');
  assert.deepEqual(state.moves, [1]);
});
test('P20: positions outside the current preview do not move or reset the engine', async () => {
  for (const position of [4, 8]) {
    const { sync, state } = rig(); sync.notify(1); state.position = position;
    assert.equal(await sync.reconcile({ ...context, start: 5 }), 'ignored');
    assert.deepEqual(state.moves, []);
  }
});
test('P20: failed read retains its hint for a later operation', async () => {
  for (const position of [-1, NaN, Infinity, 0.5]) {
    const { sync, state } = rig(); sync.notify(1); state.position = position;
    assert.equal(await sync.reconcile(context), 'failed'); assert.deepEqual(state.moves, []);
    state.position = 0;
    assert.equal(await sync.reconcile(context), 'aligned');
  }
});
test('P20: thrown read does not become an empty field or successful sync', async () => {
  const { sync, state, port } = rig(); sync.notify(1);
  port.queryCursor = async () => { throw new Error('no text should be logged'); };
  assert.equal(await sync.reconcile(context), 'failed'); assert.deepEqual(state.moves, []);
});
test('P20: a read from an old client cannot align the new client', async () => {
  const { sync, state, port } = rig(); const pending = deferred(); sync.notify(1);
  port.queryCursor = () => pending.promise;
  const result = sync.reconcile(context); state.epoch = 2; pending.resolve(0);
  assert.equal(await result, 'stale'); assert.deepEqual(state.moves, []);
  assert.equal(await sync.reconcile(context), 'ignored');
});
test('P20: reset while reading invalidates the notification version', async () => {
  const { sync, state, port } = rig(); const pending = deferred(); sync.notify(1);
  port.queryCursor = () => pending.promise;
  const result = sync.reconcile(context); sync.reset(); pending.resolve(0);
  assert.equal(await result, 'retry'); assert.deepEqual(state.moves, []);
  assert.equal(await sync.reconcile(context), 'ignored');
});
test('P20: a newer notification requires fresh readback before aligning', async () => {
  const { sync, state, port } = rig(); const pending = deferred(); sync.notify(1);
  port.queryCursor = () => pending.promise;
  const result = sync.reconcile(context); sync.notify(1); pending.resolve(0);
  assert.equal(await result, 'retry'); assert.deepEqual(state.moves, []);
  port.queryCursor = async () => 1;
  assert.equal(await sync.reconcile(context), 'aligned'); assert.deepEqual(state.moves, [1]);
});
test('P20: notification during alignment is preserved for the next read', async () => {
  const { sync, state, port } = rig(); sync.notify(1); state.position = 0;
  port.alignCursor = async position => { state.moves.push(position); sync.notify(1); return true; };
  assert.equal(await sync.reconcile(context), 'retry');
  assert.equal(await sync.reconcile({ ...context, caret: 0 }), 'unchanged');
  assert.deepEqual(state.moves, [0]);
});
test('P20: failed engine alignment retains a retry hint without resending the key', async () => {
  const { sync, state } = rig(); sync.notify(1); state.position = 0; state.ok = false;
  assert.equal(await sync.reconcile(context), 'failed');
  state.ok = true; assert.equal(await sync.reconcile(context), 'aligned');
  assert.deepEqual(state.moves, [0, 0]);
});
test('P20: range selection appearing during read prevents alignment', async () => {
  const { sync, state, port } = rig(); sync.notify(1);
  port.queryCursor = async () => { state.selected = true; return 0; };
  assert.equal(await sync.reconcile(context), 'ignored'); assert.deepEqual(state.moves, []);
});
test('P20: surrogate-interior editor position never reaches native arrows', async () => {
  const { sync, state } = rig(); sync.notify(1); state.position = 2;
  assert.equal(await sync.reconcile({ ...context, text: 'a😀b', previewLength: 4, caret: 4 }), 'failed');
  assert.deepEqual(state.moves, []);
});

function nativeRig(steps) {
  const bridge = new ScriptedBridge(steps); const engine = new MozcEngine(bridge); let sequence = 0;
  return { bridge, engine, send: event => engine.dispatch('cursor-test', 1, ++sequence, event) };
}
test('P20: native alignment moves live composition then inserts at the selected position', async () => {
  const r = nativeRig([
    { operation: 'literal', text: 'かき', output: response('かき', { caret_utf16: 2 }) },
    { operation: 'arrowLeft', output: response('かき', { caret_utf16: 1 }) },
    { operation: 'arrowLeft', output: response('かき', { caret_utf16: 0 }) },
    { operation: 'convert', text: 'sa', output: response('さかき', { caret_utf16: 1 }) }
  ]);
  await r.send({ kind: 'text', text: 'かき' });
  const aligned = await r.send({ kind: 'compositionCursor', cursor: 0 });
  assert.equal(aligned.errorCode, 0); assert.equal(aligned.caretUtf16, 0);
  assert.deepEqual(aligned.effects, []);
  const inserted = await r.send({ kind: 'kana', text: 'さ' });
  assert.equal(inserted.errorCode, 0); assert.equal(r.engine.getPreedit(), 'さかき');
  assert.deepEqual(inserted.effects, []); r.bridge.assertDone();
});
test('P20: native supplementary-character movement consumes one verified arrow', async () => {
  const r = nativeRig([
    { operation: 'literal', output: response('a😀', { caret_utf16: 3 }) },
    { operation: 'arrowLeft', output: response('a😀', { caret_utf16: 1 }) }
  ]);
  await r.send({ kind: 'text', text: 'a😀' });
  assert.equal((await r.send({ kind: 'compositionCursor', cursor: 1 })).errorCode, 0);
  r.bridge.assertDone();
});
test('P20: unchanged native caret does not execute an arrow or change revision', async () => {
  const r = nativeRig([{ operation: 'literal', output: response('かき', { caret_utf16: 2 }) }]);
  const typed = await r.send({ kind: 'text', text: 'かき' });
  const same = await r.send({ kind: 'compositionCursor', cursor: 2 });
  assert.equal(same.revision, typed.revision); assert.equal(same.errorCode, 0); r.bridge.assertDone();
});
test('P20: unverified native cursor, text mutation or commit is not a successful alignment', async () => {
  for (const output of [response('かき', { caret_utf16: 2 }), response('か', { caret_utf16: 1 }),
    response('かき', { caret_utf16: 1, result: 'unexpected' }), JSON.stringify({ ok: false })]) {
    const r = nativeRig([
      { operation: 'literal', output: response('かき', { caret_utf16: 2 }) },
      { operation: 'arrowLeft', output }
    ]);
    await r.send({ kind: 'text', text: 'かき' });
    const result = await r.send({ kind: 'compositionCursor', cursor: 1 });
    assert.notEqual(result.errorCode, 0); assert.equal(result.errorRecoverable, false);
    assert.deepEqual(result.effects, []); r.bridge.assertDone();
  }
});
test('P20: readback for the next key waits until the preceding whole input operation finishes', async () => {
  const { sync, state, port } = rig(); const started = deferred(); const previewDone = deferred(); const order = [];
  const queue = new InputOperationQueue(() => state.epoch, () => 'stale');
  port.queryCursor = async () => { order.push('read'); state.reads++; return state.position; };
  const first = queue.enqueue(async () => {
    started.resolve(); await previewDone.promise; state.position = 1; sync.notify(1); order.push('preview'); return 'first';
  });
  await started.promise;
  const second = queue.enqueue(async () => { return sync.reconcile({ ...context, caret: 1 }); });
  await Promise.resolve(); assert.equal(state.reads, 0);
  previewDone.resolve(); await first;
  assert.equal(await second, 'unchanged'); assert.deepEqual(order, ['preview', 'read']);
  assert.deepEqual(state.moves, []);
});
test('P20: client change during native alignment is stale even if it reported success', async () => {
  const { sync, state, port } = rig(); sync.notify(1); state.position = 0;
  port.alignCursor = async () => { state.epoch = 2; return true; };
  assert.equal(await sync.reconcile(context), 'stale');
});
test('P20: thrown native arrow does not claim that the composition cursor is known', async () => {
  const r = nativeRig([
    { operation: 'literal', output: response('かき', { caret_utf16: 2 }) },
    { operation: 'arrowLeft', error: new Error('fixture failure') }
  ]);
  await r.send({ kind: 'text', text: 'かき' });
  const result = await r.send({ kind: 'compositionCursor', cursor: 0 });
  assert.notEqual(result.errorCode, 0); assert.equal(result.errorRecoverable, false); r.bridge.assertDone();
});
test('P20: malformed native cursor target is rejected before issuing commands', async () => {
  const r = nativeRig([{ operation: 'literal', output: response('a😀', { caret_utf16: 3 }) }]);
  await r.send({ kind: 'text', text: 'a😀' });
  const result = await r.send({ kind: 'compositionCursor', cursor: 2 });
  assert.notEqual(result.errorCode, 0); assert.equal(result.errorRecoverable, true); r.bridge.assertDone();
});
test('P20: sync and product coordinator retain the OS preview and do not commit while aligning', async () => {
  const bridge = new ScriptedBridge([
    { operation: 'literal', output: response('かき', { caret_utf16: 2 }) },
    { operation: 'arrowLeft', output: response('かき', { caret_utf16: 1 }) },
    { operation: 'arrowLeft', output: response('かき', { caret_utf16: 0 }) },
    { operation: 'convert', text: 'sa', output: response('さかき', { caret_utf16: 1 }) }
  ]);
  const engine = new MozcEngine(bridge); const editor = new FakeEditor('先', 1);
  const coordinator = new ImeCoordinator(editor); coordinator.setEngine(engine); await coordinator.loadPreviewSupport();
  const preview = new CompositionPreview({ getEpoch: () => editor.getEpoch(), queryCursor: () => editor.queryCursor(),
    clearPreview: async () => {}, disableJapanesePreview: () => {}, englishCursor: () => {},
    refreshPreview: (...args) => coordinator.refreshPreview(...args) });
  const sync = new CompositionCursorSync({ getEpoch: () => editor.getEpoch(), hasSelection: () => editor.hasSelection(),
    queryCursor: () => editor.queryCursor(), alignCursor: async cursor => {
      await coordinator.postEvent({ kind: 'compositionCursor', cursor });
      return coordinator.getSnapshot().lastError === 'ok';
    } });
  await coordinator.postEvent({ kind: 'text', text: 'かき' });
  await preview.refresh(coordinator.getSnapshot(), engine.getPreedit(), false);
  editor.cursor = 1; sync.notify(1);
  assert.equal(await sync.reconcile({ ...context, start: preview.getStart(), previewLength: preview.getLength() }), 'aligned');
  assert.equal(editor.count('setPreview'), 1); assert.equal(editor.count('insert'), 0);
  await coordinator.postEvent({ kind: 'kana', text: 'さ' });
  await preview.refresh(coordinator.getSnapshot(), engine.getPreedit(), false);
  assert.equal(editor.text, '先さかき'); assert.deepEqual(editor.preview, { start: 1, end: 4 });
  assert.equal(editor.count('insert'), 0); assert.equal(editor.count('finishPreview'), 0); bridge.assertDone();
});
