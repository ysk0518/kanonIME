import common from '@ohos.app.ability.common';
import { KeyboardSettings } from '../components/KeyboardSettings';
import { SettingsPageId } from '../common/SettingsMenuModel';

@Entry
@Component
struct SettingsPage {
  @State private page: SettingsPageId = SettingsPageId.Top;
  private backgroundBusy: boolean = false;

  private async close(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try { await context.terminateSelf(); } catch (e) { }
  }

  onBackPress(): boolean {
    if (this.backgroundBusy) { return true; }
    if (this.page === SettingsPageId.Top) { this.close(); }
    else { this.page = SettingsPageId.Top; }
    return true;
  }

  build() {
    Column() {
      KeyboardSettings({ page: this.page, onOpen: (page: SettingsPageId) => { this.page = page; },
        onClose: () => { this.onBackPress(); },
        onBackgroundBusy: (busy: boolean) => { this.backgroundBusy = busy; } })
        .width('100%').height('100%')
    }
    .width('100%').height('100%')
  }
}
