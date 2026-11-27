const test = require('node:test');
const assert = require('node:assert/strict');
const { BackgroundConfig, backgroundDraftChanged } = require('../../entry/src/main/ets/common/BackgroundAppearance.ets');
const { DEFAULT_SHORTCUT_ORDER, shortcutOrder, availableShortcuts, canMoveShortcut, moveShortcut,
  addShortcut, removeShortcut } = require('../../entry/src/main/ets/common/ShortcutConfigValues.ets');
const { KeyboardSettingsSnapshot, applySettingsPatch } = require('../../entry/src/main/ets/common/KeyboardSettingsModel.ets');
const { SettingsNumber, settingsNumberPatch, settingsShortcutPatch } =
  require('../../entry/src/main/ets/common/SettingsMenuModel.ets');

test('P57: shortcut arrows disable at the corresponding edge', () => {
  const order = ['clipboard', 'settings', 'edit'];
  assert.equal(canMoveShortcut(order, 'clipboard', -1), false);
  assert.equal(canMoveShortcut(order, 'clipboard', 1), true);
  assert.equal(canMoveShortcut(order, 'settings', -1), true);
  assert.equal(canMoveShortcut(order, 'settings', 1), true);
  assert.equal(canMoveShortcut(order, 'edit', -1), true);
  assert.equal(canMoveShortcut(order, 'edit', 1), false);
  assert.equal(canMoveShortcut(['settings'], 'settings', 1), false);
  assert.equal(canMoveShortcut([], 'settings', -1), false);
  assert.equal(canMoveShortcut(order, 'missing', 1), false);
  assert.deepEqual(moveShortcut(order, 'edit', 1), order);
});

test('P57: shortcut edits persist the visible order including an empty toolbar', () => {
  const original = shortcutOrder(DEFAULT_SHORTCUT_ORDER);
  const snapshot = new KeyboardSettingsSnapshot();
  const expanded = addShortcut(original, 'edit');
  assert.deepEqual(expanded, ['clipboard', 'settings', 'edit']);
  assert.deepEqual(availableShortcuts(original), ['edit']);
  assert.deepEqual(availableShortcuts(expanded), []);
  assert.deepEqual(addShortcut(expanded, 'edit'), expanded);
  assert.deepEqual(addShortcut(expanded, 'unknown'), expanded);
  const movedUp = moveShortcut(expanded, 'edit', -1);
  assert.deepEqual(movedUp, ['clipboard', 'edit', 'settings']);
  const movedDown = moveShortcut(movedUp, 'clipboard', 1);
  assert.deepEqual(movedDown, ['edit', 'clipboard', 'settings']);
  const removed = removeShortcut(movedDown, 'clipboard');
  assert.deepEqual(settingsShortcutPatch(removed), { shortcutOrder: 'edit,settings' });
  assert.equal(applySettingsPatch(snapshot, settingsShortcutPatch(removed)).shortcutOrder, 'edit,settings');
  assert.equal(applySettingsPatch(snapshot,
    settingsShortcutPatch(removeShortcut(removeShortcut(removed, 'edit'), 'settings'))).shortcutOrder, '');
  assert.deepEqual(original, ['clipboard', 'settings']);
});

test('P57: size slider writes only the clamped whole-percent keyboard height', () => {
  assert.deepEqual(settingsNumberPatch(SettingsNumber.Height, 123.6), { heightPercent: 124 });
  assert.deepEqual(settingsNumberPatch(SettingsNumber.Height, 60), { heightPercent: 80 });
  assert.deepEqual(settingsNumberPatch(SettingsNumber.Height, 190), { heightPercent: 150 });
  assert.deepEqual(settingsNumberPatch(SettingsNumber.Height, NaN), { heightPercent: 100 });
  const snapshot = new KeyboardSettingsSnapshot();
  const patch = settingsNumberPatch(SettingsNumber.Height, 120);
  assert.deepEqual(applySettingsPatch(snapshot, patch), { ...snapshot, heightPercent: 120 });
});

test('P57: theme drafts compare editable content independently of the saved version', () => {
  const saved = Object.assign(new BackgroundConfig(), { version: 42 });
  assert.equal(backgroundDraftChanged(new BackgroundConfig(), saved), false);
  const gif = Object.assign(new BackgroundConfig(), { photo: 'gif-data', format: 'gif', poster: 'poster-data',
    sourceId: 'gif-12-1', gifResolution: 320, gifFps: 24, gifWidth: 320, gifHeight: 160, gifFrames: 24 });
  assert.equal(backgroundDraftChanged(gif, saved), true);
  assert.equal(backgroundDraftChanged(new BackgroundConfig(), gif), true);
  for (const [field, value] of Object.entries({
    photo: 'new-data', format: 'jpeg', poster: 'new-poster', animate: false, sourceId: 'gif-12-2',
    gifResolution: 120, gifFps: 15, gifWidth: 120, gifHeight: 60, gifFrames: 12,
    zoom: 150, x: 15, y: -20, brightness: 80, keyOpacity: 50
  })) {
    const draft = Object.assign(new BackgroundConfig(), gif);
    draft[field] = value;
    assert.equal(backgroundDraftChanged(draft, gif), true, field);
    draft[field] = gif[field];
    assert.equal(backgroundDraftChanged(draft, gif), false, field);
  }
});
