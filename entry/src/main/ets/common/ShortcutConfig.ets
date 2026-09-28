import { SubMenuType } from '../model/KeyboardKeyData';

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

export function shortcutName(id: string): string {
  return id === 'settings' ? 'キーボード設定' : id === 'clipboard' ? 'クリップボード' : 'テキスト編集';
}

export function shortcutIcon(id: string): Resource {
  return id === 'settings' ? $r('app.media.ic_settings') :
    id === 'clipboard' ? $r('app.media.ic_clipboard') : $r('app.media.ic_edit');
}

export function shortcutTarget(id: string): number {
  return id === 'settings' ? SubMenuType.SETTINGS : id === 'clipboard' ? SubMenuType.CLIPBOARD : SubMenuType.EDIT;
}

export function initializeShortcutConfig(): void {
  PersistentStorage.persistProp('kanonShortcutOrder', DEFAULT_SHORTCUT_ORDER);
  const saved: string = AppStorage.get<string>('kanonShortcutOrder') ?? DEFAULT_SHORTCUT_ORDER;
  AppStorage.setOrCreate('kanonShortcutOrder', shortcutOrder(saved).join(','));
}
