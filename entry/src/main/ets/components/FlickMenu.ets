import { photoKeyColor } from '../common/KeyboardKeyPalette';
import { backgroundKeyColor } from '../common/KeyboardBackground';
import { FlickKey } from './FlickKey';
import { DeleteItem } from './DeleteItem';
import { LayoutItem } from './LayoutItem';
import { ModeCycleItem } from './ModeCycleItem';
import { ConvertSpaceItem } from './ConvertSpaceItem';
import { ReturnItem } from './ReturnItem';
import { spaceKeyLabel } from '../model/KeyboardKeyLabels';
import inputMethodEngine from '@ohos.inputMethodEngine';
import { kanonIme } from '../kanon/KanonIme';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { FLICK_ACTION_COLUMN_WIDTH, FLICK_SIDE_PADDING } from '../common/KeyboardLayout';
import { keyboardHaptics } from '../common/KeyboardHaptics';
import { gamingControlPressed, gamingKeyColor, gamingKeyOutline, gamingKeyCenter, gamingKeyTint } from '../common/GamingKeyFeedback';
import { GamingPoint } from '../common/GamingEffectModel';

@Component
export struct FlickMenu {
  @StorageProp('kanonBackgroundHasPhoto') hasBackgroundPhoto: boolean = false;
  @StorageLink('kanonBackgroundKeyOpacity') backgroundKeyOpacity: number = 100;
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('kanonLayout') layout: string = 'jp_flick';
  @State private englishUpper: boolean = false;
  @StorageProp('kanonGamingPhase') gamingPhase: number = -1;
  @StorageProp('kanonGamingWaveTime') gamingTime: number = 0;
  @State private controlCenters: (GamingPoint | undefined)[] =
    [undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined];
  @State private pressedControl: number = -1;
  // The session reports a sentence start in English (Samsung Keyboard's automatic capitals).
  @StorageLink('kanonSentenceStart') @Watch('applySentenceStart') sentenceStart: boolean = false;
  private autoUpper: boolean = false;
  private keys: string[][] = [
    ['あ', 'い', 'う', 'え', 'お'], ['か', 'き', 'く', 'け', 'こ'], ['さ', 'し', 'す', 'せ', 'そ'],
    ['た', 'ち', 'つ', 'て', 'と'], ['な', 'に', 'ぬ', 'ね', 'の'], ['は', 'ひ', 'ふ', 'へ', 'ほ'],
    ['ま', 'み', 'む', 'め', 'も'], ['や', '（', 'ゆ', '）', 'よ'], ['ら', 'り', 'る', 'れ', 'ろ'],
    ['小゛゜'], ['わ', 'を', 'ん', 'ー', '〜'], ['、', '。', '？', '！', '…']
  ];
  private englishKeys: string[][] = [
    ['@', '/', ':', '~', '1'], ['a', 'b', 'c', '', '2'], ['d', 'e', 'f', '', '3'],
    ['g', 'h', 'i', '', '4'], ['j', 'k', 'l', '', '5'], ['m', 'n', 'o', '', '6'],
    ['p', 'q', 'r', 's', '7'], ['t', 'u', 'v', '', '8'], ['w', 'x', 'y', 'z', '9'],
    ['shift'], ['-', '#', '0', '', ''], ['.', ',', '?', '!', '']
  ];
  private englishLabels: string[] = ['@/:~', 'abc', 'def', 'ghi', 'jkl', 'mno', 'pqrs', 'tuv', 'wxyz', 'a/A', '-#', '.,?!'];
  private digitHints: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', ''];

  aboutToDisappear(): void { kanonIme.endToggleInput(); }

  @Builder
  control(label: string, action: number) {
    Text(label)
      .minFontSize(8).maxFontSize(action === 5 ? 14 : 16)
      .maxFontScale(Math.max(1, Math.min(1.5, this.inputStyle.basicButtonHeight / 24)))
      .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .fontColor(gamingKeyColor(this.gamingPhase, this.gamingTime, this.controlCenters[action],
        photoKeyColor(action === 8 && this.englishUpper ? $r('app.color.candidate_accent') : $r('app.color.key_text'),
          this.hasBackgroundPhoto)))
      .fontWeight(action === 8 && this.englishUpper ? FontWeight.Medium : FontWeight.Normal)
      .textAlign(TextAlign.Center)
      .width('100%')
      .height('100%')
      .backgroundColor(backgroundKeyColor(action === 8 && this.englishUpper
        ? $r('app.color.candidate_selected') : $r('app.color.key_item_gray'),
        this.backgroundKeyOpacity, this.backgroundThemeVersion, this.hasBackgroundPhoto))
      .accessibilityText(action === 8 ? (this.englishUpper ? '小文字に切り替え' : '次の英字を大文字にする') :
        action === 1 ? '直前の確定を取り消す' : label)
      .borderRadius(6)
      .outline(gamingKeyOutline(this.gamingPhase, this.gamingTime, this.controlCenters[action], 6, this.pressedControl === action))
      .linearGradient(gamingKeyTint(this.gamingTime, this.controlCenters[action]))
      .onAreaChange((_old: Area, area: Area) => { this.controlCenters[action] = gamingKeyCenter(area); })
      .onTouch((event: TouchEvent) => {
        if (gamingControlPressed(event, this.gamingPhase, this.pressedControl === action)) {
          this.pressedControl = action;
        } else if (this.pressedControl === action) { this.pressedControl = -1; }
      })
      .onClick(() => {
        if (action === 1) {
          if (kanonIme.toggleInputEnabled()) { kanonIme.keyToggleBack(); }
          else { kanonIme.keyUndo(); }
        }
        else if (action === 2) { kanonIme.keyMove(inputMethodEngine.CURSOR_LEFT); }
        else if (action === 4) { kanonIme.keyDelete(); }
        else if (action === 5) { kanonIme.keySpace(); }
        else if (action === 6) {
          if (kanonIme.toggleInputEnabled()) { kanonIme.keyToggleRight(); }
          else { kanonIme.keyMove(inputMethodEngine.CURSOR_RIGHT); }
        }
        else if (action === 8) {
          keyboardHaptics.key(); kanonIme.endToggleInput(); this.autoUpper = false; this.englishUpper = !this.englishUpper;
        }
      })
      .id(`flick_control_${action}`)
  }

  aboutToAppear(): void { this.applySentenceStart(); }

  // Capitalize once for a sentence start; undo only a capital this set itself.
  applySentenceStart(): void {
    if (this.layout === 'en_flick' && this.sentenceStart && !this.englishUpper) {
      this.englishUpper = true;
      this.autoUpper = true;
    } else if (!this.sentenceStart && this.autoUpper) {
      this.englishUpper = false;
      this.autoUpper = false;
    }
  }

  build() {
    Column({ space: this.inputStyle.keyGap }) {
      ForEach([0, 1, 2, 3], (row: number) => {
        Row({ space: this.inputStyle.keyGap }) {
          Column() {
            if (row === 3) { LayoutItem({ keyWidth: '100%', keyRadius: 6, globe: true }) }
            else if (row === 2) { ModeCycleItem({ keyWidth: '100%', keyRadius: 6, flick: true }) }
            else { this.control(row === 0 ? '↺' : '←', row === 0 ? 1 : 2) }
          }.width(FLICK_ACTION_COLUMN_WIDTH).height('100%')
          ForEach((this.layout === 'en_flick' ? this.englishKeys : this.keys).slice(row * 3, row * 3 + 3),
            (values: string[], index: number) => {
            Column() {
              if (this.layout === 'en_flick' && values[0] === 'shift') {
                this.control(this.englishUpper ? 'A/a' : 'a/A', 8)
              } else {
                FlickKey({ values: values, modifier: values[0] === '小゛゜',
                  english: this.layout === 'en_flick', uppercase: this.englishUpper,
                  digitHint: this.digitHints[row * 3 + index],
                  displayLabel: this.layout === 'en_flick' ? this.englishLabels[row * 3 + index] :
                    row === 3 && index === 2 ? '、。?!' : '',
                  onLetter: () => { this.englishUpper = false; } })
              }
            }
              .layoutWeight(1).height('100%')
          }, (values: string[]) => values[0])
          Column() {
            if (row === 0) { DeleteItem({ keyWidth: '100%' }) }
            else if (row === 2 && this.layout !== 'en_flick') { ConvertSpaceItem() }
            else if (row === 3) { ReturnItem({ returnWidth: '100%', keyId: 'flick_control_7', flick: true }) }
            else { this.control(row === 1 ? '→' : spaceKeyLabel('EN'), row === 1 ? 6 : 5) }
          }.width(FLICK_ACTION_COLUMN_WIDTH).height('100%')
        }
        .layoutWeight(1)
        .width('100%')
      })
    }
    .padding({ left: FLICK_SIDE_PADDING, right: FLICK_SIDE_PADDING, top: 6, bottom: 6 })
    .width('100%')
    .constraintSize({ maxWidth: 720 })
    .height('100%')
  }
}
