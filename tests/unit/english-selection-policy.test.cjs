const test = require('node:test');
const assert = require('node:assert/strict');
const { evaluateEnglishSelection } = require('../../entry/src/main/ets/kanon/EnglishSelectionPolicy.ets');
const { EnglishPrediction } = require('../../entry/src/main/ets/kanon/EnglishPrediction.ets');

const base = { editing: false, undoCursor: undefined, hasPrefix: false,
  expectedCursor: -1, hasCompositionCursor: false };
const keep = { collapsed: true, dropUndo: false, clearPrediction: false, abandonComposition: false };
const active = { hasPrefix: true, expectedCursor: 5, hasCompositionCursor: true };
const cases = [
  ['empty state accepts a collapsed position', 2, 2, {}, keep],
  ['empty state records a noncollapsed selection', 1, 2, {}, { ...keep, collapsed: false }],
  ['matching composition cursor preserves prediction', 5, 5, active, keep],
  ['mismatched composition cursor abandons prediction', 4, 4, active,
    { ...keep, clearPrediction: true, abandonComposition: true }],
  ['range ending at expected cursor still abandons prediction', 3, 5, active,
    { ...keep, collapsed: false, clearPrediction: true, abandonComposition: true }],
  ['direct English mismatch clears prefix without composition abandonment', 4, 4,
    { hasPrefix: true, expectedCursor: 5 }, { ...keep, clearPrediction: true }],
  ['composition cursor without a prefix still tracks mismatch', 4, 4,
    { expectedCursor: 5, hasCompositionCursor: true },
    { ...keep, clearPrediction: true, abandonComposition: true }],
  ['matching undo cursor preserves undo', 5, 5, { undoCursor: 5 }, keep],
  ['mismatched undo cursor invalidates undo', 4, 4, { undoCursor: 5 }, { ...keep, dropUndo: true }],
  ['range ending at undo cursor invalidates undo', 3, 5, { undoCursor: 5 },
    { ...keep, collapsed: false, dropUndo: true }],
  ['internal editing suppresses mismatch actions', 1, 1,
    { ...active, undoCursor: 5, editing: true }, keep],
  ['internal editing still records a selected range', 1, 3,
    { ...active, undoCursor: 5, editing: true }, { ...keep, collapsed: false }]
];

for (const [name, begin, end, context, expected] of cases) {
  test(`P18: ${name}`, () => {
    const input = Object.freeze({ ...base, ...context });
    assert.deepEqual(evaluateEnglishSelection(begin, end, input), expected);
    assert.deepEqual(evaluateEnglishSelection(begin, end, input), expected);
  });
}

function rig() {
  const notices = [];
  const prediction = new EnglishPrediction({ undoChanged: visible => notices.push(['undo', visible]),
    cleared: () => notices.push(['clear']), selectionAbandoned: () => notices.push(['abandoned']) });
  prediction.updateComposition('he');
  prediction.setCompositionCursor(5);
  return { prediction, notices };
}

test('P18: integration preserves notification order and consumes abandonment only once', () => {
  const { prediction, notices } = rig();
  prediction.rememberCompletion('he', 'hello', 5, 1);
  notices.length = 0;
  prediction.selectionChanged(4, 4);
  assert.deepEqual(notices, [['undo', false], ['undo', false], ['clear'], ['abandoned']]);
  assert.equal(prediction.getPrefix(), '');
  assert.equal(prediction.getItems().length, 0);
  assert.equal(prediction.takeCompositionAbandoned(), true);
  assert.equal(prediction.takeCompositionAbandoned(), false);
  prediction.selectionChanged(4, 4);
  assert.equal(notices.length, 4);
});

test('P18: internal range notification disables seeding without clearing English state', () => {
  const { prediction, notices } = rig();
  prediction.rememberCompletion('he', 'hello', 5, 1);
  notices.length = 0;
  prediction.editing = true;
  prediction.selectionChanged(1, 3);
  assert.equal(prediction.canSeed(), false);
  assert.equal(prediction.getPrefix(), 'he');
  assert.deepEqual(notices, []);
  prediction.selectionChanged(5, 5);
  prediction.editing = false;
  assert.equal(prediction.canSeed(), true);
  assert.equal(prediction.takeUndo().word, 'hello');
});

test('P18: provisional late mismatched notification follows existing policy after editing ends', () => {
  const { prediction } = rig();
  prediction.editing = true;
  prediction.selectionChanged(4, 4);
  assert.equal(prediction.getPrefix(), 'he');
  prediction.editing = false;
  // No source identifier is supplied. This does not classify the notification as a user tap.
  prediction.selectionChanged(4, 4);
  assert.equal(prediction.getPrefix(), '');
  assert.equal(prediction.takeCompositionAbandoned(), true);
});

test('P18: matching-position notification alone cannot detect OS preview completion', () => {
  const { prediction, notices } = rig();
  prediction.selectionChanged(5, 5);
  assert.equal(prediction.getPrefix(), 'he');
  assert.equal(prediction.takeCompositionAbandoned(), false);
  assert.deepEqual(notices, []);
});
