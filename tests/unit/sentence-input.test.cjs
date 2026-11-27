const test = require('node:test');
const assert = require('node:assert/strict');
const { doubleSpacePeriod, sentenceStart, autoCapitalField } = require('../../entry/src/main/ets/kanon/SentenceInput.ets');

test('P52: a word and one space end with a period on the second space', () => {
  for (const before of ['hello ', 'ok ', 'A1 ', 'done) ', 'said" ']) { assert.equal(doubleSpacePeriod(before), true, before); }
  for (const before of ['', ' ', 'hello', 'hello  ', 'end. ', 'what? ', 'あ ', '\n ']) {
    assert.equal(doubleSpacePeriod(before), false, JSON.stringify(before));
  }
});

test('P52: a sentence starts in an empty field, on a new line, or after . ! ? and a space', () => {
  for (const before of ['', '  ', 'Hi. ', 'Why? ', 'Wow! ', 'He said "no." ', 'line\n', 'x.\n  ']) {
    assert.equal(sentenceStart(before), true, JSON.stringify(before));
  }
  for (const before of ['Hi', 'Hi ', 'Hi.', 'e.g', 'one, ', 'a: ']) {
    assert.equal(sentenceStart(before), false, JSON.stringify(before));
  }
});

test('P52: only text fields capitalize sentences', () => {
  assert.equal(autoCapitalField(0), true);
  assert.equal(autoCapitalField(1), true);
  for (const pattern of [2, 3, 5, 6, 7, 8, 9, 11]) { assert.equal(autoCapitalField(pattern), false, String(pattern)); }
});
