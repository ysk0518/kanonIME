const test = require('node:test');
const assert = require('node:assert/strict');
const { PreviewCaretPlacement } = require('../../entry/src/main/ets/kanon/PreviewCaretPlacement.ets');
const { PreviewSelectionReceipt, writePreviewWithReceipt } = require('../../entry/src/main/ets/kanon/PreviewSelectionReceipt.ets');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { EditorOperationQueue } = require('../../entry/src/main/ets/kanon/EditorOperationQueue.ets');
const { editorQueueRig, pending } = require('../support/editor-queue-rig.cjs');
const { FakeEditor } = require('../support/fakes.cjs');

const context = { text: 'かきく', start: 5, position: 5 };
function rig(indexes = [8, 7, 6, 5]) {
  const state = { epoch: 1, reads: 0, moves: [], expectedPositions: [], indexes: [...indexes], last: indexes[0] };
  const port = { getEpoch: () => state.epoch,
    queryCursor: async () => { state.reads++; if (state.indexes.length) { state.last = state.indexes.shift(); } return state.last; },
    moveCursor: async (direction, expected) => { state.moves.push(direction); state.expectedPositions.push(expected); } };
  return { state, port, placement: new PreviewCaretPlacement() };
}

test('P22: left movement uses document origin and verifies every code-point step', async () => {
  const r = rig(); assert.equal(await r.placement.place(r.port, context), true);
  assert.deepEqual(r.state.moves, [-1, -1, -1]); assert.equal(r.state.reads, 4);
  assert.deepEqual(r.state.expectedPositions, [7, 6, 5]);
});
test('P22: right movement reaches the end of the known preview', async () => {
  const r = rig([5, 6, 7, 8]);
  assert.equal(await r.placement.place(r.port, { ...context, position: 8 }), true);
  assert.deepEqual(r.state.moves, [1, 1, 1]);
});
test('P22: already positioned caret requires one read and no cursor write', async () => {
  const r = rig([5]); assert.equal(await r.placement.place(r.port, context), true);
  assert.equal(r.state.reads, 1); assert.deepEqual(r.state.moves, []);
});
test('P22: supplementary characters take one movement and two UTF-16 units', async () => {
  const r = rig([9, 8, 6]);
  assert.equal(await r.placement.place(r.port, { text: 'a😀b', start: 5, position: 6 }), true);
  assert.deepEqual(r.state.moves, [-1, -1]); assert.equal(r.state.reads, 3);
  assert.deepEqual(r.state.expectedPositions, [8, 6]);
});

test('P22: cursor readback waits for a late position notification after the SDK reply', async () => {
  const r = rig([8, 7]); const receipt = new PreviewSelectionReceipt(); const replied = pending();
  r.port.moveCursor = async (direction, expected) => {
    r.state.moves.push(direction); const wait = receipt.arm(1, expected);
    await writePreviewWithReceipt(async () => { replied.resolve(); }, wait);
  };
  const result = r.placement.place(r.port, { ...context, position: 7 });
  await replied.promise; assert.equal(r.state.reads, 1);
  receipt.observe(1, 7, 7); assert.equal(await result, true);
  assert.equal(r.state.reads, 2); assert.deepEqual(r.state.moves, [-1]);
});
test('P22: a position notification before SDK completion still waits for the reply', async () => {
  const r = rig([8, 7]); const receipt = new PreviewSelectionReceipt(); const entered = pending(), reply = pending();
  r.port.moveCursor = async (direction, expected) => {
    const wait = receipt.arm(1, expected); entered.resolve();
    await writePreviewWithReceipt(() => reply.promise, wait);
  };
  const result = r.placement.place(r.port, { ...context, position: 7 }); await entered.promise;
  receipt.observe(1, 7, 7); await Promise.resolve(); assert.equal(r.state.reads, 1);
  reply.resolve(); assert.equal(await result, true);
});
test('P22: another observed position does not permit the next cursor read', async () => {
  const r = rig([8, 7]); const receipt = new PreviewSelectionReceipt(); const entered = pending();
  r.port.moveCursor = async (direction, expected) => {
    const wait = receipt.arm(1, expected); entered.resolve(); await writePreviewWithReceipt(async () => {}, wait);
  };
  const result = r.placement.place(r.port, { ...context, position: 7 }); await entered.promise;
  receipt.observe(1, 8, 8); receipt.observe(1, 7, 8); await Promise.resolve();
  assert.equal(r.state.reads, 1);
  receipt.observe(1, 7, 7); assert.equal(await result, true);
});
test('P22: API deadline cancels a pending position observation without a follow-up read', async () => {
  const r = rig([8, 7]); const receipt = new PreviewSelectionReceipt(); const { clock } = editorQueueRig();
  const entered = pending(), completed = pending();
  const queue = new EditorOperationQueue({ schedule: clock.schedule, unschedule: clock.unschedule,
    errorCode: () => -2, log: (op, event) => {
      if (op === 'previewCaret' && event === 'timeout') { r.placement.cancel(); receipt.cancel(); }
    } });
  queue.attach({ name: 'fixture' }); r.port.getEpoch = () => queue.getEpoch();
  r.port.moveCursor = async (direction, expected) => {
    r.state.moves.push(direction); const wait = receipt.arm(1, expected); entered.resolve();
    await writePreviewWithReceipt(async () => {}, wait);
  };
  const result = queue.enqueue('previewCaret', async () => {
    const matched = await r.placement.place(r.port, { ...context, position: 7 });
    completed.resolve(matched); return `matched=${matched}`;
  });
  await entered.promise; clock.advance(3000); assert.equal((await result).code, -3);
  assert.equal(await completed.promise, false); receipt.observe(1, 7, 7);
  assert.equal(r.state.reads, 1); assert.deepEqual(r.state.moves, [-1]);
  await Promise.resolve(); await Promise.resolve();
  assert.equal((await queue.enqueue('next', async () => 'next')).ok, true);
});
test('P22: invalid targets and preview origins are rejected before reading the client', async () => {
  for (const patch of [{ start: -1 }, { start: NaN }, { start: 1.5 }, { start: Number.MAX_SAFE_INTEGER },
    { position: 4 }, { position: 9 }, { position: Infinity }, { position: 5.5 }, { text: '' }]) {
    const r = rig(); assert.equal(await r.placement.place(r.port, { ...context, ...patch }), false);
    assert.equal(r.state.reads, 0); assert.deepEqual(r.state.moves, []);
  }
});
test('P22: a surrogate-interior target never issues a client read or move', async () => {
  const r = rig();
  assert.equal(await r.placement.place(r.port, { text: 'a😀b', start: 5, position: 7 }), false);
  assert.equal(r.state.reads, 0); assert.deepEqual(r.state.moves, []);
});
test('P22: out-of-preview or invalid client positions do not move any text', async () => {
  for (const index of [-1, 4, 9, NaN, Infinity, 6.5]) {
    const r = rig([index]); assert.equal(await r.placement.place(r.port, context), false);
    assert.deepEqual(r.state.moves, []);
  }
  const r = rig([7]);
  assert.equal(await r.placement.place(r.port, { text: 'a😀b', start: 5, position: 5 }), false);
  assert.deepEqual(r.state.moves, []);
});
test('P22: an unchanged or unexpected readback stops after the first command without retry', async () => {
  for (const index of [8, 5, 99]) {
    const r = rig([8, index]); assert.equal(await r.placement.place(r.port, context), false);
    assert.deepEqual(r.state.moves, [-1]); assert.equal(r.state.reads, 2);
  }
});
test('P22: initial cursor read rejection preserves the error and performs no movement', async () => {
  const r = rig(); const error = new Error('fixed read error');
  r.port.queryCursor = async () => { throw error; };
  await assert.rejects(r.placement.place(r.port, context), value => value === error);
  assert.deepEqual(r.state.moves, []);
});
test('P22: movement rejection preserves the error and does not query or retry afterwards', async () => {
  const r = rig(); const error = new Error('fixed move error');
  r.port.moveCursor = async direction => { r.state.moves.push(direction); throw error; };
  await assert.rejects(r.placement.place(r.port, context), value => value === error);
  assert.equal(r.state.reads, 1); assert.deepEqual(r.state.moves, [-1]);
});
test('P22: client change during initial read prevents movement on the old client', async () => {
  const r = rig(); const read = pending(); r.port.queryCursor = () => read.promise;
  const result = r.placement.place(r.port, context); r.state.epoch++; read.resolve(8);
  assert.equal(await result, false); assert.deepEqual(r.state.moves, []);
});
test('P22: cancellation during movement prevents follow-up reads and commands', async () => {
  const r = rig(); const entered = pending(), moved = pending();
  r.port.moveCursor = async direction => { r.state.moves.push(direction); entered.resolve(); await moved.promise; };
  const result = r.placement.place(r.port, context); await entered.promise;
  r.placement.cancel(); moved.resolve(); assert.equal(await result, false);
  assert.equal(r.state.reads, 1); assert.deepEqual(r.state.moves, [-1]);
});
test('P22: client change during a movement cannot dispatch another old-client command', async () => {
  const r = rig();
  r.port.moveCursor = async direction => { r.state.moves.push(direction); r.state.epoch++; };
  assert.equal(await r.placement.place(r.port, context), false);
  assert.equal(r.state.reads, 1); assert.deepEqual(r.state.moves, [-1]);
});
test('P22: cancellation during readback prevents a second movement', async () => {
  const r = rig(); const readback = pending(), entered = pending();
  r.port.queryCursor = async () => { r.state.reads++; if (r.state.reads === 1) { return 8; } entered.resolve(); return readback.promise; };
  const result = r.placement.place(r.port, context); await entered.promise;
  r.placement.cancel(); readback.resolve(7); assert.equal(await result, false);
  assert.deepEqual(r.state.moves, [-1]);
});
test('P22: a newer placement supersedes an old pending read without forwarding it', async () => {
  const r = rig(); const oldRead = pending(); let reads = 0;
  r.port.queryCursor = async () => ++reads === 1 ? oldRead.promise : 5;
  const old = r.placement.place(r.port, context);
  assert.equal(await r.placement.place(r.port, context), true);
  oldRead.resolve(8); assert.equal(await old, false); assert.deepEqual(r.state.moves, []);
});
test('P22: coordinator passes only its known preview origin and text to caret placement', async () => {
  const editor = new FakeEditor('先頭', 2); const received = [];
  editor.previewCaret = async (...args) => { received.push(args); return { ok: true, code: 0 }; };
  const coordinator = new ImeCoordinator(editor); await coordinator.loadPreviewSupport();
  await coordinator.refreshPreview('かき', 2, 2, 1);
  assert.deepEqual(received, [[3, 2, 'かき']]);
  assert.equal(editor.count('setPreview'), 1); assert.equal(editor.count('insert'), 0);
});
test('P22: API queue deadline cancels caret placement and releases its gate only after late completion', async () => {
  const r = rig(); const { clock } = editorQueueRig(); const entered = pending(), moved = pending(), completed = pending();
  const queue = new EditorOperationQueue({ schedule: clock.schedule, unschedule: clock.unschedule,
    errorCode: () => -2, log: (op, event) => { if (op === 'previewCaret' && event === 'timeout') { r.placement.cancel(); } } });
  queue.attach({ name: 'fixture' }); r.port.getEpoch = () => queue.getEpoch();
  r.port.moveCursor = async direction => { r.state.moves.push(direction); entered.resolve(); await moved.promise; };
  const result = queue.enqueue('previewCaret', async () => {
    const matched = await r.placement.place(r.port, context); completed.resolve(matched); return `matched=${matched}`;
  });
  await entered.promise; clock.advance(3000); assert.equal((await result).code, -3);
  assert.equal((await queue.enqueue('next', async () => 'next')).code, -6);
  moved.resolve(); assert.equal(await completed.promise, false);
  assert.deepEqual(r.state.moves, [-1]); assert.equal(r.state.reads, 1);
  await Promise.resolve(); await Promise.resolve();
  assert.equal((await queue.enqueue('next', async () => 'next')).ok, true);
});
