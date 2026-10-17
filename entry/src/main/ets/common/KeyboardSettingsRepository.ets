import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import { debugLog, debugErrorCode } from './DebugLog';
import { KeyboardSettingsSnapshot, KeyboardSettingsPatch, KeyboardSettingsRecord, KeyboardSettingsChange,
  SettingsPeer, applySettingsPatch, copySettings, validSettingsRecord, decodeSettingsRecord } from './KeyboardSettingsModel';
import { LegacyKeyboardSettings, migrateLegacySettings } from './KeyboardSettingsMigration';
import { SettingsStoragePort, saveSettingsRecord } from './SettingsPersistence';
import { copySettingsRecord, effectiveSettings, advanceSettingsRecord, committedSettingsRecord,
  queuedSettingsRecord, QueuedSettingsRecord, receivedSettingsRecord, acceptedSettingsRecord } from './SettingsRecordPolicy';
import { DEFAULT_LAYOUT_ORDER, DEFAULT_FLICK_DISTANCE, DEFAULT_LONG_PRESS_MS, DEFAULT_HAPTIC_LEVEL,
  DEFAULT_KEY_PREVIEW_ENABLED, DEFAULT_FLICK_ENABLED } from './KeyboardConfigValues';
import { DEFAULT_SHORTCUT_ORDER, shortcutOrder } from './ShortcutConfigValues';
import { DEFAULT_KEYBOARD_HEIGHT_PERCENT } from './KeyboardLayout';

const CONFIG_FILE: string = 'kanon_keyboard_config';
const RECORD_KEY: string = 'settings_record_v1';
let store: preferences.Preferences | undefined;
let record: KeyboardSettingsRecord = new KeyboardSettingsRecord();
let openError: string = 'not-open';

export function openSettingsRepository(context: common.Context): void {
  try {
    store = preferences.getPreferencesSync(context.getApplicationContext(),
      { name: CONFIG_FILE, storageType: preferences.StorageType.GSKV });
    const raw: preferences.ValueType = store.getSync(RECORD_KEY, '');
    if (typeof raw !== 'string') { throw new Error('Invalid settings storage'); }
    if (raw.length > 0) {
      record = decodeSettingsRecord(raw);
      publishSettings(undefined);
    } else {
      const legacy: preferences.Preferences = preferences.getPreferencesSync(context,
        { name: CONFIG_FILE, storageType: preferences.StorageType.GSKV });
      persist(migrateSettings(store, legacy));
    }
    openError = 'none';
  } catch (error) {
    store = undefined;
    openError = debugErrorCode(error);
    debugLog.record('config', `repository open failed code=${openError}`);
  }
}

function legacyValue(primary: preferences.Preferences, legacy: preferences.Preferences,
  key: string, fallback: preferences.ValueType): preferences.ValueType {
  try { return primary.hasSync(key) ? primary.getSync(key, fallback) : legacy.getSync(key, fallback); }
  catch (error) { throw new Error('Legacy settings read failed'); }
}

function legacyHas(primary: preferences.Preferences, legacy: preferences.Preferences, key: string): boolean {
  try { return primary.hasSync(key) || legacy.hasSync(key); }
  catch (error) { throw new Error('Legacy settings read failed'); }
}

function migrateSettings(primary: preferences.Preferences, legacy: preferences.Preferences): KeyboardSettingsRecord {
  const values: LegacyKeyboardSettings = new LegacyKeyboardSettings();
  const order: preferences.ValueType = legacyValue(primary, legacy, 'layout_order',
    AppStorage.get<string>('kanonLayoutOrder') ?? DEFAULT_LAYOUT_ORDER);
  const flick: preferences.ValueType = legacyValue(primary, legacy, 'flick_enabled', DEFAULT_FLICK_ENABLED);
  values.flickEnabled = typeof flick === 'boolean' ? flick : DEFAULT_FLICK_ENABLED;
  values.layoutOrder = typeof order === 'string' ? order : DEFAULT_LAYOUT_ORDER;
  values.flickDistance = AppStorage.get<number>('kanonFlickDistance') ?? DEFAULT_FLICK_DISTANCE;
  values.longPressMs = AppStorage.get<number>('kanonLongPressMs') ?? DEFAULT_LONG_PRESS_MS;
  values.keyPreview = AppStorage.get<boolean>('kanonFlickPreviewEnabled') ?? DEFAULT_KEY_PREVIEW_ENABLED;
  const haptic: preferences.ValueType = legacyValue(primary, legacy, 'haptic_level', DEFAULT_HAPTIC_LEVEL);
  values.hapticLevel = typeof haptic === 'number' ? haptic : DEFAULT_HAPTIC_LEVEL;
  values.shortcutOrder = AppStorage.get<string>('kanonShortcutOrder') ?? DEFAULT_SHORTCUT_ORDER;
  const height: preferences.ValueType = legacyValue(primary, legacy, 'height_percent', DEFAULT_KEYBOARD_HEIGHT_PERCENT);
  values.heightPercent = typeof height === 'number' ? height : DEFAULT_KEYBOARD_HEIGHT_PERCENT;
  values.heightPresent = legacyHas(primary, legacy, 'height_percent');
  values.layoutPresent = typeof order === 'string';
  const next: KeyboardSettingsRecord = migrateLegacySettings(values);
  debugLog.record('config', 'legacy settings migrated');
  return next;
}

function copyRecord(): KeyboardSettingsRecord {
  return copySettingsRecord(record);
}

export function readSettings(): KeyboardSettingsSnapshot {
  return effectiveSettings(record);
}

function setValue(key: string, value: string | number | boolean): void {
  if (AppStorage.get<string | number | boolean>(key) !== value) { AppStorage.setOrCreate(key, value); }
}

function publishSettings(previous: KeyboardSettingsSnapshot | undefined): void {
  const snapshot: KeyboardSettingsSnapshot = readSettings();
  setValue('kanonFlickEnabled', snapshot.flickEnabled);
  setValue('kanonFlickDistance', snapshot.flickDistance);
  setValue('kanonLongPressMs', snapshot.longPressMs);
  setValue('kanonFlickPreviewEnabled', snapshot.keyPreview);
  setValue('kanonKeyGap', snapshot.keyGap);
  setValue('kanonCandidateFontSize', snapshot.candidateFontSize);
  setValue('kanonCandidateRows', snapshot.candidateRows);
  setValue('kanonHapticLevel', snapshot.hapticLevel);
  setValue('kanonShortcutOrder', snapshot.shortcutOrder);
  if (!previous || previous.heightPercent !== snapshot.heightPercent || AppStorage.get<number>('kanonKeyboardHeightPercent') === undefined) {
    setValue('kanonKeyboardHeightPercent', snapshot.heightPercent);
  }
  setValue('kanonLayoutOrder', snapshot.layoutOrder);
  setValue('kanonSettingsRevision', snapshot.revision);
  setValue('kanonSettingsPendingCount', record.pending.length);
  setValue('kanonSettingsGeneration', (AppStorage.get<number>('kanonSettingsGeneration') ?? 0) + 1);
}

function persist(next: KeyboardSettingsRecord): void {
  if (!store) { throw new Error('Keyboard settings storage unavailable'); }
  if (!validSettingsRecord(next)) { throw new Error('Invalid settings record'); }
  const previous: KeyboardSettingsSnapshot = readSettings();
  try {
    const storage: preferences.Preferences = store;
    const port: SettingsStoragePort = {
      maximumLength: preferences.MAX_VALUE_LENGTH,
      write: (payload: string): void => { storage.putSync(RECORD_KEY, payload); },
      flush: (): void => { storage.flushSync(); }
    };
    saveSettingsRecord(next, port);
  } catch (error) {
    debugLog.record('config', `repository save failed code=${debugErrorCode(error)}`);
    throw new Error('Keyboard settings save failed');
  }
  record = next;
  publishSettings(previous);
}

function advance(next: KeyboardSettingsRecord): void {
  advanceSettingsRecord(next, Date.now());
}

export function ensureSettingsRevision(): KeyboardSettingsSnapshot {
  if (record.snapshot.revision === 0) {
    const next: KeyboardSettingsRecord = copyRecord();
    advance(next);
    persist(next);
  }
  return copySettings(record.snapshot);
}

export function commitSettings(patch: KeyboardSettingsPatch): KeyboardSettingsSnapshot {
  const next: KeyboardSettingsRecord = committedSettingsRecord(record, patch, Date.now());
  persist(next);
  return copySettings(next.snapshot);
}

export function queueSettings(patch: KeyboardSettingsPatch): KeyboardSettingsChange {
  const queued: QueuedSettingsRecord = queuedSettingsRecord(record, patch);
  persist(queued.record);
  return queued.change;
}

export function nextSettingsChange(): KeyboardSettingsChange | undefined {
  return record.pending.length === 0 ? undefined : JSON.parse(JSON.stringify(record.pending[0])) as KeyboardSettingsChange;
}

export function settingsActor(): string { return record.actor; }
export function settingsIssuedSequence(): number { return record.nextSequence - 1; }
export function settingsRepositoryReady(): boolean { return store !== undefined; }
export function publishCurrentSettings(): void { publishSettings(undefined); }
export function settingsPendingCount(): number { return record.pending.length; }
export function settingsLastPendingSequence(): number {
  return record.pending.length === 0 ? 0 : record.pending[record.pending.length - 1].sequence;
}
export function settingsBaseRevision(): number { return record.snapshot.revision; }
export function legacyHeightPresent(): boolean { return record.legacyHeightPresent; }
export function legacyLayoutPresent(): boolean { return record.legacyLayoutPresent; }

/** Preserve IME-owned legacy height/language choices once, before the first full snapshot. */
export function importLegacySettings(snapshot: KeyboardSettingsSnapshot, heightPresent: boolean,
  layoutPresent: boolean): void {
  if (record.bootstrapComplete) { return; }
  const next: KeyboardSettingsRecord = copyRecord();
  const patch: KeyboardSettingsPatch = {};
  if (snapshot.revision === 0) {
    if (!next.heightChosen && heightPresent) { patch.heightPercent = snapshot.heightPercent; }
    if (!next.languagesChosen && layoutPresent) {
      const kind: string = next.snapshot.layoutOrder.split(',')[0].endsWith('_flick') ? 'flick' : 'qwerty';
      patch.layoutOrder = snapshot.layoutOrder.split(',').map((id: string) => `${id.startsWith('en_') ? 'en' : 'jp'}_${kind}`).join(',');
    }
  }
  next.snapshot = applySettingsPatch(next.snapshot, patch);
  next.bootstrapComplete = true;
  advance(next);
  persist(next);
}

export function acceptSettingsChange(change: KeyboardSettingsChange): SettingsPeer {
  const next: KeyboardSettingsRecord | undefined = acceptedSettingsRecord(record, change, Date.now());
  if (next === undefined) {
    return record.peers.find((peer: SettingsPeer) => peer.actor === change.actor) as SettingsPeer;
  }
  const peer: SettingsPeer = next.peers[next.peers.length - 1];
  persist(next);
  return peer;
}

export function receiveSettings(snapshot: KeyboardSettingsSnapshot, actor: string, sequence: number): void {
  const next: KeyboardSettingsRecord = receivedSettingsRecord(record, snapshot, actor, sequence);
  persist(next);
}

export function settingsDiagnostics(): string {
  const snapshot: KeyboardSettingsSnapshot = readSettings();
  return `store=${store !== undefined} openError=${openError} revision=${record.snapshot.revision} pending=${record.pending.length} flick=${snapshot.flickEnabled} distance=${snapshot.flickDistance} longPress=${snapshot.longPressMs} preview=${snapshot.keyPreview} keyGap=${snapshot.keyGap} haptic=${snapshot.hapticLevel} height=${snapshot.heightPercent} shortcuts=${shortcutOrder(snapshot.shortcutOrder).length}`;
}
