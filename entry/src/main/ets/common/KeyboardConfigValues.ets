export const DEFAULT_LAYOUT_ORDER: string = 'jp_flick,en_flick';
export const KEYBOARD_LAYOUTS: string[] = ['jp_flick', 'jp_qwerty', 'en_flick', 'en_qwerty'];
export const DEFAULT_FLICK_ENABLED: boolean = true;
export const DEFAULT_HAPTIC_LEVEL: number = 1;
export const DEFAULT_FLICK_DISTANCE: number = 18;
export const DEFAULT_LONG_PRESS_MS: number = 400;
export const DEFAULT_KEY_PREVIEW_ENABLED: boolean = true;

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
