const test = require('node:test');
const assert = require('node:assert/strict');
const layout = require('../../entry/src/main/ets/common/KeyboardLayout.ets');

test('L01: key spacing is normalized and defaults remain compatible', () => {
  assert.equal(layout.keyboardKeyGap(NaN), 6);
  assert.equal(layout.keyboardKeyGap(Infinity), 6);
  assert.equal(layout.keyboardKeyGap(-1), 0);
  assert.equal(layout.keyboardKeyGap(11), 10);
  assert.equal(layout.keyboardKeyGap(4.6), 5);
  assert.equal(layout.effectiveKeyGap(360, 247, 6), 6);
});

test('L01: gaps fit ten columns and four rows in narrow panels', () => {
  for (const width of [180, 240, 360, 720]) {
    for (const height of [120, 160, 247, 400]) {
      for (const value of [0, 6, 10]) {
        const gap = layout.effectiveKeyGap(width, height, value);
        assert.ok(gap >= 0 && gap <= value);
        assert.ok((width - 12 - 9 * gap) / 10 >= 16 - Number.EPSILON * 32);
        assert.ok((height - 12 - 3 * gap) / 4 >= 24 - Number.EPSILON * 32);
      }
    }
  }
});

test('L02: saved height uses integers while dragging preserves tenths', () => {
  assert.equal(layout.keyboardHeightPercent(119.6), 120);
  assert.equal(layout.keyboardHeightPreviewPercent(119.64), 119.6);
  assert.equal(layout.keyboardHeightPercent(NaN), 100);
  assert.equal(layout.keyboardHeightPercent(50), 80);
  assert.equal(layout.keyboardHeightPercent(200), 150);
});

test('L02: panel remains within portrait and landscape limits', () => {
  for (const [width, height] of [[360, 800], [800, 360], [240, 400]]) {
    let previous = 0;
    for (const percent of [80, 100, 150]) {
      const actual = layout.panelHeight(width, height, 1.5, percent);
      const limit = Math.min(height * (width > height ? 0.55 : 0.48), height - 96);
      assert.ok(actual > 0 && actual <= limit);
      assert.ok(actual >= previous); previous = actual;
    }
  }
});

test('clipboard columns adapt to width and font size', () => {
  assert.equal(layout.clipboardColumns(320, 1), 2);
  assert.equal(layout.clipboardColumns(320, 2), 1);
  assert.equal(layout.clipboardColumns(1000, 1), 4);
});
