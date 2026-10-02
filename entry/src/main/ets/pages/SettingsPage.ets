import common from '@ohos.app.ability.common';
import { KeyboardSettings } from '../components/KeyboardSettings';

@Entry
@Component
struct SettingsPage {
  private async close(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try { await context.terminateSelf(); } catch (e) { }
  }

  build() {
    Column() {
      KeyboardSettings({ onClose: () => this.close() })
        .width('100%').height('100%')
    }
    .width('100%').height('100%')
  }
}
