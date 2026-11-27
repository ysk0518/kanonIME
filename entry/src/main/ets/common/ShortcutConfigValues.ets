// Samsung Keyboard's toolbar shows the clipboard before the settings.
export const DEFAULT_SHORTCUT_ORDER: string = 'clipboard,settings';
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

export function availableShortcuts(order: string[]): string[] {
  return SHORTCUT_IDS.filter((id: string) => !order.includes(id));
}

export function canMoveShortcut(order: string[], id: string, direction: number): boolean {
  const index: number = order.indexOf(id);
  const next: number = index + direction;
  return (direction === -1 || direction === 1) && index >= 0 && next >= 0 && next < order.length;
}

export function moveShortcut(order: string[], id: string, direction: number): string[] {
  if (!canMoveShortcut(order, id, direction)) { return order; }
  const index: number = order.indexOf(id);
  const next: number = index + direction;
  const result: string[] = order.slice();
  result[index] = result[next];
  result[next] = id;
  return result;
}

export function removeShortcut(order: string[], id: string): string[] {
  return order.filter((item: string) => item !== id);
}

export function addShortcut(order: string[], id: string): string[] {
  return availableShortcuts(order).includes(id) ? order.concat([id]) : order;
}
