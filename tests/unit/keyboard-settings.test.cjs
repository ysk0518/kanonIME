const test = require('node:test');
const assert = require('node:assert/strict');
const { KeyboardSettingsSnapshot, KeyboardSettingsRecord, validSettingsPatch, validSettingsSnapshot,
  validSettingsRecord, copySettings, applySettingsPatch, mergeSettingsPatch, decodeSettingsRecord
} = require('../../entry/src/main/ets/common/KeyboardSettingsModel.ets');
const { LegacyKeyboardSettings, migrateLegacySettings } = require('../../entry/src/main/ets/common/KeyboardSettingsMigration.ets');
const { shortcutOrder } = require('../../entry/src/main/ets/common/ShortcutConfigValues.ets');

function record() {
  const result = new KeyboardSettingsRecord(); result.actor = '1-2'; return result;
}

test('P10: default settings satisfy the product validation rules', () => {
  const value = new KeyboardSettingsSnapshot();
  assert.equal(validSettingsSnapshot(value), true);
  assert.equal(value.layoutOrder, 'jp_flick,en_flick');
  assert.equal(value.keyGap, 6); assert.equal(value.heightPercent, 100);
  assert.equal(value.shortcutOrder, 'settings,clipboard');
});

test('P10: numeric patch limits accept boundaries and reject outside or nonfinite values', () => {
  for (const [key, low, high] of [['flickDistance', 12, 30], ['longPressMs', 250, 650],
    ['keyGap', 0, 10], ['heightPercent', 80, 150]]) {
    for (const value of [low, high]) { assert.equal(validSettingsPatch({ [key]: value }), true); }
    for (const value of [low - 1, high + 1, NaN, Infinity, '100']) {
      assert.equal(validSettingsPatch({ [key]: value }), false);
    }
  }
});

test('P10: boolean and haptic settings reject inappropriate types and levels', () => {
  assert.equal(validSettingsPatch({ flickEnabled: false, keyPreview: false, hapticLevel: 0 }), true);
  for (const patch of [{ flickEnabled: 0 }, { keyPreview: 'false' }, { hapticLevel: 3 }, { hapticLevel: 1.5 }]) {
    assert.equal(validSettingsPatch(patch), false);
  }
});

test('P10: layout patch accepts one entry per language and rejects duplicates or unknown entries', () => {
  assert.equal(validSettingsPatch({ layoutOrder: 'en_qwerty,jp_flick' }), true);
  for (const layoutOrder of ['', 'jp_flick,jp_qwerty', 'jp_flick,jp_flick', 'unknown',
    'jp_flick,en_flick,jp_qwerty']) {
    assert.equal(validSettingsPatch({ layoutOrder }), false);
  }
});

test('P10: modifying one setting preserves unedited values and original snapshot', () => {
  const original = applySettingsPatch(new KeyboardSettingsSnapshot(), {
    layoutOrder: 'en_qwerty,jp_qwerty', flickDistance: 25, longPressMs: 550, hapticLevel: 2
  });
  const before = JSON.stringify(original);
  const updated = applySettingsPatch(original, { heightPercent: 120 });
  assert.equal(updated.heightPercent, 120);
  assert.equal(updated.layoutOrder, 'en_qwerty,jp_qwerty');
  assert.equal(updated.flickDistance, 25); assert.equal(updated.longPressMs, 550);
  assert.equal(updated.hapticLevel, 2);
  assert.equal(JSON.stringify(original), before);
});

test('P10: key gap and saved height are rounded after patch validation', () => {
  const result = applySettingsPatch(new KeyboardSettingsSnapshot(), { keyGap: 4.6, heightPercent: 119.6 });
  assert.equal(result.keyGap, 5); assert.equal(result.heightPercent, 120);
});

test('P10: disabling flick selects QWERTY without changing enabled languages or order', () => {
  const original = applySettingsPatch(new KeyboardSettingsSnapshot(), { layoutOrder: 'en_flick,jp_flick' });
  const result = applySettingsPatch(original, { flickEnabled: false });
  assert.equal(result.layoutOrder, 'en_qwerty,jp_qwerty');
  assert.equal(validSettingsSnapshot(result), true);
});

test('P10: explicit layout kind changes both enabled language layouts consistently', () => {
  const result = applySettingsPatch(new KeyboardSettingsSnapshot(), { layoutKind: 'qwerty' });
  assert.equal(result.layoutOrder, 'jp_qwerty,en_qwerty');
  assert.equal(result.flickEnabled, true);
});

test('P10: invalid patches throw before changing source settings', () => {
  const original = new KeyboardSettingsSnapshot(); const before = JSON.stringify(original);
  assert.throws(() => applySettingsPatch(original, { keyGap: 99 }), /Invalid keyboard settings/);
  assert.equal(JSON.stringify(original), before);
});

test('P10: shortcuts preserve explicit empty order and normalize duplicates', () => {
  assert.deepEqual(shortcutOrder(''), []);
  assert.deepEqual(shortcutOrder('edit,settings,edit'), ['edit', 'settings']);
  assert.equal(applySettingsPatch(new KeyboardSettingsSnapshot(), { shortcutOrder: '' }).shortcutOrder, '');
  assert.equal(applySettingsPatch(new KeyboardSettingsSnapshot(), {
    shortcutOrder: 'edit,settings,edit'
  }).shortcutOrder, 'edit,settings');
  assert.equal(validSettingsPatch({ shortcutOrder: 'unknown' }), false);
});

test('P10: merging patches keeps earlier edits and uses latest explicit values including zero', () => {
  const base = { keyGap: 8, hapticLevel: 2, heightPercent: 120 };
  assert.deepEqual(mergeSettingsPatch(base, { keyGap: 0, keyPreview: false }),
    { keyGap: 0, hapticLevel: 2, heightPercent: 120, keyPreview: false });
  assert.deepEqual(base, { keyGap: 8, hapticLevel: 2, heightPercent: 120 });
});

test('P10: explicit language order clears older pending layout kind', () => {
  const merged = mergeSettingsPatch({ layoutKind: 'qwerty', keyGap: 8 }, { layoutOrder: 'en_flick' });
  assert.equal(merged.layoutKind, undefined);
  assert.equal(merged.layoutOrder, 'en_flick'); assert.equal(merged.keyGap, 8);
});

test('P10: schema-1 snapshot without keyGap fills six and preserves all other fields', () => {
  const original = applySettingsPatch(new KeyboardSettingsSnapshot(), { layoutOrder: 'en_qwerty', heightPercent: 130 });
  delete original.keyGap;
  assert.equal(validSettingsSnapshot(original), true);
  const normalized = copySettings(original);
  assert.equal(normalized.keyGap, 6);
  assert.equal(normalized.layoutOrder, 'en_qwerty'); assert.equal(normalized.heightPercent, 130);
  assert.equal(original.keyGap, undefined);
});

test('P10: settings copies preserve unknown metadata without sharing nested references', () => {
  const original = new KeyboardSettingsSnapshot(); original.futureMetadata = { enabled: true };
  const copied = copySettings(original); copied.futureMetadata.enabled = false;
  assert.equal(original.futureMetadata.enabled, true);
});

test('P10: snapshot validation rejects schema, revision and flick-layout contradictions', () => {
  for (const patch of [{ schema: 2 }, { revision: -1 }, { revision: 1.5 },
    { revision: Number.MAX_SAFE_INTEGER + 1 }, { flickEnabled: false }, { keyGap: 99 }]) {
    assert.equal(validSettingsSnapshot({ ...new KeyboardSettingsSnapshot(), ...patch }), false);
  }
});

test('P10: record validation checks pending ownership, sequence order and bounded queue', () => {
  const value = record(); value.nextSequence = 3;
  value.pending = [{ actor: '1-2', sequence: 1, patch: { keyGap: 8 } },
    { actor: '1-2', sequence: 2, patch: { heightPercent: 120 } }];
  assert.equal(validSettingsRecord(value), true);
  for (const change of [copy => { copy.pending[0].actor = '2-3'; },
    copy => { copy.pending[1].sequence = 1; }, copy => { copy.pending[1].sequence = 3; },
    copy => { copy.pending.push({ actor: '1-2', sequence: 2, patch: {} }); }]) {
    const copy = JSON.parse(JSON.stringify(value)); change(copy);
    assert.equal(validSettingsRecord(copy), false);
  }
});

test('P10: record validation rejects invalid actor, peer and migration flag', () => {
  for (const patch of [{ actor: 'invalid' }, { nextSequence: 0 }, { bootstrapComplete: 'true' },
    { peers: [{ actor: '1-2', sequence: -1 }] }]) {
    assert.equal(validSettingsRecord({ ...record(), ...patch }), false);
  }
});

test('P10: stored legacy record normalization preserves pending edits and chosen flags', () => {
  const value = record(); delete value.snapshot.keyGap;
  value.snapshot.layoutOrder = 'en_qwerty'; value.snapshot.heightPercent = 130;
  value.nextSequence = 2; value.pending = [{ actor: '1-2', sequence: 1, patch: { keyPreview: false } }];
  value.heightChosen = true; value.bootstrapComplete = true;
  const loaded = decodeSettingsRecord(JSON.stringify(value));
  assert.equal(loaded.snapshot.keyGap, 6);
  assert.equal(loaded.snapshot.layoutOrder, 'en_qwerty'); assert.equal(loaded.snapshot.heightPercent, 130);
  assert.deepEqual(loaded.pending, value.pending);
  assert.equal(loaded.heightChosen, true); assert.equal(loaded.bootstrapComplete, true);
});

test('P10: malformed or unsupported stored records are rejected rather than reset to defaults', () => {
  for (const payload of ['{', 'null', '{}', JSON.stringify({ ...record(), schema: 2 })]) {
    assert.throws(() => decodeSettingsRecord(payload));
  }
});

test('P10: legacy migration keeps selected language, layout, height and shortcut order', () => {
  const legacy = new LegacyKeyboardSettings();
  legacy.layoutOrder = 'en_flick,jp_flick'; legacy.flickEnabled = false;
  legacy.heightPercent = 128; legacy.heightPresent = true; legacy.shortcutOrder = 'edit,settings';
  const migrated = migrateLegacySettings(legacy);
  assert.equal(validSettingsRecord(migrated), true);
  assert.equal(migrated.snapshot.layoutOrder, 'en_qwerty,jp_qwerty');
  assert.equal(migrated.snapshot.heightPercent, 128);
  assert.equal(migrated.snapshot.shortcutOrder, 'edit,settings');
  assert.equal(migrated.snapshot.keyGap, 6);
  assert.equal(migrated.heightChosen, true); assert.equal(migrated.bootstrapComplete, false);
});

test('P10: legacy migration bounds numeric values and supplies defaults for nonfinite numbers', () => {
  const legacy = new LegacyKeyboardSettings(); legacy.flickDistance = 99; legacy.longPressMs = 10;
  legacy.heightPercent = 151; legacy.hapticLevel = 3;
  const bounded = migrateLegacySettings(legacy).snapshot;
  assert.equal(bounded.flickDistance, 30); assert.equal(bounded.longPressMs, 250);
  assert.equal(bounded.heightPercent, 150); assert.equal(bounded.hapticLevel, 1);
  legacy.flickDistance = NaN; legacy.longPressMs = Infinity; legacy.heightPercent = NaN;
  const fallback = migrateLegacySettings(legacy).snapshot;
  assert.equal(fallback.flickDistance, 18); assert.equal(fallback.longPressMs, 400);
  assert.equal(fallback.heightPercent, 100);
});

test('P10: legacy migration does not mutate its source or invent a chosen height', () => {
  const legacy = new LegacyKeyboardSettings(); legacy.layoutPresent = false;
  const before = JSON.stringify(legacy); const migrated = migrateLegacySettings(legacy);
  assert.equal(JSON.stringify(legacy), before);
  assert.equal(migrated.legacyHeightPresent, false); assert.equal(migrated.heightChosen, false);
  assert.equal(migrated.legacyLayoutPresent, false); assert.equal(migrated.languagesChosen, false);
});
