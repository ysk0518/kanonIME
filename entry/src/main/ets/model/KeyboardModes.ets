import { languageLayouts, layoutLanguage, nextLanguageLayout } from '../common/KeyboardConfigValues';
import { MenuType } from './KeyboardKeyData';

// EditorAttribute.inputPattern uses inputMethod.TextInputType values.
enum EditorNumberPattern {
  Number = 2,
  Phone = 3,
  Password = 8
}

export function numberFlickKind(inputPattern: number): string {
  switch (inputPattern) {
    case EditorNumberPattern.Number: return 'number';
    case EditorNumberPattern.Phone: return 'phone';
    case EditorNumberPattern.Password: return 'digits';
    default: return 'general';
  }
}

export function keyboardMenuType(layout: string, menuType: number, inputPattern: number): number {
  if (numberFlickKind(inputPattern) !== 'general') { return MenuType.NUMBER; }
  if (menuType === MenuType.NUMBER && !layout.endsWith('_flick')) { return MenuType.NORMAL; }
  return menuType;
}

export function numberModeReturnLanguage(order: string): string {
  return languageLayouts(order).some((id: string) => layoutLanguage(id) === 'JP') ? 'JP' : 'EN';
}

export function nextModeCycleTarget(flick: boolean, menuType: number, mode: string, order: string): string {
  if (flick && menuType === MenuType.NUMBER) { return numberModeReturnLanguage(order); }
  if (flick && mode === 'EN') { return 'NUMBER'; }
  const next: string = layoutLanguage(nextLanguageLayout(order, mode === 'EN' ? 'en_qwerty' : 'jp_qwerty'));
  return next !== mode ? next : flick ? 'NUMBER' : '';
}
