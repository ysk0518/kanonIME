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
import { SubMenuType } from '../model/KeyboardKeyData';

@Preview
@Component
export struct Submenu {
  @StorageLink('submenuType') submenuType: number = SubMenuType.NORMAL;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();

  build() {
    Grid() {
      GridItem() {
        Text('設定')
          .fontColor($r('app.color.text_normal'))
          .fontSize(this.inputStyle.editFontSize)
          .width('100%')
          .height('50%')
          .textAlign(TextAlign.Center)
          .id('keyboardSettings')
          .onClick(() => { this.submenuType = SubMenuType.SETTINGS; })
      }
      GridItem() {
        Column({ space: 8 }) {
          Text('クリップボード')
            .fontColor($r('app.color.text_normal'))
            .fontSize(this.inputStyle.editFontSize)
          Image($r('app.media.ic_clipboard'))
            .fillColor($r('app.color.key_text'))
            .width(24).height(24)
        }
        .width('100%')
        .height('50%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.submenuType = SubMenuType.CLIPBOARD; })
        .id('clipboard_open')
      }
      GridItem() {
        Column() {
          Image($r('app.media.ic_edit'))
            .fillColor($r('app.color.key_text'))
            .size({ width: this.inputStyle.editPicSize, height: this.inputStyle.editPicSize })
            .objectFit(ImageFit.Cover)
          Text($r('app.string.edit'))
            .fontColor($r('app.color.text_normal'))
            .fontSize(this.inputStyle.editFontSize)
            .opacity(0.6)
            .margin({ top: 8 })
        }
        .width('100%')
        .height('50%')
        .justifyContent(FlexAlign.Center)
        .id('btnEdit')
        .onClick(() => {
          this.submenuType = SubMenuType.EDIT;
        })
      }
      GridItem() {
        Column() {
          Text('G-01')
            .fontColor($r('app.color.text_normal'))
            .fontSize(this.inputStyle.editFontSize)
            .opacity(0.6)
            .margin({ top: 8 })
        }
        .width('100%')
        .height('50%')
        .justifyContent(FlexAlign.Center)
        .id('btnG01')
        .onClick(() => {
          this.submenuType = SubMenuType.G01;
        })
      }
      GridItem() {
        Column() {
          Text('M2')
            .fontColor($r('app.color.text_normal'))
            .fontSize(this.inputStyle.editFontSize)
            .opacity(0.6)
            .margin({ top: 8 })
        }
        .width('100%')
        .height('50%')
        .justifyContent(FlexAlign.Center)
        .id('btnM2')
        .onClick(() => {
          this.submenuType = SubMenuType.M2;
        })
      }
      GridItem() {
        Column() {
          Text('M3')
            .fontColor($r('app.color.text_normal'))
            .fontSize(this.inputStyle.editFontSize)
            .opacity(0.6)
            .margin({ top: 8 })
        }
        .width('100%')
        .height('50%')
        .justifyContent(FlexAlign.Center)
        .id('btnM3')
        .onClick(() => {
          this.submenuType = SubMenuType.M3;
        })
      }
    }
    .width('100%')
    .height('100%')
    .columnsTemplate('1fr 1fr 1fr')
    .columnsGap(12)
    .rowsGap(12)
    .backgroundColor($r('app.color.menu_background'))
  }
}
