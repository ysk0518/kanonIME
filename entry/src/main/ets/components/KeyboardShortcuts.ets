import { SubMenuType } from '../model/KeyboardKeyData';
import { DEFAULT_SHORTCUT_ORDER, shortcutOrder, shortcutIcon, shortcutName, shortcutTarget } from '../common/ShortcutConfig';
import InputMethodExtensionContext from '@ohos.InputMethodExtensionContext';
import { openKeyboardSettings } from '../common/SettingsLauncher';
import { DEFAULT_TOOLBAR_HEIGHT } from '../common/KeyboardLayout';

@Component
export struct KeyboardShortcuts {
  @StorageLink('kanonToolbarHeight') toolbarHeight: number = DEFAULT_TOOLBAR_HEIGHT;
  @StorageLink('submenuType') submenuType: number = SubMenuType.NORMAL;
  @StorageLink('kanonShortcutOrder') shortcutConfig: string = DEFAULT_SHORTCUT_ORDER;

  @Builder
  shortcut(icon: Resource, label: string, target: number, key: string, settings: boolean) {
    Column() {
    Stack() {
      Image(icon).width(20).height(20).fillColor(!settings && this.submenuType === target ?
        $r('app.color.candidate_accent') : $r('app.color.key_text'))
    }
    .width('100%').constraintSize({ maxWidth: 40 }).height(32).borderRadius(16)
    .backgroundColor(!settings && this.submenuType === target ? $r('app.color.candidate_selected') : Color.Transparent)
    }.layoutWeight(1).height(this.toolbarHeight).justifyContent(FlexAlign.Center)
    .accessibilityText(label)
    .onClick(async () => {
      AppStorage.setOrCreate('kanonCandidatesExpanded', false);
      if (settings) {
        const context: InputMethodExtensionContext = this.getUIContext().getHostContext() as InputMethodExtensionContext;
        if (await openKeyboardSettings(context)) { this.submenuType = SubMenuType.NORMAL; }
        else { this.submenuType = SubMenuType.MENU; }
      } else {
        this.submenuType = this.submenuType === target ? SubMenuType.NORMAL : target;
      }
    })
    .id(key)
  }

  build() {
    Row() {
      ForEach(shortcutOrder(this.shortcutConfig), (id: string) => {
        this.shortcut(shortcutIcon(id), shortcutName(id), shortcutTarget(id), `shortcut_${id}`, id === 'settings')
      }, (id: string) => id)
    }
    .height(this.toolbarHeight)
    .width('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
  }
}
