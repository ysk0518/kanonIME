import { MenuType, SubMenuType } from '../model/KeyboardKeyData';
import { InputHandler } from '../model/KeyboardController';
import { kanonIme } from '../kanon/KanonIme';
import { KeyboardShortcuts } from './KeyboardShortcuts';
import { SymbolToggleItem } from './SymbolToggleItem';
import { EmojiToggleItem } from './EmojiToggleItem';
import { DEFAULT_TOOLBAR_HEIGHT } from '../common/KeyboardLayout';
import { DEFAULT_SHORTCUT_ORDER, shortcutOrder } from '../common/ShortcutConfig';

@Component
export struct KeyboardToolbar {
  @StorageLink('kanonToolbarHeight') toolbarHeight: number = DEFAULT_TOOLBAR_HEIGHT;
  @StorageLink('submenuType') submenuType: number = SubMenuType.NORMAL;
  @StorageLink('kanonMode') mode: string = 'JP';
  @StorageLink('kanonNeedsRecovery') needsRecovery: boolean = false;
  @StorageLink('kanonEnglishUndo') englishUndo: boolean = false;
  @StorageLink('kanonLayout') layout: string = 'jp_flick';
  @Consume menuType: number;
  @StorageLink('kanonShortcutOrder') shortcutConfig: string = DEFAULT_SHORTCUT_ORDER;

  build() {
    Row() {
      // Samsung Keyboard order: emoji, symbols, shortcuts, more, then hide.
      // Every button gets an equal cell, so the icons sit evenly apart.
      Column() { EmojiToggleItem({ buttonHeight: this.toolbarHeight }) }.layoutWeight(1)
      Column() { SymbolToggleItem({ buttonHeight: this.toolbarHeight }) }.layoutWeight(1)
      KeyboardShortcuts().layoutWeight(Math.max(1, shortcutOrder(this.shortcutConfig).length))
      if (this.submenuType === SubMenuType.NORMAL && this.needsRecovery) {
        Column() {
        Text('再開').fontSize(13).fontColor($r('app.color.text_error')).width('100%').height(this.toolbarHeight)
          .textAlign(TextAlign.Center).onClick(() => { kanonIme.cancelCompose(); }).id('cand_mode')
        }.layoutWeight(0.7)
      } else if (this.submenuType === SubMenuType.NORMAL && this.menuType === MenuType.NORMAL &&
        this.layout === 'en_qwerty' && this.mode === 'EN' && this.englishUndo) {
        Column() {
        Text('戻す').fontSize(13).fontColor($r('app.color.candidate_accent')).width('100%').height(this.toolbarHeight)
          .textAlign(TextAlign.Center).onClick(() => { kanonIme.keyUndoEnglish(); })
          .accessibilityText('英語の補完を取り消す').id('english_completion_undo')
        }.layoutWeight(0.7)
      }
      Stack() {
        Stack() {
        Image(this.submenuType === SubMenuType.NORMAL ? $r('app.media.ic_more_horiz') : $r('app.media.ic_keyboard'))
          .width(20).height(20).fillColor($r('app.color.key_text'))
        }.width(32).height(32).borderRadius(16)
          .backgroundColor(this.submenuType === SubMenuType.NORMAL ? Color.Transparent : $r('app.color.candidate_selected'))
      }
      .layoutWeight(1).height(this.toolbarHeight)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        AppStorage.setOrCreate('kanonCandidatesExpanded', false);
        this.submenuType = this.submenuType === SubMenuType.NORMAL ? SubMenuType.MENU : SubMenuType.NORMAL;
      })
      .accessibilityText(this.submenuType === SubMenuType.NORMAL ? 'キーボードメニュー' : 'キーボードに戻る')
      .id('keyboardMenu')
      Stack() {
        Image($rawfile('down.svg')).width(20).height(20).fillColor($r('app.color.key_text'))
      }
      .layoutWeight(1).height(this.toolbarHeight)
      .onClick(() => { this.submenuType = SubMenuType.NORMAL; InputHandler.getInstance().hideKeyboardSelf(); })
      .accessibilityText('キーボードを閉じる').id('kikaInputDown')
    }
    .width('100%').height(this.toolbarHeight).padding({ left: 8, right: 8 })
    .backgroundColor($r('app.color.candidate_background'))
  }
}
