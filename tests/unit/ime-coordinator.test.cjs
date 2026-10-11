const test = require('node:test');
const assert = require('node:assert/strict');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { FakeEditor, update, deferred } = require('../support/fakes.cjs');

async function rig(dispatch) {
  const editor = new FakeEditor();
  const coordinator = new ImeCoordinator(editor);
  coordinator.setEngine({ dispatch });
  await coordinator.loadPreviewSupport();
  return { editor, coordinator };
}

test('R08: cursor-only updates do not resend unchanged preview text', async () => {
  const { editor, coordinator } = await rig((s, e, n) => update(s, e, n));
  assert.equal(await coordinator.refreshPreview('あいう', 0, 0, 3), true);
  await coordinator.refreshPreview('あいう', 0, 3, 2);
  await coordinator.refreshPreview('あいう', 0, 3, 1);
  await coordinator.refreshPreview('あいう', 0, 3, 3);
  assert.equal(editor.count('setPreview'), 1);
  assert.deepEqual(editor.calls.filter(call => call.operation === 'previewCaret').map(call => call.position), [2, 1, 3]);
  assert.equal(editor.text, 'あいう');
  assert.deepEqual(editor.preview, { start: 0, end: 3 });
});

test('R09: unconfirmed editor cursor does not rewrite or retry the text', async () => {
  const { editor, coordinator } = await rig((s, e, n) => update(s, e, n));
  await coordinator.refreshPreview('あいう', 0, 0, 3);
  editor.caretMatches = false;
  assert.equal(await coordinator.refreshPreview('あいう', 0, 3, 1), true);
  assert.equal(coordinator.getSnapshot().lastError, 'preview-caret--7');
  assert.equal(editor.count('setPreview'), 1);
  assert.equal(editor.count('previewCaret'), 1);
  assert.equal(editor.count('insert'), 0);
  assert.equal(coordinator.isPreviewCaretAligned(), false);
});

test('P21: caret alignment is restored only after a successful preview placement', async () => {
  const { editor, coordinator } = await rig((s, e, n) => update(s, e, n));
  assert.equal(coordinator.isPreviewCaretAligned(), false);
  await coordinator.refreshPreview('かき', 0, 0, 2);
  assert.equal(coordinator.isPreviewCaretAligned(), true);
  editor.caretMatches = false;
  await coordinator.refreshPreview('かｓき', 0, 2, 2);
  assert.equal(coordinator.isPreviewCaretAligned(), false);
  // Text success alone does not confirm a midpoint caret.
  await coordinator.refreshPreview('かさき', 0, 3, 2);
  assert.equal(coordinator.isPreviewCaretAligned(), false);
  editor.caretMatches = true;
  await coordinator.refreshPreview('かさき', 0, 3, 2);
  assert.equal(coordinator.isPreviewCaretAligned(), true);
  coordinator.onEditorChanged();
  assert.equal(coordinator.isPreviewCaretAligned(), false);
});

test('P21: successful end typing reestablishes a known caret after a failed midpoint move', async () => {
  const { editor, coordinator } = await rig((s, e, n) => update(s, e, n));
  editor.caretMatches = false;
  await coordinator.refreshPreview('かき', 0, 0, 1);
  assert.equal(coordinator.isPreviewCaretAligned(), false);
  await coordinator.refreshPreview('かきく', 0, 2, 3);
  assert.equal(coordinator.isPreviewCaretAligned(), true);
  coordinator.setPreviewUnsupported();
  assert.equal(coordinator.isPreviewCaretAligned(), false);
});

test('P21: rejected preview updates and stale completions never confirm a caret', async () => {
  const { editor, coordinator } = await rig((s, e, n) => update(s, e, n));
  await coordinator.refreshPreview('かき', 0, 0, 2);
  editor.setPreview = async () => ({ ok: false, code: -5 });
  assert.equal(await coordinator.refreshPreview('かきく', 0, 2, 3), false);
  assert.equal(coordinator.isPreviewCaretAligned(), false);
  const pending = deferred(); editor.setPreview = () => pending.promise;
  const refreshed = coordinator.refreshPreview('かきく', 0, 2, 3);
  editor.epoch++; coordinator.onEditorChanged(); pending.resolve({ ok: true, code: 0 });
  assert.equal(await refreshed, false);
  assert.equal(coordinator.isPreviewCaretAligned(), false);
});

test('R05: segment commit replaces old preview once and reports consumed length', async () => {
  const { editor, coordinator } = await rig((s, e, n, event) => update(s, e, n,
    event.kind === 'select' ? { preeditLen: 1, effects: [{ effectId: 'segment', text: '愛' }] } :
      { preeditLen: 3, candidateCount: 1, candidates: [{ id: 11, label: '愛' }] }));
  await coordinator.postEvent({ kind: 'text', text: 'fixture' });
  await coordinator.refreshPreview('あいう', 0, 0, 2);
  await coordinator.postEvent({ kind: 'select', candidateId: 11,
    expectedRevision: coordinator.getSnapshot().revision });
  assert.equal(editor.text, '愛');
  assert.equal(editor.count('insert'), 1);
  assert.equal(coordinator.getSnapshot().commitLength, 1);
  // The composition root owns re-anchoring; this tests the editor contract at its new origin.
  await coordinator.refreshPreview('う', 1, 1, 1);
  assert.equal(editor.text, '愛う');
  assert.deepEqual(editor.preview, { start: 1, end: 2 });
});

test('C01: a delayed result for an old editor is not inserted in the new editor', async () => {
  const started = deferred(); const pending = deferred();
  const { editor, coordinator } = await rig((s, e, n) => {
    started.resolve(); return pending.promise.then(() => update(s, e, n,
      { effects: [{ effectId: 'old', text: '古い入力' }] }));
  });
  const processing = coordinator.postEvent({ kind: 'text', text: 'a' });
  await started.promise;
  editor.epoch++;
  pending.resolve(); await processing;
  assert.equal(editor.count('insert'), 0);
  assert.equal(coordinator.getSnapshot().droppedStale, 1);
});

test('C02: candidate revision mismatch is rejected before engine dispatch', async () => {
  let calls = 0;
  const { editor, coordinator } = await rig((s, e, n) => {
    calls++; return update(s, e, n, { preeditLen: 1 });
  });
  await coordinator.postEvent({ kind: 'text', text: 'あ' });
  await coordinator.postEvent({ kind: 'select', candidateId: 1, expectedRevision: 0 });
  assert.equal(calls, 1);
  assert.equal(coordinator.getSnapshot().lastError, 'stale-revision');
  assert.equal(editor.count('insert'), 0);
});

test('C03: duplicate commit effects are inserted only once', async () => {
  const { editor, coordinator } = await rig((s, e, n) => update(s, e, n,
    { effects: [{ effectId: 'same-effect', text: '確定' }] }));
  await coordinator.postEvent({ kind: 'text', text: 'a' });
  await coordinator.postEvent({ kind: 'text', text: 'b' });
  assert.equal(editor.text, '確定');
  assert.equal(editor.count('insert'), 1);
  assert.equal(coordinator.getSnapshot().dupSuppressed, 1);
});

test('C04: commit failure is held without retry until an explicit reset', async () => {
  let calls = 0;
  const { editor, coordinator } = await rig((s, e, n, event) => {
    calls++; return update(s, e, n, event.kind === 'reset' ? {} :
      { effects: [{ effectId: 'commit', text: '確定' }] });
  });
  editor.failInsert = true;
  await coordinator.postEvent({ kind: 'text', text: 'a' });
  await coordinator.postEvent({ kind: 'text', text: 'b' });
  assert.equal(editor.count('insert'), 1);
  assert.equal(calls, 1);
  assert.equal(coordinator.getSnapshot().needsRecovery, true);
  await coordinator.postEvent({ kind: 'reset' });
  assert.equal(coordinator.getSnapshot().needsRecovery, false);
});

test('reading failure is not mistaken for a successfully observed empty field', async () => {
  const first = await rig((s, e, n) => update(s, e, n));
  await first.coordinator.postEvent({ kind: 'backspace' });
  assert.equal(first.editor.count('deleteForward'), 0);
  const second = await rig((s, e, n) => update(s, e, n));
  second.editor.beforeResult = { ok: false, code: 12800003, value: undefined };
  await second.coordinator.postEvent({ kind: 'backspace' });
  assert.equal(second.editor.count('deleteForward'), 1);
});

test('C05: cancel clears preview cache so equal text in a new composition is resent', async () => {
  const { editor, coordinator } = await rig((s, e, n) => update(s, e, n));
  await coordinator.refreshPreview('あ', 0, 0, 1);
  await coordinator.postEvent({ kind: 'cancel' });
  await coordinator.refreshPreview('あ', 0, 1, 1);
  assert.equal(editor.count('setPreview'), 2);
});

test('preview completion from an old editor cannot establish new preview tracking', async () => {
  const editor = new FakeEditor(); const pending = deferred();
  editor.setPreview = async () => pending.promise;
  const coordinator = new ImeCoordinator(editor);
  await coordinator.loadPreviewSupport();
  const result = coordinator.refreshPreview('あ', 0, 0, 1);
  editor.epoch++;
  pending.resolve({ ok: true, code: 0 });
  assert.equal(await result, false);
});
