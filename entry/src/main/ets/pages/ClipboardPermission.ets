import abilityAccessCtrl, { PermissionRequestResult } from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import { clipboardHistory } from '../kanon/ClipboardHistory';

@Entry
@Component
struct ClipboardPermission {
  @State private message: string = 'コピーしたテキストを履歴に追加します。履歴は端末内に保存され、キーボードから削除できます。';
  @State private busy: boolean = false;
  @State private granted: boolean = false;

  private async enable(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result: PermissionRequestResult = await abilityAccessCtrl.createAtManager()
        .requestPermissionsFromUser(context, ['ohos.permission.READ_PASTEBOARD']);
      this.granted = result.authResults.length > 0 && result.authResults[0] === 0;
      this.message = this.granted ? '有効になりました。元のアプリでキーボードを開いてください。' :
        'クリップボードの読み取りが許可されませんでした。端末の権限設定を確認してください。';
      AppStorage.setOrCreate('kanonClipboardAutoStatus', this.granted ? 'ready' : 'permission');
      if (this.granted) { clipboardHistory.refresh(); }
    } catch (e) { this.message = '権限を有効にできませんでした。'; }
    finally { this.busy = false; }
  }

  build() {
    Column({ space: 20 }) {
      Text('クリップボード履歴').fontSize(24).fontColor($r('app.color.text_normal'))
      Text(this.message).fontSize(16).fontColor($r('app.color.text_normal'))
      if (!this.granted) {
        Button('履歴を有効にする').enabled(!this.busy).onClick(() => this.enable()).id('clipboard_enable_permission')
      }
      Button('元のアプリに戻る').enabled(!this.busy)
        .onClick(() => {
          const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
          context.terminateSelf();
        })
    }
    .padding(24).width('100%').height('100%').justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.menu_background'))
  }
}
