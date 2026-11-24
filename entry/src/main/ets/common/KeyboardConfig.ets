import {
  KANON_FLICK_ENABLED, KANON_HAPTIC_LEVEL, KANON_KEYBOARD_HEIGHT_PERCENT, KANON_LAST_LAYOUT,
  KANON_LAYOUT, KANON_LAYOUT_ORDER, KANON_MODE
} from './AppStorageKeys';
import common from '@ohos.app.ability.common';
import { initializeShortcutConfig } from './ShortcutConfig';
import { openSettingsRepository, readSettings, settingsDiagnostics,
  settingsRepositoryReady, publishCurrentSettings } from './KeyboardSettingsRepository';
import { DEFAULT_LAYOUT_ORDER, DEFAULT_FLICK_DISTANCE, DEFAULT_LONG_PRESS_MS, DEFAULT_KEY_PREVIEW_ENABLED,
  languageLayouts, layoutLanguage } from './KeyboardConfigValues';
export { DEFAULT_LAYOUT_ORDER, DEFAULT_FLICK_DISTANCE, DEFAULT_LONG_PRESS_MS, DEFAULT_KEY_PREVIEW_ENABLED,
  DEFAULT_HAPTIC_LEVEL, DEFAULT_FLICK_ENABLED, KEYBOARD_LAYOUTS,
  layoutOrder, languageLayouts, layoutLanguage, layoutName, nextLanguageLayout } from './KeyboardConfigValues';

// Compatibility reads use the effective snapshot; writes use KeyboardSettingsSync.
export function openKeyboardPreferences(context: common.Context): void { openSettingsRepository(context); }
export function keyboardConfigDiagnostics(): string { return settingsDiagnostics(); }
export function readSharedLayoutOrder(): string { return readSettings().layoutOrder; }
export function readSharedFlickEnabled(): boolean { return readSettings().flickEnabled; }
export function readSharedHapticLevel(): number { return readSettings().hapticLevel; }
export function readKeyboardHeightPercent(): number { return readSettings().heightPercent; }

export function refreshSharedFlickEnabled(): void {
  const value: boolean = readSharedFlickEnabled();
  if (AppStorage.get<boolean>(KANON_FLICK_ENABLED) !== value) { AppStorage.setOrCreate(KANON_FLICK_ENABLED, value); }
}

export function refreshSharedLayoutOrder(): string {
  const order: string = readSharedLayoutOrder();
  refreshSharedFlickEnabled();
  if (AppStorage.get<string>(KANON_LAYOUT_ORDER) !== order) { AppStorage.setOrCreate(KANON_LAYOUT_ORDER, order); }
  return order;
}

export function refreshSharedHapticLevel(): void {
  const value: number = readSharedHapticLevel();
  if (AppStorage.get<number>(KANON_HAPTIC_LEVEL) !== value) { AppStorage.setOrCreate(KANON_HAPTIC_LEVEL, value); }
}

export function refreshKeyboardHeightPercent(): void {
  const value: number = readKeyboardHeightPercent();
  if (AppStorage.get<number>(KANON_KEYBOARD_HEIGHT_PERCENT) !== value) { AppStorage.setOrCreate(KANON_KEYBOARD_HEIGHT_PERCENT, value); }
}

export function initializeKeyboardConfig(context: common.Context): void {
  // Load legacy properties before the one-time repository migration.
  initializeShortcutConfig();
  PersistentStorage.persistProp('kanonLayoutOrder', DEFAULT_LAYOUT_ORDER);
  PersistentStorage.persistProp('kanonFlickDistance', DEFAULT_FLICK_DISTANCE);
  PersistentStorage.persistProp('kanonLongPressMs', DEFAULT_LONG_PRESS_MS);
  PersistentStorage.persistProp('kanonFlickPreviewEnabled', DEFAULT_KEY_PREVIEW_ENABLED);
  openSettingsRepository(context);
  if (settingsRepositoryReady()) {
    // Migration is durable. Stop the legacy bindings from becoming a second writer.
    for (const key of ['kanonLayoutOrder', 'kanonFlickDistance', 'kanonLongPressMs',
      'kanonFlickPreviewEnabled', 'kanonShortcutOrder']) { PersistentStorage.deleteProp(key); }
    publishCurrentSettings();
  }
  const selected: string[] = languageLayouts(readSharedLayoutOrder());
  PersistentStorage.persistProp('kanonLastLayout', selected[0]);
  const last: string = AppStorage.get<string>(KANON_LAST_LAYOUT) ?? selected[0];
  const current: string = selected.find((id: string) => layoutLanguage(id) === layoutLanguage(last)) ?? selected[0];
  AppStorage.setOrCreate(KANON_LAST_LAYOUT, current);
  AppStorage.setOrCreate(KANON_LAYOUT, current);
  AppStorage.setOrCreate(KANON_MODE, layoutLanguage(current));
}
