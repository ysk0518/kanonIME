import { initializeShortcutConfig } from './ShortcutConfig';

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

export function initializeKeyboardConfig(): void {
  initializeShortcutConfig();
  PersistentStorage.persistProp('kanonLayoutOrder', DEFAULT_LAYOUT_ORDER);
  PersistentStorage.persistProp('kanonFlickDistance', DEFAULT_FLICK_DISTANCE);
  PersistentStorage.persistProp('kanonLongPressMs', DEFAULT_LONG_PRESS_MS);
  PersistentStorage.persistProp('kanonFlickPreviewEnabled', true);
  const saved: string = AppStorage.get<string>('kanonLayoutOrder') ?? DEFAULT_LAYOUT_ORDER;
  const order: string[] = languageLayouts(saved);
  PersistentStorage.persistProp('kanonLastLayout', order[0]);
  const last: string = AppStorage.get<string>('kanonLastLayout') ?? order[0];
  const current: string = order.includes(last) ? last : order[0];
  AppStorage.setOrCreate('kanonLayoutOrder', order.join(','));
  AppStorage.setOrCreate('kanonLastLayout', current);
  AppStorage.setOrCreate('kanonLayout', current);
  AppStorage.setOrCreate('kanonMode', layoutLanguage(current));
}
