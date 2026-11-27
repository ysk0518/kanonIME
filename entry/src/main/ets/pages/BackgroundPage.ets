import common from '@ohos.app.ability.common';
import { KeyboardBackgroundSettings } from '../components/KeyboardBackgroundSettings';

@Entry
@Component
struct BackgroundPage {
  private backgroundBack: (() => void) | undefined = undefined;

  private async close(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try { await context.terminateSelf(); } catch (error) {}
  }

  onBackPress(): boolean {
    if (this.backgroundBack !== undefined) { this.backgroundBack(); }
    else { this.close(); }
    return true;
  }

  build() {
    Column() {
      KeyboardBackgroundSettings({ onClose: () => { this.close(); },
        onBackHandlerChange: (handler: (() => void) | undefined) => { this.backgroundBack = handler; } })
    }.width('100%').height('100%')
  }
}
