import { kanonIme } from '../kanon/KanonIme';
import { MenuType } from '../model/KeyboardKeyData';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { DEFAULT_LAYOUT_ORDER, nextLanguageLayout } from '../common/KeyboardConfig';

@Component
export struct LanguageItem {
  keyWidth: Resource | string | undefined = undefined;
  keyRadius: number = 4;
  @Consume menuType: number;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('kanonLayoutOrder') layoutOrder: string = DEFAULT_LAYOUT_ORDER;
  @StorageLink('kanonLayout') layout: string = 'jp_flick';

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Image($r('app.media.ic_globe'))
        .width(22).height(22)
        .fillColor($r('app.color.key_text'))
        .accessibilityLevel('no')
    }
      .width(this.keyWidth ?? this.inputStyle.basicButtonWidth)
      .height('100%')
      .backgroundColor($r('app.color.key_item_gray'))
      .borderRadius(this.keyRadius)
      .enabled(nextLanguageLayout(this.layoutOrder, this.layout) !== this.layout)
      .opacity(nextLanguageLayout(this.layoutOrder, this.layout) === this.layout ? 0.4 : 1)
      .accessibilityText('言語切り替え')
      .id('languageItem')
      .onClick(async () => {
        await kanonIme.switchMode();
        this.menuType = MenuType.NORMAL;
      })
  }
}
