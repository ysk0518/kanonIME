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
import { MenuKey, numberSourceListData, sourceListType } from '../model/KeyboardKeyData';
import { SpaceItem } from './SpaceItem';
import { ReturnItem } from './ReturnItem';
import { LayoutItem } from './LayoutItem';
import { ModeCycleItem } from './ModeCycleItem';

// 数字键盘
@Component
export struct NumberMenu {
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @Consume menuType: number;
  private numberList: sourceListType[] = numberSourceListData;

  build() {
    Column({ space: this.inputStyle.keyGap }) {
      Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        ForEach(this.numberList.slice(0, 10), (item: sourceListType) => {
          KeyItem({ keyValue: { content: item.content, title: item.content, upperContent: item.content } })
        }, (item: sourceListType) => item.content)
      }
      .width('100%')
      .layoutWeight(1)

      Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        ForEach(this.numberList.slice(10, 20), (item: sourceListType) => {
          KeyItem({ keyValue: { content: item.content, title: item.content, upperContent: item.content } })
        }, (item: sourceListType) => item.content)
      }
      .width('100%')
      .layoutWeight(1)

      Flex({ justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        KeyItemGray({ keyValue: MenuKey.SPECIAL_KEY })
        ForEach(this.numberList.slice(20), (item: sourceListType) => {
          KeyItem({ keyValue: { content: item.content, title: item.content, upperContent: item.content } })
        }, (item: sourceListType) => item.content)
        DeleteItem()
      }
      .width('100%')
      .layoutWeight(1)

      Row({ space: this.inputStyle.bottomKeyGap }) {
        LayoutItem()
        ModeCycleItem()
        KeyItem({ keyValue: { content: '_', title: '_', upperContent: '_' } })
        KeyItem({ keyValue: { content: ',', title: ',', upperContent: ',' } })

        Column() { SpaceItem({ spaceWith: '100%' }) }.layoutWeight(1).height('100%')
        KeyItem({ keyValue: { content: '.', title: '.', upperContent: '.' } })
        ReturnItem({ returnWidth: this.inputStyle.returnButtonWidthType_2 })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%').height('100%')
    .padding(6)
    .constraintSize({ maxWidth: 720 })
  }
}
