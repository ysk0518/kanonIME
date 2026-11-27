import { gamingControlPressed, gamingKeyColor, gamingKeyOutline, gamingKeyX } from '../common/GamingKeyFeedback';
import { backgroundKeyColor } from '../common/KeyboardBackground';
import { kanonIme } from '../kanon/KanonIme';
import { spaceKeyLabel } from '../model/KeyboardKeyLabels';

@Component
export struct ConvertSpaceItem {
  @StorageProp('kanonGamingPhase') gamingPhase: number = -1;
  @State private gamingX: number = 0;
  @State private gamingPressed: boolean = false;
  @StorageLink('kanonBackgroundKeyOpacity') backgroundKeyOpacity: number = 100;
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  @StorageLink('kanonJapaneseComposing') japaneseComposing: boolean = false;

  build() {
    Text(spaceKeyLabel('JP', true, this.japaneseComposing))
      .minFontSize(8).maxFontSize(14).maxFontScale(1.25)
      .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(TextAlign.Center)
      .fontColor(gamingKeyColor(this.gamingPhase, this.gamingX, $r('app.color.key_text')))
      .width('100%')
      .height('100%')
      .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'), this.backgroundKeyOpacity, this.backgroundThemeVersion))
      .borderRadius(6)
      .outline(gamingKeyOutline(this.gamingPhase, this.gamingX, 6, this.gamingPressed))
      .onAreaChange((_old: Area, area: Area) => { this.gamingX = gamingKeyX(area); })
      .onTouch((event: TouchEvent) => {
        this.gamingPressed = gamingControlPressed(event, this.gamingPhase, this.gamingPressed);
      })
      .onClick(() => { kanonIme.keySpace(); })
      .id('flick_convert_space')
  }
}
