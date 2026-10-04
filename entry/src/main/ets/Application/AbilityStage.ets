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
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import AbilityStage from "@ohos.app.ability.AbilityStage";
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import Log from '../model/Log';
import { initializeKeyboardConfig } from '../common/KeyboardConfig';
import { keyboardBackground } from '../common/KeyboardBackground';
import { clipboardStore } from '../common/ClipboardStore';
import { Configuration as AbilityConfiguration } from '@ohos.app.ability.Configuration';
import { keyboardController } from '../model/KeyboardController';
import { BusinessError } from '@ohos.base';

const TAG: string = 'AbilityStage->';

export default class MyAbilityStage extends AbilityStage {
  onCreate(): void {
    initializeKeyboardConfig(this.context);
    keyboardBackground.initialize(this.context).catch(() => {});
    clipboardStore.initialize();
    keyboardController.updateFontScale(this.context.config.fontSizeScale ?? 1);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (error) {
      Log.showInfo(TAG, `setColorMode failed code=${(error as BusinessError).code}`);
    }
    AppStorage.setOrCreate<number>('windowWidth', -1);
    AppStorage.setOrCreate<number>('windowHeight', -1);
    Log.showInfo(TAG, '[Demo] MyAbilityStage onCreate');
  }

  onConfigurationUpdate(config: AbilityConfiguration): void {
    if (config.colorMode !== undefined) { AppStorage.setOrCreate('kanonBackgroundThemeVersion', Date.now()); }
    if (config.fontSizeScale !== undefined) { keyboardController.updateFontScale(config.fontSizeScale); }
  }
}
