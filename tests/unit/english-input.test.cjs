const test = require('node:test');
const assert = require('node:assert/strict');
const { EnglishPrediction } = require('../../entry/src/main/ets/kanon/EnglishPrediction.ets');
const { EnglishEngine } = require('../../entry/src/main/ets/kanon/EnglishEngine.ets');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { FakeEditor } = require('../support/fakes.cjs');

function rig() {
  const notifications = [];
  const prediction = new EnglishPrediction({ undoChanged: value => notifications.push(['undo', value]),
    cleared: () => notifications.push(['clear']), selectionAbandoned: () => notifications.push(['abandoned']) });
  const engine = new EnglishEngine(prediction); let sequence = 0;
  return { prediction, engine, notifications, send: event => engine.dispatch('english-test', 1, ++sequence, event) };
}

test('P09: English suggestions remain composing until Space selects a candidate', async () => {
  const r = rig(); const typed = await r.send({ kind: 'text', text: 'he' });
  assert.equal(typed.phase, 'composing');
  assert.equal(typed.candidates[0].label, 'hello');
  assert.equal(r.engine.getPreedit(), 'he');
  const selected = await r.send({ kind: 'convert' });
  assert.equal(selected.phase, 'converting');
  assert.equal(r.engine.getPreedit(), 'hello');
  assert.deepEqual(selected.effects, []);
});

test('P09: Enter commits selected English candidate once and clears composition', async () => {
  const r = rig(); await r.send({ kind: 'text', text: 'he' }); await r.send({ kind: 'convert' });
  const committed = await r.send({ kind: 'enter' });
  assert.equal(committed.effects.length, 1);
  assert.equal(committed.effects[0].text, 'hello');
  assert.equal(committed.phase, 'empty');
  assert.equal(r.engine.getTypedText(), '');
  assert.equal(r.prediction.getPrefix(), '');
  assert.equal((await r.send({ kind: 'enter' })).effects.length, 0);
});

test('P09: Enter without conversion commits typed text rather than first suggestion', async () => {
  const r = rig(); await r.send({ kind: 'text', text: 'he' });
  const committed = await r.send({ kind: 'enter' });
  assert.equal(committed.effects[0].text, 'he');
});

test('P09: Space cycles candidates without producing commit effects', async () => {
  const r = rig(); await r.send({ kind: 'text', text: 'he' });
  const count = r.prediction.getItems().length;
  for (let i = 0; i <= count; i++) {
    const result = await r.send({ kind: 'convert' });
    assert.equal(r.prediction.getSelectedIndex(), i % count);
    assert.deepEqual(result.effects, []);
  }
});

test('P09: Delete first cancels highlighted completion then deletes typed characters', async () => {
  const r = rig(); await r.send({ kind: 'text', text: 'he' }); await r.send({ kind: 'convert' });
  const cancelled = await r.send({ kind: 'backspace' });
  assert.equal(r.engine.getPreedit(), 'he');
  assert.equal(cancelled.phase, 'composing');
  assert.deepEqual(cancelled.effects, []);
  await r.send({ kind: 'backspace' }); assert.equal(r.engine.getPreedit(), 'h');
  const empty = await r.send({ kind: 'backspace' }); assert.equal(empty.phase, 'empty');
});

test('P09: deleting an emoji removes a complete surrogate pair', async () => {
  const r = rig(); await r.send({ kind: 'text', text: 'a😀' });
  await r.send({ kind: 'backspace' }); assert.equal(r.engine.getPreedit(), 'a');
});

test('P09: new text after selection retains displayed completion', async () => {
  const r = rig(); await r.send({ kind: 'text', text: 'he' }); await r.send({ kind: 'convert' });
  const result = await r.send({ kind: 'text', text: '!' });
  assert.equal(r.engine.getPreedit(), 'hello!');
  assert.equal(result.phase, 'composing');
  assert.deepEqual(result.effects, []);
});

test('P09: candidate tap commits matching ID and invalid ID keeps typed text', async () => {
  const r = rig(); const typed = await r.send({ kind: 'text', text: 'he' });
  const bad = await r.send({ kind: 'select', candidateId: -1 });
  assert.equal(bad.errorCode, 2);
  assert.equal(r.engine.getPreedit(), 'he');
  assert.deepEqual(bad.effects, []);
  const good = await r.send({ kind: 'select', candidateId: typed.candidates[1].id });
  assert.equal(good.effects[0].text, typed.candidates[1].label);
  assert.equal(good.phase, 'empty');
});

test('P09 provisional: Space with no completion commits text followed by a space', async () => {
  const r = rig(); await r.send({ kind: 'text', text: 'qqqq' });
  const result = await r.send({ kind: 'convert' });
  assert.equal(result.effects[0].text, 'qqqq ');
  assert.equal(result.phase, 'empty');
});

test('P09: cancel and local reset clear engine and shared prediction state', async () => {
  for (const reset of [async r => r.send({ kind: 'cancel' }), async r => r.engine.resetLocal()]) {
    const r = rig(); await r.send({ kind: 'text', text: 'he' }); await r.send({ kind: 'convert' });
    await reset(r);
    assert.equal(r.engine.getPreedit(), '');
    assert.deepEqual(r.prediction.getItems(), []);
    assert.equal(r.prediction.getSelectedIndex(), -1);
  }
});

test('P09: injected prediction instances do not share composition', async () => {
  const first = rig(); const second = rig();
  await first.send({ kind: 'text', text: 'he' });
  assert.equal(second.engine.getPreedit(), '');
  assert.deepEqual(second.prediction.getItems(), []);
});

test('P09 provisional: authored vocabulary preserves prefix case and limits unique suggestions to eight', () => {
  const r = rig();
  r.prediction.updateComposition('HE');
  assert.equal(r.prediction.getItems()[0].label, 'HELLO');
  r.prediction.updateComposition('He');
  assert.equal(r.prediction.getItems()[0].label, 'Hello');
  r.prediction.updateComposition('a');
  const items = r.prediction.getItems();
  assert.equal(items.length, 8);
  assert.equal(new Set(items.map(item => item.label)).size, items.length);
});

test('P09: prediction extracts trailing word and clears prefix for punctuation or excess length', () => {
  const r = rig(); r.prediction.updateComposition('say he');
  assert.equal(r.prediction.getPrefix(), 'he');
  r.prediction.updateComposition('say he!'); assert.equal(r.prediction.getPrefix(), '');
  r.prediction.updateComposition('a'.repeat(41)); assert.equal(r.prediction.getPrefix(), '');
});

test('P09: direct English prefix tracks insertion origin and backspace', () => {
  const r = rig(); r.prediction.text('h', 3); r.prediction.text('e', 4);
  assert.equal(r.prediction.getPrefix(), 'he'); assert.equal(r.prediction.getCursor(), 5);
  r.prediction.backspace(); assert.equal(r.prediction.getCursor(), 4);
  r.prediction.backspace(); assert.equal(r.prediction.getCursor(), -1);
});

test('P09: remembered completion undo is taken once and sends metadata-only visibility', () => {
  const r = rig(); r.prediction.rememberCompletion('he', 'hello', 5, 1);
  assert.deepEqual(r.prediction.takeUndo(), { prefix: 'he', word: 'hello', cursor: 5, epoch: 1 });
  assert.equal(r.prediction.takeUndo(), undefined);
  assert.deepEqual(r.notifications, [['undo', true], ['undo', false], ['undo', false]]);
});

test('P09: external selection movement clears prediction and abandons composition once', () => {
  const r = rig(); r.prediction.updateComposition('he'); r.prediction.setCompositionCursor(5);
  r.prediction.selectionChanged(4, 4);
  assert.equal(r.prediction.getPrefix(), '');
  assert.equal(r.prediction.takeCompositionAbandoned(), true);
  assert.equal(r.prediction.takeCompositionAbandoned(), false);
  assert.deepEqual(r.notifications, [['undo', false], ['clear'], ['abandoned']]);
});

test('P09: matching cursor and internal selection changes do not abandon composition', () => {
  const r = rig(); r.prediction.updateComposition('he'); r.prediction.setCompositionCursor(5);
  r.prediction.selectionChanged(5, 5);
  assert.equal(r.prediction.getPrefix(), 'he');
  r.prediction.editing = true; r.prediction.selectionChanged(0, 3);
  assert.equal(r.prediction.getPrefix(), 'he');
  assert.equal(r.prediction.takeCompositionAbandoned(), false);
  assert.equal(r.prediction.canSeed(), false);
});

test('P09: external selection invalidates completion undo', () => {
  const r = rig(); r.prediction.rememberCompletion('he', 'hello', 5, 1);
  r.prediction.selectionChanged(3, 3);
  assert.equal(r.prediction.takeUndo(), undefined);
});

test('P09: restoring direct prefix recreates suggestions at the specified cursor', () => {
  const r = rig(); r.prediction.restorePrefix('he', 7);
  assert.equal(r.prediction.getCursor(), 7);
  assert.equal(r.prediction.getItems()[0].label, 'hello');
});

test('P09: runtime UI adapter is excluded from platform-free tests', () => {
  assert.throws(() => require('../../entry/src/main/ets/kanon/EnglishRuntime.ets'),
    /Platform global in unit-test target: AppStorage/);
});

async function connected() {
  const r = rig(); const editor = new FakeEditor(); const coordinator = new ImeCoordinator(editor);
  await coordinator.loadPreviewSupport(); coordinator.setEnglishEngine(r.engine);
  await coordinator.postEvent({ kind: 'mode', text: 'EN' });
  return { ...r, editor, coordinator };
}

test('P09: real English engine and Coordinator select with Space and commit with Enter', async () => {
  const r = await connected();
  await r.coordinator.postEvent({ kind: 'text', text: 'he' });
  await r.coordinator.refreshPreview(r.engine.getPreedit(), 0, 0, 2);
  assert.equal(r.coordinator.getSnapshot().state, 'EN_COMPOSING');
  await r.coordinator.postEvent({ kind: 'convert' });
  await r.coordinator.refreshPreview(r.engine.getPreedit(), 0, 2, 5);
  assert.equal(r.editor.text, 'hello');
  assert.equal(r.coordinator.getSnapshot().state, 'EN_CONVERTING');
  await r.coordinator.postEvent({ kind: 'enter' });
  assert.equal(r.editor.text, 'hello');
  assert.equal(r.editor.count('insert'), 1);
  assert.equal(r.coordinator.getSnapshot().state, 'EN_EMPTY');
});

test('P09: language change commits English composition before switching mode', async () => {
  const r = await connected();
  await r.coordinator.postEvent({ kind: 'text', text: 'he' });
  await r.coordinator.refreshPreview(r.engine.getPreedit(), 0, 0, 2);
  await r.coordinator.postEvent({ kind: 'mode', text: 'JP' });
  assert.equal(r.editor.text, 'he');
  assert.equal(r.editor.count('insert'), 1);
  assert.equal(r.coordinator.getSnapshot().state, 'JP_EMPTY');
  assert.equal(r.engine.getPreedit(), '');
});

test('P09: Coordinator completion undo removes suffix and restores English prefix to engine', async () => {
  const r = await connected();
  await r.coordinator.postEvent({ kind: 'text', text: 'he' });
  await r.coordinator.refreshPreview(r.engine.getPreedit(), 0, 0, 2);
  await r.coordinator.postEvent({ kind: 'convert' });
  await r.coordinator.refreshPreview(r.engine.getPreedit(), 0, 2, 5);
  await r.coordinator.postEvent({ kind: 'enter' });
  await r.coordinator.postEvent({ kind: 'undoCompletion', text: 'hello', cursor: 5, prefixLength: 2 });
  assert.equal(r.editor.text, 'he');
  assert.equal(r.engine.getPreedit(), 'he');
  assert.equal(r.coordinator.getSnapshot().state, 'EN_COMPOSING');
  assert.equal(r.coordinator.getSnapshot().lastError, 'ok');
});
