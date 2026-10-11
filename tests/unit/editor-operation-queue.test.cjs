const test = require('node:test');
const assert = require('node:assert/strict');
const { EDITOR_OPERATION_TIMEOUT_MS } = require('../../entry/src/main/ets/kanon/EditorOperationQueue.ets');
const { cancelEditorPreview } = require('../../entry/src/main/ets/kanon/PreviewLifecycle.ets');
const { editorQueueRig, waitingOperation, pending } = require('../support/editor-queue-rig.cjs');

test('P17: without an input client both operation paths reject without dispatch', async () => {
  const r = editorQueueRig(false); let calls = 0;
  assert.deepEqual(await r.queue.enqueue('write', async () => { calls++; return 'done'; }),
    { op: 'write', ok: false, code: -1, detail: 'no-client' });
  assert.deepEqual(await r.queue.enqueueValue('read', async () => { calls++; return ''; }),
    { ok: false, code: -1, value: undefined });
  assert.equal(calls, 0); assert.equal(r.clock.timers.size, 0);
});

test('P17: attach and detach advance the input target generation', () => {
  const r = editorQueueRig(false);
  assert.equal(r.queue.getEpoch(), 0);
  assert.equal(r.queue.attach(r.client), 1);
  assert.equal(r.queue.attach(r.client), 2);
  assert.equal(r.queue.detach(), 3);
});

test('P17: metadata operations use the attached client and preserve operation details', async () => {
  const r = editorQueueRig();
  assert.deepEqual(await r.queue.enqueue('insert', async client => {
    assert.equal(client, r.client); return 'len=2';
  }), { op: 'insert', ok: true, code: 0, detail: 'len=2' });
  assert.deepEqual(r.logs, [['insert', 'ok', 'len=2']]);
  assert.equal(r.clock.timers.size, 0);
});

test('P17: empty text, zero position and false values are successful reads', async () => {
  const r = editorQueueRig();
  for (const value of ['', 0, false]) {
    assert.deepEqual(await r.queue.enqueueValue('read', async () => value), { ok: true, code: 0, value });
  }
  assert.equal(r.clock.timers.size, 0);
});

test('P17: writes and reads share one FIFO until the full operation completes', async () => {
  const r = editorQueueRig(); const calls = [];
  const gate = pending(), entered = pending();
  const first = r.queue.enqueue('first', async () => { calls.push('first'); entered.resolve(); await gate.promise; return 'done'; });
  const read = r.queue.enqueueValue('read', async () => { calls.push('read'); return 3; });
  const last = r.queue.enqueue('last', async () => { calls.push('last'); return 'done'; });
  await entered.promise; assert.deepEqual(calls, ['first']);
  gate.resolve(); await Promise.all([first, read, last]);
  assert.deepEqual(calls, ['first', 'read', 'last']);
});

test('P17: a multi-await operation keeps subsequent calls waiting through readback', async () => {
  const r = editorQueueRig(); const firstStage = pending(), readback = pending(), reachedReadback = pending();
  let nextCalls = 0;
  const first = r.queue.enqueue('caret', async () => { await firstStage.promise; reachedReadback.resolve(); await readback.promise; return 'matched=true'; });
  const next = r.queue.enqueue('next', async () => { nextCalls++; return 'done'; });
  firstStage.resolve(); await reachedReadback.promise; assert.equal(nextCalls, 0);
  readback.resolve(); await Promise.all([first, next]); assert.equal(nextCalls, 1);
});

test('P17: platform rejection is not retried and does not strand the queue', async () => {
  const r = editorQueueRig(); let calls = 0;
  assert.deepEqual(await r.queue.enqueue('rejected', async () => { calls++; return null; }),
    { op: 'rejected', ok: false, code: -5, detail: 'rejected' });
  assert.equal(calls, 1);
  assert.equal((await r.queue.enqueue('next', async () => 'done')).ok, true);
});

test('P17: asynchronous SDK errors keep their code and never log the error message', async () => {
  const r = editorQueueRig(); const error = Object.assign(new Error('fixture-message-not-for-log'), { code: 12800003 });
  assert.deepEqual(await r.queue.enqueue('failed', async () => { throw error; }),
    { op: 'failed', ok: false, code: 12800003, detail: 'code=12800003' });
  assert.equal(JSON.stringify(r.logs).includes(error.message), false);
  assert.equal((await r.queue.enqueueValue('next', async () => 0)).ok, true);
  assert.equal(r.clock.timers.size, 0);
});

test('P17: synchronous callback errors are caught before creating a deadline', async () => {
  const r = editorQueueRig();
  assert.equal((await r.queue.enqueue('failed', () => { throw new Error('fixture'); })).code, -2);
  assert.equal(r.clock.callbacks.size, 0);
  assert.equal((await r.queue.enqueue('next', async () => 'done')).ok, true);
});

test('P17: read payload stays in the returned value and never in metadata logs', async () => {
  const r = editorQueueRig(); const value = 'fixed-read-payload';
  assert.deepEqual(await r.queue.enqueueValue('qForward', async () => value), { ok: true, code: 0, value });
  assert.deepEqual(r.logs, [['qForward', 'ok', '']]);
});

test('P17: the existing three-second deadline expires once without resending', async () => {
  const r = editorQueueRig(); const task = waitingOperation(r.queue);
  await task.started; assert.equal(EDITOR_OPERATION_TIMEOUT_MS, 3000);
  r.clock.advance(2999); assert.equal(r.logs.length, 0);
  r.clock.advance(1);
  assert.deepEqual(await task.result, { op: 'waiting', ok: false, code: -3, detail: 'timeout' });
  r.clock.advance(9000); assert.deepEqual(r.logs, [['waiting', 'timeout', '']]);
  task.completion.resolve('done');
});

test('P17: unresolved timed-out writes block both subsequent operation paths', async () => {
  const r = editorQueueRig(); const task = waitingOperation(r.queue); let calls = 0;
  await task.started; r.clock.advance(3000); await task.result;
  assert.deepEqual(await r.queue.enqueue('blocked', async () => { calls++; return 'done'; }),
    { op: 'blocked', ok: false, code: -6, detail: 'unresolved-write' });
  assert.deepEqual(await r.queue.enqueueValue('blocked-read', async () => { calls++; return ''; }),
    { ok: false, code: -6, value: undefined });
  assert.equal(calls, 0); task.completion.resolve('done');
});

test('P17: late write success opens the queue without changing the timeout result', async () => {
  const r = editorQueueRig(); const task = waitingOperation(r.queue);
  await task.started; r.clock.advance(3000); const timedOut = await task.result;
  task.completion.resolve('len=1'); await task.completion.promise;
  assert.equal((await r.queue.enqueue('next', async () => 'done')).ok, true);
  assert.equal(timedOut.ok, false); assert.equal(timedOut.code, -3);
  assert.equal(r.logs.filter(log => log[0] === 'waiting' && log[1] === 'ok').length, 0);
});

test('P17: late write failure also opens the queue without retry or a false success', async () => {
  const r = editorQueueRig(); const task = waitingOperation(r.queue);
  await task.started; r.clock.advance(3000); await task.result;
  task.completion.reject(new Error('fixture-late-failure'));
  await assert.rejects(task.completion.promise);
  assert.equal((await r.queue.enqueue('next', async () => 'done')).ok, true);
  assert.equal(r.logs.filter(log => log[0] === 'waiting').length, 1);
});

test('P17: a read timeout permits later writes and ignores the late payload', async () => {
  const r = editorQueueRig(); const task = waitingOperation(r.queue, true);
  await task.started; r.clock.advance(3000);
  assert.deepEqual(await task.result, { ok: false, code: -3, value: undefined });
  assert.equal((await r.queue.enqueue('next', async () => 'done')).ok, true);
  task.completion.resolve('fixed-late-payload'); await task.completion.promise;
  assert.equal(JSON.stringify(r.logs).includes('fixed-late-payload'), false);
});

test('P17: attaching a new target bypasses the old unresolved queue', async () => {
  const r = editorQueueRig(); const task = waitingOperation(r.queue);
  await task.started; const newClient = { name: 'new-target' }; r.queue.attach(newClient);
  let dispatchedClient;
  const next = r.queue.enqueue('new', async client => { dispatchedClient = client; return 'done'; });
  try {
    await Promise.resolve();
    assert.equal(dispatchedClient, newClient, 'New target dispatch must not wait for the old unresolved operation');
    assert.equal((await next).ok, true);
  } finally { task.completion.resolve('done'); await task.result; }
});

test('P17: old queued operations never dispatch onto a new target', async () => {
  const r = editorQueueRig(); const task = waitingOperation(r.queue); let calls = 0;
  await task.started;
  const oldQueued = r.queue.enqueue('old-queued', async () => { calls++; return 'done'; });
  r.queue.attach({ name: 'new' }); task.completion.resolve('done'); await task.result;
  assert.equal((await oldQueued).code, -4); assert.equal(calls, 0);
});

test('P17: old timeout callbacks cannot block the new target', async () => {
  const r = editorQueueRig(); const task = waitingOperation(r.queue);
  await task.started; r.queue.attach({ name: 'new' }); r.clock.advance(3000); await task.result;
  assert.equal((await r.queue.enqueue('new', async () => 'done')).ok, true);
  task.completion.resolve('done');
});

test('P17: late settlement from an old target cannot release a new unresolved write', async () => {
  const r = editorQueueRig(); const old = waitingOperation(r.queue, false, 'old');
  await old.started; r.clock.advance(3000); await old.result;
  r.queue.attach({ name: 'new' }); const current = waitingOperation(r.queue, false, 'current');
  await current.started; r.clock.advance(3000); await current.result;
  old.completion.resolve('done'); await old.completion.promise;
  assert.equal((await r.queue.enqueue('blocked', async () => 'done')).code, -6);
  current.completion.resolve('done'); await current.completion.promise;
  assert.equal((await r.queue.enqueue('next', async () => 'done')).ok, true);
});

test('P17: operation queues have independent clients, deadlines and blockage', async () => {
  const first = editorQueueRig(), second = editorQueueRig(); const task = waitingOperation(first.queue);
  await task.started; first.clock.advance(3000); await task.result;
  assert.equal((await second.queue.enqueue('second', async client => { assert.equal(client, second.client); return 'done'; })).ok, true);
  assert.equal((await first.queue.enqueue('blocked', async () => 'done')).code, -6);
  task.completion.resolve('done');
});

test('P17: completed old writes are rejected at the completion boundary', async () => {
  const r = editorQueueRig(); const task = waitingOperation(r.queue, false, 'old');
  await task.started; r.queue.attach({ name: 'new' }); task.completion.resolve('len=1');
  assert.deepEqual(await task.result, { op: 'old', ok: false, code: -4, detail: 'stale-epoch' });
  assert.equal(r.logs.filter(log => log[0] === 'old' && log[1] === 'ok').length, 0);
});

test('P17: completed old reads do not expose values after detach', async () => {
  const r = editorQueueRig(); const task = waitingOperation(r.queue, true);
  await task.started; r.queue.detach(); task.completion.resolve('fixed-old-target-value');
  assert.deepEqual(await task.result, { ok: false, code: -4, value: undefined });
});

test('P17: a late error from an old operation is reported as stale rather than current failure', async () => {
  const r = editorQueueRig(); const task = waitingOperation(r.queue);
  await task.started; r.queue.attach({ name: 'new' }); task.completion.reject(Object.assign(new Error('fixture'), { code: 12800003 }));
  assert.equal((await task.result).code, -4);
  assert.equal(r.logs.some(log => log[1] === 'fail'), false);
});

test('P17: an already cancelled deadline callback cannot report a later timeout', async () => {
  const r = editorQueueRig();
  assert.equal((await r.queue.enqueue('done', async () => 'len=1')).ok, true);
  assert.equal(r.clock.timers.size, 0);
  r.clock.callbacks.get(0)();
  assert.equal(r.logs.filter(log => log[1] === 'timeout').length, 0);
  assert.equal((await r.queue.enqueue('next', async () => 'done')).ok, true);
});

test('P17: queue and preview cancellation reject the old completion without finishing the new field', async () => {
  const r = editorQueueRig(); const started = pending(), cleared = pending(); const calls = [];
  const port = {
    getEpoch: () => r.queue.getEpoch(),
    setPreview: async (text, start, end) => {
      const result = await r.queue.enqueue('setPreview', async client => {
        assert.deepEqual([text, start, end], ['', -1, -1]);
        calls.push(['clear', client]); started.resolve(); await cleared.promise; return 'len=0';
      });
      return { ok: result.ok, code: result.code };
    },
    finishPreview: async () => {
      const result = await r.queue.enqueue('finishPreview', async client => { calls.push(['finish', client]); return 'done'; });
      return { ok: result.ok, code: result.code };
    }
  };
  const cancellation = cancelEditorPreview(port); await started.promise;
  const nextClient = { name: 'new-target' }; r.queue.attach(nextClient); cleared.resolve();
  assert.deepEqual(await cancellation, { ok: false, code: -4 });
  assert.deepEqual(calls, [['clear', r.client]]);
  assert.equal((await r.queue.enqueue('new-input', async client => { assert.equal(client, nextClient); return 'len=1'; })).ok, true);
});
