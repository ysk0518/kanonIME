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

import { hapTasks } from '@ohos/hvigor-ohos-plugin';

import { hvigor } from '@ohos/hvigor';
import { execFileSync } from 'child_process';
import { copyFileSync } from 'fs';
import { join } from 'path';

// Native libraries are loaded directly from the HAP and require page alignment.
// Align the unsigned archive after packaging, before any signature is created.
export default {
  system: hapTasks,
  plugins: [{
    pluginId: 'kanon-native-alignment',
    apply(node) {
      hvigor.taskGraphResolved(() => {
        const task = node.getTaskByName('default@PackageHap');
        if (!task) { throw new Error('PackageHap task missing'); }
        task.afterRun(() => {
          const outputDir = join(__dirname, 'build/default/outputs/default');
          const unsigned = join(outputDir, 'entry-default-unsigned.hap');
          const aligned = join(outputDir, 'entry-default-unsigned-aligned.hap');
          execFileSync(process.execPath, [join(__dirname, '../tools/align-hap.cjs'), unsigned, aligned],
            { stdio: 'inherit' });
          copyFileSync(aligned, unsigned);
        });
      });
    }
  }]
};
