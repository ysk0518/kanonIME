const test = require('node:test');
const assert = require('node:assert/strict');
const { ExternalEditorSync } = require('../../entry/src/main/ets/kanon/ExternalEditorSync.ets');
const { deferred } = require('../support/fakes.cjs');

function rig() {
  const state = { epoch: 1, reads: 0, result: { ok: true, code: 0, value: false } };
  const port = { getEpoch: () => state.epoch, queryEmpty: async () => { state.reads++; return state.result; } };
  return { state, port, sync: new ExternalEditorSync(port) };
}

test('external editor: no hint or composition does not read the field', async () => {
  const r = rig();
  assert.equal(await r.sync.reconcile(true), 'ignored');
  r.sync.textChanged(1, true);
  assert.equal(await r.sync.reconcile(false), 'ignored');
  assert.equal(await r.sync.reconcile(true), 'ignored');
  assert.equal(r.state.reads, 0);
});
test('external editor: empty text is a hint, not proof of an empty field', async () => {
  const r = rig(); r.sync.textChanged(1, true);
  assert.equal(await r.sync.reconcile(true), 'present');
  assert.equal(r.sync.hasPending(), false);
});
test('external editor: position zero and range selections do not imply deletion', async () => {
  const r = rig(); r.sync.selectionChanged(1, 0, 2);
  assert.equal(await r.sync.reconcile(true), 'ignored');
  r.sync.selectionChanged(1, 0, 0);
  assert.equal(await r.sync.reconcile(true), 'present');
});
test('external editor: only a successful current-client empty read proves empty', async () => {
  const r = rig(); r.state.result.value = true; r.sync.textChanged(1, true);
  assert.equal(await r.sync.reconcile(true), 'empty');
  assert.equal(await r.sync.reconcile(true), 'ignored');
});
test('external editor: failed reads and timeouts preserve state and remain pending', async () => {
  for (const code of [-3, -6, 12800003]) {
    const r = rig(); r.sync.textChanged(1, true);
    r.state.result = { ok: false, code, value: undefined };
    assert.equal(await r.sync.reconcile(true), 'failed');
    assert.equal(r.sync.hasPending(), true);
  }
});
test('external editor: a hidden panel and client error do not prove an empty field', async () => {
  const r = rig(); r.sync.visibilityChanged(1);
  r.state.result = { ok: false, code: 12800003, value: undefined };
  assert.equal(await r.sync.reconcile(true), 'failed');
  assert.equal(r.sync.hasPending(), true);
});
test('external editor: hiding alone or a hidden timeout must not discard the draft', async () => {
  const r = rig(); r.sync.visibilityChanged(1);
  assert.equal(await r.sync.reconcile(true), 'present');
  r.sync.visibilityChanged(1);
  r.state.result = { ok: false, code: -3, value: undefined };
  assert.equal(await r.sync.reconcile(true), 'failed');
});
test('external editor: a changed target rejects the old empty read', async () => {
  const r = rig(); const d = deferred(); r.port.queryEmpty = () => d.promise;
  r.sync.textChanged(1, true); const pending = r.sync.reconcile(true); r.state.epoch = 2;
  d.resolve({ ok: true, code: 0, value: true });
  assert.equal(await pending, 'stale');
});
test('external editor: later notifications invalidate a read before state changes', async () => {
  const r = rig(); const d = deferred(); r.port.queryEmpty = () => d.promise;
  r.sync.textChanged(1, true); const pending = r.sync.reconcile(true); r.sync.selectionChanged(1, 2, 2);
  d.resolve({ ok: true, code: 0, value: true });
  assert.equal(await pending, 'retry');
});
test('external editor: a reopening panel invalidates an in-flight hidden-client error', async () => {
  const r = rig(); const d = deferred(); r.port.queryEmpty = () => d.promise;
  r.sync.visibilityChanged(1); const pending = r.sync.reconcile(true); r.sync.visibilityChanged(1);
  d.resolve({ ok: false, code: 12800003, value: undefined });
  assert.equal(await pending, 'retry');
});
test('external editor: reset drops hints from the previous composition', async () => {
  const r = rig(); r.sync.textChanged(1, true); r.sync.reset();
  assert.equal(await r.sync.reconcile(true), 'ignored');
  assert.equal(r.state.reads, 0);
});
test('external editor: an exception cannot become an empty read', async () => {
  const r = rig(); r.sync.textChanged(1, true); r.port.queryEmpty = async () => { throw new Error('read failed'); };
  assert.equal(await r.sync.reconcile(true), 'failed');
});
