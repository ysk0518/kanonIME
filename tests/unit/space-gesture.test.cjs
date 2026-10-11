const test = require('node:test');
const assert = require('node:assert/strict');
const { SpaceGesture } = require('../../entry/src/main/ets/kanon/SpaceGesture.ets');

function rig() {
  let now = 0; let nextTimer = 0; let epoch = 1;
  const timers = new Map(); const callbacks = new Map();
  const calls = []; let state = [false, false]; let rejectMove;
  const gesture = new SpaceGesture({
    getEpoch: () => epoch,
    schedule: (callback, delay) => {
      const id = nextTimer++; timers.set(id, { callback, due: now + delay });
      callbacks.set(id, callback); return id;
    },
    unschedule: id => timers.delete(id),
    tap: () => calls.push('tap'),
    move: direction => {
      calls.push(direction);
      if (rejectMove) { return new Promise((resolve, reject) => { rejectMove.reject = reject; }); }
      return Promise.resolve();
    },
    feedback: () => calls.push('feedback'),
    changed: (pressing, dragging) => { state = [pressing, dragging]; }
  });
  return { gesture, calls, timers, callbacks,
    get state() { return state; },
    advance(ms) {
      now += ms;
      for (const [id, entry] of [...timers]) {
        if (entry.due <= now) { timers.delete(id); entry.callback(); }
      }
    },
    changeEditor() { epoch++; },
    delayMove() { rejectMove = {}; return rejectMove; },
    movements() { return calls.filter(value => value === 'left' || value === 'right'); }
  };
}

test('R10: a short Space tap emits once on release', () => {
  const r = rig(); r.gesture.down(1, 100, 50, 400);
  r.advance(399);
  assert.deepEqual(r.calls, []);
  r.gesture.contact(1, 100, 50, true);
  r.gesture.contact(1, 100, 50, true);
  r.advance(1000);
  assert.deepEqual(r.calls, ['tap']);
  assert.deepEqual(r.state, [false, false]);
  assert.equal(r.timers.size, 0);
});

test('R11: held Space emits movement in order and never a release tap', () => {
  const r = rig(); r.gesture.down(1, 100, 50, 400); r.advance(400);
  assert.deepEqual(r.state, [true, true]);
  r.gesture.contact(1, 136, 50, false);
  r.gesture.contact(1, 118, 50, false);
  r.gesture.contact(1, 82, 50, true);
  assert.deepEqual(r.movements(), ['right', 'right', 'left', 'left', 'left']);
  assert.equal(r.calls.includes('tap'), false);
  assert.deepEqual(r.state, [false, false]);
});

test('R11: holding without dragging does not insert Space', () => {
  const r = rig(); r.gesture.down(1, 100, 50, 400); r.advance(400);
  r.gesture.contact(1, 100, 50, true);
  assert.deepEqual(r.calls, ['feedback']);
});

test('R11 provisional: movement origin is the finger position when hold activates', () => {
  const r = rig(); r.gesture.down(1, 100, 50, 400);
  r.gesture.contact(1, 110, 50, false); r.advance(400);
  r.gesture.contact(1, 127, 50, false);
  assert.deepEqual(r.movements(), []);
  r.gesture.contact(1, 128, 50, false);
  assert.deepEqual(r.movements(), ['right']);
});

test('R11 provisional: 18vp steps are symmetric and repeated positions do not repeat moves', () => {
  for (const sign of [-1, 1]) {
    const r = rig(); r.gesture.down(1, 100, 50, 400); r.advance(400);
    r.gesture.contact(1, 100 + sign * 17.9, 50, false);
    assert.deepEqual(r.movements(), []);
    r.gesture.contact(1, 100 + sign * 18, 50, false);
    r.gesture.contact(1, 100 + sign * 18, 50, false);
    assert.deepEqual(r.movements(), [sign < 0 ? 'left' : 'right']);
  }
});

test('R11 provisional: a large jump is limited to sixteen moves per event', () => {
  const r = rig(); r.gesture.down(1, 0, 0, 400); r.advance(400);
  r.gesture.contact(1, 1800, 0, false);
  assert.equal(r.movements().length, 16);
  r.gesture.contact(1, 1800, 0, false);
  assert.equal(r.movements().length, 32);
});

test('R12: cancel before or after hold discards the pending tap and timer', () => {
  for (const elapsed of [200, 400]) {
    const r = rig(); r.gesture.down(1, 100, 50, 400); r.advance(elapsed);
    r.gesture.cancel(); r.advance(1000); r.gesture.contact(1, 136, 50, true);
    assert.deepEqual(r.movements(), []);
    assert.equal(r.calls.includes('tap'), false);
    assert.deepEqual(r.state, [false, false]);
    assert.equal(r.timers.size, 0);
  }
});

test('R12: editor changes before timer expiry or during drag suppress further actions', () => {
  for (const elapsed of [200, 400]) {
    const r = rig(); r.gesture.down(1, 100, 50, 400); r.advance(elapsed);
    r.changeEditor(); r.advance(400); r.gesture.contact(1, 136, 50, true);
    assert.deepEqual(r.movements(), []);
    assert.equal(r.calls.includes('tap'), false);
    assert.deepEqual(r.state, [false, false]);
  }
});

test('R12: cancelled timer callback cannot activate a later gesture', () => {
  const r = rig(); r.gesture.down(1, 100, 50, 400);
  const stale = r.callbacks.get(0);
  r.gesture.cancel(); r.gesture.down(2, 100, 50, 400); stale();
  assert.deepEqual(r.state, [true, false]);
  r.gesture.contact(2, 100, 50, true);
  assert.deepEqual(r.calls, ['tap']);
});

test('R12: a delayed movement failure cannot cancel the next gesture', async () => {
  const r = rig(); const pending = r.delayMove();
  r.gesture.down(1, 100, 50, 400); r.advance(400);
  r.gesture.contact(1, 118, 50, false);
  r.gesture.cancel(); r.gesture.down(2, 100, 50, 400);
  pending.reject(new Error('Old movement failed')); await Promise.resolve();
  assert.deepEqual(r.state, [true, false]);
  r.gesture.contact(2, 100, 50, true);
  assert.equal(r.calls.filter(value => value === 'tap').length, 1);
});

test('R12: movement failure cancels the active gesture', async () => {
  const r = rig(); const pending = r.delayMove();
  r.gesture.down(1, 100, 50, 400); r.advance(400);
  r.gesture.contact(1, 118, 50, false);
  pending.reject(new Error('Movement failed')); await Promise.resolve();
  assert.deepEqual(r.state, [false, false]);
  r.gesture.contact(1, 136, 50, true);
  assert.deepEqual(r.movements(), ['right']);
  assert.equal(r.calls.includes('tap'), false);
});

test('R10: another finger cannot release or replace the first finger', () => {
  const r = rig(); r.gesture.down(1, 100, 50, 400);
  r.gesture.down(2, 150, 50, 400); r.gesture.contact(2, 150, 50, true);
  assert.deepEqual(r.state, [true, false]);
  r.gesture.contact(1, 100, 50, true);
  assert.deepEqual(r.calls, ['tap']);
});

test('R10 provisional: drifting beyond tap slop before hold cancels input', () => {
  for (const [x, y] of [[113, 50], [100, 63]]) {
    const r = rig(); r.gesture.down(1, 100, 50, 400);
    r.gesture.contact(1, x, y, false); r.advance(400); r.gesture.contact(1, x, y, true);
    assert.deepEqual(r.calls, []);
    assert.deepEqual(r.state, [false, false]);
  }
});
