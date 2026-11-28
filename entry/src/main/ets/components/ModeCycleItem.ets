import { photoKeyColor } from '../common/KeyboardKeyPalette';
import { gamingControlPressed, gamingKeyColor, gamingKeyOutline, gamingKeyCenter, gamingKeyTint } from '../common/GamingKeyFeedback';
import { GamingPoint } from '../common/GamingEffectModel';
import { backgroundKeyColor } from '../common/KeyboardBackground';
import { kanonIme } from '../kanon/KanonIme';
import { refreshSharedLayoutOrder } from '../common/KeyboardConfig';
import { MenuType } from '../model/KeyboardKeyData';
import { nextModeCycleTarget, numberFlickKind } from '../model/KeyboardModes';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { keyboardHaptics } from '../common/KeyboardHaptics';

@Component
export struct ModeCycleItem {
  @StorageProp('kanonBackgroundHasPhoto') hasBackgroundPhoto: boolean = false;
  @StorageProp('kanonGamingPhase') gamingPhase: number = -1;
  @StorageProp('kanonGamingWaveTime') gamingTime: number = 0;
  @State private gamingCenter: GamingPoint | undefined = undefined;
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
          .fontColor(gamingKeyColor(this.gamingPhase, this.gamingTime, this.gamingCenter, photoKeyColor($r('app.color.key_text'), this.hasBackgroundPhoto)))
      } else {
        Row({ space: 1 }) {
          Text('あ').fontSize(14).maxFontScale(1).maxLines(1).fontColor(gamingKeyColor(this.gamingPhase, this.gamingTime, this.gamingCenter,
            photoKeyColor(this.active() === 'あ' ? $r('app.color.candidate_accent') :
              $r('app.color.key_item_normal_text'), this.hasBackgroundPhoto)))
            .fontWeight(this.gamingPhase >= 0 && this.active() === 'あ' ? FontWeight.Bold : FontWeight.Normal)
          Text('A').fontSize(14).maxFontScale(1).maxLines(1).fontColor(gamingKeyColor(this.gamingPhase, this.gamingTime, this.gamingCenter,
            photoKeyColor(this.active() === 'A' ? $r('app.color.candidate_accent') :
              $r('app.color.key_item_normal_text'), this.hasBackgroundPhoto)))
            .fontWeight(this.gamingPhase >= 0 && this.active() === 'A' ? FontWeight.Bold : FontWeight.Normal)
          if (this.flick) {
            Text('1').fontSize(14).maxFontScale(1).maxLines(1).fontColor(gamingKeyColor(this.gamingPhase, this.gamingTime, this.gamingCenter,
              photoKeyColor(this.active() === '1' ? $r('app.color.candidate_accent') :
                $r('app.color.key_item_normal_text'), this.hasBackgroundPhoto)))
              .fontWeight(this.gamingPhase >= 0 && this.active() === '1' ? FontWeight.Bold : FontWeight.Normal)
          }
        }
      }
    }
    .width(this.keyWidth ?? this.inputStyle.switchButtonWidth)
    .height('100%')
    .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'),
      this.backgroundKeyOpacity, this.backgroundThemeVersion, this.hasBackgroundPhoto))
    .borderRadius(this.keyRadius)
    .outline(gamingKeyOutline(this.gamingPhase, this.gamingTime, this.gamingCenter, this.keyRadius, this.gamingPressed))
    .linearGradient(gamingKeyTint(this.gamingTime, this.gamingCenter))
    .onAreaChange((_old: Area, area: Area) => { this.gamingCenter = gamingKeyCenter(area); })
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
