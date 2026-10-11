const { EditorOperationQueue } = require('../../entry/src/main/ets/kanon/EditorOperationQueue.ets');

function pending() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function editorQueueRig(attach = true) {
  let now = 0, serial = 0;
  const timers = new Map(), callbacks = new Map(), logs = [];
  const clock = {
    timers, callbacks,
    schedule(callback, delay) {
      const id = serial++;
      timers.set(id, { due: now + delay, callback }); callbacks.set(id, callback);
      return id;
    },
    unschedule(id) { timers.delete(id); },
    advance(ms) {
      now += ms;
      for (const [id, task] of [...timers]) {
        if (task.due <= now) { timers.delete(id); task.callback(); }
      }
    }
  };
  const queue = new EditorOperationQueue({ schedule: clock.schedule, unschedule: clock.unschedule,
    errorCode: error => Number.isFinite(error?.code) ? error.code : -2,
    log: (...event) => logs.push(event) });
  const client = { name: 'fixture-client' };
  if (attach) { queue.attach(client); }
  return { queue, clock, logs, client };
}

function waitingOperation(queue, valueOperation = false, op = 'waiting') {
  const started = pending(), completion = pending();
  const invoke = () => { started.resolve(); return completion.promise; };
  const result = valueOperation ? queue.enqueueValue(op, invoke) : queue.enqueue(op, invoke);
  return { started: started.promise, completion, result };
}

module.exports = { pending, editorQueueRig, waitingOperation };
