// Modified for kanonIME by ysk0518 and contributors, 2026.
/*
 * Copyright (c) 2023-2024 Huawei Device Co., Ltd.
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

import { kanonIme } from '../kanon/KanonIme';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';

enum EntryKey {
  Send = 'Send',
  Search = 'Search',
  Go = 'Go'
}

@Styles function pressedStyles() {
  .backgroundColor($r('app.color.key_item_gray_pressed'))
}

@Styles function normalStyles() {
  .backgroundColor($r('app.color.key_item_gray'))
}

// 返回组件
@Component
export struct ReturnItem {
  @StorageLink('enterKeyType') enterKeyType: EnterKeyType = EnterKeyType.Done
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @Prop returnWidth: number = 72;

  build() {
    if (this.returnWidth) {
      Stack() {
        if (this.enterKeyType === EnterKeyType.Send) {
          Text(EntryKey.Send)
            .fontSize(this.inputStyle.symbol_fontSize).maxFontScale(Math.max(1, Math.min(1.5, (this.inputStyle.basicButtonHeight - 8) / 28))).maxLines(1)
            .fontColor($r('app.color.key_text'))
        } else if (this.enterKeyType === EnterKeyType.Search) {
          Text(EntryKey.Search)
            .fontSize(this.inputStyle.symbol_fontSize).maxFontScale(Math.max(1, Math.min(1.5, (this.inputStyle.basicButtonHeight - 8) / 28))).maxLines(1)
            .fontColor($r('app.color.key_text'))
        } else if (this.enterKeyType === EnterKeyType.Go) {
          Text(EntryKey.Go)
            .fontSize(this.inputStyle.symbol_fontSize).maxFontScale(Math.max(1, Math.min(1.5, (this.inputStyle.basicButtonHeight - 8) / 28))).maxLines(1)
            .fontColor($r('app.color.key_text'))
        } else {
          Image($rawfile('return.svg'))
            .fillColor($r('app.color.key_text'))
            .width(this.inputStyle.returnPicSize)
            .height(this.inputStyle.returnPicSize)
        }
      }
      .backgroundColor($r('app.color.key_item_gray'))
      .width(this.returnWidth)
      .borderRadius(4)
      .height('100%')
      .id('returnItem')
      .shadow({ radius: 1, color: $r('app.color.shadow'), offsetY: 3 })
      .onClick(() => {
        kanonIme.keyReturn();
      })
      .stateStyles({
        normal: normalStyles, pressed: pressedStyles
      })
    }
  }
}
