import { backgroundKeyColor } from '../common/KeyboardBackground';
// Modified for kanonIME by ysk0518 and contributors, 2026.
/*
 * Copyright (c) 2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF InputStyle KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { DeleteItem } from './DeleteItem';
import { KeyState, MenuType, keySourceListType, keySourceListData, qwertyDigits } from '../model/KeyboardKeyData';
import { isUrlInputPattern } from '../model/KeyboardKeyLabels';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { KeyItem } from './KeyItem';
import { KeyItemNumber } from './KeyItemNumber';
import { KeyItemGray } from './KeyItemGray';
import { SpaceItem } from './SpaceItem';
import { ReturnItem } from './ReturnItem';
import { LayoutItem } from './LayoutItem';
import { ModeCycleItem } from './ModeCycleItem';
import { keyboardHaptics } from '../common/KeyboardHaptics';
import { gamingControlPressed, gamingKeyColor, gamingKeyOutline, gamingKeyCenter, gamingKeyTint } from '../common/GamingKeyFeedback';
import { GamingPoint } from '../common/GamingEffectModel';

@Styles function pressedStyles() {
  .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray_pressed'), AppStorage.get<number>('kanonBackgroundKeyOpacity') ?? 100))
}

@Styles function normalStyles() {
  .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'), AppStorage.get<number>('kanonBackgroundKeyOpacity') ?? 100))
}

// key键盘
@Component
export struct KeyMenu {
  @StorageLink('kanonBackgroundKeyOpacity') backgroundKeyOpacity: number = 100;
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('kanonLayout') layout: string = 'jp_qwerty';
  @StorageLink('inputPattern') inputPattern: number = 0;
  @StorageLink('kanonFlickEnabled') flickEnabled: boolean = true;
  @Consume menuType: number;
  @Provide keyState: number = KeyState.LOWER_CASE;
  @StorageProp('kanonGamingPhase') gamingPhase: number = -1;
  @StorageProp('kanonGamingWaveTime') gamingTime: number = 0;
  @State private shiftCenter: GamingPoint | undefined = undefined;
  @State private gamingPressed: boolean = false;
  // The session reports a sentence start in English (Samsung Keyboard's automatic capitals).
  @StorageLink('kanonSentenceStart') @Watch('applySentenceStart') sentenceStart: boolean = false;
  private autoShift: boolean = false;
  private keyList: keySourceListType[] = keySourceListData;

  aboutToAppear(): void { this.applySentenceStart(); }

  // Shift once for a sentence start; undo only a shift this set itself.
  applySentenceStart(): void {
    if (this.layout === 'en_qwerty' && this.sentenceStart && this.keyState === KeyState.LOWER_CASE) {
      this.keyState = KeyState.ONCE_UPPER_CASE;
      this.autoShift = true;
    } else if (!this.sentenceStart && this.autoShift) {
      if (this.keyState === KeyState.ONCE_UPPER_CASE) { this.keyState = KeyState.LOWER_CASE; }
      this.autoShift = false;
    }
  }

  private comma(): string {
    return isUrlInputPattern(this.inputPattern) ? '/' : this.layout === 'jp_qwerty' ? '、' : ',';
  }

  build() {
    Column({ space: this.inputStyle.keyGap }) {
      Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        ForEach(qwertyDigits, (digit: string) => {
          KeyItem({ keyValue: { content: digit, title: digit, upperContent: digit },
            keyId: `qwerty_digit_${digit}` })
        }, (digit: string) => digit)
      }
      .width('100%')
      .layoutWeight(1)

      Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        ForEach(this.keyList.slice(0, 10), (item: keySourceListType) => {
          KeyItemNumber({ keyValue: item })
        }, (item: keySourceListType) => item.content)
      }
      .width('100%')
      .layoutWeight(1)

      Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        if (this.layout !== 'jp_qwerty') {
          Stack() {}.width('4%').height(0)
        }

        ForEach(this.keyList.slice(10, 19), (item: keySourceListType) => {
          KeyItemNumber({ keyValue: item })
        }, (item: keySourceListType) => item.content)
        if (this.layout === 'jp_qwerty') {
          KeyItem({ keyValue: { content: 'ー', title: 'ー', upperContent: 'ー' },
            kanaInput: true, keyId: 'qwerty_long_vowel' })
        } else {
          Stack() {}.width('4%').height(0)
        }
      }
      .width('100%')
      .layoutWeight(1)

      Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        Stack() {
          Image($rawfile(this.keyState === KeyState.ONCE_UPPER_CASE ? 'shift light.svg' : this.keyState === KeyState.UPPER_CASE ? 'shift light long.svg' : 'shift.svg'))
            .fillColor(gamingKeyColor(this.gamingPhase, this.gamingTime, this.shiftCenter, $r('app.color.key_text')))
            .width(this.inputStyle.featurePicSize)
            .height(this.inputStyle.featurePicSize)
        }
        .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'), this.backgroundKeyOpacity, this.backgroundThemeVersion))
        .borderRadius(4)
        .outline(gamingKeyOutline(this.gamingPhase, this.gamingTime, this.shiftCenter, 4, this.gamingPressed))
        .linearGradient(gamingKeyTint(this.gamingTime, this.shiftCenter))
        .onAreaChange((_old: Area, area: Area) => { this.shiftCenter = gamingKeyCenter(area); })
        .onTouch((event: TouchEvent) => {
          this.gamingPressed = gamingControlPressed(event, this.gamingPhase, this.gamingPressed);
        })
        .onClick(() => {
          keyboardHaptics.key();
          this.autoShift = false;
          if (this.keyState === KeyState.LOWER_CASE) {
            this.keyState = KeyState.ONCE_UPPER_CASE;
          } else if (this.keyState === KeyState.ONCE_UPPER_CASE) {
            this.keyState = KeyState.UPPER_CASE;
          } else if (this.keyState === KeyState.UPPER_CASE) {
            this.keyState = KeyState.LOWER_CASE;
          }
        })
        .height('100%')
        .width(this.inputStyle.switchButtonWidth)
        .shadow({ radius: 1, color: $r('app.color.shadow'), offsetY: 3 })
        .stateStyles({
          normal: normalStyles, pressed: pressedStyles
        })

        ForEach(this.keyList.slice(19), (item: keySourceListType) => {
          KeyItemNumber({ keyValue: item })
        }, (item: keySourceListType) => item.content)
        DeleteItem()
      }
      .width('100%')
      .layoutWeight(1)

      Row({ space: this.inputStyle.bottomKeyGap }) {
        Column() {
          KeyItemGray({ keyValue: '!#1', keyWidth: '100%', keyId: 'qwerty_symbols',
            onActivate: () => { this.menuType = MenuType.SPECIAL; } })
        }.layoutWeight(1.25).height('100%')
        Column() { ModeCycleItem({ keyWidth: '100%' }) }.layoutWeight(1.5).height('100%')
        // Without 12-key there is nothing to switch to, so the space takes the room.
        if (this.flickEnabled) { Column() { LayoutItem({ keyWidth: '100%', globe: true }) }.layoutWeight(1).height('100%') }
        Column() {
          KeyItem({ keyValue: { content: this.comma(), title: this.comma(), upperContent: this.comma() },
            keyId: 'qwerty_comma', keyWidth: '100%' })
        }.layoutWeight(1).height('100%')
        Column() { SpaceItem({ spaceWith: '100%' }) }.layoutWeight(4).height('100%')
        Column() {
          KeyItem({ keyValue: { content: this.layout === 'jp_qwerty' ? '。' : '.',
            title: this.layout === 'jp_qwerty' ? '。' : '.', upperContent: this.layout === 'jp_qwerty' ? '。' : '.' },
            keyId: 'qwerty_period', keyWidth: '100%' })
        }.layoutWeight(1).height('100%')
        if (isUrlInputPattern(this.inputPattern)) {
          Column() {
            KeyItem({ keyValue: { content: 'www.', title: 'www.', upperContent: 'www.' },
              keyId: 'qwerty_www', keyWidth: '100%', directInput: true })
          }.layoutWeight(1.75).height('100%')
        }
        Column() { ReturnItem({ returnWidth: '100%' }) }.layoutWeight(1.5).height('100%')
      }
      .width('100%')
      .layoutWeight(1)

    }
    .width('100%')
    .height('100%')
    .padding(6)
    .constraintSize({ maxWidth: 720 })
  }
}
