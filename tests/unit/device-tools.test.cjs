const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { join } = require('node:path');
const { test } = require('node:test');

test('DT: device tools parse fixtures and guard device operations', t => {
  const script = join(__dirname, '../../tools/device/KanonDevice.Tests.ps1');
  for (const shell of ['powershell', 'pwsh']) {
    const result = spawnSync(shell, ['-NoProfile', '-NonInteractive', '-File', script], {
      encoding: 'utf8',
      timeout: 25000,
    });
    if (result.error?.code === 'ENOENT') continue;
    if (result.error) throw result.error;
    assert.equal(result.status, 0, [result.stdout, result.stderr].join('\n'));
    assert.match(result.stdout, /Passed [1-9]\d* device assertions\./);
    return;
  }
  t.skip('PowerShell is unavailable');
});
