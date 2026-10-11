const test = require('node:test');
const assert = require('node:assert/strict');
const { CompositionPreview } = require('../../entry/src/main/ets/kanon/CompositionPreview.ets');
const { cancelEditorPreview } = require('../../entry/src/main/ets/kanon/PreviewLifecycle.ets');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { FakeEditor, deferred, update } = require('../support/fakes.cjs');

function snapshot(values = {}) {
  return { ...new ImeCoordinator(new FakeEditor()).getSnapshot(),
    state: 'JP_COMPOSING', preeditLen: 3, caretUtf16: 3, ...values };
}
function rig() {
  const r = { epoch: 1, cursor: 3, calls: [], ok: true, query: null, refresh: null, clear: null };
  r.preview = new CompositionPreview({
    getEpoch: () => r.epoch,
    queryCursor: async () => { r.calls.push(['query']); return r.query ? r.query.promise : r.cursor; },
    clearPreview: async () => { r.calls.push(['clear']); if (r.clearError) { throw r.clearError; }
      if (r.clear) { await r.clear.promise; } },
    refreshPreview: async (...args) => { r.calls.push(['refresh', ...args]); return r.refresh ? r.refresh.promise : r.ok; },
    disableJapanesePreview: () => r.calls.push(['disable']),
    englishCursor: position => r.calls.push(['english', position])
  });
  return r;
}

test('P06: first display queries origin and subsequent display uses the previous length', async () => {
  const r = rig();
  await r.preview.refresh(snapshot(), 'あいう', false);
  await r.preview.refresh(snapshot({ preeditLen: 2, caretUtf16: 1 }), 'あう', false);
  assert.deepEqual(r.calls, [['query'], ['refresh', 'あいう', 3, 3, 3], ['refresh', 'あう', 3, 6, 1]]);
});

test('P06: partial commit advances the tracked origin once and resets replaced length', async () => {
  const r = rig(); await r.preview.refresh(snapshot(), 'あいう', false);
  r.cursor = 100;
  await r.preview.reconcile(snapshot({ preeditLen: 1, commitLength: 2 }), 'select', 'JP');
  await r.preview.refresh(snapshot({ preeditLen: 1, caretUtf16: 1 }), 'う', false);
  assert.equal(r.preview.getStart(), 5);
  assert.deepEqual(r.calls.at(-1), ['refresh', 'う', 5, 5, 1]);
  assert.equal(r.calls.filter(call => call[0] === 'query').length, 1);
});

test('P06 provisional: partial commit without origin retains cursor and zero fallbacks', async () => {
  for (const cursor of [7, -1]) {
    const r = rig(); r.cursor = cursor;
    await r.preview.reconcile(snapshot({ commitLength: 2 }), 'select', 'JP');
    assert.equal(r.preview.getStart(), cursor < 0 ? 2 : 9);
  }
});

test('P06: failed commit does not advance origin', async () => {
  const r = rig(); r.preview.restore(3);
  await r.preview.reconcile(snapshot({ commitLength: 2, lastError: 'commit-fail' }), 'select', 'JP');
  assert.equal(r.preview.getStart(), 3);
  assert.deepEqual(r.calls, []);
});

test('P06: successful full commit closes tracking without deleting committed text', async () => {
  const r = rig(); r.preview.restore(3);
  await r.preview.reconcile(snapshot({ preeditLen: 0, commitLength: 2 }), 'enter', 'JP');
  assert.equal(r.preview.getStart(), -1);
  assert.deepEqual(r.calls, []);
});

test('P06: cancellation clears old preview once before closing tracking', async () => {
  const r = rig(); r.preview.restore(3);
  const empty = snapshot({ preeditLen: 0, commitLength: 0 });
  await r.preview.reconcile(empty, 'cancel', 'JP');
  await r.preview.reconcile(empty, 'cancel', 'JP');
  assert.deepEqual(r.calls, [['clear']]);
  assert.equal(r.preview.getStart(), -1);
});

test('P06: clearing failure still closes cancelled tracking without retry', async () => {
  const r = rig(); r.preview.restore(3); r.clearError = new Error('Clear failed');
  await r.preview.reconcile(snapshot({ preeditLen: 0 }), 'cancel', 'JP');
  assert.equal(r.preview.getStart(), -1);
  assert.deepEqual(r.calls, [['clear']]);
});

test('P06: successful language change closes tracking without a preview deletion', async () => {
  const r = rig(); r.preview.restore(3);
  await r.preview.reconcile(snapshot({ mode: 'EN', state: 'EN_EMPTY', preeditLen: 0 }), 'mode', 'JP');
  assert.equal(r.preview.getStart(), -1);
  assert.deepEqual(r.calls, []);
});

test('P06: direct English and empty compositions reset tracking without sending preview', async () => {
  for (const s of [snapshot({ mode: 'EN', state: 'DIRECT_EN' }), snapshot({ preeditLen: 0 })]) {
    const r = rig(); r.preview.restore(3); await r.preview.refresh(s, 'fixture', false);
    assert.equal(r.preview.getStart(), -1);
    assert.deepEqual(r.calls, []);
  }
});

test('P06: English preview reports the UTF-16 cursor before updating display', async () => {
  const r = rig(); r.preview.restore(7);
  await r.preview.refresh(snapshot({ mode: 'EN', state: 'EN_COMPOSING', preeditLen: 2, caretUtf16: 2 }), '😀', true);
  assert.deepEqual(r.calls, [['english', 9], ['refresh', '😀', 7, 7, 2]]);
});

test('P06: failed Japanese preview disables support without recording new length', async () => {
  const r = rig(); r.preview.restore(3); r.ok = false;
  await r.preview.refresh(snapshot(), 'あいう', false);
  r.ok = true; await r.preview.refresh(snapshot({ preeditLen: 1 }), 'う', false);
  assert.deepEqual(r.calls, [['refresh', 'あいう', 3, 3, 3], ['disable'], ['refresh', 'う', 3, 3, 3]]);
});

test('P06: failed English preview does not disable Japanese support', async () => {
  const r = rig(); r.ok = false;
  await r.preview.refresh(snapshot({ mode: 'EN', state: 'EN_COMPOSING' }), 'abc', true);
  assert.equal(r.calls.some(call => call[0] === 'disable'), false);
});

test('P06: unavailable cursor skips preview rather than inserting text', async () => {
  const r = rig(); r.cursor = -1;
  await r.preview.refresh(snapshot(), 'あいう', false);
  assert.equal(r.preview.getStart(), -1);
  assert.deepEqual(r.calls, [['query']]);
});

test('P06: noncomposition state and empty text do not alter tracked origin', async () => {
  const r = rig(); r.preview.restore(7);
  await r.preview.refresh(snapshot({ state: 'ENGINE_ERROR' }), 'あいう', false);
  await r.preview.refresh(snapshot(), '', false);
  assert.equal(r.preview.getStart(), 7);
  assert.deepEqual(r.calls, []);
});

test('P06: cursor query from a reset composition cannot overwrite a restored origin', async () => {
  const r = rig(); r.query = deferred();
  const pending = r.preview.refresh(snapshot(), 'あいう', false);
  r.preview.restore(10); r.query.resolve(3); await pending;
  assert.equal(r.preview.getStart(), 10);
  assert.deepEqual(r.calls, [['query']]);
});

test('P06: editor change during cursor query prevents preview submission', async () => {
  const r = rig(); r.query = deferred();
  const pending = r.preview.refresh(snapshot(), 'あいう', false);
  r.epoch++; r.query.resolve(3); await pending;
  assert.equal(r.preview.getStart(), -1);
  assert.deepEqual(r.calls, [['query']]);
});

test('P06: late preview completion cannot restore a previous composition length', async () => {
  const r = rig(); r.preview.restore(3); r.refresh = deferred();
  const old = r.preview.refresh(snapshot(), 'あいう', false);
  r.preview.restore(10); r.refresh.resolve(true); await old; r.refresh = null;
  await r.preview.refresh(snapshot({ preeditLen: 1 }), 'う', false);
  assert.deepEqual(r.calls.at(-1), ['refresh', 'う', 10, 10, 3]);
});

test('P06: late preview failure cannot disable a new composition', async () => {
  const r = rig(); r.preview.restore(3); r.refresh = deferred();
  const old = r.preview.refresh(snapshot(), 'あいう', false);
  r.preview.restore(10); r.refresh.resolve(false); await old;
  assert.equal(r.calls.some(call => call[0] === 'disable'), false);
});

test('P06: old preview completion cannot restore length after partial reanchoring', async () => {
  const r = rig(); r.preview.restore(3); r.refresh = deferred();
  const old = r.preview.refresh(snapshot(), 'あいう', false);
  await r.preview.reconcile(snapshot({ preeditLen: 1, commitLength: 2 }), 'select', 'JP');
  r.refresh.resolve(true); await old; r.refresh = null;
  await r.preview.refresh(snapshot({ preeditLen: 1, caretUtf16: 1 }), 'う', false);
  assert.deepEqual(r.calls.at(-1), ['refresh', 'う', 5, 5, 1]);
});

test('P06: cancellation completion cannot reset a newly restored composition', async () => {
  const r = rig(); r.preview.restore(3); r.clear = deferred();
  const old = r.preview.reconcile(snapshot({ preeditLen: 0 }), 'cancel', 'JP');
  r.preview.restore(10); r.clear.resolve(); await old;
  assert.equal(r.preview.getStart(), 10);
});

test('P06: preview owner and Coordinator preserve text after partial commit', async () => {
  const editor = new FakeEditor('既存:', 3);
  const coordinator = new ImeCoordinator(editor);
  coordinator.setEngine({ dispatch: (s, e, n, event) => update(s, e, n,
    event.kind === 'select' ? { preeditLen: 1, effects: [{ effectId: `part-${n}`, text: '😀' }] } :
      { preeditLen: 3, candidateCount: 1, candidates: [{ id: 1, label: '😀' }] }) });
  await coordinator.loadPreviewSupport();
  const preview = new CompositionPreview({ getEpoch: () => editor.getEpoch(), queryCursor: () => editor.queryCursor(),
    clearPreview: () => cancelEditorPreview(editor).then(() => {}),
    refreshPreview: (...args) => coordinator.refreshPreview(...args),
    disableJapanesePreview: () => coordinator.setPreviewUnsupported(), englishCursor: () => {} });
  await coordinator.postEvent({ kind: 'text', text: 'fixture' });
  await preview.refresh(coordinator.getSnapshot(), 'あいう', false);
  await coordinator.postEvent({ kind: 'select', candidateId: 1, expectedRevision: coordinator.getSnapshot().revision });
  await preview.reconcile(coordinator.getSnapshot(), 'select', 'JP');
  await preview.refresh(coordinator.getSnapshot(), 'う', false);
  assert.equal(editor.text, '既存:😀う');
  assert.deepEqual(editor.preview, { start: 5, end: 6 });
  assert.equal(editor.count('insert'), 1);
});
