import { photoKeyColor } from '../common/KeyboardKeyPalette';
import { gamingControlPressed, gamingKeyColor, gamingKeyOutline, gamingKeyCenter, gamingKeyTint } from '../common/GamingKeyFeedback';
import { GamingPoint } from '../common/GamingEffectModel';
import { backgroundKeyColor } from '../common/KeyboardBackground';
import { kanonIme } from '../kanon/KanonIme';
import { MenuType } from '../model/KeyboardKeyData';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { refreshSharedFlickEnabled } from '../common/KeyboardConfig';
import { keyboardHaptics } from '../common/KeyboardHaptics';

@Component
export struct LayoutItem {
  @StorageProp('kanonBackgroundHasPhoto') hasBackgroundPhoto: boolean = false;
  @StorageProp('kanonGamingPhase') gamingPhase: number = -1;
  @StorageProp('kanonGamingWaveTime') gamingTime: number = 0;
  @State private gamingCenter: GamingPoint | undefined = undefined;
  @State private gamingPressed: boolean = false;
  @StorageLink('kanonBackgroundKeyOpacity') backgroundKeyOpacity: number = 100;
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  keyWidth: Resource | string | number | undefined = undefined;
  keyRadius: number = 4;
  globe: boolean = false;
  @Prop fromNumberMode: boolean = false;
  @Consume menuType: number;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('kanonLayout') layout: string = 'jp_flick';
  @StorageLink('kanonFlickEnabled') flickEnabled: boolean = true;

  build() {
    Column({ space: 1 }) {
      if (this.globe) {
        Image($r('app.media.ic_globe')).fillColor(gamingKeyColor(this.gamingPhase, this.gamingTime, this.gamingCenter, photoKeyColor($r('app.color.key_text'), this.hasBackgroundPhoto))).width(22).height(22)
      } else if (!this.flickEnabled) {
        Text(this.menuType === MenuType.SPECIAL ? 'ABC' : '#+=')
          .fontSize(14).maxFontScale(1).maxLines(1).fontColor(gamingKeyColor(this.gamingPhase, this.gamingTime, this.gamingCenter, photoKeyColor($r('app.color.key_text'), this.hasBackgroundPhoto)))
      } else {
        Image(this.layout.endsWith('flick') ? $r('app.media.ic_layout_qwerty') : $r('app.media.ic_layout_12key'))
        .fillColor(gamingKeyColor(this.gamingPhase, this.gamingTime, this.gamingCenter, photoKeyColor($r('app.color.key_text'), this.hasBackgroundPhoto)))
        .width(22)
        .height(22)
        Text(this.layout.endsWith('flick') ? 'QWERTY' : '12')
          .fontSize(this.layout.endsWith('flick') ? 9 : 10)
          .maxFontScale(1)
          .fontColor(gamingKeyColor(this.gamingPhase, this.gamingTime, this.gamingCenter, photoKeyColor($r('app.color.key_text'), this.hasBackgroundPhoto)))
          .maxLines(1)
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width(this.keyWidth ?? this.inputStyle.basicButtonWidth)
    .height('100%')
    .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'),
      this.backgroundKeyOpacity, this.backgroundThemeVersion, this.hasBackgroundPhoto))
    .borderRadius(this.keyRadius)
    .outline(gamingKeyOutline(this.gamingPhase, this.gamingTime, this.gamingCenter, this.keyRadius, this.gamingPressed))
    .linearGradient(gamingKeyTint(this.gamingTime, this.gamingCenter))
    .onAreaChange((_old: Area, area: Area) => { this.gamingCenter = gamingKeyCenter(area); })
    .enabled(this.flickEnabled || !this.globe)
    .opacity(this.flickEnabled || !this.globe ? 1 : 0.4)
    .accessibilityText(!this.flickEnabled && !this.globe ? (this.menuType === MenuType.SPECIAL ?
      $r('app.string.keyboard_back_letters') : $r('app.string.keyboard_show_symbols')) :
      this.fromNumberMode ? $r('app.string.keyboard_switch_qwerty_letters') : $r('app.string.keyboard_switch_layout'))
    .id('layoutItem')
    .onTouch((event: TouchEvent) => {
      this.gamingPressed = gamingControlPressed(event, this.gamingPhase, this.gamingPressed);
    })
    .onClick(async () => {
      refreshSharedFlickEnabled();
      if (!this.flickEnabled) {
        if (this.globe) { return; }
        keyboardHaptics.key();
        this.menuType = this.menuType === MenuType.SPECIAL ? MenuType.NORMAL : MenuType.SPECIAL;
        return;
      }
      if (await kanonIme.toggleLayout(this.fromNumberMode) && this.menuType === MenuType.SPECIAL) {
        this.menuType = MenuType.NORMAL;
      }
    })
  }
}
