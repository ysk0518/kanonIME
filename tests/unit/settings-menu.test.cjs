const test = require('node:test');
const assert = require('node:assert/strict');
const { SETTINGS_MENU, SettingsPageId: Page, SettingsMenuAction: Action, SettingsToggle: Toggle,
  SettingsNumber: NumberSetting, settingsLanguageSummary, settingsThemeSummary,
  settingsLanguagePatch, settingsLayoutPatch, settingsTogglePatch, settingsNumberPatch,
  settingsShortcutPatch, settingsReset
} = require('../../entry/src/main/ets/common/SettingsMenuModel.ets');
const { applySettingsPatch, KeyboardSettingsSnapshot, validSettingsPatch } =
  require('../../entry/src/main/ets/common/KeyboardSettingsModel.ets');
const { BackgroundConfig } = require('../../entry/src/main/ets/common/BackgroundAppearance.ets');
const { string: strings } = require('../../entry/src/main/resources/base/element/string.json');
const { pair } = require('../support/settings-sync-rig.cjs');

const text = Object.fromEntries(strings.map(({ name, value }) => [name, value]));

test('P55: the menu groups route to their dedicated pages in order', () => {
  assert.deepEqual(SETTINGS_MENU.map(group => group.styleHeading), [false, false, false, true, false, false]);
  assert.deepEqual(SETTINGS_MENU.map(group => group.rows.map(row => [row.action, row.page])), [
    [[Action.Open, Page.Languages]], [[Action.Open, Page.JapaneseInput]], [],
    [[Action.Open, Page.Theme], [Action.Open, Page.Size], [Action.Open, Page.Layout], [Action.Open, Page.Toolbar]],
    [[Action.Open, Page.Feedback]], [[Action.Reset, Page.Top], [Action.Open, Page.About]]
  ]);
});

test('P56: the smart input card exposes three independent switches and reset restores them', () => {
  const group = SETTINGS_MENU[2];
  assert.deepEqual(group.smartInput, [Toggle.EmojiSuggestions, Toggle.AutoCapitalize, Toggle.DoubleSpacePeriod]);
  assert.deepEqual(SETTINGS_MENU[1].rows.map(row => row.page), [Page.JapaneseInput]);
  assert.equal(SETTINGS_MENU[3].styleHeading, true);
  const fields = ['emojiSuggestions', 'autoCapitalize', 'doubleSpacePeriod'];
  let snapshot = new KeyboardSettingsSnapshot();
  for (const [index, toggle] of group.smartInput.entries()) {
    const patch = settingsTogglePatch(toggle, false);
    assert.deepEqual(patch, { [fields[index]]: false });
    assert.deepEqual(settingsTogglePatch(toggle, true), { [fields[index]]: true });
    snapshot = applySettingsPatch(snapshot, patch);
  }
  const reset = applySettingsPatch(snapshot, settingsReset().patch);
  for (const field of fields) { assert.equal(reset[field], true); }
});

test('P55: summaries use the enabled language order and saved background state', () => {
  function languages(order) {
    return settingsLanguageSummary(order,
      text.settings_japanese, text.settings_summary_english, text.settings_summary_separator);
  }
  assert.equal(languages('jp_flick,en_flick'), '日本語、English');
  assert.equal(languages('en_qwerty,jp_qwerty'), 'English、日本語');
  assert.equal(languages('en_flick'), 'English');
  assert.equal(languages('jp_qwerty'), '日本語');
  assert.equal(settingsThemeSummary(false, text.settings_theme_standard, text.settings_theme_image), '標準の背景');
  assert.equal(settingsThemeSummary(true, text.settings_theme_standard, text.settings_theme_image), '背景画像あり');
});

test('P55: language switches preserve a shared layout and keep one language enabled', () => {
  const current = applySettingsPatch(new KeyboardSettingsSnapshot(), { layoutOrder: 'en_qwerty' });
  assert.equal(settingsLanguagePatch(current, 'EN', false), undefined);
  assert.equal(settingsLanguagePatch(current, 'EN', true), undefined);
  assert.deepEqual(settingsLanguagePatch(current, 'JP', true), { layoutOrder: 'en_qwerty,jp_qwerty' });
  const both = applySettingsPatch(current, settingsLanguagePatch(current, 'JP', true));
  assert.deepEqual(settingsLanguagePatch(both, 'EN', false), { layoutOrder: 'jp_qwerty' });
  assert.deepEqual(settingsLayoutPatch(both, true), { layoutKind: 'flick' });
  const flick = applySettingsPatch(both, settingsLayoutPatch(both, true));
  assert.deepEqual(settingsLayoutPatch(flick, false), { layoutKind: 'qwerty' });
  assert.equal(settingsLayoutPatch(flick, true), undefined);
  const disabled = applySettingsPatch(flick, settingsTogglePatch(Toggle.Flick, false));
  assert.equal(disabled.layoutOrder, 'en_qwerty,jp_qwerty');
  assert.equal(settingsLayoutPatch(disabled, true), undefined);
});

test('P55: each immediate edit saves only the corresponding field', () => {
  const cases = [
    [settingsTogglePatch(Toggle.Flick, false), { flickEnabled: false }],
    [settingsTogglePatch(Toggle.MultiTap, true), { toggleInputEnabled: true }],
    [settingsTogglePatch(Toggle.KeyPreview, false), { keyPreview: false }],
    [settingsNumberPatch(NumberSetting.FlickDistance, 22), { flickDistance: 22 }],
    [settingsNumberPatch(NumberSetting.LongPress, 550), { longPressMs: 550 }],
    [settingsNumberPatch(NumberSetting.KeyGap, 7.8), { keyGap: 8 }],
    [settingsNumberPatch(NumberSetting.CandidateFont, 16.2), { candidateFontSize: 16 }],
    [settingsNumberPatch(NumberSetting.CandidateRows, 2), { candidateRows: 2 }],
    [settingsNumberPatch(NumberSetting.Haptics, 2), { hapticLevel: 2 }],
    [settingsNumberPatch(NumberSetting.KeySound, 1), { keySoundLevel: 1 }],
    [settingsShortcutPatch(['clipboard', 'settings']), { shortcutOrder: 'clipboard,settings' }],
    [settingsShortcutPatch([]), { shortcutOrder: '' }]
  ];
  for (const [patch, expected] of cases) {
    assert.deepEqual(patch, expected);
    assert.equal(validSettingsPatch(patch), true);
  }
});

test('P55: confirmed reset restores every keyboard field and the standard background', () => {
  const reset = settingsReset();
  assert.deepEqual(reset.background, new BackgroundConfig());
  const customized = applySettingsPatch(new KeyboardSettingsSnapshot(), {
    layoutOrder: 'en_qwerty', flickEnabled: false, toggleInputEnabled: true, flickDistance: 24,
    longPressMs: 500, keyPreview: false, keyGap: 8, candidateFontSize: 20, candidateRows: 2,
    hapticLevel: 2, keySoundLevel: 2, shortcutOrder: '', heightPercent: 130
  });
  customized.revision = 42;
  const defaults = new KeyboardSettingsSnapshot();
  defaults.revision = customized.revision;
  assert.deepEqual(applySettingsPatch(customized, reset.patch), { ...defaults });
  assert.equal(Object.keys(reset.patch).length, Object.keys(defaults).length - 3);
});

test('P55: successive menu edits persist without waiting for the IME and then sync', async () => {
  const r = await pair();
  await r.app.core.save(settingsTogglePatch(Toggle.MultiTap, true), false);
  await r.app.core.save(settingsNumberPatch(NumberSetting.KeySound, 2), false);
  assert.equal(r.app.state.record.snapshot.toggleInputEnabled, true);
  assert.equal(r.app.state.record.snapshot.keySoundLevel, 2);
  assert.equal(r.app.state.states.get('settings').status, 'pending');
  await r.pump();
  assert.equal(r.ime.state.record.snapshot.toggleInputEnabled, true);
  assert.equal(r.ime.state.record.snapshot.keySoundLevel, 2);
  assert.equal(r.app.state.states.get('settings').status, 'applied');
});
