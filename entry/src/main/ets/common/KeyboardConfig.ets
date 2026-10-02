import { initializeShortcutConfig } from './ShortcutConfig';
import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';

const CONFIG_FILE: string = 'kanon_keyboard_config';
const LAYOUT_KEY: string = 'layout_order';
let sharedPreferences: preferences.Preferences | undefined = undefined;

export function openKeyboardPreferences(context: common.Context): void {
  sharedPreferences = preferences.getPreferencesSync(context,
    { name: CONFIG_FILE, storageType: preferences.StorageType.GSKV });
}

export function readSharedLayoutOrder(): string | undefined {
  if (sharedPreferences === undefined) { return undefined; }
  const value: string = sharedPreferences.getSync(LAYOUT_KEY, '') as string;
  return value.length > 0 ? value : undefined;
}

export function writeSharedLayoutOrder(value: string): void {
  if (sharedPreferences === undefined) { throw new Error('Keyboard preferences are unavailable'); }
  sharedPreferences.putSync(LAYOUT_KEY, languageLayouts(value).join(','));
  sharedPreferences.flushSync();
}

export function refreshSharedLayoutOrder(): string {
  const value: string | undefined = readSharedLayoutOrder();
  if (value !== undefined && value !== AppStorage.get<string>('kanonLayoutOrder')) {
    AppStorage.setOrCreate('kanonLayoutOrder', value);
  }
  return value ?? AppStorage.get<string>('kanonLayoutOrder') ?? DEFAULT_LAYOUT_ORDER;
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
  if (stored === undefined) { writeSharedLayoutOrder(order.join(',')); }
  AppStorage.setOrCreate('kanonLastLayout', current);
  AppStorage.setOrCreate('kanonLayout', current);
  AppStorage.setOrCreate('kanonMode', layoutLanguage(current));
}
