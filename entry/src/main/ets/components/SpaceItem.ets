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

import { kanonIme } from '../kanon/KanonIme';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { DEFAULT_LONG_PRESS_MS } from '../common/KeyboardConfig';
import { editorAdapter } from '../kanon/EditorAdapter';
import { keyboardHaptics } from '../common/KeyboardHaptics';
import inputMethodEngine from '@ohos.inputMethodEngine';

const SPACE_DRAG_STEP: number = 18;
const SPACE_TAP_SLOP: number = 12;

// 空格组件
@Component
export struct SpaceItem {
  @StorageLink('kanonBackgroundKeyOpacity') backgroundKeyOpacity: number = 100;
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  spaceWith: Resource | string | undefined = undefined;
  @StorageLink('inputStyle') @Watch('cancelTouch') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('kanonMode') @Watch('cancelTouch') imeMode: string = 'JP';
  @StorageLink('kanonLayout') @Watch('cancelTouch') layout: string = 'jp_qwerty';
  @StorageLink('kanonKeyboardVisible') @Watch('cancelTouch') keyboardVisible: boolean = false;
  @StorageLink('kanonLongPressMs') longPressMs: number = DEFAULT_LONG_PRESS_MS;
  @StorageLink('kanonConversionReading') conversionReading: string = '';
  @StorageLink('kanonList') candidates: string[] = [];
  @State private pressing: boolean = false;
  @State private dragging: boolean = false;
  private finger: number = -1;
  private startEpoch: number = -1;
  private holdTimer: number = -1;
  private startX: number = 0;
  private startY: number = 0;
  private latestX: number = 0;
  private dragOriginX: number = 0;
  private sentSteps: number = 0;

  private cancelTouch(): void {
    if (this.holdTimer >= 0) { clearTimeout(this.holdTimer); this.holdTimer = -1; }
    this.pressing = false;
    this.dragging = false;
    this.finger = -1;
    this.startEpoch = -1;
    this.sentSteps = 0;
  }

  aboutToDisappear(): void { this.cancelTouch(); }

  private dragTo(x: number): void {
    if (!this.dragging || this.startEpoch !== editorAdapter.getEpoch()) { this.cancelTouch(); return; }
    const target: number = Math.trunc((x - this.dragOriginX) / SPACE_DRAG_STEP);
    const delta: number = target - this.sentSteps;
    if (delta === 0) { return; }
    const step: number = delta < 0 ? -1 : 1;
    const direction: number = step < 0 ? inputMethodEngine.CURSOR_LEFT : inputMethodEngine.CURSOR_RIGHT;
    keyboardHaptics.key();
    // Submit movement in touch order through the existing IME serial queue.
    for (let count: number = 0; count < Math.min(16, Math.abs(delta)); count++) {
      this.sentSteps += step;
      kanonIme.keyMove(direction, false).catch(() => this.cancelTouch());
    }
  }

  private touch(event: TouchEvent): void {
    if (event.type === TouchType.Cancel) { this.cancelTouch(); return; }
    if (event.type === TouchType.Down && this.finger < 0 && event.changedTouches.length > 0) {
      const point: TouchObject = event.changedTouches[0];
      this.finger = point.id;
      this.startEpoch = editorAdapter.getEpoch();
      this.startX = point.windowX;
      this.startY = point.windowY;
      this.latestX = point.windowX;
      this.pressing = true;
      this.dragging = false;
      this.sentSteps = 0;
      this.holdTimer = setTimeout(() => {
        this.holdTimer = -1;
        if (!this.pressing || this.startEpoch !== editorAdapter.getEpoch()) { this.cancelTouch(); return; }
        this.dragging = true;
        this.dragOriginX = this.latestX;
        keyboardHaptics.key();
      }, this.longPressMs);
      return;
    }
    for (const point of event.changedTouches) {
      if (point.id !== this.finger) { continue; }
      if (this.startEpoch !== editorAdapter.getEpoch()) { this.cancelTouch(); return; }
      this.latestX = point.windowX;
      if (!this.dragging && Math.max(Math.abs(point.windowX - this.startX),
        Math.abs(point.windowY - this.startY)) > SPACE_TAP_SLOP) {
        this.cancelTouch();
        return;
      }
      if (this.dragging && (event.type === TouchType.Move || event.type === TouchType.Up)) {
        this.dragTo(point.windowX);
      }
      if (event.type === TouchType.Up) {
        const tap: boolean = !this.dragging && this.pressing;
        this.cancelTouch();
        if (tap) { kanonIme.keySpace(); }
      }
      return;
    }
  }

  build() {
    if (this.spaceWith) {
      Stack() {
        Text(this.dragging ? (this.imeMode === 'JP' && this.conversionReading.length > 0 ?
          $r('app.string.keyboard_space_drag_range') : $r('app.string.keyboard_space_drag_cursor')) :
          this.imeMode === 'EN' && this.candidates.length > 0 ? $r('app.string.keyboard_convert') : 'space')
          .fontSize(this.dragging ? 14 : this.inputStyle.symbol_fontSize)
          .maxFontScale(Math.max(1, Math.min(1.5, (this.inputStyle.basicButtonHeight - 8) / 28))).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('app.color.key_text'))
      }
      .backgroundColor(backgroundKeyColor(this.pressing ? $r('app.color.key_item_normal_pressed') :
        $r('app.color.key_item_normal'), this.backgroundKeyOpacity, this.backgroundThemeVersion))
      .width(this.spaceWith)
      .borderRadius(4)
      .height('100%')
      .id('spaceItem')
      .onTouch((event: TouchEvent) => this.touch(event))
      .accessibilityText($r('app.string.keyboard_space_drag_help'))
      .shadow({ radius: 1, color: $r('app.color.shadow'), offsetY: 3 })
    }
  }
}
