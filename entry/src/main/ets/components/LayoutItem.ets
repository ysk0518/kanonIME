import { backgroundKeyColor } from '../common/KeyboardBackground';
import { kanonIme } from '../kanon/KanonIme';
import { MenuType } from '../model/KeyboardKeyData';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { refreshSharedFlickEnabled } from '../common/KeyboardConfig';
import { keyboardHaptics } from '../common/KeyboardHaptics';

@Component
export struct LayoutItem {
  @StorageLink('kanonBackgroundKeyOpacity') backgroundKeyOpacity: number = 100;
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  keyWidth: Resource | string | number | undefined = undefined;
  keyRadius: number = 4;
  @Consume menuType: number;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('kanonLayout') layout: string = 'jp_flick';
  @StorageLink('kanonFlickEnabled') flickEnabled: boolean = true;

  build() {
    Column({ space: 1 }) {
      if (!this.flickEnabled) {
        Text(this.menuType === MenuType.SPECIAL ? 'ABC' : '#+=')
          .fontSize(14).maxFontScale(1).maxLines(1).fontColor($r('app.color.key_text'))
      } else {
        Image(this.layout.endsWith('flick') ? $r('app.media.ic_layout_qwerty') : $r('app.media.ic_layout_12key'))
        .fillColor($r('app.color.key_text'))
        .width(22)
        .height(22)
        Text(this.layout.endsWith('flick') ? 'QWERTY' : '12')
          .fontSize(this.layout.endsWith('flick') ? 9 : 10)
          .maxFontScale(1)
          .fontColor($r('app.color.key_text'))
          .maxLines(1)
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width(this.keyWidth ?? this.inputStyle.basicButtonWidth)
    .height('100%')
    .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'), this.backgroundKeyOpacity, this.backgroundThemeVersion))
    .borderRadius(this.keyRadius)
    .accessibilityText(!this.flickEnabled ? (this.menuType === MenuType.SPECIAL ?
      $r('app.string.keyboard_back_letters') : $r('app.string.keyboard_show_symbols')) :
      $r('app.string.keyboard_switch_layout'))
    .id('layoutItem')
    .onClick(async () => {
      refreshSharedFlickEnabled();
      if (!this.flickEnabled) {
        keyboardHaptics.key();
        this.menuType = this.menuType === MenuType.SPECIAL ? MenuType.NORMAL : MenuType.SPECIAL;
        return;
      }
      if (await kanonIme.toggleLayout() && this.menuType === MenuType.SPECIAL) {
        this.menuType = MenuType.NORMAL;
      }
    })
  }
}
