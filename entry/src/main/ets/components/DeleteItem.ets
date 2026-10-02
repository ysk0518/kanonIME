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
  .backgroundColor($r('app.color.key_item_gray_pressed'))
}

@Styles function normalStyles() {
  .backgroundColor($r('app.color.key_item_gray'))
}

// タップで1文字削除。長押しでは間隔を短縮し、前の削除が完了してから次を送る。
@Component
export struct DeleteItem {
  keyWidth: Resource | string | undefined = undefined;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  private pressing: boolean = false;
  private busy: boolean = false;
  private pressStarted: number = 0;
  private repeatTimer: number = -1;

  aboutToDisappear(): void { this.stopRepeat(); }

  private stopRepeat(): void {
    this.pressing = false;
    if (this.repeatTimer >= 0) {
      clearTimeout(this.repeatTimer);
      this.repeatTimer = -1;
    }
  }

  private scheduleRepeat(delayMs: number): void {
    if (this.repeatTimer >= 0) {
      clearTimeout(this.repeatTimer);
    }
    this.repeatTimer = setTimeout(() => {
      this.repeatTimer = -1;
      this.repeatOnce();
    }, delayMs);
  }

  private async deleteOnce(feedback: boolean): Promise<void> {
    this.busy = true;
    try { await kanonIme.keyDelete(feedback); }
    catch (e) { this.stopRepeat(); }
    finally { this.busy = false; }
  }

  private async repeatOnce(): Promise<void> {
    if (!this.pressing) {
      return;
    }
    if (this.busy) {
      this.scheduleRepeat(25);
      return;
    }
    await this.deleteOnce(false);
    if (!this.pressing) {
      return;
    }
    const heldMs: number = Date.now() - this.pressStarted;
    const delayMs: number = Math.max(40, 120 - Math.floor(Math.max(0, heldMs - 250) / 15));
    this.scheduleRepeat(delayMs);
  }

  build() {
    Stack() {
      Image($rawfile('delete.svg'))
            .fillColor($r('app.color.key_text'))
        .width(this.inputStyle.featurePicSize)
        .height(this.inputStyle.featurePicSize)
    }
    .backgroundColor($r('app.color.key_item_gray'))
    .borderRadius(4)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        if (this.pressing) {
          return;
        }
        this.pressing = true;
        this.pressStarted = Date.now();
        this.deleteOnce(true);
        this.scheduleRepeat(250);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.stopRepeat();
      }
    })
    .width(this.keyWidth ?? this.inputStyle.switchButtonWidth)
    .height('100%')
    .id('deleteItem')
    .shadow({ radius: 1, color: $r('app.color.shadow'), offsetY: 3 })
    .stateStyles({
      normal: normalStyles, pressed: pressedStyles
    })
  }
}
