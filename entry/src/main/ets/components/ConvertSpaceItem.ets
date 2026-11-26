import { backgroundKeyColor } from '../common/KeyboardBackground';
import { kanonIme } from '../kanon/KanonIme';
import { spaceKeyLabel } from '../model/KeyboardKeyLabels';

@Component
export struct ConvertSpaceItem {
  @StorageLink('kanonBackgroundKeyOpacity') backgroundKeyOpacity: number = 100;
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  @StorageLink('kanonJapaneseComposing') japaneseComposing: boolean = false;

  build() {
    Text(spaceKeyLabel('JP', true, this.japaneseComposing))
      .minFontSize(8).maxFontSize(14).maxFontScale(1.25)
      .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(TextAlign.Center)
      .fontColor($r('app.color.key_text'))
      .width('100%')
      .height('100%')
      .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'), this.backgroundKeyOpacity, this.backgroundThemeVersion))
      .borderRadius(6)
      .onClick(() => { kanonIme.keySpace(); })
      .id('flick_convert_space')
  }
}
