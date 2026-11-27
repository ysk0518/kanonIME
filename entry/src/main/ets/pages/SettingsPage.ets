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
    else { this.showPage(SettingsPageId.Top); }
  }

  // Animate page changes; KeyboardSettings gives each page its slide.
  private showPage(page: SettingsPageId): void {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => { this.page = page; });
  }

  onBackPress(): boolean {
    if (this.page === SettingsPageId.Theme && this.backgroundBack !== undefined) { this.backgroundBack(); }
    else { this.leavePage(); }
    return true;
  }

  build() {
    Column() {
      KeyboardSettings({ page: this.page, onOpen: (page: SettingsPageId) => { this.showPage(page); },
        onClose: () => this.leavePage(),
        onBackgroundBackHandler: (handler: (() => void) | undefined) => { this.backgroundBack = handler; } })
        .width('100%').height('100%')
    }
    .width('100%').height('100%')
  }
}
