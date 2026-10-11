const test = require('node:test');
const assert = require('node:assert/strict');
const { SettingsReceiptStore } = require('../../entry/src/main/ets/common/SettingsReceiptState.ets');
const { SettingsRetryTimer } = require('../../entry/src/main/ets/common/SettingsRetryTimer.ets');
const { validRequestReceipt } = require('../../entry/src/main/ets/common/SettingsAckPolicy.ets');

function clock() {
  let now = 0; let serial = 0; const timers = new Map(); const callbacks = new Map();
  return { timers, callbacks,
    schedule(callback, delay) { const id = serial++; timers.set(id, { callback, due: now + delay }); callbacks.set(id, callback); return id; },
    unschedule(id) { timers.delete(id); },
    advance(ms) { now += ms; for (const [id, entry] of [...timers]) {
      if (entry.due <= now) { timers.delete(id); entry.callback(); }
    } }
  };
}
function receipt() {
  const c = clock(); const states = new Map(); const logs = [];
  const store = new SettingsReceiptStore({ schedule: c.schedule, unschedule: c.unschedule,
    publish: (scope, saved, applied, state) => states.set(scope, { saved, applied, state }),
    log: (...args) => logs.push(args) });
  return { c, store, states, logs };
}
function retry() {
  const c = clock(); const r = { c, calls: 0, errors: [], pending: null };
  r.timer = new SettingsRetryTimer({ schedule: c.schedule, unschedule: c.unschedule,
    retry: async () => { r.calls++; if (r.pending) { await r.pending; } r.timer.schedule(); },
    failed: error => r.errors.push(error) });
  return r;
}

test('P12: saved revision stays pending until an applied confirmation', () => {
  const r = receipt(); r.store.saved('settings', 10);
  assert.deepEqual(r.states.get('settings'), { saved: 10, applied: 0, state: 'pending' });
});
test('P12: applied confirmation resolves matching wait and cancels its timer', async () => {
  const r = receipt(); r.store.saved('settings', 10); const wait = r.store.wait('settings', 10);
  r.store.applied('settings', 10);
  assert.equal(await wait, true); assert.equal(r.c.timers.size, 0);
  assert.equal(r.states.get('settings').state, 'applied');
});
test('P12: older ACK cannot confirm a newer saved revision', async () => {
  const r = receipt(); r.store.saved('settings', 20); const wait = r.store.wait('settings', 20);
  r.store.applied('settings', 10); r.c.advance(2000);
  assert.equal(await wait, false); assert.equal(r.states.get('settings').state, 'pending');
});
test('P12: multiple waiters complete only up to the confirmed revision', async () => {
  const r = receipt(); const first = r.store.wait('request', 1); const second = r.store.wait('request', 2);
  r.store.applied('request', 1); assert.equal(await first, true); assert.equal(r.c.timers.size, 1);
  r.c.advance(2000); assert.equal(await second, false);
});
test('P12: settings, request and background confirmations are independent', async () => {
  const r = receipt(); const wait = r.store.wait('background', 1);
  r.store.applied('settings', 10); r.store.applied('request', 10); r.c.advance(2000);
  assert.equal(await wait, false);
});
test('P12: timeout returns false while preserving saved data and pending state', async () => {
  const r = receipt(); r.store.saved('request', 2); const wait = r.store.wait('request', 2, 100);
  r.c.advance(99); assert.equal(r.c.timers.size, 1); r.c.advance(1);
  assert.equal(await wait, false);
  assert.deepEqual(r.states.get('request'), { saved: 2, applied: 0, state: 'pending' });
  assert.equal(r.logs.filter(log => log[0] === 'timeout').length, 1);
});
test('P12: late ACK after timeout updates applied state and future wait succeeds', async () => {
  const r = receipt(); r.store.saved('request', 2); const wait = r.store.wait('request', 2);
  r.c.advance(2000); assert.equal(await wait, false); r.store.applied('request', 2);
  assert.equal(await r.store.wait('request', 2), true); assert.equal(r.c.timers.size, 0);
});
test('P12: confirmation received before wait needs no timer', async () => {
  const r = receipt(); r.store.applied('settings', 10);
  assert.equal(await r.store.wait('settings', 10), true); assert.equal(r.c.timers.size, 0);
});
test('P12: notification failure preserves saved and applied revisions', () => {
  const r = receipt(); r.store.applied('settings', 5); r.store.saved('settings', 10); r.store.failed('settings', 'failure');
  assert.deepEqual(r.states.get('settings'), { saved: 10, applied: 5, state: 'error' });
});
test('P12: stale cancelled timeout does not log or resolve again after confirmation', async () => {
  const r = receipt(); const wait = r.store.wait('settings', 10); const callback = r.c.callbacks.get(0);
  r.store.applied('settings', 10); assert.equal(await wait, true); callback();
  assert.equal(r.logs.some(log => log[0] === 'timeout'), false);
});
test('P12: older saved or applied values never roll revision tracking back', () => {
  const r = receipt(); r.store.saved('settings', 20); r.store.saved('settings', 10);
  r.store.applied('settings', 20); r.store.applied('settings', 10);
  assert.deepEqual(r.states.get('settings'), { saved: 20, applied: 20, state: 'applied' });
});
test('P12: separate receipt stores do not share applied state', async () => {
  const first = receipt(); const second = receipt(); first.store.applied('settings', 10);
  const wait = second.store.wait('settings', 10); second.c.advance(2000);
  assert.equal(await wait, false);
});
test('P12: retry budget permits three attempts and then stops', async () => {
  const r = retry(); r.timer.schedule();
  for (let i = 0; i < 4; i++) { r.c.advance(2000); await Promise.resolve(); }
  assert.equal(r.calls, 3); assert.equal(r.c.timers.size, 0);
});
test('P12: repeated scheduling creates a single timer and waits two seconds', () => {
  const r = retry(); r.timer.schedule(); r.timer.schedule();
  assert.equal(r.c.timers.size, 1); r.c.advance(1999); assert.equal(r.calls, 0);
  r.c.advance(1); assert.equal(r.calls, 1);
});
test('P12: stopping retries cancels timer and resets budget', async () => {
  const r = retry(); r.timer.schedule(); r.timer.stop(); r.c.advance(2000);
  assert.equal(r.calls, 0); r.timer.schedule();
  for (let i = 0; i < 3; i++) { r.c.advance(2000); await Promise.resolve(); }
  assert.equal(r.calls, 3);
});
test('P12: an old cancelled callback cannot consume a new timer', () => {
  const r = retry(); r.timer.schedule(); const old = r.c.callbacks.get(0);
  r.timer.stop(); r.timer.schedule(); old();
  assert.equal(r.calls, 0); assert.equal(r.c.timers.size, 1);
});
test('P12: resetting budget preserves the existing scheduled deadline', () => {
  const r = retry(); r.timer.schedule(); r.c.advance(1000); r.timer.resetBudget(); r.timer.schedule();
  assert.equal(r.c.timers.size, 1); r.c.advance(1000); assert.equal(r.calls, 1);
});
test('P12: late retry failure after stop cannot mark a new sync attempt failed', async () => {
  const r = retry(); let reject;
  r.pending = new Promise((resolve, fail) => { reject = fail; });
  r.timer.schedule(); r.c.advance(2000); r.timer.stop(); reject(new Error('old failure'));
  await Promise.resolve(); await Promise.resolve(); assert.deepEqual(r.errors, []);
});
test('P12: active retry failure is reported once without an implicit retry', async () => {
  const r = retry(); let reject; const failure = new Error('active failure');
  r.pending = new Promise((resolve, fail) => { reject = fail; });
  r.timer.schedule(); r.c.advance(2000); reject(failure);
  await Promise.resolve(); await Promise.resolve(); assert.deepEqual(r.errors, [failure]);
  assert.equal(r.c.timers.size, 0);
});
test('P12: request receipts require own actor and an issued safe sequence', () => {
  assert.equal(validRequestReceipt('1-2', '1-2', 2, 2), true);
  for (const [actor, sequence] of [['3-4', 2], ['1-2', 3], ['1-2', -1], ['1-2', NaN], ['1-2', 1.5]]) {
    assert.equal(validRequestReceipt(actor, '1-2', sequence, 2), false);
  }
});
test('P12: a future request ACK does not falsely confirm locally saved edits', async () => {
  const r = receipt(); r.store.saved('request', 2);
  if (validRequestReceipt('1-2', '1-2', 3, 2)) { r.store.applied('request', 3); }
  const wait = r.store.wait('request', 2); r.c.advance(2000);
  assert.equal(await wait, false); assert.equal(r.states.get('request').state, 'pending');
});
