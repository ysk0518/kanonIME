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

import { DeleteItem } from './DeleteItem';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { KeyItem } from './KeyItem';
import { KeyItemGray } from './KeyItemGray';
import { ReturnItem } from './ReturnItem';
import { MenuType, keySourceListType, symbolPageRows } from '../model/KeyboardKeyData';
import { isUrlInputPattern, urlFieldKeyText } from '../model/KeyboardKeyLabels';
import { DEFAULT_URL_FIELD_KEY } from '../common/UrlFieldKey';
import { SpaceItem } from './SpaceItem';
import { LayoutItem } from './LayoutItem';

// 符号键盘
@Component
export struct SymbolMenu {
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('inputPattern') inputPattern: number = 0;
  @StorageLink('kanonUrlFieldKey') urlFieldKey: string = DEFAULT_URL_FIELD_KEY;
  @StorageLink('kanonFlickEnabled') flickEnabled: boolean = true;
  @Consume menuType: number;
  @State private page: number = 0;

  private comma(): string {
    return isUrlInputPattern(this.inputPattern) ? '/' : ',';
  }

  private urlKeyValue(): keySourceListType {
    const text: string = urlFieldKeyText(this.inputPattern, this.urlFieldKey);
    return { content: text, title: text, upperContent: text };
  }

  @Builder
  symbolKeys(row: number) {
    ForEach(symbolPageRows[this.page][row], (symbol: string) => {
      KeyItem({ keyValue: { content: symbol, title: symbol, upperContent: symbol },
        keyId: `symbol_key_${symbol}` })
    }, (symbol: string) => symbol)
  }

  build() {
    Column({ space: this.inputStyle.keyGap }) {
      Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        this.symbolKeys(0)
      }
      .width('100%')
      .layoutWeight(1)

      Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        this.symbolKeys(1)
      }
      .width('100%')
      .layoutWeight(1)

      Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        this.symbolKeys(2)
      }
      .width('100%')
      .layoutWeight(1)

      Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        KeyItemGray({ keyValue: this.page === 0 ? '1/2' : '2/2', keyId: 'symbol_page_toggle',
          onActivate: () => { this.page = 1 - this.page; } })
        this.symbolKeys(3)
        DeleteItem()
      }
      .width('100%')
      .layoutWeight(1)

      Row({ space: this.inputStyle.bottomKeyGap }) {
        Column() {
          KeyItemGray({ keyValue: 'ABC', keyWidth: '100%', keyId: 'symbol_abc',
            onActivate: () => { this.menuType = MenuType.NORMAL; } })
        }.layoutWeight(1.25).height('100%')
        // Without 12-key there is nothing to switch to, so the space takes the room.
        if (this.flickEnabled) { Column() { LayoutItem({ keyWidth: '100%', globe: true }) }.layoutWeight(1).height('100%') }
        Column() {
          KeyItem({ keyValue: { content: this.comma(), title: this.comma(), upperContent: this.comma() },
            keyId: 'symbol_comma', keyWidth: '100%' })
        }.layoutWeight(1).height('100%')
        Column() { SpaceItem({ spaceWith: '100%' }) }.layoutWeight(4).height('100%')
        Column() {
          KeyItem({ keyValue: { content: '.', title: '.', upperContent: '.' },
            keyId: 'symbol_key_.', keyWidth: '100%' })
        }.layoutWeight(1).height('100%')
        if (urlFieldKeyText(this.inputPattern, this.urlFieldKey) !== '') {
          Column() {
            KeyItem({ keyValue: this.urlKeyValue(),
              keyId: 'symbol_www', keyWidth: '100%', directInput: true })
          }.layoutWeight(1.75).height('100%')
        }
        Column() { ReturnItem({ returnWidth: '100%' }) }.layoutWeight(1.5).height('100%')
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%').height('100%')
    .padding(6)
    .constraintSize({ maxWidth: 720 })
  }
}
