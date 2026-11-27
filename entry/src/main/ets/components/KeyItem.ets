import { gamingKeyColor, gamingKeyOutline, gamingKeyX, gamingPresses } from '../common/GamingKeyFeedback';
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

import { keySourceListType, } from '../model/KeyboardKeyData';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { kanonIme } from '../kanon/KanonIme';
import { editorAdapter } from '../kanon/EditorAdapter';
import { keyboardHaptics } from '../common/KeyboardHaptics';
import { keyRollover } from '../common/KeyRollover';


// 无大小写的按键组件
@Component
export struct KeyItem {
  @StorageProp('kanonGamingPhase') gamingPhase: number = -1;
  @State private gamingX: number = 0;
  @StorageLink('kanonBackgroundKeyOpacity') backgroundKeyOpacity: number = 100;
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  @Prop @Watch('cancelTouch') keyValue: keySourceListType | undefined = undefined;
  kanaInput: boolean = false;
  directInput: boolean = false;
  keyId: string = '';
  keyWidth: number | string | undefined = undefined;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  private finger: number = -1;
  private startEpoch: number = -1;
  private pending: (() => void) | undefined = undefined;
  @State private active: boolean = false;

  private cancelTouch(): void {
    if (this.pending !== undefined) { keyRollover.release(this.pending); }
    this.pending = undefined;
    this.finger = -1;
    this.startEpoch = -1;
    this.active = false;
  }

  aboutToDisappear(): void { this.cancelTouch(); }

  private touch(event: TouchEvent): void {
    if (event.type === TouchType.Cancel) { this.cancelTouch(); return; }
    // A key still held (here or elsewhere) is entered first so fast overlapping presses keep their order.
    if (event.type === TouchType.Down) { keyRollover.land(); }
    if (event.type === TouchType.Down && this.finger < 0 && event.changedTouches.length > 0 && this.keyValue) {
      this.finger = event.changedTouches[0].id;
      this.active = true;
      this.startEpoch = editorAdapter.getEpoch();
      const content: string = this.keyValue.content;
      const epoch: number = this.startEpoch;
      const enter: () => void = (): void => {
        this.active = false;
        this.enterKey(content, epoch);
      };
      this.pending = enter;
      keyRollover.hold(enter);
      keyboardHaptics.press();
      gamingPresses.down(event);
      return;
    }
    for (const touch of event.changedTouches) {
      if (touch.id !== this.finger) { continue; }
      if (event.type !== TouchType.Up) { return; }
      const enter: (() => void) | undefined = this.pending;
      this.pending = undefined;
      this.finger = -1;
      this.active = false;
      if (enter !== undefined && keyRollover.release(enter)) { enter(); }
      return;
    }
  }

  private enterKey(content: string, epoch: number): void {
    if (epoch !== editorAdapter.getEpoch()) { return; }
    if (this.directInput) {
      keyboardHaptics.key();
      kanonIme.keyPaste(content);
    } else if (this.kanaInput) { kanonIme.keyKana(content); }
    else { kanonIme.keyText(content); }
  }

  build() {
    Flex({ direction: FlexDirection.Column, alignItems: ItemAlign.Center, justifyContent: FlexAlign.Center }) {
      if (this.keyValue) {
        Text(this.keyValue.content)
          .minFontSize(8).maxFontSize(this.inputStyle.symbol_fontSize)
          .maxFontScale(Math.max(1, Math.min(1.5, (this.inputStyle.basicButtonHeight - 8) / 28))).maxLines(1)
          .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(gamingKeyColor(this.gamingPhase, this.gamingX, $r('app.color.key_text'), this.active))
      }
    }
    .backgroundColor(backgroundKeyColor(this.active ? $r('app.color.key_item_normal_pressed') : $r('app.color.key_item_normal'), this.backgroundKeyOpacity, this.backgroundThemeVersion))
    .borderRadius(4)
    .outline(gamingKeyOutline(this.gamingPhase, this.gamingX, 4, this.active))
    .onAreaChange((_old: Area, area: Area) => { this.gamingX = gamingKeyX(area); })
    .width(this.keyWidth ?? this.inputStyle.basicButtonWidth)
    .height('100%')
    .shadow({ radius: 1, color: $r('app.color.shadow'), offsetY: 3 })
    .onTouch((event: TouchEvent) => this.touch(event))
    .id(this.keyId.length > 0 ? this.keyId : `qwerty_symbol_${this.keyValue?.content ?? ''}`)
  }
}
