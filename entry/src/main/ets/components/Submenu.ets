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
import InputMethodExtensionContext from '@ohos.InputMethodExtensionContext';
import { openKeyboardSettings } from '../common/SettingsLauncher';

@Preview
@Component
export struct Submenu {
  @StorageLink('submenuType') submenuType: number = SubMenuType.NORMAL;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @State private settingsError: boolean = false;

  private async showSettings(background: boolean = false): Promise<void> {
    const context: InputMethodExtensionContext = this.getUIContext().getHostContext() as InputMethodExtensionContext;
    if (await openKeyboardSettings(context, background)) {
      this.settingsError = false;
      this.submenuType = SubMenuType.NORMAL;
    } else { this.settingsError = true; }
  }

  // Samsung Keyboard's "more" panel: round icons with names in a grid.
  @Builder
  item(icon: Resource, label: string, key: string, action: () => void) {
    Column({ space: 8 }) {
      Stack() {
        Image(icon).width(24).height(24).fillColor($r('app.color.key_text'))
      }
      .width(52).height(52).borderRadius(26)
      .backgroundColor($r('app.color.key_item_normal'))
      Text(label).fontColor($r('app.color.text_normal')).maxFontSize(13).minFontSize(9)
        .maxLines(1).heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
        .textAlign(TextAlign.Center).width('100%')
    }
    .width('100%').padding({ top: 12, bottom: 4 })
    .alignItems(HorizontalAlign.Center)
    .onClick(action)
    .accessibilityText(label)
    .id(key)
  }

  build() {
    Column() {
      Grid() {
        GridItem() { this.item($r('app.media.ic_gear'), '設定', 'keyboardSettings', () => { this.showSettings(); }) }
        GridItem() {
          this.item($r('app.media.ic_globe'), '使用する言語', 'keyboardLanguageSettings',
            () => { this.submenuType = SubMenuType.SETTINGS; })
        }
        GridItem() {
          this.item($r('app.media.ic_resize'), 'サイズ', 'keyboardSizeSettings', () => { this.submenuType = SubMenuType.SIZE; })
        }
        GridItem() {
          this.item($r('app.media.ic_image'), '背景画像', 'keyboardBackgroundSettings', () => { this.showSettings(true); })
        }
        GridItem() {
          this.item($r('app.media.ic_clipboard'), 'クリップボード', 'clipboard_open',
            () => { this.submenuType = SubMenuType.CLIPBOARD; })
        }
        GridItem() {
          this.item($r('app.media.ic_edit'), 'テキスト編集', 'btnEdit', () => { this.submenuType = SubMenuType.EDIT; })
        }
      }
      .width('100%')
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .rowsGap(8)
      .padding({ left: 8, right: 8, top: 8 })
      if (this.settingsError) {
        Text('設定を開けませんでした。アプリアイコンから設定を開けます。')
          .fontSize(12).fontColor($r('app.color.text_error')).padding(8)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.menu_background'))
  }
}
