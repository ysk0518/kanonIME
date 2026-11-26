const test = require('node:test');
const assert = require('node:assert/strict');
const { KeyboardSound } = require('../../entry/src/main/ets/common/KeyboardSound.ets');
const { deferred } = require('../support/fakes.cjs');

test('P46: off never calls playback', () => {
  const volumes = [];
  const sound = new KeyboardSound({ play: async volume => { volumes.push(volume); } });
  sound.key(0);
  assert.deepEqual(volumes, []);
});

test('P46: each enabled press requests playback at the selected volume', async () => {
  const volumes = [];
  const playback = deferred();
  const sound = new KeyboardSound({ play: volume => {
    volumes.push(volume);
    return playback.promise;
  } });
  sound.key(1);
  sound.key(2);
  sound.key(2);
  assert.equal(volumes.length, 3);
  assert.ok(volumes[0] > 0 && volumes[0] < volumes[1] && volumes[1] <= 1);
  assert.equal(volumes[1], volumes[2]);
  playback.resolve();
  await playback.promise;
});

test('P46: playback exceptions and rejections stay out of key handling', async () => {
  let calls = 0;
  const sound = new KeyboardSound({ play: () => {
    calls++;
    if (calls === 1) { throw new Error('SoundPool unavailable'); }
    return calls === 2 ? Promise.reject(new Error('play failed')) : Promise.resolve();
  } });
  assert.doesNotThrow(() => sound.key(1));
  assert.doesNotThrow(() => sound.key(2));
  // Let Node observe any unhandled rejection before checking the next press.
  await new Promise(resolve => setImmediate(resolve));
  sound.key(1);
  assert.equal(calls, 3);
});

test('P46: character keys give feedback on touch-down and release skips it once', () => {
  const { readFileSync } = require('node:fs');
  const { resolve } = require('node:path');
  const read = name => readFileSync(resolve(__dirname, '../../entry/src/main/ets', name), 'utf8');
  for (const name of ['components/FlickKey.ets', 'components/KeyItem.ets', 'components/KeyItemNumber.ets']) {
    const source = read(name);
    const down = source.slice(source.indexOf('event.type === TouchType.Down'));
    assert.match(down.slice(0, 700), /keyboardHaptics\.press\(\);/, name);
  }
  const haptics = read('common/KeyboardHaptics.ets');
  assert.match(haptics, /key\(\): void \{\s*if \(this\.pressedAt >= 0\) \{[\s\S]*?this\.pressedAt = -1;\s*if \(pressed\) \{ return; \}/);
  const sound = read('common/HarmonyKeyboardSound.ets');
  assert.doesNotMatch(sound, /pool\.stop\(/);
});
