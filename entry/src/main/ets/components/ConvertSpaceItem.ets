import { kanonIme } from '../kanon/KanonIme';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';

@Component
export struct ConvertSpaceItem {
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('kanonState') imeState: string = 'JP_EMPTY';
  @StorageLink('kanonList') candidates: string[] = [];

  build() {
    Text(this.imeState !== 'JP_EMPTY' || this.candidates.length > 0 ? '変換' : '空白')
      .fontSize(16)
      .maxFontScale(Math.max(1, Math.min(1.5, this.inputStyle.basicButtonHeight / 24)))
      .maxLines(1)
      .textAlign(TextAlign.Center)
      .fontColor($r('app.color.key_text'))
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.key_item_gray'))
      .borderRadius(6)
      .onClick(() => { kanonIme.keySpace(); })
      .id('flick_convert_space')
  }
}
