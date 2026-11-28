const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { join } = require('node:path');
const { test } = require('node:test');
const { PerfKeyboardFrame, perfMessage } = require('../../entry/src/main/ets/common/PerfTraceModel.ets');

test('P63: messages retain the wall clock and sequence', () => {
  assert.equal(perfMessage('key.done', 1795910400224, '23'), 'P63 key.done 1795910400224 23');
  assert.equal(perfMessage('field.focus', 1795910400100, ''), 'P63 field.focus 1795910400100 -');
});

test('P63: one frame per show, including reused layout', () => {
  const panel = new PerfKeyboardFrame();
  assert.equal(panel.show(), false);
  assert.equal(panel.layout(0, 350), false);
  assert.equal(panel.layout(600, 350), true);
  assert.equal(panel.layout(600, 360), false);
  assert.equal(panel.show(), false);
  panel.hide();
  assert.equal(panel.show(), true);
  panel.reset();
  assert.equal(panel.show(), false);
  panel.reset();
  assert.equal(panel.layout(600, 350), false);
  assert.equal(panel.show(), true);
});

test('P63: PowerShell parses and correlates device log fixtures', t => {
  const script = join(__dirname, '../../tools/device/KanonPerf.Tests.ps1');
  for (const shell of ['powershell', 'pwsh']) {
    const result = spawnSync(shell, ['-NoProfile', '-NonInteractive', '-File', script], {
      encoding: 'utf8',
      timeout: 25000,
    });
    if (result.error?.code === 'ENOENT') continue;
    if (result.error) throw result.error;
    assert.equal(result.status, 0, [result.stdout, result.stderr].join('\n'));
    assert.match(result.stdout, /Passed [1-9]\d* perf assertions\./);
    return;
  }
  t.skip('PowerShell is unavailable');
});

test('P64: the IME starts loading Mozc when it is created and later callers join that load', () => {
  const { readFileSync } = require('node:fs');
  // Read through the mutation hook so the mutation suite can check these assertions.
  const source = (file) => {
    const text = readFileSync(require.resolve(`../../entry/src/main/ets/${file}`), 'utf8');
    const mutation = process.env.KANON_TEST_MUTATION;
    return mutation ? require('../support/source-mutations.cjs').mutate(file, text, mutation) : text.replace(/\r\n/g, '\n');
  };
  const controller = source('model/KeyboardController.ets');
  // The profile must be set before the load, and the load must start in onCreate,
  // not when the keyboard page appears.
  assert.match(controller, /kanonIme\.configureProfile\(context\.filesDir\);\s*kanonIme\.warmUpEngine\(\);/);
  const bridge = source('kanon/NativeMozcBridge.ets');
  // A second prepare while the first is loading returns the same promise.
  assert.match(bridge, /if \(this\.pending === null\) \{\s*this\.pending = this\.load\(\)/);
  assert.match(bridge, /return this\.pending;/);
});
