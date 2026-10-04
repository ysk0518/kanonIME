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
import { KeyState, keySourceListType, keySourceListData } from '../model/KeyboardKeyData';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { KeyItem } from './KeyItem';
import { KeyItemNumber } from './KeyItemNumber';
import { SpaceItem } from './SpaceItem';
import { ReturnItem } from './ReturnItem';
import { LayoutItem } from './LayoutItem';
import { ModeCycleItem } from './ModeCycleItem';
import { keyboardHaptics } from '../common/KeyboardHaptics';

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
  @Consume menuType: number;
  @Provide keyState: number = KeyState.LOWER_CASE;
  private keyList: keySourceListType[] = keySourceListData;

  build() {
    Column({ space: 6 }) {
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
            .fillColor($r('app.color.key_text'))
            .width(this.inputStyle.featurePicSize)
            .height(this.inputStyle.featurePicSize)
        }
        .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'), this.backgroundKeyOpacity, this.backgroundThemeVersion))
        .borderRadius(4)
        .onClick(() => {
          keyboardHaptics.key();
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

      Row({ space: 4 }) {
        LayoutItem()
        ModeCycleItem()
        if (this.layout === 'jp_qwerty') {
          KeyItem({ keyValue: { content: '、', title: '、', upperContent: '、' }, keyId: 'qwerty_comma' })
        } else {
          KeyItem({ keyValue: { content: ',', title: ',', upperContent: ',' }, keyId: 'qwerty_comma' })
        }
        Column() { SpaceItem({ spaceWith: '100%' }) }.layoutWeight(1).height('100%')
        if (this.layout === 'jp_qwerty') {
          KeyItem({ keyValue: { content: '。', title: '。', upperContent: '。' }, keyId: 'qwerty_period' })
        } else {
          KeyItem({ keyValue: { content: '.', title: '.', upperContent: '.' }, keyId: 'qwerty_period' })
        }
        ReturnItem({ returnWidth: this.inputStyle.returnButtonWidthType_1 })
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
