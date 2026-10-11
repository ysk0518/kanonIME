const test = require('node:test');
const assert = require('node:assert/strict');
const { cancelEditorPreview } = require('../../entry/src/main/ets/kanon/PreviewLifecycle.ets');
const { FakeEditor, deferred } = require('../support/fakes.cjs');

test('P16: clearing preview text alone leaves an empty platform session', async () => {
  const editor = new FakeEditor('傘');
  await editor.setPreview('き', -1, -1);
  await editor.setPreview('', -1, -1);
  assert.equal(editor.text, '傘');
  assert.deepEqual(editor.preview, { start: 1, end: 1 });
});

test('P16: cancellation clears then finishes without changing committed text', async () => {
  const editor = new FakeEditor('傘');
  await editor.setPreview('き', -1, -1);
  editor.calls = [];
  assert.deepEqual(await cancelEditorPreview(editor), { ok: true, code: 0 });
  assert.equal(editor.text, '傘');
  assert.equal(editor.preview, null);
  assert.deepEqual(editor.calls, [
    { operation: 'setPreview', text: '', start: -1, end: -1 },
    { operation: 'finishPreview' }
  ]);
  await editor.deleteForward(1);
  await editor.setPreview('ｋ', -1, -1);
  await editor.setPreview('き', -1, -1);
  assert.equal(editor.text, 'き');
});

test('P16: clearing must complete before ending the preview session', async () => {
  const editor = new FakeEditor();
  const clearing = deferred();
  editor.setPreview = () => clearing.promise;
  const cancellation = cancelEditorPreview(editor);
  assert.equal(editor.count('finishPreview'), 0);
  clearing.resolve({ ok: true, code: 0 });
  await cancellation;
  assert.equal(editor.count('finishPreview'), 1);
});

test('P16: failed clearing does not finish or retry and returns its error', async () => {
  const editor = new FakeEditor();
  editor.setPreview = async () => ({ ok: false, code: 12800003 });
  assert.deepEqual(await cancelEditorPreview(editor), { ok: false, code: 12800003 });
  assert.equal(editor.count('finishPreview'), 0);
});

test('P16: changed input target while clearing must not finish the new target', async () => {
  const editor = new FakeEditor();
  editor.setPreview = async () => { editor.epoch++; return { ok: true, code: 0 }; };
  assert.deepEqual(await cancelEditorPreview(editor), { ok: false, code: -4 });
  assert.equal(editor.count('finishPreview'), 0);
});

test('P16: finish errors and a target change during finish are not reported as success', async () => {
  const editor = new FakeEditor();
  editor.finishPreview = async () => ({ ok: false, code: 12800003 });
  assert.deepEqual(await cancelEditorPreview(editor), { ok: false, code: 12800003 });
  editor.finishPreview = async () => { editor.epoch++; return { ok: true, code: 0 }; };
  assert.deepEqual(await cancelEditorPreview(editor), { ok: false, code: -4 });
});
