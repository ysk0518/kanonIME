import { SubMenuType } from '../model/KeyboardKeyData';

import { DEFAULT_SHORTCUT_ORDER, shortcutOrder } from './ShortcutConfigValues';
export { DEFAULT_SHORTCUT_ORDER, SHORTCUT_IDS, shortcutOrder } from './ShortcutConfigValues';

export function shortcutName(id: string): Resource {
  return id === 'settings' ? $r('app.string.settings_title') : id === 'clipboard' ? $r('app.string.shortcut_clipboard') : $r('app.string.shortcut_edit');
}

export function shortcutIcon(id: string): Resource {
  return id === 'settings' ? $r('app.media.ic_settings') :
    id === 'clipboard' ? $r('app.media.ic_clipboard') : $r('app.media.ic_edit');
}

export function shortcutTarget(id: string): number {
  return id === 'clipboard' ? SubMenuType.CLIPBOARD : id === 'edit' ? SubMenuType.EDIT : SubMenuType.NORMAL;
}

export function initializeShortcutConfig(): void {
  PersistentStorage.persistProp('kanonShortcutOrder', DEFAULT_SHORTCUT_ORDER);
  const saved: string = AppStorage.get<string>('kanonShortcutOrder') ?? DEFAULT_SHORTCUT_ORDER;
  AppStorage.setOrCreate('kanonShortcutOrder', shortcutOrder(saved).join(','));
}
