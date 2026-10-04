// Modified for kanonIME by ysk0518 and contributors, 2026.
/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
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

import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import hilog from '@ohos.hilog';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { BusinessError } from '@ohos.base';

export default class EntryAbility extends UIAbility {
  private clipboardPermission: boolean = false;
  private preview: boolean = false;
  private background: boolean = false;
  private mainStage: window.WindowStage | undefined;
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.clipboardPermission = want.parameters?.['kanonClipboardPermission'] === true;
    this.preview = want.parameters?.['kanonPreview'] === true;
    this.background = want.parameters?.['kanonBackground'] === true;
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.mainStage = windowStage;
    // Main window is created, set main page for this ability
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent(this.clipboardPermission ? 'pages/ClipboardPermission' :
      this.preview ? 'pages/PrivatePreview' : this.background ? 'pages/BackgroundPage' : 'pages/SettingsPage', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(0x0000, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    this.mainStage = undefined;
    // Main window is destroyed, release UI related resources
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const stage: window.WindowStage | undefined = this.mainStage;
    if (!stage) { return; }
    const page: string = want.parameters?.['kanonClipboardPermission'] === true ? 'pages/ClipboardPermission' :
      want.parameters?.['kanonPreview'] === true ? 'pages/PrivatePreview' :
      want.parameters?.['kanonBackground'] === true ? 'pages/BackgroundPage' : 'pages/SettingsPage';
    try {
      stage.loadContent(page, (err) => {
        if (err.code) {
          hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        }
      });
    } catch (error) {
      hilog.error(0x0000, 'testTag', 'Failed to load the content. Code: %{public}d', (error as BusinessError).code);
    }
  }

  onForeground(): void {
    AppStorage.setOrCreate('kanonSettingsForeground', true);
    // Ability has brought to foreground
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    AppStorage.setOrCreate('kanonSettingsForeground', false);
    // Ability has back to background
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
