import { kanonIme } from '../kanon/KanonIme';
import { languageLayouts, layoutLanguage, refreshSharedLayoutOrder } from '../common/KeyboardConfig';
import { MenuType } from '../model/KeyboardKeyData';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { keyboardHaptics } from '../common/KeyboardHaptics';

@Component
export struct ModeCycleItem {
  keyWidth: Resource | string | number | undefined = undefined;
  keyRadius: number = 4;
  @Consume menuType: number;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('kanonMode') mode: string = 'JP';
  @StorageLink('inputPattern') inputPattern: InputType = InputType.Normal;

  private numericOnly(): boolean {
    return this.inputPattern === InputType.Number || this.inputPattern === InputType.PhoneNumber ||
      this.inputPattern === InputType.NUMBER_PASSWORD;
  }

  private active(): string {
    return this.menuType === MenuType.NUMBER || this.numericOnly() ? '1' :
      this.mode === 'EN' ? 'A' : 'あ';
  }

  private async cycle(): Promise<void> {
    if (this.numericOnly()) { return; }
    keyboardHaptics.key();
    const configured: string[] = languageLayouts(refreshSharedLayoutOrder());
    const japanese: boolean = configured.some((id: string) => layoutLanguage(id) === 'JP');
    const english: boolean = configured.some((id: string) => layoutLanguage(id) === 'EN');
    if (this.menuType === MenuType.NUMBER) {
      const target: string = japanese ? 'JP' : 'EN';
      if (this.mode !== target) { await kanonIme.switchMode(); }
      if (AppStorage.get<string>('kanonMode') === target) { this.menuType = MenuType.NORMAL; }
    } else if (this.mode === 'JP' && english) {
      await kanonIme.switchMode();
      if (AppStorage.get<string>('kanonMode') === 'EN') { this.menuType = MenuType.NORMAL; }
    } else {
      this.menuType = MenuType.NUMBER;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Row({ space: 1 }) {
        Text('あ').fontSize(14).maxFontScale(1).maxLines(1).fontColor(this.active() === 'あ' ? $r('app.color.candidate_accent') :
          $r('app.color.key_item_normal_text'))
        Text('A').fontSize(14).maxFontScale(1).maxLines(1).fontColor(this.active() === 'A' ? $r('app.color.candidate_accent') :
          $r('app.color.key_item_normal_text'))
        Text('1').fontSize(14).maxFontScale(1).maxLines(1).fontColor(this.active() === '1' ? $r('app.color.candidate_accent') :
          $r('app.color.key_item_normal_text'))
      }
    }
    .width(this.keyWidth ?? this.inputStyle.switchButtonWidth)
    .height('100%')
    .backgroundColor($r('app.color.key_item_gray'))
    .borderRadius(this.keyRadius)
    .enabled(!this.numericOnly())
    .opacity(this.numericOnly() ? 0.7 : 1)
    .accessibilityText(this.active() === 'あ' ? '英語または数字に切り替え' :
      this.active() === 'A' ? '数字に切り替え' : '日本語または英語に切り替え')
    .id('modeCycleItem')
    .onClick(() => { this.cycle(); })
  }
}
