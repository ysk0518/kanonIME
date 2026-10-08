import { backgroundKeyColor } from '../common/KeyboardBackground';
import { keySourceListData, keySourceListType } from '../model/KeyboardKeyData';

/** Appearance-only keys; gestures belong to the background editor underneath. */
@Component
export struct BackgroundKeyPreview {
  @Prop qwerty: boolean = false;
  @Prop keyOpacity: number = 100;
  @StorageLink('kanonBackgroundThemeVersion') themeVersion: number = 0;
  @StorageLink('kanonFlickEnabled') flickEnabled: boolean = true;
  private kanaRows: string[][] = [
    ['記号', 'あ', 'か', 'さ', '⌫'], ['←', 'た', 'な', 'は', '→'],
    ['あA1', 'ま', 'や', 'ら', '空白'], ['QWERTY', '小゛゜', 'わ', '、。?!', 'Enter']
  ];

  @Builder
  previewKey(label: string, weight: number = 1, control: boolean = false) {
    Text(label).fontSize(control ? 10 : this.qwerty ? 14 : 18)
      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .fontColor($r('app.color.key_text')).textAlign(TextAlign.Center)
      .layoutWeight(weight).height('100%').borderRadius(4)
      .backgroundColor(backgroundKeyColor(control ? $r('app.color.key_item_gray') :
        $r('app.color.key_item_normal'), this.keyOpacity, this.themeVersion))
  }

  build() {
    Column({ space: 4 }) {
      if (this.qwerty) {
        ForEach([0, 1], (row: number) => {
          Row({ space: 4 }) {
            ForEach(keySourceListData.slice(row === 0 ? 0 : 10, row === 0 ? 10 : 19),
              (key: keySourceListType) => { this.previewKey(key.content) }, (key: keySourceListType) => key.content)
            if (row === 1) { this.previewKey('ー') }
          }.width('100%').layoutWeight(1)
        })
        Row({ space: 4 }) {
          this.previewKey('⇧', 1.5, true)
          ForEach(keySourceListData.slice(19), (key: keySourceListType) => {
            this.previewKey(key.content)
          }, (key: keySourceListType) => key.content)
          this.previewKey('⌫', 1.5, true)
        }.width('100%').layoutWeight(1)
        Row({ space: 4 }) {
          this.previewKey(this.flickEnabled ? '12' : '#+=', 1, true)
          this.previewKey('あA1', 1.5, true)
          this.previewKey('、')
          this.previewKey('空白', 4, true)
          this.previewKey('。')
          this.previewKey('Enter', 1.5, true)
        }.width('100%').layoutWeight(1)
      } else {
        ForEach(this.kanaRows, (row: string[]) => {
          Row({ space: 4 }) {
            ForEach(row, (label: string, index: number) => {
              this.previewKey(label, index === 0 || index === 4 ? 0.8 : 1, index === 0 || index === 4)
            })
          }.width('100%').layoutWeight(1)
        })
      }
    }.padding(8).width('100%').height('100%').hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
  }
}
