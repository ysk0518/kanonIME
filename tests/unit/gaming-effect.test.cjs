const test = require('node:test');
const assert = require('node:assert/strict');
const { GAMING_EFFECTS, GamingTapResult: Tap, GamingUnlockTaps, GamingRipples, gamingFlowPeriodMs, gamingFlowStep,
  gamingSpreadDurationMs, gamingWaveSample } =
  require('../../entry/src/main/ets/common/GamingEffectModel.ets');
const { KeyboardSettingsRecord, KeyboardSettingsSnapshot, validSettingsPatch, validSettingsSnapshot,
  applySettingsPatch, mergeSettingsPatch, decodeSettingsRecord } =
  require('../../entry/src/main/ets/common/KeyboardSettingsModel.ets');
const { LegacyKeyboardSettings, migrateLegacySettings } =
  require('../../entry/src/main/ets/common/KeyboardSettingsMigration.ets');
const { SETTINGS_MENU, SettingsPageId: Page, SettingsMenuAction: Action, SettingsNumber, settingsMenuRows,
  settingsGamingSummary, settingsNumberPatch, settingsReset } = require('../../entry/src/main/ets/common/SettingsMenuModel.ets');
const { pair } = require('../support/settings-sync-rig.cjs');
const { string: strings } = require('../../entry/src/main/resources/base/element/string.json');

test('P58: the seventh consecutive version tap unlocks and taps four to six give hints', () => {
  const taps = new GamingUnlockTaps();
  const results = Array.from({ length: 7 }, (_, i) => taps.tap(i * 1999, false));
  assert.deepEqual(results, [Tap.Quiet, Tap.Quiet, Tap.Quiet, Tap.ThreeLeft, Tap.TwoLeft, Tap.OneLeft, Tap.Unlock]);
  assert.equal(taps.tap(14000, true), Tap.AlreadyUnlocked);
  assert.equal(taps.tap(14100, false), Tap.Quiet);
});

test('P58: a gap of exactly two seconds or leaving About restarts the count', () => {
  const taps = new GamingUnlockTaps();
  for (const time of [0, 10, 20]) { assert.equal(taps.tap(time, false), Tap.Quiet); }
  assert.equal(taps.tap(2020, false), Tap.Quiet);
  assert.equal(taps.tap(2030, false), Tap.Quiet);
  assert.equal(taps.tap(2040, false), Tap.Quiet);
  assert.equal(taps.tap(2050, false), Tap.ThreeLeft);
  taps.reset();
  assert.equal(taps.tap(2060, false), Tap.Quiet);
});

test('P58: gaming fields default, migrate, validate and normalize invalid effects', () => {
  const defaults = new KeyboardSettingsSnapshot();
  assert.equal(defaults.gamingUnlocked, false);
  assert.equal(defaults.gamingEffect, 'off');
  assert.equal(validSettingsPatch({ gamingUnlocked: 'true' }), false);
  assert.equal(validSettingsSnapshot({ ...defaults, gamingUnlocked: 1 }), false);
  for (const gamingEffect of ['off', 'flow', 'ripple']) {
    const patch = { gamingUnlocked: true, gamingEffect };
    assert.equal(validSettingsPatch(patch), true);
    assert.equal(applySettingsPatch(defaults, patch).gamingEffect, gamingEffect);
  }
  const record = new KeyboardSettingsRecord();
  for (const gamingEffect of ['unknown', null, 2]) {
    const patch = { gamingEffect };
    assert.equal(applySettingsPatch(defaults, patch).gamingEffect, 'off');
    assert.equal(mergeSettingsPatch({ gamingEffect: 'flow' }, patch).gamingEffect, 'off');
    record.snapshot.gamingEffect = gamingEffect;
    assert.equal(decodeSettingsRecord(JSON.stringify(record)).snapshot.gamingEffect, 'off');
  }
  delete record.snapshot.gamingUnlocked;
  delete record.snapshot.gamingEffect;
  const legacyRecord = decodeSettingsRecord(JSON.stringify(record));
  const migrated = migrateLegacySettings(new LegacyKeyboardSettings());
  for (const { snapshot } of [legacyRecord, migrated]) {
    assert.equal(snapshot.gamingUnlocked, false);
    assert.equal(snapshot.gamingEffect, 'off');
  }
});

test('P58: the gaming row appears last in Style only after unlock and summarizes the selection', () => {
  for (const group of SETTINGS_MENU) {
    assert.deepEqual(settingsMenuRows(group, false), group.rows);
    const expected = group.styleHeading ? [...group.rows, { action: Action.Open, page: Page.Gaming }] : group.rows;
    assert.deepEqual(settingsMenuRows(group, true), expected);
  }
  const labels = ['off', 'flow', 'ripple'].map(effect =>
    strings.find(entry => entry.name === `settings_gaming_${effect}`).value);
  assert.equal(settingsGamingSummary('off', ...labels), 'オフ');
  assert.equal(settingsGamingSummary('flow', ...labels), '虹色が流れる');
  assert.equal(settingsGamingSummary('ripple', ...labels), '輪が広がる');
  assert.equal(settingsGamingSummary('invalid', ...labels), 'オフ');
});

test('P58: unlock and effect sync to the IME and reset turns off the effect while keeping discovery', async () => {
  const rig = await pair();
  await rig.app.core.save({ gamingUnlocked: true }, false);
  await rig.app.core.save({ gamingEffect: 'ripple' }, false);
  await rig.pump();
  assert.equal(rig.ime.state.record.snapshot.gamingUnlocked, true);
  assert.equal(rig.ime.state.record.snapshot.gamingEffect, 'ripple');
  await rig.app.core.save(settingsReset().patch, false);
  await rig.pump();
  for (const endpoint of [rig.app, rig.ime]) {
    assert.equal(endpoint.state.record.snapshot.gamingUnlocked, true);
    assert.equal(endpoint.state.record.snapshot.gamingEffect, 'off');
  }
});

test('P58: ripples retain only eight newest presses and expire independently', () => {
  const ripples = new GamingRipples();
  for (let i = 0; i < 8; i++) { assert.equal(ripples.add(i, i + 10, i).length, i + 1); }
  const rings = ripples.add(8, 18, 8);
  assert.deepEqual(rings.map(ring => ring.x), [1, 2, 3, 4, 5, 6, 7, 8]);
  assert.equal(rings[7].y, 18);
  assert.equal(ripples.remove(0).length, 8);
  assert.deepEqual(ripples.remove(rings[2].id).map(ring => ring.x), [1, 2, 4, 5, 6, 7, 8]);
  assert.deepEqual(ripples.add(9, 19, 408).map(ring => ring.x), [9]);
});

function wavePresses(x = 0, y = 0, startedAt = 0, speed = 3) {
  return new GamingRipples().add(x, y, startedAt, gamingSpreadDurationMs(speed), 40);
}

function waveAt(x, y, now, presses = wavePresses(), previous = now) {
  return gamingWaveSample({ x, y }, { presses, now, previous, maxRadius: 200 });
}

test('P58b: the peak travels by distance and time, with a one-key-wide band', () => {
  assert.equal(waveAt(0, 0, -1).intensity, 0);
  assert.equal(waveAt(0, 0, 0).intensity, 1);
  assert.equal(waveAt(0, 0, 100).intensity, 0);
  assert.equal(waveAt(30, 40, 100).intensity, 1);
  assert.equal(waveAt(60, 0, 100).intensity, 0.5);
  assert.equal(waveAt(70, 0, 100).intensity, 0);
  assert.equal(waveAt(30, 0, 100).intensity, 0);
  assert.notEqual(waveAt(50, 0, 100).hue, waveAt(60, 0, 100).hue);
  assert.notEqual(waveAt(50, 0, 90).hue, waveAt(50, 0, 100).hue);
});

test('P58b: the wave is zero at the maximum radius and after expiry', () => {
  assert.equal(waveAt(200, 0, 396).intensity, 0);
  assert.equal(waveAt(198, 0, 396).intensity, 1);
  assert.equal(waveAt(198, 0, 400).intensity, 0);
  assert.equal(waveAt(198, 0, 450).intensity, 0);
});

test('P58b: overlapping presses use the strongest wave and retain eight newest presses', () => {
  const first = wavePresses();
  const second = wavePresses(60, 0, 100);
  const strongest = waveAt(60, 0, 100, second);
  assert.deepEqual(waveAt(60, 0, 100, [...second, ...first]), strongest);
  assert.deepEqual(waveAt(60, 0, 100, [...first, ...second]), strongest);
  const history = new GamingRipples();
  for (let i = 0; i < 9; i++) { history.add(i, 0, i, gamingSpreadDurationMs(5), 40); }
  assert.deepEqual(history.activeAt(8).map(press => press.x), [1, 2, 3, 4, 5, 6, 7, 8]);
  assert.deepEqual(history.activeAt(185).map(press => press.x), [8]);
  assert.deepEqual(history.activeAt(186), []);
});

test('P58b: a fast wave lights keys crossed between frames including its last frame', () => {
  const presses = wavePresses(0, 0, 0, 5);
  assert.equal(waveAt(22, 0, 0, presses).intensity, 0);
  assert.equal(waveAt(22, 0, 50, presses).intensity, 0);
  assert.equal(waveAt(22, 0, 50, presses, 0).intensity, 1);
  assert.equal(waveAt(190, 0, 200, presses, 150).intensity, 1);
  assert.equal(waveAt(190, 0, 250, presses, 200).intensity, 0);
});

test('P58b: flow cycles and wave and ripple durations follow the same speed ratios', () => {
  const speeds = [1, 2, 3, 4, 5];
  assert.deepEqual(speeds.map(gamingFlowPeriodMs), [7200, 5400, 3600, 2400, 1600]);
  assert.deepEqual(speeds.map(gamingSpreadDurationMs), [800, 600, 400, 267, 178]);
  for (const speed of speeds) {
    const period = gamingFlowPeriodMs(speed);
    assert.equal(gamingFlowStep(period / 2, speed), 18);
    assert.equal(gamingFlowStep(period - 1, speed), 35);
    assert.equal(gamingFlowStep(period, speed), 0);
    const presses = wavePresses(0, 0, 0, speed);
    assert.equal(waveAt(100, 0, gamingSpreadDurationMs(speed) / 2, presses).intensity, 1);
  }
});

test('P58b: speed validates integer levels and old settings default to level three', () => {
  const defaults = new KeyboardSettingsSnapshot();
  assert.equal(defaults.gamingSpeed, 3);
  for (const gamingSpeed of [1, 2, 3, 4, 5]) {
    assert.equal(validSettingsPatch({ gamingSpeed }), true);
    assert.equal(validSettingsSnapshot({ ...defaults, gamingSpeed }), true);
  }
  for (const gamingSpeed of [0, 6, -1, 3.5, NaN, Infinity, '3', null]) {
    assert.equal(validSettingsPatch({ gamingSpeed }), false);
    assert.equal(validSettingsSnapshot({ ...defaults, gamingSpeed }), false);
    assert.throws(() => applySettingsPatch(defaults, { gamingSpeed }), /Invalid keyboard settings/);
  }
  const record = new KeyboardSettingsRecord();
  record.snapshot.gamingEffect = 'ripple';
  delete record.snapshot.gamingSpeed;
  const migrated = decodeSettingsRecord(JSON.stringify(record)).snapshot;
  assert.equal(migrated.gamingSpeed, 3);
  assert.equal(migrated.gamingEffect, 'ripple');
  assert.equal(migrateLegacySettings(new LegacyKeyboardSettings()).snapshot.gamingSpeed, 3);
});

test('P58b: wave is accepted and the gaming summary uses the selected label', () => {
  assert.deepEqual(GAMING_EFFECTS.slice(0, 4), ['off', 'flow', 'wave', 'ripple']);
  const labels = ['off', 'flow', 'ripple', 'wave'].map(effect =>
    strings.find(entry => entry.name === `settings_gaming_${effect}`).value);
  assert.equal(settingsGamingSummary('wave', ...labels), 'キーが波紋で光る');
  const defaults = new KeyboardSettingsSnapshot();
  assert.equal(validSettingsPatch({ gamingEffect: 'wave' }), true);
  assert.equal(applySettingsPatch(defaults, { gamingEffect: 'wave' }).gamingEffect, 'wave');
  assert.deepEqual(mergeSettingsPatch({ gamingSpeed: 4 }, { gamingEffect: 'wave', gamingSpeed: 5 }),
    { gamingEffect: 'wave', gamingSpeed: 5 });
  const record = new KeyboardSettingsRecord();
  record.snapshot.gamingEffect = 'wave';
  assert.equal(decodeSettingsRecord(JSON.stringify(record)).snapshot.gamingEffect, 'wave');
});

test('P58b: speed syncs independently and reset restores level three', async () => {
  const rig = await pair();
  await rig.app.core.save({ gamingUnlocked: true, gamingEffect: 'wave' }, false);
  await rig.app.core.save(settingsNumberPatch(SettingsNumber.GamingSpeed, 5), false);
  await rig.pump();
  assert.equal(rig.ime.state.record.snapshot.gamingEffect, 'wave');
  assert.equal(rig.ime.state.record.snapshot.gamingSpeed, 5);
  await rig.app.core.save(settingsReset().patch, false);
  await rig.pump();
  for (const endpoint of [rig.app, rig.ime]) {
    assert.equal(endpoint.state.record.snapshot.gamingSpeed, 3);
    assert.equal(endpoint.state.record.snapshot.gamingEffect, 'off');
    assert.equal(endpoint.state.record.snapshot.gamingUnlocked, true);
  }
});
