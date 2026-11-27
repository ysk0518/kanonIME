import common from '@ohos.app.ability.common';
import { KeyboardSettings } from '../components/KeyboardSettings';
import { SettingsPageId } from '../common/SettingsMenuModel';

@Entry
@Component
struct SettingsPage {
  @State private page: SettingsPageId = SettingsPageId.Top;
  private backgroundBack: (() => void) | undefined = undefined;

  private async close(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try { await context.terminateSelf(); } catch (e) { }
  }

  private leavePage(): void {
    if (this.page === SettingsPageId.Top) { this.close(); }
    else { this.page = SettingsPageId.Top; }
  }

  onBackPress(): boolean {
    if (this.page === SettingsPageId.Theme && this.backgroundBack !== undefined) { this.backgroundBack(); }
    else { this.leavePage(); }
    return true;
  }

  build() {
    Column() {
      KeyboardSettings({ page: this.page, onOpen: (page: SettingsPageId) => { this.page = page; },
        onClose: () => this.leavePage(),
        onBackgroundBackHandler: (handler: (() => void) | undefined) => { this.backgroundBack = handler; } })
        .width('100%').height('100%')
    }
    .width('100%').height('100%')
  }
}
