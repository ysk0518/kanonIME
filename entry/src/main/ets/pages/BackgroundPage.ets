import common from '@ohos.app.ability.common';
import { KeyboardBackgroundSettings } from '../components/KeyboardBackgroundSettings';

@Entry
@Component
struct BackgroundPage {
  build() {
    Column() {
      KeyboardBackgroundSettings({ onClose: async () => {
        const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
        try { await context.terminateSelf(); } catch (error) {}
      } })
    }.width('100%').height('100%')
  }
}
