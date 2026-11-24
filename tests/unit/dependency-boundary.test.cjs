const test = require('node:test');
const assert = require('node:assert/strict');
const { readdirSync } = require('node:fs');
const { join } = require('node:path');

const kanonRoot = join(__dirname, '../../entry/src/main/ets/kanon');
// Harmony SDK adapters, platform wiring, and the AppStorage adapters.
const platformModules = new Set([
  'AppStorageImeBindings.ets', 'AppStorageImeView.ets', 'ClipboardHistory.ets',
  'ClipboardSnapshot.ets', 'EditorAdapter.ets', 'EnglishRuntime.ets', 'KanonIme.ets',
  'NativeMozcBridge.ets', 'RealEditorPort.ets', 'SdkEditorDirections.ets'
]);

function verifyCoreModules(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const filename = join(directory, entry.name);
    if (entry.isDirectory()) {
      verifyCoreModules(filename);
    } else if (entry.name.endsWith('.ets') && !(directory === kanonRoot && platformModules.has(entry.name))) {
      assert.doesNotThrow(() => require(filename), filename);
    }
  }
}

test('test loader rejects Harmony infrastructure instead of silently stubbing it', () => {
  assert.throws(() => require('../../entry/src/main/ets/kanon/NativeMozcBridge.ets'),
    /Platform import in unit-test target: @ohos.file.fs/);
});

test('P32: SDK-free kanon modules load without AppStorage', () => {
  verifyCoreModules(kanonRoot);
});
