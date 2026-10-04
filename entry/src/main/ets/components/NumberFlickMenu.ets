import inputMethodEngine from '@ohos.inputMethodEngine';
import { MenuType } from '../model/KeyboardKeyData';
import { numberFlickKeys } from '../model/NumberFlickData';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { FLICK_ACTION_COLUMN_WIDTH, FLICK_KEY_GAP, FLICK_SIDE_PADDING } from '../common/KeyboardLayout';
import { kanonIme } from '../kanon/KanonIme';
import { keyboardHaptics } from '../common/KeyboardHaptics';
import { FlickKey } from './FlickKey';
import { backgroundKeyColor } from '../common/KeyboardBackground';
import { DeleteItem } from './DeleteItem';
import { LayoutItem } from './LayoutItem';
import { ModeCycleItem } from './ModeCycleItem';

@Component
export struct NumberFlickMenu {
  @StorageLink('kanonBackgroundKeyOpacity') backgroundKeyOpacity: number = 100;
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  @Consume menuType: number;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('inputPattern') inputPattern: InputType = InputType.Normal;
  @StorageLink('enterKeyType') enterKeyType: EnterKeyType = EnterKeyType.Done;

  private kind(): string {
    if (this.inputPattern === InputType.NUMBER_PASSWORD) { return 'digits'; }
    if (this.inputPattern === InputType.PhoneNumber) { return 'phone'; }
    if (this.inputPattern === InputType.Number) { return 'number'; }
    return 'general';
  }

  @Builder
  control(label: string, action: number) {
    Text(label)
      .fontSize(16).maxFontScale(Math.max(1, Math.min(1.5, this.inputStyle.basicButtonHeight / 24)))
      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .fontColor($r('app.color.key_text')).textAlign(TextAlign.Center)
      .width('100%').height('100%').borderRadius(6)
      .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'), this.backgroundKeyOpacity, this.backgroundThemeVersion))
      .enabled(this.kind() === 'general' || (action !== 1 && action !== 5))
      .opacity(this.kind() !== 'general' && (action === 1 || action === 5) ? 0.4 : 1)
      .onClick(() => {
        if (action === 1) { keyboardHaptics.key(); this.menuType = MenuType.SPECIAL; }
        else if (action === 2) { kanonIme.keyMove(inputMethodEngine.CURSOR_LEFT); }
        else if (action === 5) { kanonIme.keyText(' '); }
        else if (action === 6) { kanonIme.keyMove(inputMethodEngine.CURSOR_RIGHT); }
        else { kanonIme.keyReturn(); }
      }).id(`number_flick_control_${action}`)
  }

  build() {
    Column({ space: FLICK_KEY_GAP }) {
      ForEach([0, 1, 2, 3], (row: number) => {
        Row({ space: FLICK_KEY_GAP }) {
          Column() {
            if (row === 3) { LayoutItem({ keyWidth: '100%', keyRadius: 6 }) }
            else if (row === 2) { ModeCycleItem({ keyWidth: '100%', keyRadius: 6 }) }
            else { this.control(row === 0 ? '記号' : '←', row === 0 ? 1 : 2) }
          }.width(FLICK_ACTION_COLUMN_WIDTH).height('100%')
          ForEach(numberFlickKeys(this.kind()).slice(row * 3, row * 3 + 3), (values: string[], index: number) => {
            Column() {
              if (values[0].length > 0) {
                FlickKey({ values: values, textInput: true,
                  keyId: `number_flick_${row * 3 + index}` })
              }
            }.layoutWeight(1).height('100%')
          }, (_values: string[], index: number) => `${row * 3 + index}:${this.kind()}`)
          Column() {
            if (row === 0) { DeleteItem({ keyWidth: '100%' }) }
            else { this.control(row === 1 ? '→' : row === 2 ? 'space' :
              this.enterKeyType === EnterKeyType.Send ? '送信' :
              this.enterKeyType === EnterKeyType.Search ? '検索' : '↵', row === 1 ? 6 : row === 2 ? 5 : 7) }
          }.width(FLICK_ACTION_COLUMN_WIDTH).height('100%')
        }.layoutWeight(1).width('100%')
      })
    }
    .padding({ left: FLICK_SIDE_PADDING, right: FLICK_SIDE_PADDING, top: 6, bottom: 6 })
    .width('100%').height('100%').constraintSize({ maxWidth: 720 })
  }
}
