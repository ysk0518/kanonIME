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

import { keySourceListType, } from '../model/KeyboardKeyData';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { kanonIme } from '../kanon/KanonIme';
import { editorAdapter } from '../kanon/EditorAdapter';


// 无大小写的按键组件
@Component
export struct KeyItem {
  keyValue: keySourceListType | undefined = undefined;
  kanaInput: boolean = false;
  keyId: string = '';
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  private finger: number = -1;
  private startEpoch: number = -1;
  @State private active: boolean = false;

  aboutToDisappear(): void { this.finger = -1; this.active = false; }

  private touch(event: TouchEvent): void {
    if (event.type === TouchType.Cancel) { this.finger = -1; this.active = false; return; }
    if (event.type === TouchType.Down && this.finger < 0 && event.changedTouches.length > 0 && this.keyValue) {
      this.finger = event.changedTouches[0].id;
      this.active = true;
      this.startEpoch = editorAdapter.getEpoch();
      return;
    }
    for (const touch of event.changedTouches) {
      if (touch.id !== this.finger) { continue; }
      if (event.type !== TouchType.Up) { return; }
      this.finger = -1;
      this.active = false;
      if (this.startEpoch !== editorAdapter.getEpoch() || !this.keyValue) { return; }
      if (this.kanaInput) { kanonIme.keyKana(this.keyValue.content); }
      else { kanonIme.keyText(this.keyValue.content); }
      return;
    }
  }

  build() {
    Flex({ direction: FlexDirection.Column, alignItems: ItemAlign.Center, justifyContent: FlexAlign.Center }) {
      if (this.keyValue) {
        Text(this.keyValue.content)
          .fontSize(this.inputStyle.symbol_fontSize).maxFontScale(Math.max(1, Math.min(1.5, (this.inputStyle.basicButtonHeight - 8) / 28))).maxLines(1)
          .fontColor($r('app.color.key_text'))
      }
    }
    .backgroundColor(this.active ? $r('app.color.key_item_normal_pressed') : $r('app.color.key_item_normal'))
    .borderRadius(4)
    .width(this.inputStyle.basicButtonWidth)
    .height('100%')
    .shadow({ radius: 1, color: $r('app.color.shadow'), offsetY: 3 })
    .onTouch((event: TouchEvent) => this.touch(event))
    .id(this.keyId.length > 0 ? this.keyId : `qwerty_symbol_${this.keyValue?.content ?? ''}`)
  }
}
