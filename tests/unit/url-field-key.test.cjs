const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { KeyboardSettingsRecord, applySettingsPatch, decodeSettingsRecord, mergeSettingsPatch, validSettingsPatch } =
  require('../../entry/src/main/ets/common/KeyboardSettingsModel.ets');
const { URL_FIELD_KEY_OPTIONS } = require('../../entry/src/main/ets/common/UrlFieldKey.ets');
const { settingsReset } = require('../../entry/src/main/ets/common/SettingsMenuModel.ets');
const { saveSettingsRecord } = require('../../entry/src/main/ets/common/SettingsPersistence.ets');
const { committedSettingsRecord, effectiveSettings, queuedSettingsRecord } =
  require('../../entry/src/main/ets/common/SettingsRecordPolicy.ets');
const { isUrlInputPattern, urlFieldKeyText } = require('../../entry/src/main/ets/model/KeyboardKeyLabels.ets');
const { pair } = require('../support/settings-sync-rig.cjs');

test('P60: missing and invalid saved URL keys fall back without losing other settings', () => {
  const record = new KeyboardSettingsRecord();
  assert.equal(record.snapshot.urlFieldKey, 'www.');
  record.snapshot.keyGap = 8;
  for (const value of [undefined, null, '', '.net', 1, false, ['hide']]) {
    record.snapshot.urlFieldKey = value;
    const loaded = decodeSettingsRecord(JSON.stringify(record));
    assert.equal(loaded.snapshot.urlFieldKey, 'www.');
    assert.equal(loaded.snapshot.keyGap, 8);
    if (value !== undefined) {
      assert.equal(validSettingsPatch({ urlFieldKey: value }), false);
      assert.throws(() => applySettingsPatch(loaded.snapshot, { urlFieldKey: value }), /Invalid keyboard settings/);
    }
  }

  const queued = queuedSettingsRecord(new KeyboardSettingsRecord(), { urlFieldKey: 'hide', keyGap: 9 }).record;
  queued.pending[0].patch.urlFieldKey = '.net';
  const loaded = decodeSettingsRecord(JSON.stringify(queued));
  assert.deepEqual(loaded.pending[0].patch, { urlFieldKey: 'www.', keyGap: 9 });
  assert.equal(effectiveSettings(loaded).keyGap, 9);
});

test('P60: all URL key choices survive saving and reloading', () => {
  assert.deepEqual(URL_FIELD_KEY_OPTIONS, ['www.', '.com', '/', 'hide']);
  let record = new KeyboardSettingsRecord();
  for (const value of ['.com', '/', 'hide', 'www.']) {
    const patch = { urlFieldKey: value };
    assert.equal(validSettingsPatch(patch), true);
    assert.deepEqual(mergeSettingsPatch({ keyGap: 8, urlFieldKey: 'www.' }, patch), { keyGap: 8, urlFieldKey: value });
    const next = committedSettingsRecord(record, patch, 100);
    let pending;
    let durable;
    saveSettingsRecord(next, {
      maximumLength: 10000,
      write: payload => { pending = payload; },
      flush: () => { durable = pending; }
    });
    assert.equal(JSON.parse(durable).snapshot.urlFieldKey, value);
    record = decodeSettingsRecord(durable);
    assert.equal(record.snapshot.urlFieldKey, value);
  }
});

test('P60: the URL pattern selects the configured key and all other patterns omit it', () => {
  assert.equal(isUrlInputPattern(6), true);
  for (const [value, expected] of [['www.', 'www.'], ['.com', '.com'], ['/', '/'], ['hide', ''],
    [undefined, 'www.'], ['.net', 'www.']]) {
    assert.equal(urlFieldKeyText(6, value), expected);
    for (const pattern of [0, 1, 2, 3, 4, 5, 7, 8, 9, 99]) {
      assert.equal(isUrlInputPattern(pattern), false);
      assert.equal(urlFieldKeyText(pattern, value), '');
    }
  }
});

test('P60: immediate URL key edits and reset sync to the IME', async () => {
  const r = await pair();
  for (const value of ['.com', '/', 'hide']) {
    await r.app.core.save({ urlFieldKey: value }, false);
    assert.equal(r.app.state.record.snapshot.urlFieldKey, value);
    await r.pump();
    assert.equal(r.ime.state.applied.at(-1).snapshot.urlFieldKey, value);
  }
  await r.app.core.save(settingsReset().patch, false);
  await r.pump();
  assert.equal(r.app.state.record.snapshot.urlFieldKey, 'www.');
  assert.equal(r.ime.state.applied.at(-1).snapshot.urlFieldKey, 'www.');
});

test('P60: the layout menu shows the localized URL key radio choices', () => {
  const main = join(__dirname, '../../entry/src/main');
  const component = readFileSync(join(main, 'ets/components/KeyboardSettings.ets'), 'utf8');
  assert.match(component, /this\.page === SettingsPageId\.Layout\) \{\s+this\.layoutOptions\(\)/);
  assert.match(component, /layoutOptions\(\) \{[^]*?this\.urlFieldKeyOptions\(\)/);
  assert.match(component, /urlFieldKeyOptions\(\) \{[^]*?ForEach\(URL_FIELD_KEY_OPTIONS,[^]*?Radio\(/);
  assert.match(component, /urlFieldKeyOptions\(\) \{[^]*?settings_url_field_key_help/);
  for (const [locale, label, hide] of [['base', 'URL 入力欄のキー', '表示しない'],
    ['en_US', 'Key in URL fields', 'Hide'], ['zh_CN', '网址输入框中的按键', '隐藏']]) {
    const { string } = JSON.parse(readFileSync(join(main, 'resources', locale, 'element/string.json'), 'utf8'));
    const strings = new Map(string.map(item => [item.name, item.value]));
    assert.equal(strings.get('settings_url_field_key'), label);
    assert.equal(strings.get('settings_url_field_key_hide'), hide);
    assert.ok(strings.get('settings_url_field_key_help'));
  }
});
