const test = require('node:test');
const assert = require('node:assert/strict');
const { advanceCompositionStart } = require('../../entry/src/main/ets/kanon/CompositionPosition.ets');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { FakeEditor, update } = require('../support/fakes.cjs');

test('R05: partial commit advances the tracked origin by committed UTF-16 length', () => {
  assert.equal(advanceCompositionStart(7, 100, '愛'.length), 8);
  assert.equal(advanceCompositionStart(7, 0, '😀'.length), 9);
  assert.equal(advanceCompositionStart(0, 100, 1), 1);
});

test('R05 provisional: missing tracked origin uses the existing cursor fallback', () => {
  assert.equal(advanceCompositionStart(-1, 7, 2), 9);
  assert.equal(advanceCompositionStart(-1, -1, 2), 2);
});

test('R05: repeated partial commits keep prefix and suffix at their calculated origins', async () => {
  const editor = new FakeEditor('既存:', 3);
  const coordinator = new ImeCoordinator(editor);
  coordinator.setEngine({ dispatch: (s, e, n, event) => update(s, e, n,
    event.kind === 'select' ? { preeditLen: 1, effects: [{ effectId: `part-${n}`, text: '😀' }] } :
      { preeditLen: 3, candidateCount: 1, candidates: [{ id: 1, label: '😀' }] }) });
  await coordinator.loadPreviewSupport();
  await coordinator.postEvent({ kind: 'text', text: 'fixture' });
  let start = 3;
  await coordinator.refreshPreview('あいう', start, start, 2);
  for (let count = 0; count < 2; count++) {
    await coordinator.postEvent({ kind: 'select', candidateId: 1,
      expectedRevision: coordinator.getSnapshot().revision });
    const snapshot = coordinator.getSnapshot();
    assert.equal(snapshot.commitLength, 2);
    start = advanceCompositionStart(start, 0, snapshot.commitLength);
    await coordinator.refreshPreview('う', start, start, 1);
    assert.equal(editor.text, '既存:' + '😀'.repeat(count + 1) + 'う');
    assert.deepEqual(editor.preview, { start, end: start + 1 });
  }
  assert.equal(editor.count('insert'), 2);
});
