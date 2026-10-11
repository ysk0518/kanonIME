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
import { SpaceGesture, SpaceGesturePort } from '../kanon/SpaceGesture';

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
  private spacePort: SpaceGesturePort = {
    getEpoch: (): number => editorAdapter.getEpoch(),
    schedule: (callback: () => void, delayMs: number): number => setTimeout(callback, delayMs),
    unschedule: (timer: number): void => { clearTimeout(timer); },
    tap: (): void => { kanonIme.keySpace(); },
    move: (direction: string): Promise<void> => kanonIme.keyMove(direction === 'left' ?
      inputMethodEngine.CURSOR_LEFT : inputMethodEngine.CURSOR_RIGHT, false),
    feedback: (): void => { keyboardHaptics.key(); },
    changed: (pressing: boolean, dragging: boolean): void => {
      this.pressing = pressing;
      this.dragging = dragging;
    }
  };
  private spaceGesture: SpaceGesture = new SpaceGesture(this.spacePort);

  private cancelTouch(): void {
    this.spaceGesture.cancel();
  }

  aboutToDisappear(): void { this.cancelTouch(); }

  private touch(event: TouchEvent): void {
    if (event.type === TouchType.Cancel) { this.cancelTouch(); return; }
    if (event.type === TouchType.Down && event.changedTouches.length > 0) {
      const point: TouchObject = event.changedTouches[0];
      this.spaceGesture.down(point.id, point.windowX, point.windowY, this.longPressMs);
      return;
    }
    for (const point of event.changedTouches) {
      this.spaceGesture.contact(point.id, point.windowX, point.windowY, event.type === TouchType.Up);
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
