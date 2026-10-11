const test = require('node:test');
const assert = require('node:assert/strict');
const { PreviewSelectionReceipt, writePreviewWithReceipt } = require('../../entry/src/main/ets/kanon/PreviewSelectionReceipt.ets');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { FakeEditor, deferred } = require('../support/fakes.cjs');
const { EditorOperationQueue } = require('../../entry/src/main/ets/kanon/EditorOperationQueue.ets');
const { editorQueueRig } = require('../support/editor-queue-rig.cjs');

test('P20: preview API completion alone does not complete the required position receipt', async () => {
  const receipt = new PreviewSelectionReceipt(); const wait = receipt.arm(1, 3); let finished = false;
  const result = writePreviewWithReceipt(async () => {}, wait).then(value => { finished = true; return value; });
  await Promise.resolve(); await Promise.resolve(); assert.equal(finished, false);
  receipt.observe(1, 3, 3); assert.equal(await result, true);
});
test('P20: selection notification before API completion is retained', async () => {
  const receipt = new PreviewSelectionReceipt(); const api = deferred(); const wait = receipt.arm(1, 3);
  const result = writePreviewWithReceipt(() => api.promise, wait);
  receipt.observe(1, 3, 3); api.resolve(); assert.equal(await result, true);
});
test('P20: stale positions, other clients and selected ranges cannot release preview receipt', async () => {
  const receipt = new PreviewSelectionReceipt(); const wait = receipt.arm(1, 3); let finished = false;
  wait.ready.then(() => { finished = true; });
  receipt.observe(1, 1, 1); receipt.observe(2, 3, 3); receipt.observe(1, 1, 3);
  await Promise.resolve(); assert.equal(finished, false);
  receipt.observe(1, 3, 3); assert.equal(await wait.ready, true);
});
test('P20: API rejection cancels only its own receipt and preserves the original error', async () => {
  const receipt = new PreviewSelectionReceipt(); const wait = receipt.arm(1, 3); const failure = new Error('fixture');
  await assert.rejects(writePreviewWithReceipt(async () => { throw failure; }, wait), error => error === failure);
  assert.equal(await wait.ready, false);
});
test('P20: timeout or detach cancels receipt without issuing a late caret operation', async () => {
  const receipt = new PreviewSelectionReceipt(); const wait = receipt.arm(1, 3); const operations = [];
  const result = writePreviewWithReceipt(async () => { operations.push('setPreview'); }, wait)
    .then(observed => { if (observed) { operations.push('caret'); } return observed; });
  await Promise.resolve(); receipt.cancel(); receipt.observe(1, 3, 3);
  assert.equal(await result, false); assert.deepEqual(operations, ['setPreview']);
});
test('P20: late cancellation from an old API cannot cancel the new receipt', async () => {
  const receipt = new PreviewSelectionReceipt(); const old = receipt.arm(1, 3); const fresh = receipt.arm(2, 4);
  old.cancel(); assert.equal(await old.ready, false);
  receipt.observe(2, 4, 4); assert.equal(await fresh.ready, true);
});
test('P20: duplicate receipt notifications cannot change a completed result', async () => {
  const receipt = new PreviewSelectionReceipt(); const wait = receipt.arm(1, 3);
  receipt.observe(1, 3, 3); receipt.cancel(); wait.cancel(); receipt.observe(1, 3, 3);
  assert.equal(await wait.ready, true);
});
test('P20: a position observed before arming is not adopted as a new receipt', async () => {
  const receipt = new PreviewSelectionReceipt(); receipt.observe(1, 3, 3);
  const wait = receipt.arm(1, 3); let finished = false; wait.ready.then(() => { finished = true; });
  await Promise.resolve(); assert.equal(finished, false); wait.cancel(); assert.equal(await wait.ready, false);
});
test('P20: preview updates without a following internal caret move do not wait for notification', async () => {
  let called = 0;
  assert.equal(await writePreviewWithReceipt(async () => { called++; }, undefined), true);
  assert.equal(called, 1);
});
test('P20: coordinator waits for preview position observation before moving caret', async () => {
  const receipt = new PreviewSelectionReceipt(); const editor = new FakeEditor(); const expectedEnds = [];
  const setPreview = editor.setPreview.bind(editor);
  editor.setPreview = async (text, start, end, observedEnd) => {
    expectedEnds.push(observedEnd);
    const wait = receipt.arm(editor.getEpoch(), observedEnd);
    const observed = await writePreviewWithReceipt(async () => { await setPreview(text, start, end); }, wait);
    return { ok: observed, code: observed ? 0 : -5 };
  };
  const coordinator = new ImeCoordinator(editor); await coordinator.loadPreviewSupport();
  const refreshed = coordinator.refreshPreview('かきく', 4, 4, 1);
  await Promise.resolve(); await Promise.resolve();
  assert.equal(editor.count('previewCaret'), 0); assert.deepEqual(expectedEnds, [7]);
  receipt.observe(1, 7, 7); assert.equal(await refreshed, true);
  assert.deepEqual(editor.calls.filter(call => call.operation === 'previewCaret').map(call => call.position), [5]);
});
test('P20: failed receipt prevents coordinator caret move and does not finish or insert', async () => {
  const receipt = new PreviewSelectionReceipt(); const editor = new FakeEditor();
  editor.setPreview = async () => {
    const wait = receipt.arm(1, 3); const observed = await writePreviewWithReceipt(async () => {}, wait);
    return { ok: observed, code: -3 };
  };
  const coordinator = new ImeCoordinator(editor); await coordinator.loadPreviewSupport();
  const refreshed = coordinator.refreshPreview('かきく', 0, 0, 1);
  await Promise.resolve(); receipt.cancel(); assert.equal(await refreshed, false);
  assert.equal(editor.count('previewCaret'), 0); assert.equal(editor.count('insert'), 0);
  assert.equal(editor.count('finishPreview'), 0);
});
test('P20: replacing a preview at its end requires no extra receipt metadata', async () => {
  const editor = new FakeEditor(); const observed = []; const setPreview = editor.setPreview.bind(editor);
  editor.setPreview = async (text, start, end, observedEnd) => { observed.push(observedEnd); return setPreview(text, start, end); };
  const coordinator = new ImeCoordinator(editor); await coordinator.loadPreviewSupport();
  assert.equal(await coordinator.refreshPreview('かき', 0, 0, 2), true);
  assert.deepEqual(observed, [undefined]); assert.equal(editor.count('previewCaret'), 0);
});
test('P20: API queue timeout cancels position wait and releases the unresolved write gate', async () => {
  const { clock } = editorQueueRig(); const receipt = new PreviewSelectionReceipt(); const started = deferred();
  const queue = new EditorOperationQueue({ schedule: clock.schedule, unschedule: clock.unschedule,
    errorCode: () => -2, log: (op, event) => { if (op === 'setPreview' && event === 'timeout') { receipt.cancel(); } } });
  queue.attach({ name: 'fixed' });
  const result = queue.enqueue('setPreview', async () => {
    const wait = receipt.arm(1, 3); started.resolve();
    return await writePreviewWithReceipt(async () => {}, wait) ? 'observed' : null;
  });
  await started.promise; clock.advance(3000);
  assert.equal((await result).code, -3);
  await Promise.resolve(); await Promise.resolve();
  assert.equal((await queue.enqueue('next', async () => 'next')).ok, true);
});
