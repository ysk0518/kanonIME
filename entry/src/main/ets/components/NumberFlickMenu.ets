import inputMethodEngine from '@ohos.inputMethodEngine';
import { MenuType } from '../model/KeyboardKeyData';
import { numberFlickKeys } from '../model/NumberFlickData';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { kanonIme } from '../kanon/KanonIme';
import { FlickKey } from './FlickKey';
import { DeleteItem } from './DeleteItem';
import { LanguageItem } from './LanguageItem';

@Component
export struct NumberFlickMenu {
  @Consume menuType: number;
  @StorageLink('kanonLayout') layout: string = 'jp_flick';
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
      .fontSize(14).maxFontScale(Math.max(1, Math.min(1.5, this.inputStyle.basicButtonHeight / 24)))
      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .fontColor($r('app.color.key_text')).textAlign(TextAlign.Center)
      .width('100%').height('100%').borderRadius(6)
      .backgroundColor($r('app.color.key_item_gray'))
      .enabled(this.kind() === 'general' || (action !== 0 && action !== 1 && action !== 5))
      .opacity(this.kind() !== 'general' && (action === 0 || action === 1 || action === 5) ? 0.4 : 1)
      .onClick(() => {
        if (action === 0) { this.menuType = MenuType.NORMAL; }
        else if (action === 1) { this.menuType = MenuType.SPECIAL; }
        else if (action === 2) { kanonIme.keyMove(inputMethodEngine.CURSOR_LEFT); }
        else if (action === 5) { kanonIme.keyText(' '); }
        else if (action === 6) { kanonIme.keyMove(inputMethodEngine.CURSOR_RIGHT); }
        else { kanonIme.keyReturn(); }
      }).id(`number_flick_control_${action}`)
  }

  build() {
    Column({ space: 6 }) {
      ForEach([0, 1, 2, 3], (row: number) => {
        Row({ space: 6 }) {
          Column() {
            if (row === 3) { LanguageItem({ keyWidth: '100%', keyRadius: 6 }) }
            else { this.control(row === 0 ? (this.layout === 'jp_flick' ? 'かな' : 'ABC') : row === 1 ? '記号' : '←', row) }
          }.width('13%').height('100%')
          ForEach(numberFlickKeys(this.kind()).slice(row * 3, row * 3 + 3), (values: string[], index: number) => {
            Column() {
              if (values[0].length > 0) {
                FlickKey({ values: values, textInput: true, showDirections: true, guideAbove: row === 3,
                  keyId: `number_flick_${row * 3 + index}` })
              }
            }.layoutWeight(1).height('100%')
          }, (_values: string[], index: number) => `${row * 3 + index}:${this.kind()}`)
          Column() {
            if (row === 0) { DeleteItem({ keyWidth: '100%' }) }
            else { this.control(row === 1 ? 'space' : row === 2 ? '→' :
              this.enterKeyType === EnterKeyType.Send ? '送信' :
              this.enterKeyType === EnterKeyType.Search ? '検索' : '↵', row + 4) }
          }.width('13%').height('100%')
        }.layoutWeight(1).width('100%')
      })
    }
    .padding(6).width('100%').height('100%').constraintSize({ maxWidth: 720 })
  }
}
