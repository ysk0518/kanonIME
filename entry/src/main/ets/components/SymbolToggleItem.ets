import { keyboardHaptics } from '../common/KeyboardHaptics';
import { MenuType, SubMenuType } from '../model/KeyboardKeyData';

@Component
export struct SymbolToggleItem {
  @Consume menuType: number;
  @StorageLink('submenuType') submenuType: number = SubMenuType.NORMAL;
  @StorageLink('inputPattern') inputPattern: InputType = InputType.Normal;
  buttonHeight: number = 36;

  private enabledForField(): boolean {
    return this.inputPattern !== InputType.Number && this.inputPattern !== InputType.PhoneNumber &&
      this.inputPattern !== InputType.NUMBER_PASSWORD;
  }

  build() {
    Text('!?#')
      .fontSize(15).maxFontScale(1.25).maxLines(1)
      .fontColor(this.menuType === MenuType.SPECIAL ? $r('app.color.candidate_accent') : $r('app.color.key_text'))
      .textAlign(TextAlign.Center)
      .width(40).height(this.buttonHeight)
      .enabled(this.enabledForField()).opacity(this.enabledForField() ? 1 : 0.4)
      .accessibilityText(this.menuType === MenuType.SPECIAL ?
        $r('app.string.keyboard_back_letters') : $r('app.string.keyboard_show_symbols'))
      .id('keyboardSymbols')
      .onClick(() => {
        keyboardHaptics.key();
        AppStorage.setOrCreate('kanonCandidatesExpanded', false);
        this.menuType = this.menuType === MenuType.SPECIAL ? MenuType.NORMAL : MenuType.SPECIAL;
        this.submenuType = SubMenuType.NORMAL;
      })
  }
}
