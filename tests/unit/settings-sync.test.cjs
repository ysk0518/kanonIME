const test = require('node:test');
const assert = require('node:assert/strict');
const { REQUEST, UPDATE, CHANGE, ACK } = require('../../entry/src/main/ets/common/SettingsSyncCore.ets');
const { pair } = require('../support/settings-sync-rig.cjs');
const { deferred } = require('../support/fakes.cjs');

test('P13: authoritative save confirms only after replica apply and returning ACK', async () => {
  const r = await pair(); const save = r.app.core.save({ keyGap: 8 });
  for (let i = 0; i < 8; i++) { await Promise.resolve(); }
  assert.equal(r.app.state.states.get('settings').status, 'pending');
  await r.deliver(UPDATE);
  assert.equal(r.ime.state.applied.at(-1).snapshot.keyGap, 8);
  assert.equal(r.app.state.states.get('settings').status, 'pending');
  await r.deliver(ACK); assert.equal((await save).confirmed, true);
});

test('P13: replica save survives transport and is confirmed by owner snapshot', async () => {
  const r = await pair(); const save = r.ime.core.save({ heightPercent: 120 });
  for (let i = 0; i < 8; i++) { await Promise.resolve(); }
  assert.equal(r.ime.state.record.pending.length, 1);
  await r.deliver(CHANGE); await r.deliver(UPDATE);
  assert.equal((await save).confirmed, true);
  assert.equal(r.ime.state.record.pending.length, 0);
  assert.equal(r.app.state.record.snapshot.heightPercent, 120);
});

test('P13: failed replica application remains retryable after owner acknowledged change', async () => {
  const r = await pair(); await r.ime.core.save({ keyGap: 8 }, false);
  r.ime.core.onApplied = async () => { throw new Error('apply failed'); };
  await r.deliver(CHANGE); await r.deliver(UPDATE);
  assert.equal(r.ime.state.sent.filter(event => event.event === ACK).length, 0);
  r.ime.core.onApplied = async () => {};
  await r.clock.advance(2000); await r.pump();
  assert.equal(r.ime.state.states.get('request').status, 'applied');
});

test('P13: failed durable save publishes neither update nor saved receipt', async () => {
  const r = await pair(); r.app.state.failSave = true;
  await assert.rejects(r.app.core.save({ keyGap: 8 }), /save failed/);
  assert.equal(r.app.state.record.snapshot.keyGap, 6);
  assert.equal(r.app.state.states.has('settings'), false);
  assert.deepEqual(r.app.state.sent, []);
});

test('P13: transport failure keeps replica outbox and retry can finish later', async () => {
  const r = await pair(); r.ime.state.failPublish = true;
  await r.ime.core.save({ keyGap: 8 }, false); await r.clock.advance(0);
  assert.equal(r.ime.state.record.pending.length, 1);
  assert.equal(r.ime.state.states.get('request').status, 'error');
  r.ime.state.failPublish = false; await r.clock.advance(2000); await r.pump();
  assert.equal(r.ime.state.record.pending.length, 0);
  assert.equal(r.ime.state.states.get('request').status, 'applied');
});

test('P13: dropped change is resent with the same actor, sequence and patch', async () => {
  const r = await pair(); await r.ime.core.save({ keyGap: 8 }, false); await r.clock.advance(0);
  const dropped = r.messages.splice(r.messages.findIndex(event => event.event === CHANGE), 1)[0];
  assert.ok(dropped); await r.clock.advance(2000);
  const resent = r.messages.find(event => event.event === CHANGE);
  assert.equal(resent.data, dropped.data); await r.pump();
  assert.equal(r.ime.state.states.get('request').status, 'applied');
});

test('P13: pending onApplied must finish before sending ACK', async () => {
  const r = await pair(); const started = deferred(); const applied = deferred();
  r.ime.core.onApplied = async () => { started.resolve(); await applied.promise; };
  const save = r.app.core.save({ keyGap: 8 });
  const delivery = r.deliver(UPDATE); await started.promise;
  assert.equal(r.messages.some(event => event.event === ACK), false);
  assert.equal(r.app.state.states.get('settings').status, 'pending');
  applied.resolve(); await delivery; await r.deliver(ACK);
  assert.equal((await save).confirmed, true);
});

test('P13: replica storage failure does not ACK or consume pending changes', async () => {
  const r = await pair(); await r.ime.core.save({ keyGap: 8 }, false);
  r.ime.state.failSave = true; await r.deliver(CHANGE); await r.deliver(UPDATE);
  assert.equal(r.ime.state.record.pending.length, 1);
  assert.equal(r.ime.state.sent.some(event => event.event === ACK), false);
  r.ime.state.failSave = false; await r.clock.advance(2000); await r.pump();
  assert.equal(r.ime.state.states.get('request').status, 'applied');
});

test('P13: failed ACK publication retries application confirmation without losing saved settings', async () => {
  const r = await pair(); const save = r.app.core.save({ keyGap: 8 });
  r.ime.state.failPublish = true; await r.deliver(UPDATE);
  assert.equal(r.ime.state.record.snapshot.keyGap, 8);
  assert.equal(r.app.state.states.get('settings').status, 'pending');
  r.ime.state.failPublish = false; await r.clock.advance(2000); await r.pump();
  // The first caller's two-second wait has already expired; late ACK updates live status.
  assert.equal((await save).confirmed, false);
  assert.equal(r.app.state.states.get('settings').status, 'applied');
});

test('P13: duplicate change does not advance authoritative revision or reapply patch', async () => {
  const r = await pair(); await r.ime.core.save({ keyGap: 8 }, false);
  const change = await r.deliver(CHANGE); const revision = r.app.state.record.snapshot.revision;
  await r.app.core.receiveEvent(change);
  assert.equal(r.app.state.record.snapshot.revision, revision);
  assert.equal(r.app.state.record.peers.length, 1);
  await r.pump(); assert.equal(r.ime.state.record.pending.length, 0);
});

test('P13: wrong sender and oversized update are ignored before storage or application', async () => {
  const r = await pair(); const before = JSON.stringify(r.ime.state.record);
  const snapshot = { ...r.app.state.record.snapshot, revision: 200, keyGap: 8 };
  await r.ime.core.receiveEvent({ event: UPDATE, sender: 'ime', data: JSON.stringify(snapshot) });
  await r.ime.core.receiveEvent({ event: UPDATE, sender: 'app', data: ' '.repeat(4001) });
  assert.equal(JSON.stringify(r.ime.state.record), before); assert.deepEqual(r.ime.state.applied, []);
});

test('P13: malformed JSON does not poison receive queue for a later valid update', async () => {
  const r = await pair();
  await assert.rejects(r.ime.core.receiveEvent({ event: UPDATE, sender: 'app', data: '{' }));
  await r.ime.core.receiveEvent({ event: UPDATE, sender: 'app', data: JSON.stringify({
    ...r.app.state.record.snapshot, revision: 200, keyGap: 8
  }) });
  assert.equal(r.ime.state.record.snapshot.keyGap, 8);
  assert.equal(r.ime.state.applied.length, 1);
});

test('P13: future ACK sequence cannot confirm or remove a replica saved change', async () => {
  const r = await pair(); await r.ime.core.save({ keyGap: 8 }, false);
  await r.ime.core.receiveEvent({ event: UPDATE, sender: 'app', actor: '2-2', sequence: 99,
    data: JSON.stringify({ ...r.app.state.record.snapshot, revision: 200 }) });
  assert.equal(r.ime.state.record.pending.length, 1);
  assert.notEqual(r.ime.state.states.get('request').status, 'applied');
});

test('P13: back-to-back replica edits retain sequence order and both reach owner', async () => {
  const r = await pair();
  await Promise.all([r.ime.core.save({ keyGap: 8 }, false), r.ime.core.save({ heightPercent: 120 }, false)]);
  assert.deepEqual(r.ime.state.record.pending.map(change => change.sequence), [1, 2]);
  await r.pump();
  assert.equal(r.app.state.record.snapshot.keyGap, 8); assert.equal(r.app.state.record.snapshot.heightPercent, 120);
  assert.equal(r.ime.state.record.pending.length, 0);
  assert.equal(r.ime.state.states.get('request').status, 'applied');
});

test('P13: repeated application failure retries again with height refresh still requested', async () => {
  const r = await pair(); await r.ime.core.save({ keyGap: 8 }, false);
  const heights = [];
  r.ime.core.onApplied = async (snapshot, heightChanged) => {
    heights.push(heightChanged); if (heights.length < 3) { throw new Error('not ready'); }
  };
  await r.deliver(CHANGE);
  const update = r.messages.find(event => event.event === UPDATE);
  const snapshot = JSON.parse(update.data); snapshot.heightPercent = 120; update.data = JSON.stringify(snapshot);
  await r.deliver(UPDATE);
  await r.clock.advance(2000); assert.equal(heights.length, 2);
  await r.clock.advance(2000); await r.pump();
  assert.deepEqual(heights, [true, true, true]);
  assert.equal(r.ime.state.states.get('request').status, 'applied');
});

test('P13: exhausted application budget keeps saved values and explicit request can recover', async () => {
  const r = await pair(); await r.ime.core.save({ keyGap: 8 }, false);
  let failure = true; let attempts = 0;
  r.ime.core.onApplied = async () => { attempts++; if (failure) { throw new Error('not ready'); } };
  await r.deliver(CHANGE); await r.deliver(UPDATE);
  for (let i = 0; i < 3; i++) { await r.clock.advance(2000); }
  assert.equal(attempts, 4); assert.equal(r.ime.state.record.snapshot.keyGap, 8);
  assert.notEqual(r.ime.state.states.get('request').status, 'applied');
  failure = false; await r.ime.core.request(); await r.pump();
  assert.equal(r.ime.state.states.get('request').status, 'applied');
});

test('P13: editing during peer application causes latest effective settings to be applied again', async () => {
  const r = await pair(); await r.ime.core.save({ keyGap: 8 }, false);
  const started = deferred(); const gate = deferred(); const peerHeights = [];
  r.ime.core.onApplied = async (snapshot, heightChanged, fromPeer) => {
    if (!fromPeer) { return; }
    peerHeights.push(snapshot.heightPercent);
    if (peerHeights.length === 1) { started.resolve(); await gate.promise; }
  };
  await r.deliver(CHANGE); const update = r.deliver(UPDATE); await started.promise;
  await r.ime.core.save({ heightPercent: 120 }, false); gate.resolve(); await update;
  assert.ok(peerHeights.includes(120));
  await r.pump();
  assert.equal(r.app.state.record.snapshot.heightPercent, 120);
  assert.equal(r.ime.state.states.get('request').status, 'applied');
});
