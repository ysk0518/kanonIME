import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import { debugLog, debugErrorCode } from './DebugLog';
import { KeyboardSettingsSnapshot, KeyboardSettingsPatch, KeyboardSettingsRecord, KeyboardSettingsChange,
  SettingsPeer, applySettingsPatch, mergeSettingsPatch, copySettings, validSettingsRecord } from './KeyboardSettingsModel';
import { DEFAULT_LAYOUT_ORDER, DEFAULT_FLICK_DISTANCE, DEFAULT_LONG_PRESS_MS, DEFAULT_HAPTIC_LEVEL,
  DEFAULT_KEY_PREVIEW_ENABLED, DEFAULT_FLICK_ENABLED, languageLayouts } from './KeyboardConfigValues';
import { DEFAULT_SHORTCUT_ORDER, shortcutOrder } from './ShortcutConfig';
import { DEFAULT_KEYBOARD_HEIGHT_PERCENT, keyboardHeightPercent } from './KeyboardLayout';

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
      const loaded: KeyboardSettingsRecord = JSON.parse(raw) as KeyboardSettingsRecord;
      if (!validSettingsRecord(loaded)) { throw new Error('Invalid settings record'); }
      record = loaded;
      record.snapshot = copySettings(loaded.snapshot);
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

function bounded(value: preferences.ValueType, minimum: number, maximum: number, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? Math.max(minimum, Math.min(maximum, value)) : fallback;
}

function migrateSettings(primary: preferences.Preferences, legacy: preferences.Preferences): KeyboardSettingsRecord {
  const next = new KeyboardSettingsRecord();
  const snapshot = new KeyboardSettingsSnapshot();
  const order: preferences.ValueType = legacyValue(primary, legacy, 'layout_order',
    AppStorage.get<string>('kanonLayoutOrder') ?? DEFAULT_LAYOUT_ORDER);
  const flick: preferences.ValueType = legacyValue(primary, legacy, 'flick_enabled', DEFAULT_FLICK_ENABLED);
  snapshot.flickEnabled = typeof flick === 'boolean' ? flick : DEFAULT_FLICK_ENABLED;
  snapshot.layoutOrder = languageLayouts(typeof order === 'string' ? order : DEFAULT_LAYOUT_ORDER).join(',');
  snapshot.flickDistance = bounded(AppStorage.get<number>('kanonFlickDistance') ?? DEFAULT_FLICK_DISTANCE, 12, 30, DEFAULT_FLICK_DISTANCE);
  snapshot.longPressMs = bounded(AppStorage.get<number>('kanonLongPressMs') ?? DEFAULT_LONG_PRESS_MS, 250, 650, DEFAULT_LONG_PRESS_MS);
  snapshot.keyPreview = AppStorage.get<boolean>('kanonFlickPreviewEnabled') ?? DEFAULT_KEY_PREVIEW_ENABLED;
  const haptic: preferences.ValueType = legacyValue(primary, legacy, 'haptic_level', DEFAULT_HAPTIC_LEVEL);
  snapshot.hapticLevel = haptic === 0 || haptic === 2 ? haptic : DEFAULT_HAPTIC_LEVEL;
  snapshot.shortcutOrder = shortcutOrder(AppStorage.get<string>('kanonShortcutOrder') ?? DEFAULT_SHORTCUT_ORDER).join(',');
  const height: preferences.ValueType = legacyValue(primary, legacy, 'height_percent', DEFAULT_KEYBOARD_HEIGHT_PERCENT);
  snapshot.heightPercent = keyboardHeightPercent(typeof height === 'number' ? height : DEFAULT_KEYBOARD_HEIGHT_PERCENT);
  next.snapshot = applySettingsPatch(snapshot, {});
  next.legacyHeightPresent = legacyHas(primary, legacy, 'height_percent');
  next.legacyLayoutPresent = typeof order === 'string';
  next.heightChosen = next.legacyHeightPresent;
  debugLog.record('config', 'legacy settings migrated');
  return next;
}

function copyRecord(): KeyboardSettingsRecord {
  return JSON.parse(JSON.stringify(record)) as KeyboardSettingsRecord;
}

export function readSettings(): KeyboardSettingsSnapshot {
  let snapshot: KeyboardSettingsSnapshot = copySettings(record.snapshot);
  for (const change of record.pending) { snapshot = applySettingsPatch(snapshot, change.patch); }
  return snapshot;
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
    const payload: string = JSON.stringify(next);
    if (payload.length > preferences.MAX_VALUE_LENGTH) { throw new Error('Settings storage limit'); }
    store.putSync(RECORD_KEY, payload);
    store.flushSync();
  } catch (error) {
    debugLog.record('config', `repository save failed code=${debugErrorCode(error)}`);
    throw new Error('Keyboard settings save failed');
  }
  record = next;
  publishSettings(previous);
}

function advance(next: KeyboardSettingsRecord): void {
  next.snapshot.revision = Math.max(Date.now(), next.snapshot.revision + 1);
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
  const next: KeyboardSettingsRecord = copyRecord();
  next.snapshot = applySettingsPatch(next.snapshot, patch);
  if (patch.heightPercent !== undefined) { next.heightChosen = true; }
  if (patch.layoutOrder !== undefined) { next.languagesChosen = true; }
  advance(next);
  persist(next);
  return copySettings(next.snapshot);
}

export function queueSettings(patch: KeyboardSettingsPatch): KeyboardSettingsChange {
  // Validate before putting a change into the durable outbox.
  applySettingsPatch(readSettings(), patch);
  const next: KeyboardSettingsRecord = copyRecord();
  // Only the head is sent. The unsent tail can safely combine later edits without
  // changing its sequence or modifying a request the owner may already have applied.
  if (next.pending.length > 1) {
    const tail: KeyboardSettingsChange = next.pending[1];
    tail.patch = mergeSettingsPatch(tail.patch, patch);
    persist(next);
    return tail;
  }
  const change = new KeyboardSettingsChange();
  change.actor = next.actor;
  change.sequence = next.nextSequence++;
  change.patch = JSON.parse(JSON.stringify(patch)) as KeyboardSettingsPatch;
  next.pending.push(change);
  persist(next);
  return change;
}

export function nextSettingsChange(): KeyboardSettingsChange | undefined {
  return record.pending.length === 0 ? undefined : JSON.parse(JSON.stringify(record.pending[0])) as KeyboardSettingsChange;
}

export function settingsActor(): string { return record.actor; }
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
  const existing: SettingsPeer | undefined = record.peers.find((peer: SettingsPeer) => peer.actor === change.actor);
  if (existing && change.sequence <= existing.sequence) { return existing; }
  if (existing && change.sequence !== existing.sequence + 1) { return existing; }
  const next: KeyboardSettingsRecord = copyRecord();
  next.snapshot = applySettingsPatch(next.snapshot, change.patch);
  if (change.patch.heightPercent !== undefined) { next.heightChosen = true; }
  if (change.patch.layoutOrder !== undefined) { next.languagesChosen = true; }
  const peer = new SettingsPeer();
  peer.actor = change.actor;
  peer.sequence = change.sequence;
  next.peers = next.peers.filter((entry: SettingsPeer) => entry.actor !== change.actor);
  next.peers.push(peer);
  if (next.peers.length > 32) { next.peers.shift(); }
  advance(next);
  persist(next);
  return peer;
}

export function receiveSettings(snapshot: KeyboardSettingsSnapshot, actor: string, sequence: number): void {
  const next: KeyboardSettingsRecord = copyRecord();
  if (snapshot.revision >= next.snapshot.revision) { next.snapshot = copySettings(snapshot); }
  if (actor === next.actor && sequence >= 0 && sequence < next.nextSequence) {
    next.pending = next.pending.filter((change: KeyboardSettingsChange) => change.sequence > sequence);
  }
  next.bootstrapComplete = true;
  persist(next);
}

export function settingsDiagnostics(): string {
  const snapshot: KeyboardSettingsSnapshot = readSettings();
  return `store=${store !== undefined} openError=${openError} revision=${record.snapshot.revision} pending=${record.pending.length} flick=${snapshot.flickEnabled} distance=${snapshot.flickDistance} longPress=${snapshot.longPressMs} preview=${snapshot.keyPreview} keyGap=${snapshot.keyGap} haptic=${snapshot.hapticLevel} height=${snapshot.heightPercent} shortcuts=${shortcutOrder(snapshot.shortcutOrder).length}`;
}
