const test = require('node:test');
const assert = require('node:assert/strict');
const { hasBackgroundPhoto, usesDarkKeyPalette } = require('../../entry/src/main/ets/common/BackgroundAppearance.ets');

const jpeg = 'data:image/jpeg;base64,AA==';
const gif = 'data:image/gif;base64,AA==';

test('P62: image or poster counts as a photo background', () => {
  assert.equal(hasBackgroundPhoto('', ''), false);
  assert.equal(hasBackgroundPhoto(jpeg, ''), true);
  assert.equal(hasBackgroundPhoto(gif, jpeg), true);
  assert.equal(hasBackgroundPhoto('', jpeg), true);
});

test('P62: photo backgrounds select the dark palette in both system modes', () => {
  for (const systemDark of [false, true]) {
    assert.equal(usesDarkKeyPalette(hasBackgroundPhoto(jpeg, ''), systemDark), true);
    assert.equal(usesDarkKeyPalette(hasBackgroundPhoto(gif, jpeg), systemDark), true);
    assert.equal(usesDarkKeyPalette(hasBackgroundPhoto('', jpeg), systemDark), true);
    assert.equal(usesDarkKeyPalette(hasBackgroundPhoto('', ''), systemDark), systemDark);
  }
});
