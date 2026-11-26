const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { runInNewContext } = require('node:vm');
const { numberFlickKeys } = require('../../entry/src/main/ets/model/NumberFlickData.ets');
const { KANA_MODIFIER_FLICKS } = require('../../entry/src/main/ets/kanon/KanaInput.ets');

test('P41: general number keys follow tap, left, up, right and down', () => {
  assert.deepEqual(numberFlickKeys('general'), [
    ['1', '/', ':', '@', '~'], ['2', '"', '\\', '%', "'"], ['3', '+', '×', '÷', '-'],
    ['4', '*', ';', '&', '·'], ['5', '¥', '₩', '€', '$'], ['6', '<', '^', '>', '='],
    ['7', '#', '♪', '〒', '※'], ['8', '[', '{', '}', ']'], ['9', '☆', '○', '◇', '♡'],
    ['…', '「', '\u25a1', '」', ''], ['0', '(', '_', ')', ''], ['.', ',', '?', '!', '']
  ]);
});

test('P41: dedicated number fields keep their own assignments', () => {
  const digits = [...'123456789'].map(digit => [digit, '', '', '', '']);
  for (const [kind, bottom] of [
    ['number', [['.', '', '', '', ''], ['0', '', '', '', ''], ['-', '', '', '', '']]],
    ['phone', [['*', '', '', '', ''], ['0', '+', '', '', ''], ['#', '', '', '', '']]],
    ['digits', [['', '', '', '', ''], ['0', '', '', '', ''], ['', '', '', '', '']]]
  ]) {
    assert.deepEqual(numberFlickKeys(kind), [...digits, ...bottom]);
  }
});

test('P41: English directions, bottom-center -# and third-row Space', () => {
  const source = readFileSync(resolve(__dirname, '../../entry/src/main/ets/components/FlickMenu.ets'), 'utf8');
  // ArkUI cannot run in Node. Read the actual array literals and check the side-key wiring.
  const array = name => {
    const match = source.match(new RegExp('private ' + name + ': [^=]+ = (\\[[^;]+\\]);'));
    assert.ok(match, name);
    return JSON.parse(runInNewContext('JSON.stringify(' + match[1] + ')'));
  };
  assert.deepEqual(array('englishKeys'), [
    ['@', '/', ':', '~', '1'], ['a', 'b', 'c', '', '2'], ['d', 'e', 'f', '', '3'],
    ['g', 'h', 'i', '', '4'], ['j', 'k', 'l', '', '5'], ['m', 'n', 'o', '', '6'],
    ['p', 'q', 'r', 's', '7'], ['t', 'u', 'v', '', '8'], ['w', 'x', 'y', 'z', '9'],
    ['shift'], ['-', '#', '0', '', ''], ['.', ',', '?', '!', '']
  ]);
  assert.deepEqual(array('englishLabels'), ['@/:~', 'abc', 'def', 'ghi', 'jkl', 'mno', 'pqrs', 'tuv', 'wxyz', 'a/A', '-#', '.,?!']);
  assert.deepEqual(array('digitHints'), ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '']);
  assert.match(source, /\.slice\(row \* 3, row \* 3 \+ 3\)/);
  assert.match(source, /else if \(row === 2 && this\.layout !== 'en_flick'\) \{ ConvertSpaceItem\(\) \}/);
  assert.match(source, /else if \(row === 3\) \{ ReturnItem\(\{[^}]*keyId: 'flick_control_7'/);
  assert.match(source, /else \{ this\.control\(row === 1 \? '→' : spaceKeyLabel\('EN'\), row === 1 \? 6 : 5\)/);
  assert.match(source, /else if \(action === 5\) \{ kanonIme\.keySpace\(\); \}/);
});

test('P41: kana modifier flicks select the requested operation', () => {
  assert.deepEqual(KANA_MODIFIER_FLICKS, ['cycle', 'voiced', 'size', 'semiVoiced', undefined]);
});
