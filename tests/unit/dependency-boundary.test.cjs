const test = require('node:test');
const assert = require('node:assert/strict');

test('test loader rejects Harmony infrastructure instead of silently stubbing it', () => {
  assert.throws(() => require('../../entry/src/main/ets/kanon/NativeMozcBridge.ets'),
    /Platform import in unit-test target: @ohos.file.fs/);
});
