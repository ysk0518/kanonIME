const test = require('node:test');
const assert = require('node:assert/strict');
const { InputOperationQueue } = require('../../entry/src/main/ets/kanon/InputOperationQueue.ets');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { MozcEngine } = require('../../entry/src/main/ets/kanon/MozcEngine.ets');
const { CompositionPreview } = require('../../entry/src/main/ets/kanon/CompositionPreview.ets');
const { cancelEditorPreview } = require('../../entry/src/main/ets/kanon/PreviewLifecycle.ets');
const { FakeEditor, ScriptedBridge, response, deferred } = require('../support/fakes.cjs');

function rig() {
  const state = { epoch: 1, staleValue: 'current', staleCalls: 0 };
  state.queue = new InputOperationQueue(() => state.epoch, () => {
    state.staleCalls++; return state.staleValue;
  });
  return state;
}

test('P08: input operations execute and return results in FIFO order', async () => {
  const r = rig(); const seen = [];
  const results = await Promise.all([1, 2, 3].map(value => r.queue.enqueue(async () => {
    seen.push(value); return value * 10;
  })));
  assert.deepEqual(seen, [1, 2, 3]);
  assert.deepEqual(results, [10, 20, 30]);
});

test('P08: next operation waits for the complete asynchronous operation', async () => {
  const r = rig(); const started = deferred(); const finish = deferred(); const seen = [];
  const first = r.queue.enqueue(async () => {
    seen.push('start'); started.resolve(); await finish.promise; seen.push('finished'); return 1;
  });
  const second = r.queue.enqueue(async () => { seen.push('second'); return 2; });
  await started.promise; await Promise.resolve();
  assert.deepEqual(seen, ['start']);
  finish.resolve(); await first; await second;
  assert.deepEqual(seen, ['start', 'finished', 'second']);
});

test('P08: epoch is captured at enqueue and checked before execution', async () => {
  const r = rig(); let called = false;
  const pending = r.queue.enqueue(async () => { called = true; return 'old'; });
  r.epoch++;
  assert.equal(await pending, 'current');
  assert.equal(called, false);
  assert.equal(r.staleCalls, 1);
});

test('P08: obsolete queued operations are skipped and new editor input continues', async () => {
  const r = rig(); const started = deferred(); const finish = deferred(); const seen = [];
  const running = r.queue.enqueue(async () => { started.resolve(); await finish.promise; return 'running'; });
  await started.promise;
  const old = r.queue.enqueue(async () => { seen.push('old'); return 'old'; });
  r.epoch++;
  const fresh = r.queue.enqueue(async () => { seen.push('new'); return 'new'; });
  finish.resolve();
  assert.equal(await running, 'running');
  assert.equal(await old, 'current');
  assert.equal(await fresh, 'new');
  assert.deepEqual(seen, ['new']);
});

test('P08: obsolete result is obtained when dequeued rather than when enqueued', async () => {
  const r = rig(); const started = deferred(); const finish = deferred();
  const running = r.queue.enqueue(async () => { started.resolve(); await finish.promise; return 1; });
  await started.promise;
  const old = r.queue.enqueue(async () => 2);
  r.epoch++; r.staleValue = 'latest'; finish.resolve(); await running;
  assert.equal(await old, 'latest');
});

test('P08: an already running operation is not implicitly cancelled or replayed by queue', async () => {
  const r = rig(); const started = deferred(); const finish = deferred(); let calls = 0;
  const running = r.queue.enqueue(async () => {
    calls++; started.resolve(); await finish.promise; return 'result-from-running-operation';
  });
  await started.promise; r.epoch++; finish.resolve();
  assert.equal(await running, 'result-from-running-operation');
  assert.equal(calls, 1);
  assert.equal(r.staleCalls, 0);
});

test('P08: rejected operation is reported once and does not poison later input', async () => {
  const r = rig(); const error = new Error('Operation failed'); let calls = 0;
  const failed = r.queue.enqueue(async () => { calls++; throw error; });
  const rejection = assert.rejects(failed, value => value === error);
  const next = r.queue.enqueue(async () => 2);
  await rejection;
  assert.equal(await next, 2);
  assert.equal(calls, 1);
});

test('P08: synchronous throw is reported without retry and next operation executes', async () => {
  const r = rig(); const error = new Error('Sync failure');
  const failed = r.queue.enqueue(() => { throw error; });
  await assert.rejects(failed, value => value === error);
  assert.equal(await r.queue.enqueue(async () => 2), 2);
});

test('P08: failure while obtaining stale result does not block new editor input', async () => {
  let epoch = 1;
  const queue = new InputOperationQueue(() => epoch, () => { throw new Error('Snapshot unavailable'); });
  const old = queue.enqueue(async () => 1); epoch++;
  await assert.rejects(old, /Snapshot unavailable/);
  assert.equal(await queue.enqueue(async () => 2), 2);
});

test('P08: operations observe state after previous operations complete', async () => {
  const r = rig(); let mode = 'JP';
  const first = r.queue.enqueue(async () => { mode = 'EN'; return mode; });
  const next = r.queue.enqueue(async () => mode);
  assert.equal(await first, 'EN');
  assert.equal(await next, 'EN');
});

test('P08: separate instances do not share their serial tail', async () => {
  const first = rig(); const other = rig(); const started = deferred(); const finish = deferred();
  const blocked = first.queue.enqueue(async () => { started.resolve(); await finish.promise; return 1; });
  await started.promise;
  assert.equal(await other.queue.enqueue(async () => 2), 2);
  finish.resolve(); await blocked;
});

test('P08: normal bursts retain every operation without coalescing', async () => {
  const r = rig(); const seen = [];
  await Promise.all(Array.from({ length: 100 }, (_, i) => r.queue.enqueue(async () => { seen.push(i); return i; })));
  assert.deepEqual(seen, Array.from({ length: 100 }, (_, i) => i));
});

test('P08: preview and display finish before the following roman key is dispatched', async () => {
  const editor = new FakeEditor(); const coordinator = new ImeCoordinator(editor);
  const bridge = new ScriptedBridge([
    { operation: 'convert', text: 'k', output: response('ｋ') },
    { operation: 'convert', text: 'i', output: response('き') }
  ]);
  const engine = new MozcEngine(bridge); coordinator.setEngine(engine); await coordinator.loadPreviewSupport();
  const previewStarted = deferred(); const finishPreview = deferred(); let first = true;
  const preview = new CompositionPreview({
    getEpoch: () => editor.getEpoch(), queryCursor: () => editor.queryCursor(),
    clearPreview: () => cancelEditorPreview(editor).then(() => {}),
    refreshPreview: async (...args) => {
      if (first) { first = false; previewStarted.resolve(); await finishPreview.promise; }
      return coordinator.refreshPreview(...args);
    }, disableJapanesePreview: () => coordinator.setPreviewUnsupported(), englishCursor: () => {}
  });
  const queue = new InputOperationQueue(() => editor.getEpoch(), () => coordinator.getSnapshot());
  const published = [];
  const key = text => queue.enqueue(async () => {
    await coordinator.postEvent({ kind: 'text', text });
    await preview.refresh(coordinator.getSnapshot(), engine.getPreedit(), false);
    published.push(engine.getPreedit()); return coordinator.getSnapshot();
  });
  const k = key('k'); const i = key('i'); await previewStarted.promise;
  assert.equal(bridge.calls.length, 1);
  assert.deepEqual(published, []);
  finishPreview.resolve(); await k; await i;
  assert.deepEqual(published, ['ｋ', 'き']);
  assert.equal(editor.text, 'き');
  assert.equal(editor.count('insert'), 0);
  bridge.assertDone();
});
