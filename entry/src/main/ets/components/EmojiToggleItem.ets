import { keyboardHaptics } from '../common/KeyboardHaptics';
import { MenuType, SubMenuType } from '../model/KeyboardKeyData';
import { numberFlickKind } from '../model/KeyboardModes';

@Component
export struct EmojiToggleItem {
  @Consume menuType: number;
  @StorageLink('submenuType') submenuType: number = SubMenuType.NORMAL;
  @StorageLink('inputPattern') inputPattern: InputType = InputType.Normal;
  buttonHeight: number = 36;

  private enabledForField(): boolean { return numberFlickKind(this.inputPattern) === 'general'; }

  build() {
    Stack() {
      // A monochrome icon like the other toolbar buttons; a color emoji stood out.
      Stack() {
        Image($r('app.media.ic_emoji')).width(20).height(20).fillColor($r('app.color.key_text'))
      }
      .width(32).height(32).borderRadius(16)
      .backgroundColor(this.submenuType === SubMenuType.EMOJI ? $r('app.color.candidate_selected') : Color.Transparent)
    }
    .width(40).height(this.buttonHeight)
    .enabled(this.enabledForField()).opacity(this.enabledForField() ? 1 : 0.4)
    .accessibilityText(this.submenuType === SubMenuType.EMOJI ?
      $r('app.string.keyboard_back_letters') : $r('app.string.keyboard_show_emoji'))
    .id('keyboardEmoji')
    .onClick(() => {
      keyboardHaptics.key();
      AppStorage.setOrCreate('kanonCandidatesExpanded', false);
      this.menuType = MenuType.NORMAL;
      this.submenuType = this.submenuType === SubMenuType.EMOJI ? SubMenuType.NORMAL : SubMenuType.EMOJI;
    })
  }
}
