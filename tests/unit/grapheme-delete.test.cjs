const test = require('node:test');
const assert = require('node:assert/strict');
const { lastGraphemeLength } = require('../../entry/src/main/ets/kanon/GraphemeDelete.ets');

test('P37: last grapheme width covers UTF-16 pairs and extended sequences', () => {
  assert.equal(lastGraphemeLength(''), 0);
  for (const cluster of [
    'a', '😀', '👩🏽‍💻', '👨‍👩‍👧‍👦', '☕\uFE0F', '漢\u{E0100}', '👍🏿', '🇯🇵',
    '1\uFE0F\u20E3', '\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}',
    'a\u0301\u0308', 'a\u1AB0', 'a\u1DC0', 'a\u20D0', 'a\uFE20', 'か\u3099', 'は\u309A', '\r\n'
  ]) {
    assert.equal(lastGraphemeLength(`x${cluster}`), cluster.length, `width for ${cluster}`);
    assert.equal(lastGraphemeLength(`${cluster}x`), 1, `trailing ASCII after ${cluster}`);
  }
  assert.equal(lastGraphemeLength('a\uDC00'), 1);
  assert.equal(lastGraphemeLength('\u0301\u0308'), 2);
});

test('P37: regional indicators pair from the end even in an odd run', () => {
  let text = 'x🇦🇧🇨🇩🇪';
  for (const width of [4, 4, 2, 1]) {
    assert.equal(lastGraphemeLength(text), width);
    text = text.slice(0, -width);
  }
  assert.equal(text, '');
});
