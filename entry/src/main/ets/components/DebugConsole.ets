import { debugLog } from '../common/DebugLog';

@Component
export struct DebugConsole {
  @StorageLink('kanonDebugEnabled') debugEnabled: boolean = false;
  @StorageLink('kanonDebugConsole') consoleText: string = '';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void { debugLog.initialize(); }

  build() {
    Column({ space: 4 }) {
      Row({ space: 4 }) {
        Text($r('app.string.debug_mode')).fontSize(13).fontColor($r('app.color.text_normal')).layoutWeight(1)
        Radio({ value: 'off', group: 'kanon-debug-mode' }).checked(!this.debugEnabled)
          .onChange((checked: boolean) => { if (checked) { debugLog.setEnabled(false); } })
          .accessibilityText($r('app.string.debug_off')).id('debug_off')
        Text($r('app.string.debug_off')).fontSize(13).fontColor($r('app.color.text_normal'))
        Radio({ value: 'on', group: 'kanon-debug-mode' }).checked(this.debugEnabled)
          .onChange((checked: boolean) => { if (checked) { debugLog.setEnabled(true); } })
          .accessibilityText($r('app.string.debug_on')).id('debug_on')
        Text($r('app.string.debug_on')).fontSize(13).fontColor($r('app.color.text_normal'))
      }.width('100%').height(36)
      if (this.debugEnabled) {
        Row() {
          Text($r('app.string.debug_help')).fontSize(11).fontColor($r('app.color.text_secondary')).layoutWeight(1)
          Button($r('app.string.debug_clear')).height(28).fontSize(12).onClick(() => debugLog.clear())
        }.width('100%')
        Scroll(this.scroller) {
          Text(this.consoleText || $r('app.string.debug_empty'))
            .fontFamily('monospace').fontSize(11).fontColor($r('app.color.text_normal'))
            .copyOption(CopyOptions.LocalDevice).width('100%').padding(8)
        }.height(140).width('100%').backgroundColor($r('app.color.key_item_normal'))
          .borderRadius(8).id('debug_console')
      }
    }.width('100%')
  }
}
