// Modified for kanonIME by ysk0518 and contributors, 2026.
/*
 * Copyright (c) 2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the 'License');
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an 'AS IS' BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { keyVisualScale } from './KeyboardLayout';

export interface KeyStyle {
  deviceType?: string,
  basicButtonWidth: number,
  basicButtonHeight: number,
  featurePicSize: number,
  switchButtonWidth: number,
  returnPicSize: number,
  returnButtonWidthType_1: number,
  returnButtonWidthType_2: number,
  spaceButtonWidth_1: number,
  spaceButtonWidth_2: number,
  paddingTop: number,
  paddingLeftRight: number,
  downMenuHeight: number,
  downMenuPicWidth: number,
  downMenuPicHeight: number,
  downMenuWidth: number,
  litterNumberFontSize: number,
  en_fontSize: number,
  symbol_fontSize: number,
  switchNumberFontSize: number,
  number1234ontFSize?: number,
  keyboardHeight: number,
  editPicSize: number,
  editFontSize: number,
  editDriverLeft: number,
  subMenuWidth: number,
  editCircleSize: number,
  editSmallCircle: number,
  editSmallCircleMargin: number,
  editButtonSize: number,
  editImageSize: number
}

export class StyleConfiguration {
  static getSavedInputStyle(): KeyStyle {
    return AppStorage.get<KeyStyle>('inputStyle') ?? StyleConfiguration.getInputStyle(360, 247);
  }

  static getInputStyle(width: number, height: number): KeyStyle {
    const key: number = Math.max(1, (width - 12 - 9 * 6) / 10);
    const row: number = Math.max(1, (height - 12 - 3 * 6) / 4);
    const visualScale: number = keyVisualScale(row);
    const icon: number = Math.min(24, row * 0.6);
    const editSize: number = Math.max(24, Math.min(48, width / 7, (height - 8) / 4));
    return {
      basicButtonWidth: key, basicButtonHeight: row,
      featurePicSize: icon, switchButtonWidth: key * 1.5,
      returnPicSize: icon, returnButtonWidthType_1: key * 2, returnButtonWidthType_2: key * 2,
      spaceButtonWidth_1: key * 3, spaceButtonWidth_2: key * 3,
      paddingTop: 6, paddingLeftRight: 6,
      downMenuHeight: 44, downMenuPicWidth: 24, downMenuPicHeight: 12, downMenuWidth: 40,
      litterNumberFontSize: 9 * visualScale, en_fontSize: 18 * visualScale, symbol_fontSize: 16 * visualScale,
      switchNumberFontSize: 14 * visualScale, number1234ontFSize: 14 * visualScale,
      keyboardHeight: height, editPicSize: 24, editFontSize: 14, editDriverLeft: 8,
      subMenuWidth: width, editCircleSize: editSize * 3,
      editSmallCircle: editSize, editSmallCircleMargin: editSize * 2,
      editButtonSize: editSize, editImageSize: Math.min(24, editSize / 2)
    };
  }
}
