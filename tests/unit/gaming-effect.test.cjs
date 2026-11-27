const test = require('node:test');
const assert = require('node:assert/strict');
const { GamingTapResult: Tap, GamingUnlockTaps, GamingRipples } =
  require('../../entry/src/main/ets/common/GamingEffectModel.ets');
const { KeyboardSettingsRecord, KeyboardSettingsSnapshot, validSettingsPatch, validSettingsSnapshot,
  applySettingsPatch, mergeSettingsPatch, decodeSettingsRecord } =
  require('../../entry/src/main/ets/common/KeyboardSettingsModel.ets');
const { LegacyKeyboardSettings, migrateLegacySettings } =
  require('../../entry/src/main/ets/common/KeyboardSettingsMigration.ets');
const { SETTINGS_MENU, SettingsPageId: Page, SettingsMenuAction: Action, settingsMenuRows, settingsGamingSummary,
  settingsReset } = require('../../entry/src/main/ets/common/SettingsMenuModel.ets');
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
  assert.equal(settingsGamingSummary('ripple', ...labels), '押したキーから波紋');
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
