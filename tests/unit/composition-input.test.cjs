const test = require('node:test');
const assert = require('node:assert/strict');
const { literalInputs } = require('../../entry/src/main/ets/kanon/CompositionInput.ets');
const { kanaRoman, modifiedKana } = require('../../entry/src/main/ets/kanon/KanaInput.ets');

test('C06: literal replay units retain surrogate pairs and punctuation', () => {
  const units = literalInputs('あ😀!');
  assert.deepEqual(units.map(unit => unit.text), ['あ', '😀', '!']);
  assert.ok(units.every(unit => unit.literal && unit.kana === ''));
  assert.equal(units.map(unit => unit.text).join(''), 'あ😀!');
});

test('kana modifiers cycle voiced, semi-voiced and small kana', () => {
  assert.equal(modifiedKana('は'), 'ば');
  assert.equal(modifiedKana('ば'), 'ぱ');
  assert.equal(modifiedKana('ぱ'), 'は');
  assert.equal(modifiedKana('や'), 'ゃ');
  assert.equal(kanaRoman('ば'), 'ba');
  assert.equal(modifiedKana('😀'), '😀');
  assert.equal(kanaRoman('!'), '');
});
