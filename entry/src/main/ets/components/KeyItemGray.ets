import { photoKeyColor } from '../common/KeyboardKeyPalette';
import { gamingControlPressed, gamingKeyColor, gamingKeyOutline, gamingKeyCenter, gamingKeyTint } from '../common/GamingKeyFeedback';
import { GamingPoint } from '../common/GamingEffectModel';
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
import { keyboardHaptics } from '../common/KeyboardHaptics';
import { keyRollover } from '../common/KeyRollover';

// 无大小写的灰色组件
@Component
export struct KeyItemGray {
  @StorageProp('kanonBackgroundHasPhoto') hasBackgroundPhoto: boolean = false;
  photoThemeEnabled: boolean = true;
  @StorageProp('kanonGamingPhase') gamingPhase: number = -1;
  @StorageProp('kanonGamingWaveTime') gamingTime: number = 0;
  @State private gamingCenter: GamingPoint | undefined = undefined;
  @State private gamingPressed: boolean = false;
  @StorageLink('kanonBackgroundKeyOpacity') backgroundKeyOpacity: number = 100;
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  @Prop keyValue: string = '';
  keyId: string = '';
  keyWidth: string | undefined = undefined;
  onActivate: (() => void) | undefined = undefined;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();

  @Styles pressedStyles() {
    .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray_pressed'),
      this.backgroundKeyOpacity, this.backgroundThemeVersion, this.photoThemeEnabled && this.hasBackgroundPhoto))
  }

  @Styles normalStyles() {
    .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'),
      this.backgroundKeyOpacity, this.backgroundThemeVersion, this.photoThemeEnabled && this.hasBackgroundPhoto))
  }

  build() {
    Stack() {
      Text(this.keyValue)
        .minFontSize(8).maxFontSize(this.inputStyle.switchNumberFontSize).maxFontScale(1)
        .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(gamingKeyColor(this.gamingPhase, this.gamingTime, this.gamingCenter, photoKeyColor($r('app.color.key_text'), this.photoThemeEnabled && this.hasBackgroundPhoto)))
    }
    .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'),
      this.backgroundKeyOpacity, this.backgroundThemeVersion, this.photoThemeEnabled && this.hasBackgroundPhoto))
    .borderRadius(4)
    .outline(gamingKeyOutline(this.gamingPhase, this.gamingTime, this.gamingCenter, 4, this.gamingPressed))
    .linearGradient(gamingKeyTint(this.gamingTime, this.gamingCenter))
    .onAreaChange((_old: Area, area: Area) => { this.gamingCenter = gamingKeyCenter(area); })
    .onTouch((event: TouchEvent) => {
      this.gamingPressed = gamingControlPressed(event, this.gamingPhase, this.gamingPressed);
    })
    .onClick(() => {
      keyRollover.land();
      keyboardHaptics.key();
      this.onActivate?.();
    })
    .height('100%')
    .width(this.keyWidth ?? this.inputStyle.switchButtonWidth)
    .id(this.keyId)
    .shadow({ radius: 1, color: photoKeyColor($r('app.color.shadow'), this.photoThemeEnabled && this.hasBackgroundPhoto), offsetY: 3 })
    .stateStyles({
      normal: this.normalStyles, pressed: this.pressedStyles
    })
  }
}
