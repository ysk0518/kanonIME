import { gamingControlPressed, gamingKeyColor, gamingKeyOutline, gamingKeyCenter, gamingKeyTint } from '../common/GamingKeyFeedback';
import { GamingPoint } from '../common/GamingEffectModel';
import { backgroundKeyColor } from '../common/KeyboardBackground';
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
import { keyRollover } from '../common/KeyRollover';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';

import { enterKeyLabel } from '../model/KeyboardKeyLabels';

@Styles function pressedStyles() {
  .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray_pressed'), AppStorage.get<number>('kanonBackgroundKeyOpacity') ?? 100))
}

@Styles function normalStyles() {
  .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'), AppStorage.get<number>('kanonBackgroundKeyOpacity') ?? 100))
}

// 返回组件
@Component
export struct ReturnItem {
  @StorageProp('kanonGamingPhase') gamingPhase: number = -1;
  @StorageProp('kanonGamingWaveTime') gamingTime: number = 0;
  @State private gamingCenter: GamingPoint | undefined = undefined;
  @State private gamingPressed: boolean = false;
  @StorageLink('kanonBackgroundKeyOpacity') backgroundKeyOpacity: number = 100;
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  @StorageLink('enterKeyType') enterKeyType: number = 0;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('kanonEnglishComposing') englishComposing: boolean = false;
  @Prop returnWidth: number | string = 72;
  keyId: string = 'returnItem';
  flick: boolean = false;

  private label(): string {
    return enterKeyLabel(this.enterKeyType, this.englishComposing);
  }

  build() {
    if (this.returnWidth) {
      Stack() {
        if (this.label() === '改行' || this.label() === '検索') {
          Image($rawfile(this.label() === '検索' ? 'search.svg' : 'return.svg'))
            .fillColor(gamingKeyColor(this.gamingPhase, this.gamingTime, this.gamingCenter, $r('app.color.key_text')))
            .width(this.inputStyle.returnPicSize).height(this.inputStyle.returnPicSize)
        } else {
          Text(this.label())
            .minFontSize(8).maxFontSize(this.inputStyle.symbol_fontSize).maxFontScale(1.25)
            .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(gamingKeyColor(this.gamingPhase, this.gamingTime, this.gamingCenter, $r('app.color.key_text')))
        }
      }
      .backgroundColor(backgroundKeyColor($r('app.color.key_item_gray'), this.backgroundKeyOpacity, this.backgroundThemeVersion))
      .width(this.returnWidth)
      .borderRadius(this.flick ? 6 : 4)
      .outline(gamingKeyOutline(this.gamingPhase, this.gamingTime, this.gamingCenter, this.flick ? 6 : 4, this.gamingPressed))
      .linearGradient(gamingKeyTint(this.gamingTime, this.gamingCenter))
      .onAreaChange((_old: Area, area: Area) => { this.gamingCenter = gamingKeyCenter(area); })
      .height('100%')
      .accessibilityText(this.englishComposing ? '確定' : this.label())
      .id(this.keyId)
      .shadow({ radius: this.flick ? 0 : 1, color: $r('app.color.shadow'), offsetY: 3 })
      .onTouch((event: TouchEvent) => {
        this.gamingPressed = gamingControlPressed(event, this.gamingPhase, this.gamingPressed);
      })
      .onClick(() => {
        keyRollover.land();
        kanonIme.keyReturn();
      })
      .stateStyles({
        normal: normalStyles, pressed: pressedStyles
      })
    }
  }
}
