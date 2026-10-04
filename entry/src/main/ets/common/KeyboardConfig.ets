import { initializeShortcutConfig } from './ShortcutConfig';
import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { DEFAULT_KEYBOARD_HEIGHT_PERCENT, keyboardHeightPercent } from './KeyboardLayout';

const CONFIG_FILE: string = 'kanon_keyboard_config';
const LAYOUT_KEY: string = 'layout_order';
const HAPTIC_KEY: string = 'haptic_level';
const HEIGHT_KEY: string = 'height_percent';
export const DEFAULT_HAPTIC_LEVEL: number = 1;
let sharedPreferences: preferences.Preferences | undefined = undefined;

export function openKeyboardPreferences(context: common.Context): void {
  try {
    sharedPreferences = preferences.getPreferencesSync(context,
      { name: CONFIG_FILE, storageType: preferences.StorageType.GSKV });
  } catch (error) {
    sharedPreferences = undefined;
  }
}

export function readSharedLayoutOrder(): string | undefined {
  if (sharedPreferences === undefined) { return undefined; }
  try {
    const value: string = sharedPreferences.getSync(LAYOUT_KEY, '') as string;
    return value.length > 0 ? value : undefined;
  } catch (error) {
    return undefined;
  }
}

export function writeSharedLayoutOrder(value: string): void {
  if (sharedPreferences === undefined) { throw new Error('Keyboard preferences are unavailable'); }
  try {
    sharedPreferences.putSync(LAYOUT_KEY, languageLayouts(value).join(','));
    sharedPreferences.flushSync();
  } catch (error) {
    throw new Error('Failed to save keyboard layout preferences');
  }
}

export function refreshSharedLayoutOrder(): string {
  const value: string | undefined = readSharedLayoutOrder();
  if (value !== undefined && value !== AppStorage.get<string>('kanonLayoutOrder')) {
    AppStorage.setOrCreate('kanonLayoutOrder', value);
  }
  return value ?? AppStorage.get<string>('kanonLayoutOrder') ?? DEFAULT_LAYOUT_ORDER;
}

export function readSharedHapticLevel(): number {
  if (sharedPreferences === undefined) { return DEFAULT_HAPTIC_LEVEL; }
  try {
    const value: number = sharedPreferences.getSync(HAPTIC_KEY, DEFAULT_HAPTIC_LEVEL) as number;
    return value === 0 || value === 1 || value === 2 ? value : DEFAULT_HAPTIC_LEVEL;
  } catch (error) {
    return DEFAULT_HAPTIC_LEVEL;
  }
}

export function writeSharedHapticLevel(value: number): void {
  if (sharedPreferences === undefined) { throw new Error('Keyboard preferences are unavailable'); }
  try {
    sharedPreferences.putSync(HAPTIC_KEY, value === 0 || value === 2 ? value : DEFAULT_HAPTIC_LEVEL);
    sharedPreferences.flushSync();
  } catch (error) {
    throw new Error('Failed to save keyboard haptic preferences');
  }
}

export function refreshSharedHapticLevel(): void {
  AppStorage.setOrCreate('kanonHapticLevel', readSharedHapticLevel());
}

export function readKeyboardHeightPercent(): number {
  if (sharedPreferences === undefined) {
    return DEFAULT_KEYBOARD_HEIGHT_PERCENT;
  }
  try {
    const value: preferences.ValueType = sharedPreferences.getSync(HEIGHT_KEY, DEFAULT_KEYBOARD_HEIGHT_PERCENT);
    return typeof value === 'number' ? keyboardHeightPercent(value) : DEFAULT_KEYBOARD_HEIGHT_PERCENT;
  } catch (error) {
    return DEFAULT_KEYBOARD_HEIGHT_PERCENT;
  }
}

export function writeKeyboardHeightPercent(value: number): void {
  if (sharedPreferences === undefined) { throw new Error('Keyboard preferences are unavailable'); }
  try {
    sharedPreferences.putSync(HEIGHT_KEY, keyboardHeightPercent(value));
    sharedPreferences.flushSync();
  } catch (error) {
    throw new Error('Failed to save keyboard height preferences');
  }
}

export function refreshKeyboardHeightPercent(): void {
  AppStorage.setOrCreate('kanonKeyboardHeightPercent', readKeyboardHeightPercent());
}

export const DEFAULT_LAYOUT_ORDER: string = 'jp_flick,en_flick';
export const KEYBOARD_LAYOUTS: string[] = ['jp_flick', 'jp_qwerty', 'en_flick', 'en_qwerty'];
export const DEFAULT_FLICK_DISTANCE: number = 18;
export const DEFAULT_LONG_PRESS_MS: number = 400;

export function layoutOrder(value: string): string[] {
  const result: string[] = [];
  for (const id of value.split(',')) {
    if (KEYBOARD_LAYOUTS.includes(id) && !result.includes(id)) { result.push(id); }
  }
  return result.length > 0 ? result : DEFAULT_LAYOUT_ORDER.split(',');
}

export function layoutLanguage(id: string): string { return id.startsWith('en_') ? 'EN' : 'JP'; }

export function layoutName(id: string): string {
  return id === 'jp_flick' ? '日本語フリック' : id === 'jp_qwerty' ? '日本語ローマ字' :
    id === 'en_flick' ? '英語12キー' : '英語QWERTY';
}

// One chosen layout per language. Also migrates the former list of cycling layouts.
export function languageLayouts(value: string): string[] {
  const result: string[] = [];
  for (const id of layoutOrder(value)) {
    if (!result.some((item: string) => layoutLanguage(item) === layoutLanguage(id))) { result.push(id); }
  }
  return result;
}

export function nextLanguageLayout(order: string, current: string): string {
  return languageLayouts(order).find((id: string) => layoutLanguage(id) !== layoutLanguage(current)) ?? current;
}

export function initializeKeyboardConfig(context: common.Context): void {
  openKeyboardPreferences(context);
  refreshSharedHapticLevel();
  refreshKeyboardHeightPercent();
  initializeShortcutConfig();
  PersistentStorage.persistProp('kanonLayoutOrder', DEFAULT_LAYOUT_ORDER);
  PersistentStorage.persistProp('kanonFlickDistance', DEFAULT_FLICK_DISTANCE);
  PersistentStorage.persistProp('kanonLongPressMs', DEFAULT_LONG_PRESS_MS);
  PersistentStorage.persistProp('kanonFlickPreviewEnabled', true);
  const stored: string | undefined = readSharedLayoutOrder();
  const saved: string = stored ?? AppStorage.get<string>('kanonLayoutOrder') ?? DEFAULT_LAYOUT_ORDER;
  const selected: string[] = languageLayouts(saved);
  PersistentStorage.persistProp('kanonLastLayout', selected[0]);
  const last: string = AppStorage.get<string>('kanonLastLayout') ?? selected[0];
  const restored: string = selected.includes(last) ? last : selected[0];
  const suffix: string = restored.endsWith('_flick') ? 'flick' : 'qwerty';
  const order: string[] = selected.map((id: string) => `${id.startsWith('en_') ? 'en' : 'jp'}_${suffix}`);
  const current: string = `${restored.startsWith('en_') ? 'en' : 'jp'}_${suffix}`;
  AppStorage.setOrCreate('kanonLayoutOrder', order.join(','));
  if (stored === undefined && sharedPreferences !== undefined) {
    try { writeSharedLayoutOrder(order.join(',')); } catch (error) { /* AppStorage keeps the active layout. */ }
  }
  AppStorage.setOrCreate('kanonLastLayout', current);
  AppStorage.setOrCreate('kanonLayout', current);
  AppStorage.setOrCreate('kanonMode', layoutLanguage(current));
}
