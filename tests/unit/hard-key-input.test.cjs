const test = require('node:test');
const assert = require('node:assert/strict');
const { hardKeyDown, hardKeyUp, isKeyCodeAZ, isKeyCodeNumber } =
  require('../../entry/src/main/ets/model/HardKeyInput.ets');

// Values from @ohos.multimodalInput.keyCode.d.ts.
const codes = Object.freeze({
  digit0: 2000,
  digit9: 2009,
  star: 2010,
  pound: 2011,
  dpadUp: 2012,
  dpadDown: 2013,
  dpadLeft: 2014,
  dpadRight: 2015,
  dpadCenter: 2016,
  a: 2017,
  z: 2042,
  comma: 2043,
  period: 2044,
  altLeft: 2045,
  altRight: 2046,
  shiftLeft: 2047,
  shiftRight: 2048,
  space: 2050,
  enter: 2054,
  del: 2055,
  equals: 2058,
  slash: 2064,
  at: 2065,
  plus: 2066,
  forwardDel: 2071,
  numpad0: 2103,
  numpad9: 2112,
  numpadEnter: 2119,
  numpadLeftParen: 2121,
  numpadRightParen: 2122,
});

const idle = Object.freeze({ keyCodes: Object.freeze([]), specialKeyPress: false });
const down = (code, state = idle) => hardKeyDown(code, state, codes);
const up = (code, state) => hardKeyUp(code, state, codes);

test('P31: every letter produces lowercase text or uppercase with either leading Shift', () => {
  for (const shift of [codes.shiftLeft, codes.shiftRight]) {
    const pressed = down(shift);
    assert.equal(pressed.operation, undefined);
    assert.equal(pressed.unknown, false);
    assert.deepEqual(pressed.state.keyCodes, [shift]);
    for (const [index, letter] of [...'abcdefghijklmnopqrstuvwxyz'].entries()) {
      const code = codes.a + index;
      assert.equal(isKeyCodeAZ(code, codes), true);
      assert.deepEqual(down(code).operation, { kind: 'text', text: letter });
      const shifted = down(code, pressed.state);
      assert.deepEqual(shifted.operation, { kind: 'text', text: letter.toUpperCase() });
      assert.deepEqual(up(code, shifted.state).state, pressed.state);
    }
    assert.deepEqual(up(shift, pressed.state).state, idle);
  }
  assert.equal(isKeyCodeAZ(codes.a - 1, codes), false);
  assert.equal(isKeyCodeAZ(codes.z + 1, codes), false);
});

test('P31: top-row digits produce text and numeric keypad digits are classified but unhandled', () => {
  for (let n = 0; n <= 9; n++) {
    assert.equal(isKeyCodeNumber(codes.digit0 + n, codes), true);
    assert.deepEqual(down(codes.digit0 + n).operation, { kind: 'text', text: String(n) });
    assert.equal(isKeyCodeNumber(codes.numpad0 + n, codes), true);
    const numpad = down(codes.numpad0 + n);
    assert.equal(numpad.operation, undefined);
    assert.equal(numpad.unknown, true);
    assert.deepEqual(up(codes.numpad0 + n, numpad.state).state, idle);
  }
  for (const code of [codes.digit0 - 1, codes.digit9 + 1, codes.numpad0 - 1, codes.numpad9 + 1]) {
    assert.equal(isKeyCodeNumber(code, codes), false);
  }
});

test('P31: Shift in the first slot blocks a two-key nonletter chord until the keys are released', () => {
  for (const code of [codes.digit0, codes.space, codes.enter, codes.shiftRight]) {
    const shift = down(codes.shiftLeft);
    const chord = down(code, shift.state);
    assert.equal(chord.operation, undefined);
    assert.equal(chord.unknown, false);
    assert.equal(chord.state.specialKeyPress, true);
    const chordRelease = up(code, chord.state);
    assert.equal(chordRelease.handled, false);
    assert.deepEqual(chordRelease.state.keyCodes, [codes.shiftLeft]);
    assert.equal(down(codes.a, chordRelease.state).operation, undefined);
    const shiftRelease = up(codes.shiftLeft, chordRelease.state);
    assert.equal(shiftRelease.handled, false);
    assert.deepEqual(shiftRelease.state, idle);
  }
});

test('P31: Shift follows press order and repeat presses do not add held keys', () => {
  const first = down(codes.a);
  const shifted = down(codes.shiftLeft, first.state);
  const letter = down(codes.z, shifted.state);
  assert.deepEqual(letter.operation, { kind: 'text', text: 'z' });
  const release = up(codes.a, letter.state);
  const repeat = down(codes.z, release.state);
  assert.equal(repeat.repeated, true);
  assert.deepEqual(repeat.state.keyCodes, [codes.shiftLeft, codes.z]);
  assert.deepEqual(repeat.operation, { kind: 'text', text: 'Z' });
  const missing = up(codes.digit0, repeat.state);
  assert.equal(missing.missing, true);
  assert.equal(missing.handled, true);
  assert.deepEqual(missing.state, repeat.state);
  assert.deepEqual(first.state.keyCodes, [codes.a]);
});

test('P31: punctuation and function keys keep their text or IME operation', () => {
  const punctuation = [
    [codes.star, '*'], [codes.pound, '#'], [codes.comma, ','], [codes.period, '.'], [codes.equals, '='],
    [codes.slash, '/'], [codes.at, '@'], [codes.plus, '+'], [codes.numpadLeftParen, '('], [codes.numpadRightParen, ')']
  ];
  for (const [code, text] of punctuation) {
    assert.deepEqual(down(code).operation, { kind: 'text', text });
  }
  const functions = [
    [codes.space, 'space', false], [codes.enter, 'enter', false], [codes.numpadEnter, 'enter', false],
    [codes.dpadCenter, 'enter', true], [codes.del, 'delete', true], [codes.forwardDel, 'deleteForward', true],
    [codes.dpadUp, 'up', true], [codes.dpadDown, 'down', true], [codes.dpadLeft, 'left', true],
    [codes.dpadRight, 'right', true]
  ];
  for (const [code, kind, releasedFunctionKey] of functions) {
    const event = down(code);
    assert.deepEqual(event.operation, { kind });
    const release = up(code, event.state);
    assert.equal(release.handled, true);
    assert.equal(release.releasedFunctionKey, releasedFunctionKey);
    assert.deepEqual(release.state, idle);
  }
});

test('P31: Alt passes through and an unknown key suppresses input until ordinary release', () => {
  for (const alt of [codes.altLeft, codes.altRight]) {
    const event = down(alt);
    assert.equal(event.operation, undefined);
    assert.equal(event.unknown, false);
    assert.equal(event.state.specialKeyPress, false);
    assert.deepEqual(down(codes.a, event.state).operation, { kind: 'text', text: 'a' });
    assert.equal(up(alt, event.state).handled, true);
  }
  const code = 9999;
  const unknown = down(code);
  assert.equal(unknown.operation, undefined);
  assert.equal(unknown.unknown, true);
  const suppressed = down(codes.a, unknown.state);
  assert.equal(suppressed.operation, undefined);
  const release = up(code, suppressed.state);
  assert.equal(release.handled, false);
  assert.equal(release.state.specialKeyPress, true);
  const lastRelease = up(codes.a, release.state);
  assert.equal(lastRelease.handled, false);
  assert.deepEqual(lastRelease.state, idle);
});

test('P31: noninteger codes do not resolve to a letter or digit', () => {
  for (const code of [codes.a + 0.5, codes.digit0 + 0.5]) {
    const key = down(code);
    assert.equal(key.operation, undefined);
    assert.equal(key.unknown, true);
  }
  assert.equal(up(codes.dpadUp + 0.5, idle).releasedFunctionKey, true);
});

test('P31: early function-key release consumes the event before clearing special-key state', () => {
  for (const code of [codes.del, codes.forwardDel, codes.dpadUp, codes.dpadCenter]) {
    const unknown = down(9999);
    const blocked = down(code, unknown.state);
    assert.equal(blocked.operation, undefined);
    const release = up(code, up(9999, blocked.state).state);
    assert.equal(release.releasedFunctionKey, true);
    assert.equal(release.handled, true);
    assert.deepEqual(release.state, { keyCodes: [], specialKeyPress: true });
    const next = down(codes.a, release.state);
    assert.equal(next.operation, undefined);
    assert.deepEqual(up(codes.a, next.state).state, idle);
  }
});
