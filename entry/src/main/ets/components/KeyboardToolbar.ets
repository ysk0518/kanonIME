import { SubMenuType } from '../model/KeyboardKeyData';
import { InputHandler } from '../model/KeyboardController';
import { kanonIme } from '../kanon/KanonIme';
import { KeyboardShortcuts } from './KeyboardShortcuts';

@Component
export struct KeyboardToolbar {
  @StorageLink('kanonToolbarHeight') toolbarHeight: number = 44;
  @StorageLink('submenuType') submenuType: number = SubMenuType.NORMAL;
  @StorageLink('kanonMode') mode: string = 'JP';
  @StorageLink('kanonNeedsRecovery') needsRecovery: boolean = false;
  @StorageLink('kanonEnglishUndo') englishUndo: boolean = false;

  build() {
    Row() {
      Stack() {
        Image(this.submenuType === SubMenuType.NORMAL ? $r('app.media.ic_more') : $r('app.media.ic_keyboard'))
          .width(22).height(22).fillColor($r('app.color.key_text'))
      }
      .width(40).height(40).borderRadius(20)
      .backgroundColor($r('app.color.key_item_normal'))
      .onClick(() => {
        AppStorage.setOrCreate('kanonCandidatesExpanded', false);
        this.submenuType = this.submenuType === SubMenuType.NORMAL ? SubMenuType.MENU : SubMenuType.NORMAL;
      })
      .accessibilityText(this.submenuType === SubMenuType.NORMAL ? 'キーボードメニュー' : 'キーボードに戻る')
      .id('keyboardMenu')
      KeyboardShortcuts().layoutWeight(1)
      if (this.submenuType === SubMenuType.NORMAL && this.needsRecovery) {
        Column() {
        Text('再開').fontSize(13).fontColor($r('app.color.text_error')).width('100%').height(this.toolbarHeight)
          .textAlign(TextAlign.Center).onClick(() => { kanonIme.cancelCompose(); }).id('cand_mode')
        }.layoutWeight(0.7)
      } else if (this.submenuType === SubMenuType.NORMAL && this.mode === 'EN' && this.englishUndo) {
        Column() {
        Text('戻す').fontSize(13).fontColor($r('app.color.candidate_accent')).width('100%').height(this.toolbarHeight)
          .textAlign(TextAlign.Center).onClick(() => { kanonIme.keyUndoEnglish(); })
          .accessibilityText('英語の補完を取り消す').id('english_completion_undo')
        }.layoutWeight(0.7)
      }
      Stack() {
        Image($rawfile('down.svg')).width(22).height(22).fillColor($r('app.color.key_text'))
      }
      .width(40).height(this.toolbarHeight)
      .onClick(() => { this.submenuType = SubMenuType.NORMAL; InputHandler.getInstance().hideKeyboardSelf(); })
      .accessibilityText('キーボードを閉じる').id('kikaInputDown')
    }
    .width('100%').height(this.toolbarHeight).padding({ left: 8, right: 8 })
    .backgroundColor($r('app.color.candidate_background'))
  }
}
