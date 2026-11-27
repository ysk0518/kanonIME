import { gamingControlPressed, gamingKeyColor, gamingKeyOutline, gamingKeyX } from '../common/GamingKeyFeedback';
import { backgroundKeyColor } from '../common/KeyboardBackground';
import { kanonIme } from '../kanon/KanonIme';
import { refreshSharedLayoutOrder } from '../common/KeyboardConfig';
import { MenuType } from '../model/KeyboardKeyData';
import { nextModeCycleTarget, numberFlickKind } from '../model/KeyboardModes';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { keyboardHaptics } from '../common/KeyboardHaptics';

@Component
export struct ModeCycleItem {
  @StorageProp('kanonGamingPhase') gamingPhase: number = -1;
  @State private gamingX: number = 0;
  @State private gamingPressed: boolean = false;
  @StorageLink('kanonBackgroundKeyOpacity') backgroundKeyOpacity: number = 100;
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  keyWidth: Resource | string | number | undefined = undefined;
  keyRadius: number = 4;
  flick: boolean = false;
  @Consume menuType: number;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('kanonMode') mode: string = 'JP';
  @StorageLink('kanonJapaneseComposing') japaneseComposing: boolean = false;
  @StorageLink('inputPattern') inputPattern: InputType = InputType.Normal;
  @StorageLink('kanonLayoutOrder') layoutOrder: string = '';

  private numericOnly(): boolean {
    return numberFlickKind(this.inputPattern) !== 'general';
  }

  private active(): string {
    return (this.flick && this.menuType === MenuType.NUMBER) || this.numericOnly() ? '1' :
      this.mode === 'EN' ? 'A' : 'あ';
  }

  private converts(): boolean { return this.flick && this.japaneseComposing && !this.numericOnly(); }

  private accessibilityLabel(): string {
    if (this.numericOnly()) { return '数字入力'; }
    if (this.converts()) { return '変換'; }
    const target: string = nextModeCycleTarget(this.flick, this.menuType, this.mode, this.layoutOrder);
    if (target === 'JP') { return '日本語に切り替え'; }
    if (target === 'EN') { return '英語に切り替え'; }
    if (target === 'NUMBER') { return '数字に切り替え'; }
    return this.mode === 'EN' ? '英語入力' : '日本語入力';
  }

  private async cycle(): Promise<void> {
    if (this.numericOnly()) { return; }
    if (this.converts()) { await kanonIme.keySpace(); return; }
    const target: string = nextModeCycleTarget(this.flick, this.menuType, this.mode, refreshSharedLayoutOrder());
    if (target.length === 0) { return; }
    keyboardHaptics.key();
    if (this.menuType === MenuType.NUMBER) {
      await kanonIme.forgetJapaneseCommit();
      if (this.mode !== target) { await kanonIme.switchMode(); }
      if (!this.numericOnly() && this.menuType === MenuType.NUMBER &&
        AppStorage.get<string>('kanonMode') === target) { this.menuType = MenuType.NORMAL; }
    } else if (target === 'NUMBER') {
      await kanonIme.forgetJapaneseCommit();
      if (!this.numericOnly() && this.menuType === MenuType.NORMAL &&
        AppStorage.get<string>('kanonLayout')?.endsWith('_flick')) { this.menuType = MenuType.NUMBER; }
    } else {
      await kanonIme.switchMode();
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.converts()) {
        Text($r('app.string.keyboard_convert')).fontSize(16).maxFontScale(1).maxLines(1)
          .fontColor(gamingKeyColor(this.gamingPhase, this.gamingX, $r('app.color.key_text')))
      } else {
        Row({ space: 1 }) {
          Text('あ').fontSize(14).maxFontScale(1).maxLines(1).fontColor(gamingKeyColor(this.gamingPhase, this.gamingX,
            this.active() === 'あ' ? $r('app.color.candidate_accent') :
            $r('app.color.key_item_normal_text')))
            .fontWeight(this.gamingPhase >= 0 && this.active() === 'あ' ? FontWeight.Bold : FontWeight.Normal)
          Text('A').fontSize(14).maxFontScale(1).maxLines(1).fontColor(gamingKeyColor(this.gamingPhase, this.gamingX,
            this.active() === 'A' ? $r('app.color.candidate_accent') :
            $r('app.color.key_item_normal_text')))
            .fontWeight(this.gamingPhase >= 0 && this.active() === 'A' ? FontWeight.Bold : FontWeight.Normal)
          if (this.flick) {
            Text('1').fontSize(14).maxFontScale(1).maxLines(1).fontColor(gamingKeyColor(this.gamingPhase, this.gamingX,
              this.active() === '1' ? $r('app.color.candidate_accent') :
                $r('app.color.key_item_normal_text')))
              .fontWeight(this.gamingPhase >= 0 && this.active() === '1' ? FontWeight.Bold : FontWeight.Normal)
          }
        }
      }
    }
    .width(this.keyWidth ?? this.inputStyle.switchButtonWidth)
    .height('100%')
    .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'), this.backgroundKeyOpacity, this.backgroundThemeVersion))
    .borderRadius(this.keyRadius)
    .outline(gamingKeyOutline(this.gamingPhase, this.gamingX, this.keyRadius, this.gamingPressed))
    .onAreaChange((_old: Area, area: Area) => { this.gamingX = gamingKeyX(area); })
    .enabled(!this.numericOnly())
    .opacity(this.numericOnly() ? 0.7 : 1)
    .accessibilityText(this.accessibilityLabel())
    .id('modeCycleItem')
    .onTouch((event: TouchEvent) => {
      this.gamingPressed = gamingControlPressed(event, this.gamingPhase, this.gamingPressed);
    })
    .onClick(() => { this.cycle(); })
  }
}
