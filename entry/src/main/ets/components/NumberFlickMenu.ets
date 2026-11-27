import inputMethodEngine from '@ohos.inputMethodEngine';
import { numberFlickKeys } from '../model/NumberFlickData';
import { numberFlickKind } from '../model/KeyboardModes';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { FLICK_ACTION_COLUMN_WIDTH, FLICK_SIDE_PADDING } from '../common/KeyboardLayout';
import { kanonIme } from '../kanon/KanonIme';
import { FlickKey } from './FlickKey';
import { backgroundKeyColor } from '../common/KeyboardBackground';
import { DeleteItem } from './DeleteItem';
import { LayoutItem } from './LayoutItem';
import { ModeCycleItem } from './ModeCycleItem';
import { ReturnItem } from './ReturnItem';
import { spaceKeyLabel } from '../model/KeyboardKeyLabels';
import { gamingControlPressed, gamingKeyColor, gamingKeyOutline, gamingKeyCenter, gamingKeyTint } from '../common/GamingKeyFeedback';
import { GamingPoint } from '../common/GamingEffectModel';

@Component
export struct NumberFlickMenu {
  @StorageLink('kanonBackgroundKeyOpacity') backgroundKeyOpacity: number = 100;
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('inputPattern') inputPattern: InputType = InputType.Normal;
  @StorageProp('kanonGamingPhase') gamingPhase: number = -1;
  @StorageProp('kanonGamingWaveTime') gamingTime: number = 0;
  @State private controlCenters: (GamingPoint | undefined)[] =
    [undefined, undefined, undefined, undefined, undefined, undefined, undefined];
  @State private pressedControl: number = -1;

  private kind(): string {
    return numberFlickKind(this.inputPattern);
  }

  @Builder
  control(label: string, action: number) {
    Text(label)
      .fontSize(16).maxFontScale(Math.max(1, Math.min(1.5, this.inputStyle.basicButtonHeight / 24)))
      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .fontColor(gamingKeyColor(this.gamingPhase, this.gamingTime, this.controlCenters[action], $r('app.color.key_text'))).textAlign(TextAlign.Center)
      .width('100%').height('100%').borderRadius(6)
      .outline(gamingKeyOutline(this.gamingPhase, this.gamingTime, this.controlCenters[action], 6, this.pressedControl === action))
      .linearGradient(gamingKeyTint(this.gamingTime, this.controlCenters[action]))
      .onAreaChange((_old: Area, area: Area) => { this.controlCenters[action] = gamingKeyCenter(area); })
      .onTouch((event: TouchEvent) => {
        if (this.kind() !== 'general' && action === 5) { return; }
        if (gamingControlPressed(event, this.gamingPhase, this.pressedControl === action)) {
          this.pressedControl = action;
        } else if (this.pressedControl === action) { this.pressedControl = -1; }
      })
      .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'), this.backgroundKeyOpacity, this.backgroundThemeVersion))
      .enabled(this.kind() === 'general' || action !== 5)
      .opacity(this.kind() !== 'general' && action === 5 ? 0.4 : 1)
      .accessibilityText(action === 1 ? '直前の確定を取り消す' : label)
      .onClick(() => {
        if (action === 1) { kanonIme.keyUndo(); }
        else if (action === 2) { kanonIme.keyMove(inputMethodEngine.CURSOR_LEFT); }
        else if (action === 5) { kanonIme.keyText(' '); }
        else if (action === 6) { kanonIme.keyMove(inputMethodEngine.CURSOR_RIGHT); }
      }).id(`number_flick_control_${action}`)
  }

  build() {
    Column({ space: this.inputStyle.keyGap }) {
      ForEach([0, 1, 2, 3], (row: number) => {
        Row({ space: this.inputStyle.keyGap }) {
          Column() {
            if (row === 3) { LayoutItem({ keyWidth: '100%', keyRadius: 6, globe: true,
              fromNumberMode: this.kind() === 'general' }) }
            else if (row === 2) { ModeCycleItem({ keyWidth: '100%', keyRadius: 6, flick: true }) }
            else { this.control(row === 0 ? '↺' : '←', row === 0 ? 1 : 2) }
          }.width(FLICK_ACTION_COLUMN_WIDTH).height('100%')
          ForEach(numberFlickKeys(this.kind()).slice(row * 3, row * 3 + 3), (values: string[], index: number) => {
            Column() {
              if (values[0].length > 0) {
                FlickKey({ values: values, textInput: true,
                  symbolHint: this.kind() === 'general' ? values.slice(1).join('') : '',
                  keyId: `number_flick_${row * 3 + index}` })
              }
            }.layoutWeight(1).height('100%')
          }, (_values: string[], index: number) => `${row * 3 + index}:${this.kind()}`)
          Column() {
            if (row === 0) { DeleteItem({ keyWidth: '100%' }) }
            else if (row === 3) { ReturnItem({ returnWidth: '100%', keyId: 'number_flick_control_7', flick: true }) }
            else { this.control(row === 1 ? '→' : spaceKeyLabel('NUMBER'), row === 1 ? 6 : 5) }
          }.width(FLICK_ACTION_COLUMN_WIDTH).height('100%')
        }.layoutWeight(1).width('100%')
      })
    }
    .padding({ left: FLICK_SIDE_PADDING, right: FLICK_SIDE_PADDING, top: 6, bottom: 6 })
    .width('100%').height('100%').constraintSize({ maxWidth: 720 })
  }
}
