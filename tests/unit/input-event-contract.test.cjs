const test = require('node:test');
const assert = require('node:assert/strict');
const { createInputEvent, validInputEvent, decodeInputEvent, resolveInputMovement } = require('../../entry/src/main/ets/kanon/InputEventContract.ets');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { FakeEditor, update, deferred } = require('../support/fakes.cjs');

test('P07: event assembly preserves supplied values and omits absent values', () => {
  assert.deepEqual(createInputEvent('enter'), { kind: 'enter' });
  assert.deepEqual(createInputEvent('select', undefined, 0, 0), { kind: 'select', candidateId: 0, expectedRevision: 0 });
  assert.deepEqual(createInputEvent('text', ''), { kind: 'text', text: '' });
  assert.deepEqual(createInputEvent('move', undefined, undefined, undefined, 'left'), { kind: 'move', direction: 'left' });
});

test('P07: text, kana and paste require text without changing the existing empty text policy', () => {
  for (const kind of ['text', 'kana', 'paste']) {
    assert.equal(validInputEvent({ kind }), false);
    assert.equal(validInputEvent({ kind, text: 123 }), false);
    assert.equal(validInputEvent({ kind, text: '' }), true);
    assert.equal(validInputEvent({ kind, text: '😀' }), true);
  }
});

test('P07: candidate taps require ID and revision but preserve signed engine IDs', () => {
  for (const candidateId of [-1, 0, 11]) {
    assert.equal(validInputEvent({ kind: 'select', candidateId, expectedRevision: 0 }), true);
  }
  for (const event of [{ kind: 'select', candidateId: 1 }, { kind: 'select', expectedRevision: 0 },
    { kind: 'select', candidateId: NaN, expectedRevision: 0 },
    { kind: 'select', candidateId: 1, expectedRevision: -1 },
    { kind: 'select', candidateId: 1.5, expectedRevision: 0 },
    { kind: 'select', candidateId: 1, expectedRevision: Infinity }]) {
    assert.equal(validInputEvent(event), false);
  }
});

test('P07: partial commit requires current revision data', () => {
  assert.equal(validInputEvent({ kind: 'partial' }), false);
  assert.equal(validInputEvent({ kind: 'partial', expectedRevision: 0 }), true);
});

test('P07: composition arrows and mode changes use their declared values', () => {
  for (const text of ['left', 'right']) { assert.equal(validInputEvent({ kind: 'compositionArrow', text }), true); }
  for (const text of ['JP', 'EN']) { assert.equal(validInputEvent({ kind: 'mode', text }), true); }
  assert.equal(validInputEvent({ kind: 'compositionArrow', text: 'up' }), false);
  assert.equal(validInputEvent({ kind: 'mode', text: 'invalid' }), false);
});

test('P07: movement requires direction or edge and selection requires its specific target', () => {
  for (const event of [{ kind: 'move', direction: 'left' }, { kind: 'move', edge: 'begin' },
    { kind: 'move', edge: 'end' }, { kind: 'selectMove', direction: 'down' }, { kind: 'selectEdge', edge: 'begin' }]) {
    assert.equal(validInputEvent(event), true);
  }
  for (const event of [{ kind: 'move' }, { kind: 'move', direction: NaN }, { kind: 'move', edge: 'middle' },
    { kind: 'selectMove', edge: 'begin' }, { kind: 'selectEdge', direction: 0 }]) {
    assert.equal(validInputEvent(event), false);
  }
});

test('P07: undo completion requires coherent word, cursor and prefix length', () => {
  assert.equal(validInputEvent({ kind: 'undoCompletion', text: 'hello', cursor: 7, prefixLength: 2 }), true);
  for (const event of [{ kind: 'undoCompletion' },
    { kind: 'undoCompletion', text: '', cursor: 0, prefixLength: 0 },
    { kind: 'undoCompletion', text: 'hello', cursor: -1, prefixLength: 2 },
    { kind: 'undoCompletion', text: 'hello', cursor: 7, prefixLength: 6 }]) {
    assert.equal(validInputEvent(event), false);
  }
});

test('P07: payload-free operations are accepted and local or unknown requests are rejected', () => {
  for (const kind of ['modifyKana', 'backspace', 'convert', 'submit', 'enter', 'cancel', 'selectAll', 'forwardDelete', 'reset']) {
    assert.equal(validInputEvent({ kind }), true);
  }
  for (const kind of ['prepare', 'cycle', 'config', 'undoEnglish', 'converrt']) {
    assert.equal(validInputEvent({ kind }), false);
  }
});

test('P07: Japanese horizontal movement resolves using current preedit and semantic directions', () => {
  for (const [direction, text] of [['left', 'left'], ['right', 'right']]) {
    const event = { kind: 'move', direction };
    assert.deepEqual(resolveInputMovement(event, 'JP', 3), { kind: 'compositionArrow', text });
    assert.deepEqual(event, { kind: 'move', direction });
  }
});

test('P07: empty, English, vertical, edge and selection movement retain editor operation', () => {
  for (const [event, mode, length] of [[{ kind: 'move', direction: 'left' }, 'JP', 0],
    [{ kind: 'move', direction: 'left' }, 'EN', 3], [{ kind: 'move', direction: 'up' }, 'JP', 3],
    [{ kind: 'move', edge: 'begin' }, 'JP', 3], [{ kind: 'selectMove', direction: 'left' }, 'JP', 3]]) {
    assert.equal(resolveInputMovement(event, mode, length), event);
  }
});

test('P07: malformed input is rejected without engine or editor side effects', async () => {
  const editor = new FakeEditor('既存'); const coordinator = new ImeCoordinator(editor);
  let dispatched = 0;
  coordinator.setEngine({ dispatch: (s, e, n) => { dispatched++; return update(s, e, n); } });
  await coordinator.postEvent({ kind: 'text' });
  assert.equal(coordinator.getSnapshot().lastError, 'invalid-event');
  assert.equal(coordinator.getSnapshot().commitLength, 0);
  assert.equal(dispatched, 0);
  assert.deepEqual(editor.calls, []);
  assert.equal(editor.text, '既存');
});

test('P07: a malformed move cannot commit or delete an existing preview', async () => {
  const editor = new FakeEditor(); const coordinator = new ImeCoordinator(editor);
  await coordinator.loadPreviewSupport(); let dispatched = 0;
  coordinator.setEngine({ dispatch: (s, e, n) => {
    dispatched++; return update(s, e, n, { preeditLen: 1 });
  } });
  await coordinator.postEvent({ kind: 'text', text: 'あ' });
  await coordinator.refreshPreview('あ', 0, 0, 1);
  const calls = editor.calls.length;
  await coordinator.postEvent({ kind: 'move' });
  assert.equal(dispatched, 1);
  assert.equal(editor.calls.length, calls);
  assert.equal(editor.text, 'あ');
  assert.equal(coordinator.getSnapshot().preeditLen, 1);
  assert.equal(coordinator.getSnapshot().lastError, 'invalid-event');
});

test('P07: invalid event does not hold the queue and next valid input still executes', async () => {
  const coordinator = new ImeCoordinator(new FakeEditor());
  const seen = [];
  coordinator.setEngine({ dispatch: (s, e, n, event) => {
    seen.push(event.text); return update(s, e, n, { preeditLen: 1 });
  } });
  await coordinator.postEvent({ kind: 'text' });
  await coordinator.postEvent({ kind: 'text', text: 'あ' });
  assert.deepEqual(seen, ['あ']);
  assert.equal(coordinator.getSnapshot().lastError, 'ok');
});

test('P07: queued malformed events are checked after earlier operations finish', async () => {
  const pending = deferred(); const started = deferred();
  const coordinator = new ImeCoordinator(new FakeEditor());
  coordinator.setEngine({ dispatch: (s, e, n) => {
    started.resolve(); return pending.promise.then(() => update(s, e, n, { preeditLen: 1 }));
  } });
  const first = coordinator.postEvent({ kind: 'text', text: 'あ' }); await started.promise;
  const invalid = coordinator.postEvent({ kind: 'select', candidateId: 1 });
  pending.resolve(); await first; await invalid;
  assert.equal(coordinator.getSnapshot().preeditLen, 1);
  assert.equal(coordinator.getSnapshot().lastError, 'invalid-event');
});
