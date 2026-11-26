const assert = require('node:assert/strict');
const test = require('node:test');
const { MenuType, qwertyDigits, symbolPageRows } = require('../../entry/src/main/ets/model/KeyboardKeyData.ets');
const { keyboardMenuType, nextModeCycleTarget, numberFlickKind } =
  require('../../entry/src/main/ets/model/KeyboardModes.ets');
const { numberFlickKeys } = require('../../entry/src/main/ets/model/NumberFlickData.ets');
const { isUrlInputPattern, enterKeyLabel, spaceKeyLabel } =
  require('../../entry/src/main/ets/model/KeyboardKeyLabels.ets');

test('P45: QWERTY cycles between Japanese and English without entering number mode', () => {
  for (const order of ['jp_qwerty,en_qwerty', 'en_qwerty,jp_qwerty']) {
    const english = nextModeCycleTarget(false, MenuType.NORMAL, 'JP', order);
    assert.equal(english, 'EN');
    assert.equal(nextModeCycleTarget(false, MenuType.NORMAL, english, order), 'JP');
  }
});

test('P45: one enabled QWERTY language leaves the mode unchanged', () => {
  assert.equal(nextModeCycleTarget(false, MenuType.NORMAL, 'JP', 'jp_qwerty'), '');
  assert.equal(nextModeCycleTarget(false, MenuType.NORMAL, 'EN', 'en_qwerty'), '');
});

test('P45: the 12-key cycle includes numbers and skips disabled languages', () => {
  const both = 'en_flick,jp_flick';
  assert.equal(nextModeCycleTarget(true, MenuType.NORMAL, 'JP', both), 'EN');
  assert.equal(nextModeCycleTarget(true, MenuType.NORMAL, 'EN', both), 'NUMBER');
  assert.equal(nextModeCycleTarget(true, MenuType.NUMBER, 'EN', both), 'JP');
  for (const [mode, order] of [['JP', 'jp_flick'], ['EN', 'en_flick']]) {
    assert.equal(nextModeCycleTarget(true, MenuType.NORMAL, mode, order), 'NUMBER');
    assert.equal(nextModeCycleTarget(true, MenuType.NUMBER, mode, order), mode);
  }
});

test('P45: numeric editor patterns select the same number keypad on every layout', () => {
  for (const layout of ['jp_flick', 'en_flick', 'jp_qwerty', 'en_qwerty']) {
    for (const [pattern, kind, bottom] of [
      [2, 'number', ['.', '0', '-']], [3, 'phone', ['*', '0', '#']], [8, 'digits', ['', '0', '']]
    ]) {
      assert.equal(keyboardMenuType(layout, MenuType.NORMAL, pattern), MenuType.NUMBER);
      assert.equal(keyboardMenuType(layout, MenuType.SPECIAL, pattern), MenuType.NUMBER);
      assert.equal(numberFlickKind(pattern), kind);
      assert.deepEqual(numberFlickKeys(kind).slice(9).map(key => key[0]), bottom);
    }
    for (const pattern of [0, 1, 4, 5, 6, 7, 9, 10, 11]) {
      assert.equal(numberFlickKind(pattern), 'general');
      assert.equal(keyboardMenuType(layout, MenuType.NORMAL, pattern), MenuType.NORMAL);
    }
  }
});

test('P45: only a 12-key layout can display voluntary number mode', () => {
  for (const language of ['jp', 'en']) {
    assert.equal(keyboardMenuType(`${language}_flick`, MenuType.NUMBER, 0), MenuType.NUMBER);
    assert.equal(keyboardMenuType(`${language}_qwerty`, MenuType.NUMBER, 0), MenuType.NORMAL);
  }
});

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
