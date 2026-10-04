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

import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { MenuKey, MenuType } from '../model/KeyboardKeyData';
import { keyboardHaptics } from '../common/KeyboardHaptics';

@Styles function pressedStyles() {
  .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray_pressed'), AppStorage.get<number>('kanonBackgroundKeyOpacity') ?? 100))
}

@Styles function normalStyles() {
  .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'), AppStorage.get<number>('kanonBackgroundKeyOpacity') ?? 100))
}

// 无大小写的灰色组件
@Component
export struct KeyItemGray {
  @StorageLink('kanonBackgroundKeyOpacity') backgroundKeyOpacity: number = 100;
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  keyValue: string | undefined = undefined;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @Consume menuType: number;

  build() {
    Stack() {
      if (this.keyValue) {
        Text(this.keyValue).fontSize(this.inputStyle.switchNumberFontSize).maxFontScale(Math.max(1, Math.min(1.5, (this.inputStyle.basicButtonHeight - 8) / 28))).maxLines(1).fontColor($r('app.color.key_text'))
      }
    }
    .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'), this.backgroundKeyOpacity, this.backgroundThemeVersion))
    .borderRadius(4)
    .onClick(() => {
      if (this.keyValue === MenuKey.NUMBER_KEY) {
        keyboardHaptics.key();
        this.menuType = MenuType.NUMBER;
      } else if (this.keyValue === MenuKey.SPECIAL_KEY) {
        keyboardHaptics.key();
        this.menuType = MenuType.SPECIAL;
      }
    })
    .height('100%')
    .width(this.inputStyle.switchButtonWidth)
    .shadow({ radius: 1, color: $r('app.color.shadow'), offsetY: 3 })
    .stateStyles({
      normal: normalStyles, pressed: pressedStyles
    })
  }
}
