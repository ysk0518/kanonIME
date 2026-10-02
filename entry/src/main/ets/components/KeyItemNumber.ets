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
import { KeyState, keySourceListType } from '../model/KeyboardKeyData';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { DEFAULT_LONG_PRESS_MS } from '../common/KeyboardConfig';
import { showKeyPreview, hideKeyPreview } from '../common/KeyPreviewState';
import { editorAdapter } from '../kanon/EditorAdapter';

// 有大小写的按键组件
@Component
export struct KeyItemNumber {
  @StorageLink('kanonLongPressMs') longPressMs: number = DEFAULT_LONG_PRESS_MS;
  @StorageLink('kanonFlickPreviewEnabled') @Watch('previewSettingChanged') previewEnabled: boolean = true;
  @StorageLink('kanonLayout') @Watch('cancelTouch') layout: string = 'en_qwerty';
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @Consume keyState: number;
  keyValue: keySourceListType | undefined = undefined;
  @State private active: boolean = false;
  private finger: number = -1;
  private longPressTimer: number = -1;
  private longPressed: boolean = false;
  private pendingText: string = '';
  private alternateText: string = '';
  private startKeyState: number = KeyState.LOWER_CASE;
  private startEpoch: number = -1;
  private keyWidth: number = 0;
  private keyHeight: number = 0;
  private previewX: number = 0;
  private previewY: number = 0;
  private previewOwner: string = '';

  private clearLongPress(): void {
    if (this.longPressTimer >= 0) {
      clearTimeout(this.longPressTimer);
      this.longPressTimer = -1;
    }
  }

  private showPreview(): void {
    if (!this.previewEnabled) { hideKeyPreview(this.previewOwner); return; }
    showKeyPreview(this.previewOwner, this.pendingText, this.previewX, this.previewY, 'qwerty');
  }

  private previewSettingChanged(): void {
    if (!this.previewEnabled) { hideKeyPreview(this.previewOwner); }
    else if (this.finger >= 0) { this.showPreview(); }
  }

  private cancelTouch(): void {
    this.clearLongPress();
    hideKeyPreview(this.previewOwner);
    this.finger = -1;
    this.active = false;
    this.pendingText = '';
    this.alternateText = '';
    this.longPressed = false;
  }

  aboutToDisappear(): void { this.cancelTouch(); }

  private touch(event: TouchEvent): void {
    if (event.type === TouchType.Cancel) { this.cancelTouch(); return; }
    if (event.type === TouchType.Down && this.finger < 0 && event.changedTouches.length > 0 && this.keyValue) {
      const touch: TouchObject = event.changedTouches[0];
      this.finger = touch.id;
      this.active = true;
      this.longPressed = false;
      this.startEpoch = editorAdapter.getEpoch();
      this.startKeyState = this.keyState;
      this.pendingText = this.keyState === KeyState.LOWER_CASE ? this.keyValue.content : this.keyValue.upperContent;
      this.alternateText = this.keyValue.title;
      this.previewOwner = `qwerty:${this.keyValue.content}:${touch.id}`;
      this.previewX = touch.windowX - touch.x + this.keyWidth / 2;
      this.previewY = touch.windowY - touch.y - 64;
      this.showPreview();
      this.clearLongPress();
      this.longPressTimer = setTimeout(() => {
        this.longPressTimer = -1;
        if (this.finger < 0) { return; }
        if (this.startEpoch !== editorAdapter.getEpoch()) { this.cancelTouch(); return; }
        this.longPressed = true;
        this.pendingText = this.alternateText;
        this.showPreview();
      }, this.longPressMs);
      return;
    }
    for (const touch of event.changedTouches) {
      if (touch.id !== this.finger) { continue; }
      if (event.type !== TouchType.Up) { continue; }
      const value: string = this.pendingText;
      const currentEditor: boolean = this.startEpoch === editorAdapter.getEpoch();
      const consumeShift: boolean = !this.longPressed && this.startKeyState === KeyState.ONCE_UPPER_CASE;
      this.cancelTouch();
      if (!currentEditor || value.length === 0) { return; }
      if (consumeShift && this.keyState === KeyState.ONCE_UPPER_CASE) { this.keyState = KeyState.LOWER_CASE; }
      kanonIme.keyText(value);
      return;
    }
  }

  build() {
    Flex({ direction: FlexDirection.Column, alignItems: ItemAlign.Center, justifyContent: FlexAlign.Center }) {
      if (this.inputStyle.basicButtonHeight < 44 && this.keyValue) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Text(this.keyState === KeyState.LOWER_CASE ? this.keyValue.content : this.keyValue.upperContent)
            .fontSize(this.inputStyle.en_fontSize).maxFontScale(Math.max(1, Math.min(1.5, (this.inputStyle.basicButtonHeight - 8) / 28))).maxLines(1)
            .fontColor($r('app.color.key_text'))
            .fontWeight(FontWeight.Regular)
            .width('100%')
            .height('100%')
            .textAlign(TextAlign.Center)
          Text(this.keyValue.title)
            .fontSize(this.inputStyle.litterNumberFontSize).maxFontScale(Math.max(1, Math.min(1.5, (this.inputStyle.basicButtonHeight - 8) / 28))).maxLines(1)
            .fontColor($r('app.color.key_text'))
            .fontWeight(FontWeight.Regular)
            .width('12vp')
            .height('12vp')
            .textAlign(TextAlign.Center)
            .margin({ top: 1, right: 1 })
        }
        .width('100%')
        .height('100%')
      } else if (this.keyValue) {
        Text(this.keyValue.title)
          .fontSize(this.inputStyle.litterNumberFontSize).maxFontScale(Math.max(1, Math.min(1.5, (this.inputStyle.basicButtonHeight - 8) / 28))).maxLines(1)
          .fontColor($r('app.color.key_item_normal_text'))
          .fontWeight(FontWeight.Regular)
          .margin({ top: 4 })
        Text(this.keyState === KeyState.LOWER_CASE ? this.keyValue.content : this.keyValue.upperContent)
          .fontSize(this.inputStyle.en_fontSize).maxFontScale(Math.max(1, Math.min(1.5, (this.inputStyle.basicButtonHeight - 8) / 28))).maxLines(1)
          .fontColor($r('app.color.key_text'))
          .fontWeight(FontWeight.Regular)
      }
    }
    .backgroundColor(this.active ? $r('app.color.key_item_normal_pressed') : $r('app.color.key_item_normal'))
    .borderRadius(4)
    .onTouch((event: TouchEvent) => this.touch(event))
    .onAreaChange((_old: Area, area: Area) => {
      const width: number = Number(area.width);
      const height: number = Number(area.height);
      if (this.finger >= 0 && (Math.abs(width - this.keyWidth) > 0.5 || Math.abs(height - this.keyHeight) > 0.5)) {
        this.cancelTouch();
      }
      this.keyWidth = width;
      this.keyHeight = height;
    })
    .width(this.inputStyle.basicButtonWidth)
    .height('100%')
    .shadow({ radius: 1, color: $r('app.color.shadow'), offsetY: 3 })
  }
}
