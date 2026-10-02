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
import Log from '../model/Log';
import { EditView } from '../components/EditView';
import { InputHandler } from '../model/KeyboardController';
import {
  MenuType,
  SubMenuType,
  keySourceListData,
  numberSourceListData,
  symbolSourceListData,
  keySourceListType,
  sourceListType
} from '../model/KeyboardKeyData';
import { KeyMenu } from '../components/KeyMenu';
import { FlickMenu } from '../components/FlickMenu';
import { NumberMenu } from '../components/NumberMenu';
import { NumberFlickMenu } from '../components/NumberFlickMenu';
import { StyleConfiguration, KeyStyle } from '../common/StyleConfiguration';
import { SymbolMenu } from '../components/SymbolMenu';
import { Submenu } from '../components/Submenu';
import { CandidateBar } from '../components/CandidateBar';
import { TopMenu } from '../components/TopMenu';
import { ClipboardPanel } from '../components/ClipboardPanel';
import { KeyboardSettings } from '../components/KeyboardSettings';
import { FlickPreview } from '../components/FlickPreview';
import { kanonIme } from '../kanon/KanonIme';
import { DEFAULT_LAYOUT_ORDER } from '../common/KeyboardConfig';

const TAG: string = 'index->';

@Entry
@Component
struct Index {
  @StorageLink('kanonToolbarHeight') @Watch('updateMeasuredStyle') toolbarHeight: number = 44;
  private measuredWidth: number = 0;
  private measuredHeight: number = 0;
  @StorageLink('kanonLayout') layout: string = 'jp_flick';
  @StorageLink('kanonLayoutOrder') @Watch('configChanged') layoutOrder: string = DEFAULT_LAYOUT_ORDER;
  @StorageLink('kanonMode') mode: string = 'JP';
  @Provide menuType: number = MenuType.NORMAL;
  @StorageLink('kanonCandidatesExpanded') candidatesExpanded: boolean = false;
  @StorageLink('inputPattern') @Watch('inputPatternChange') inputPattern: InputType = InputType.Normal
  @StorageLink('submenuType') submenuType: number = SubMenuType.NORMAL;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();

  onBackPress(): boolean {
    Log.showInfo(TAG, 'kikaInput onBackPress');
    this.submenuType = SubMenuType.NORMAL;
    InputHandler.getInstance().hideKeyboardSelf();
    return true;
  }

  inputPatternChange(): void {
    if (this.inputPattern === InputType.Number || this.inputPattern === InputType.PhoneNumber ||
      this.inputPattern === InputType.NUMBER_PASSWORD) {
      this.menuType = MenuType.NUMBER;
    } else {
      this.menuType = MenuType.NORMAL;
    }
  }

  configChanged(): void { kanonIme.prepare(); }

  aboutToAppear(): void {
    this.inputPatternChange();
    kanonIme.prepare();
  }

  private updateMeasuredStyle(): void {
    if (this.measuredWidth <= 0 || this.measuredHeight <= 0) { return; }
    const width: number = Math.min(720, this.measuredWidth);
    const height: number = Math.max(1, this.measuredHeight - this.toolbarHeight);
    if (Math.abs(this.inputStyle.subMenuWidth - width) > 0.5 || Math.abs(this.inputStyle.keyboardHeight - height) > 0.5) {
      AppStorage.setOrCreate('inputStyle', StyleConfiguration.getInputStyle(width, height));
    }
  }

  build() {
    Stack() {
      Column() {
        if (this.submenuType === SubMenuType.NORMAL) {
          CandidateBar()
        } else {
          TopMenu()
        }
        Column() {
          if (this.submenuType > SubMenuType.NORMAL) {
            if (this.submenuType === SubMenuType.MENU) {
              Submenu()
            } else if (this.submenuType === SubMenuType.EDIT) {
              EditView();
            } else if (this.submenuType === SubMenuType.CLIPBOARD) {
              ClipboardPanel()
            } else if (this.submenuType === SubMenuType.SETTINGS) {
              KeyboardSettings({ languageOnly: true, onClose: () => { this.submenuType = SubMenuType.NORMAL; } })
            } else {
              Submenu()
            }
          } else if (!this.candidatesExpanded) {
            if (this.menuType === MenuType.NORMAL) {
              if (this.layout === 'jp_flick' || this.layout === 'en_flick') { FlickMenu() }
              else { KeyMenu() }
            } else if (this.menuType === MenuType.NUMBER) {
              if (this.layout === 'jp_flick' || this.layout === 'en_flick') { NumberFlickMenu() }
              else { NumberMenu() }
            } else {
              SymbolMenu()
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.keyboard_background'))
      }
      .height('100%')
      .width('100%')
      if (this.submenuType === SubMenuType.NORMAL) { FlickPreview() }
    }
    .height('100%')
    .width('100%')
    .onAreaChange((_old: Area, area: Area) => {
      this.measuredWidth = Number(area.width);
      this.measuredHeight = Number(area.height);
      this.updateMeasuredStyle();
    })
    .backgroundColor($r('app.color.key_item_normal'))
  }
}
