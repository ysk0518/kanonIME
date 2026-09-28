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

import { kanonIme } from '../kanon/KanonIme';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';

@Styles function pressedStyles() {
  .backgroundColor($r('app.color.key_item_normal_pressed'))
}

@Styles function normalStyles() {
  .backgroundColor($r('app.color.key_item_normal'))
}

// 空格组件
@Component
export struct SpaceItem {
  private spaceWith: Resource | string | undefined = undefined;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('kanonMode') mode: string = 'JP';
  private langSwitched: boolean = false;

  build() {
    if (this.spaceWith) {
      Stack() {
        Row() {
          Text('space')
            .fontSize(this.inputStyle.symbol_fontSize).maxFontScale(Math.max(1, Math.min(1.5, (this.inputStyle.basicButtonHeight - 8) / 28))).maxLines(1)
            .fontColor($r('app.color.key_text'))
          Text(this.mode === 'JP' ? 'あ' : 'A')
            .fontSize(10)
            .fontColor($r('app.color.key_item_normal_text'))
            .margin({ left: 4 })
        }
      }
      .backgroundColor($r('app.color.key_item_normal'))
      .width(this.spaceWith)
      .borderRadius(4)
      .height('100%')
      .id('spaceItem')
      .onClick(() => {
        if (this.langSwitched) {
          this.langSwitched = false;
          return;
        }
        kanonIme.keySpace();
      })
      .gesture(
        LongPressGesture({ duration: 250 })
          .onAction(() => {
            this.langSwitched = true;
            kanonIme.switchMode();
          })
      )
      .shadow({ radius: 1, color: $r('app.color.shadow'), offsetY: 3 })
      .stateStyles({
        normal: normalStyles, pressed: pressedStyles
      })
    }
  }
}
