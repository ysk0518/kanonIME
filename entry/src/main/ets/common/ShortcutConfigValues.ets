export const DEFAULT_SHORTCUT_ORDER: string = 'settings,clipboard';
export const SHORTCUT_IDS: string[] = ['settings', 'clipboard', 'edit'];

export function shortcutOrder(value: string): string[] {
  if (value.trim().length === 0) { return []; }
  const result: string[] = [];
  for (const item of value.split(',')) {
    const id: string = item.trim();
    if (SHORTCUT_IDS.includes(id) && !result.includes(id)) { result.push(id); }
  }
  return result.length > 0 ? result : DEFAULT_SHORTCUT_ORDER.split(',');
}
