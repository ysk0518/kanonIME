const assert = require('node:assert/strict');
const test = require('node:test');
const { qwertyDigits, symbolPageRows } = require('../../entry/src/main/ets/model/KeyboardKeyData.ets');
const { isUrlInputPattern, enterKeyLabel, spaceKeyLabel } =
  require('../../entry/src/main/ets/model/KeyboardKeyLabels.ets');

test('P42: QWERTY has a dedicated digit row in typing order', () => {
  assert.deepEqual(qwertyDigits, Array.from('1234567890'));
});

test('P42: both symbol pages follow the Samsung row order', () => {
  assert.deepEqual(symbolPageRows, [
    ['1234567890', '+×÷=/_<>[]', '!@#$%^&*()', "-'\":;,?"].map(row => Array.from(row)),
    ['1234567890', '`~\\|{}€£¥₩', '°•○●□■♤♡◇♧', '☆▪¤《》¡¿'].map(row => Array.from(row))
  ]);
});

test('P42: only the IME URL input pattern gets the URL keys', () => {
  assert.equal(isUrlInputPattern(6), true);
  // Text, multiline, numeric, phone, date, email, password, OTP and unknown patterns.
  for (const pattern of [-1, 0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 99]) {
    assert.equal(isUrlInputPattern(pattern), false, `inputPattern ${pattern}`);
  }
});

test('P42: Enter labels follow the editor action and English composition', () => {
  assert.deepEqual([0, 1, 2, 3, 4, 5, 6, 7, 8, 99].map(type => enterKeyLabel(type, false)),
    ['改行', '改行', '移動', '検索', '送信', '次へ', '完了', '改行', '改行', '改行']);
  assert.deepEqual([2, 3, 4, 5, 6].map(type => enterKeyLabel(type, true)), Array(5).fill('改行'));
});

test('P42: space labels follow the language, layout and composition state', () => {
  assert.equal(spaceKeyLabel('JP'), '日本語 ␣');
  assert.equal(spaceKeyLabel('JP', true), '日本語 ␣');
  assert.equal(spaceKeyLabel('JP', false, true), 'space');
  assert.equal(spaceKeyLabel('JP', true, true), '候補 ␣');
  assert.equal(spaceKeyLabel('EN'), 'English ␣');
  assert.equal(spaceKeyLabel('EN', true), 'English ␣');
  assert.equal(spaceKeyLabel('NUMBER', true), '␣');
  assert.equal(spaceKeyLabel('SPECIAL', false, true), '␣');
});

test('Flick off: QWERTY and symbol pages drop the globe key so the space gets wider', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  for (const name of ['KeyMenu', 'SymbolMenu']) {
    const source = fs.readFileSync(path.join(__dirname, '../../entry/src/main/ets/components', `${name}.ets`), 'utf8');
    const globe = source.split('\n').filter((line) => line.includes('globe: true'));
    assert.equal(globe.length, 1, name);
    assert.match(globe[0], /^\s*if \(this\.flickEnabled\) \{ Column\(\) \{ LayoutItem\(/, name);
    assert.match(source, /@StorageLink\('kanonFlickEnabled'\) flickEnabled: boolean = true;/, name);
  }
});
