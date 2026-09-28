import { FlickKey } from './FlickKey';
import { DeleteItem } from './DeleteItem';
import { LanguageItem } from './LanguageItem';
import inputMethodEngine from '@ohos.inputMethodEngine';
import { kanonIme } from '../kanon/KanonIme';
import { MenuType } from '../model/KeyboardKeyData';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';

@Component
export struct FlickMenu {
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('kanonLayout') layout: string = 'jp_flick';
  @Consume menuType: number;
  @StorageLink('kanonState') imeState: string = 'JP_EMPTY';
  @StorageLink('enterKeyType') enterKeyType: EnterKeyType = EnterKeyType.Done;
  @State private englishUpper: boolean = false;
  private keys: string[][] = [
    ['あ', 'い', 'う', 'え', 'お'], ['か', 'き', 'く', 'け', 'こ'], ['さ', 'し', 'す', 'せ', 'そ'],
    ['た', 'ち', 'つ', 'て', 'と'], ['な', 'に', 'ぬ', 'ね', 'の'], ['は', 'ひ', 'ふ', 'へ', 'ほ'],
    ['ま', 'み', 'む', 'め', 'も'], ['や', '（', 'ゆ', '）', 'よ'], ['ら', 'り', 'る', 'れ', 'ろ'],
    ['小゛゜'], ['わ', 'を', 'ん', 'ー', '〜'], ['、', '。', '？', '！', '…']
  ];
  private englishKeys: string[][] = [
    ['@', '#', '$', '%', '1'], ['a', 'b', 'c', '', '2'], ['d', 'e', 'f', '', '3'],
    ['g', 'h', 'i', '', '4'], ['j', 'k', 'l', '', '5'], ['m', 'n', 'o', '', '6'],
    ['p', 'q', 'r', 's', '7'], ['t', 'u', 'v', '', '8'], ['w', 'x', 'y', 'z', '9'],
    ['shift'], [' ', '', '', '', '0'], ['.', ',', '?', '!', '']
  ];
  private englishLabels: string[] = ['@#$%', 'abc', 'def', 'ghi', 'jkl', 'mno', 'pqrs', 'tuv', 'wxyz', 'a/A', 'space', '.,?!'];

  @Builder
  control(label: string, action: number) {
    Text(label)
      .fontSize(14).maxFontScale(Math.max(1, Math.min(1.5, this.inputStyle.basicButtonHeight / 24)))
      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .fontColor(action === 8 && this.englishUpper ? $r('app.color.candidate_accent') : $r('app.color.key_text'))
      .fontWeight(action === 8 && this.englishUpper ? FontWeight.Medium : FontWeight.Normal)
      .textAlign(TextAlign.Center)
      .width('100%')
      .height('100%')
      .backgroundColor(action === 8 && this.englishUpper ? $r('app.color.candidate_selected') : $r('app.color.key_item_gray'))
      .accessibilityText(action === 8 ? (this.englishUpper ? '小文字に切り替え' : '次の英字を大文字にする') : label)
      .borderRadius(6)
      .onClick(() => {
        if (action === 0) { this.menuType = MenuType.NUMBER; }
        else if (action === 1) { this.menuType = MenuType.SPECIAL; }
        else if (action === 2) { kanonIme.keyMove(inputMethodEngine.CURSOR_LEFT); }
        else if (action === 4) { kanonIme.keyDelete(); }
        else if (action === 5) {
          if (this.layout === 'en_flick') { kanonIme.keyText('-'); }
          else { kanonIme.keySpace(); }
        }
        else if (action === 6) { kanonIme.keyMove(inputMethodEngine.CURSOR_RIGHT); }
        else if (action === 8) { this.englishUpper = !this.englishUpper; }
        else { kanonIme.keyReturn(); }
      })
      .id(`flick_control_${action}`)
  }

  build() {
    Column({ space: 6 }) {
      ForEach([0, 1, 2, 3], (row: number) => {
        Row({ space: 6 }) {
          Column() {
            if (row === 3) { LanguageItem({ keyWidth: '100%', keyRadius: 6 }) }
            else { this.control(['?123', '記号', '←'][row], row) }
          }.width('13%').height('100%')
          ForEach((this.layout === 'en_flick' ? this.englishKeys : this.keys).slice(row * 3, row * 3 + 3),
            (values: string[], index: number) => {
            Column() {
              if (this.layout === 'en_flick' && values[0] === 'shift') {
                this.control(this.englishUpper ? 'A/a' : 'a/A', 8)
              } else {
                FlickKey({ values: values, modifier: values[0] === '小゛゜',
                  english: this.layout === 'en_flick', uppercase: this.englishUpper,
                  displayLabel: this.layout === 'en_flick' ? this.englishLabels[row * 3 + index] : '',
                  onLetter: () => { this.englishUpper = false; } })
              }
            }
              .layoutWeight(1).height('100%')
          }, (values: string[]) => values[0])
          Column() {
            if (row === 0) { DeleteItem({ keyWidth: '100%' }) }
            else { this.control(row === 1 ? (this.layout === 'en_flick' ? '-' : '変換') : row === 2 ? '→' :
              this.layout !== 'en_flick' && this.imeState !== 'JP_EMPTY' ? '確定' :
              this.enterKeyType === EnterKeyType.Send ? '送信' :
              this.enterKeyType === EnterKeyType.Search ? '検索' : '↵', row + 4) }
          }.width('13%').height('100%')
        }
        .layoutWeight(1)
        .width('100%')
      })
    }
    .padding({ left: 6, right: 6, top: 6, bottom: 6 })
    .width('100%')
    .constraintSize({ maxWidth: 720 })
    .height('100%')
  }
}
