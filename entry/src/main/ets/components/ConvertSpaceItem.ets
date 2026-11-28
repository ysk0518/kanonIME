import { photoKeyColor } from '../common/KeyboardKeyPalette';
import { gamingControlPressed, gamingKeyColor, gamingKeyOutline, gamingKeyCenter, gamingKeyTint } from '../common/GamingKeyFeedback';
import { GamingPoint } from '../common/GamingEffectModel';
import { backgroundKeyColor } from '../common/KeyboardBackground';
import { kanonIme } from '../kanon/KanonIme';
import { spaceKeyLabel } from '../model/KeyboardKeyLabels';

@Component
export struct ConvertSpaceItem {
  @StorageProp('kanonBackgroundHasPhoto') hasBackgroundPhoto: boolean = false;
  @StorageProp('kanonGamingPhase') gamingPhase: number = -1;
  @StorageProp('kanonGamingWaveTime') gamingTime: number = 0;
  @State private gamingCenter: GamingPoint | undefined = undefined;
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
      .fontColor(gamingKeyColor(this.gamingPhase, this.gamingTime, this.gamingCenter, photoKeyColor($r('app.color.key_text'), this.hasBackgroundPhoto)))
      .width('100%')
      .height('100%')
      .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'),
        this.backgroundKeyOpacity, this.backgroundThemeVersion, this.hasBackgroundPhoto))
      .borderRadius(6)
      .outline(gamingKeyOutline(this.gamingPhase, this.gamingTime, this.gamingCenter, 6, this.gamingPressed))
      .linearGradient(gamingKeyTint(this.gamingTime, this.gamingCenter))
      .onAreaChange((_old: Area, area: Area) => { this.gamingCenter = gamingKeyCenter(area); })
      .onTouch((event: TouchEvent) => {
        this.gamingPressed = gamingControlPressed(event, this.gamingPhase, this.gamingPressed);
      })
      .onClick(() => { kanonIme.keySpace(); })
      .id('flick_convert_space')
  }
}
