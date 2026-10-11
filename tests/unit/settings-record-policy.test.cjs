const test = require('node:test');
const assert = require('node:assert/strict');
const { KeyboardSettingsRecord, copySettings, decodeSettingsRecord } = require('../../entry/src/main/ets/common/KeyboardSettingsModel.ets');
const { effectiveSettings, committedSettingsRecord, queuedSettingsRecord,
  receivedSettingsRecord, acceptedSettingsRecord } = require('../../entry/src/main/ets/common/SettingsRecordPolicy.ets');
const { saveSettingsRecord } = require('../../entry/src/main/ets/common/SettingsPersistence.ets');

function record() { const r = new KeyboardSettingsRecord(); r.actor = '1-2'; r.snapshot.revision = 100; return r; }
// Persistence uses JSON data; runtime class prototypes are not part of the record contract.
function data(value) { return JSON.parse(JSON.stringify(value)); }
function queued() {
  return queuedSettingsRecord(queuedSettingsRecord(record(), { keyGap: 8 }).record, { heightPercent: 120 }).record;
}
function storage() {
  const state = { calls: [], payload: '', durable: '', writeError: false, flushError: false };
  state.port = { maximumLength: 10000, write: payload => {
    state.calls.push('write'); if (state.writeError) { throw new Error('write failed'); } state.payload = payload;
  }, flush: () => {
    state.calls.push('flush'); if (state.flushError) { throw new Error('flush failed'); } state.durable = state.payload;
  } };
  return state;
}

test('P11: effective settings overlay pending changes without changing authoritative base', () => {
  const r = queued(); const before = JSON.stringify(r); const view = effectiveSettings(r);
  assert.equal(view.keyGap, 8); assert.equal(view.heightPercent, 120);
  assert.equal(r.snapshot.keyGap, 6); assert.equal(r.snapshot.heightPercent, 100);
  assert.equal(JSON.stringify(r), before);
});

test('P11: first queued change receives actor and sequence while base remains unchanged', () => {
  const r = record(); const result = queuedSettingsRecord(r, { keyGap: 8 });
  assert.deepEqual(data(result.change), { actor: '1-2', sequence: 1, patch: { keyGap: 8 } });
  assert.equal(result.record.nextSequence, 2); assert.equal(result.record.snapshot.revision, 100);
  assert.equal(r.pending.length, 0); assert.equal(r.nextSequence, 1);
});

test('P11: later edits merge only unsent tail and never modify sent head or sequence', () => {
  const r = queued(); const head = JSON.stringify(r.pending[0]);
  const result = queuedSettingsRecord(r, { keyGap: 0, keyPreview: false });
  assert.equal(result.record.pending.length, 2);
  assert.equal(JSON.stringify(result.record.pending[0]), head);
  assert.equal(result.change.sequence, 2); assert.equal(result.record.nextSequence, 3);
  assert.deepEqual(result.change.patch, { heightPercent: 120, keyGap: 0, keyPreview: false });
  assert.deepEqual(r.pending[1].patch, { heightPercent: 120 });
});

test('P11: queued patch is copied and invalid patch consumes no sequence', () => {
  const r = record(); const patch = { keyGap: 8 }; const result = queuedSettingsRecord(r, patch);
  patch.keyGap = 9; assert.equal(result.change.patch.keyGap, 8);
  assert.throws(() => queuedSettingsRecord(r, { keyGap: 99 }));
  assert.equal(r.nextSequence, 1); assert.deepEqual(r.pending, []);
});

test('P11: ACK removes confirmed head and retains later pending edits over new base', () => {
  const r = queued(); const snapshot = copySettings(r.snapshot); snapshot.keyGap = 8; snapshot.revision = 200;
  const next = receivedSettingsRecord(r, snapshot, r.actor, 1);
  assert.deepEqual(next.pending.map(change => change.sequence), [2]);
  assert.equal(effectiveSettings(next).heightPercent, 120);
  assert.equal(next.snapshot.heightPercent, 100); assert.equal(next.snapshot.keyGap, 8);
  assert.equal(r.pending.length, 2); assert.equal(next.bootstrapComplete, true);
});

test('P11: foreign actor or future ACK cannot remove local pending changes', () => {
  const r = queued();
  for (const [actor, sequence] of [['3-4', 2], [r.actor, 3], [r.actor, -1]]) {
    const next = receivedSettingsRecord(r, r.snapshot, actor, sequence);
    assert.equal(next.pending.length, 2);
  }
});

test('P11: older snapshot never rolls back newer authoritative settings', () => {
  const r = queued(); const old = copySettings(r.snapshot); old.revision = 99; old.keyGap = 0;
  const next = receivedSettingsRecord(r, old, '3-4', 0);
  assert.equal(next.snapshot.revision, 100); assert.equal(next.snapshot.keyGap, 6);
  assert.equal(effectiveSettings(next).keyGap, 8);
});

test('P11: duplicate or out-of-order peer changes are not applied again', () => {
  const first = acceptedSettingsRecord(record(), { actor: '3-4', sequence: 1, patch: { keyGap: 8 } }, 200);
  for (const sequence of [1, 0, 3]) {
    assert.equal(acceptedSettingsRecord(first, { actor: '3-4', sequence, patch: { keyGap: 0 } }, 300), undefined);
  }
  assert.equal(first.snapshot.keyGap, 8); assert.equal(first.snapshot.revision, 200);
});

test('P11: next peer change preserves unedited values and advances revision with backward clock', () => {
  const first = acceptedSettingsRecord(record(), { actor: '3-4', sequence: 1, patch: { keyGap: 8 } }, 200);
  const next = acceptedSettingsRecord(first, { actor: '3-4', sequence: 2, patch: { heightPercent: 120 } }, 50);
  assert.equal(next.snapshot.revision, 201); assert.equal(next.snapshot.keyGap, 8);
  assert.equal(next.snapshot.heightPercent, 120); assert.equal(next.heightChosen, true);
  assert.equal(first.snapshot.heightPercent, 100); assert.equal(next.peers[0].sequence, 2);
});

test('P11: peer history stays bounded at thirty-two entries', () => {
  const r = record(); r.peers = Array.from({ length: 32 }, (_, i) => ({ actor: `${i + 10}-1`, sequence: 1 }));
  const next = acceptedSettingsRecord(r, { actor: '99-1', sequence: 1, patch: {} }, 200);
  assert.equal(next.peers.length, 32); assert.equal(next.peers[0].actor, '11-1');
  assert.equal(next.peers.at(-1).actor, '99-1'); assert.equal(r.peers[0].actor, '10-1');
});

test('P11: commit records explicit choices and does not discard the pending outbox', () => {
  const r = queued(); const next = committedSettingsRecord(r, { heightPercent: 130, layoutOrder: 'en_qwerty' }, 200);
  assert.equal(next.heightChosen, true); assert.equal(next.languagesChosen, true);
  assert.equal(next.snapshot.heightPercent, 130); assert.equal(next.snapshot.layoutOrder, 'en_qwerty');
  assert.deepEqual(data(next.pending), data(r.pending)); assert.equal(r.heightChosen, false);
});

test('P11: revision advances even when timestamp does not increase', () => {
  assert.equal(committedSettingsRecord(record(), {}, 50).snapshot.revision, 101);
});

test('P11: returned snapshots do not alias pending changes or authoritative values', () => {
  const r = queued(); const next = receivedSettingsRecord(r, r.snapshot, '3-4', 0);
  next.pending[0].patch.keyGap = 0; next.snapshot.keyGap = 9;
  assert.equal(r.pending[0].patch.keyGap, 8); assert.equal(r.snapshot.keyGap, 6);
});

test('P11: save writes serialized record then flushes before returning success', () => {
  const r = record(); const s = storage(); saveSettingsRecord(r, s.port);
  assert.deepEqual(s.calls, ['write', 'flush']);
  assert.equal(decodeSettingsRecord(s.durable).actor, r.actor);
});

test('P11: invalid record is rejected before accessing storage', () => {
  const s = storage(); const r = record(); r.schema = 2;
  assert.throws(() => saveSettingsRecord(r, s.port), /Invalid settings record/);
  assert.deepEqual(s.calls, []);
});

test('P11: storage length limit is checked before write and exact limit is accepted', () => {
  const s = storage(); const r = record(); s.port.maximumLength = JSON.stringify(r).length - 1;
  assert.throws(() => saveSettingsRecord(r, s.port), /Settings storage limit/);
  assert.deepEqual(s.calls, []); s.port.maximumLength++;
  saveSettingsRecord(r, s.port); assert.deepEqual(s.calls, ['write', 'flush']);
});

test('P11: write failure is reported without flush or retry', () => {
  const s = storage(); s.writeError = true;
  assert.throws(() => saveSettingsRecord(record(), s.port), /write failed/);
  assert.deepEqual(s.calls, ['write']); assert.equal(s.durable, '');
});

test('P11: flush failure is reported and does not mutate the source record', () => {
  const r = queued(); const before = JSON.stringify(r); const s = storage(); s.flushError = true;
  assert.throws(() => saveSettingsRecord(r, s.port), /flush failed/);
  assert.deepEqual(s.calls, ['write', 'flush']); assert.equal(JSON.stringify(r), before);
  assert.equal(s.durable, '');
});

test('P11: persisted outbox survives reload and keeps its effective edits', () => {
  const r = queued(); const s = storage(); saveSettingsRecord(r, s.port);
  const reloaded = decodeSettingsRecord(s.durable);
  assert.deepEqual(data(reloaded.pending), data(r.pending));
  assert.equal(effectiveSettings(reloaded).keyGap, 8); assert.equal(effectiveSettings(reloaded).heightPercent, 120);
});

test('P11: failed save of a prepared change leaves the prior immutable record available', () => {
  const original = record(); const prepared = queuedSettingsRecord(original, { keyGap: 8 });
  const s = storage(); s.flushError = true;
  assert.throws(() => saveSettingsRecord(prepared.record, s.port));
  assert.deepEqual(original.pending, []); assert.equal(original.nextSequence, 1);
  assert.equal(effectiveSettings(original).keyGap, 6);
});
