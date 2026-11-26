const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { KeyRollover } = require('../../entry/src/main/ets/common/KeyRollover.ets');

function key(rollover, out, text) {
  const enter = () => out.push(text);
  return {
    down() { rollover.land(); rollover.hold(enter); },
    up() { if (rollover.release(enter)) { enter(); } },
  };
}

test('rollover: overlapping presses keep the order they landed in (syu, not suy)', () => {
  const rollover = new KeyRollover();
  const out = [];
  const s = key(rollover, out, 's');
  const y = key(rollover, out, 'y');
  const u = key(rollover, out, 'u');
  s.down(); s.up();
  y.down();
  u.down();
  u.up();
  y.up();
  assert.deepEqual(out, ['s', 'y', 'u']);
});

test('rollover: a single press enters once on release', () => {
  const rollover = new KeyRollover();
  const out = [];
  const a = key(rollover, out, 'a');
  a.down();
  assert.deepEqual(out, []);
  a.up();
  a.up();
  assert.deepEqual(out, ['a']);
});

test('rollover: a cancelled press is never entered by a later landing', () => {
  const rollover = new KeyRollover();
  const out = [];
  const enter = () => out.push('x');
  rollover.land();
  rollover.hold(enter);
  assert.equal(rollover.release(enter), true);
  rollover.land();
  assert.deepEqual(out, []);
});

test('rollover: QWERTY letters and the keys beside them flush a held letter first', () => {
  const dir = path.join(__dirname, '../../entry/src/main/ets/components');
  for (const file of ['KeyItem.ets', 'KeyItemNumber.ets', 'SpaceItem.ets', 'DeleteItem.ets', 'ReturnItem.ets', 'KeyItemGray.ets']) {
    assert.match(fs.readFileSync(path.join(dir, file), 'utf8'), /keyRollover\.land\(\)/, file);
  }
  const item = fs.readFileSync(path.join(dir, 'KeyItem.ets'), 'utf8');
  assert.match(item, /keyRollover\.release\(enter\)\) \{ enter\(\); \}/);
});

test('rollover: the QWERTY letter key enters a held letter through the same path as its release', () => {
  const source = fs.readFileSync(path.join(__dirname, '../../entry/src/main/ets/components/KeyItemNumber.ets'), 'utf8');
  assert.match(source, /keyRollover\.hold\(enter\)/);
  assert.match(source, /keyRollover\.release\(enter\)\) \{ enter\(\); \}/);
  assert.match(source, /private enterHeld\(\): void \{[\s\S]*kanonIme\.keyText\(value\);/);
});
