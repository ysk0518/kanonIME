const { readdirSync } = require('node:fs');
const { join } = require('node:path');
const { spawnSync } = require('node:child_process');

const files = readdirSync(join(__dirname, 'unit')).filter(name => name.endsWith('.test.cjs')).sort();
if (files.length === 0) { throw new Error('No unit tests found'); }
const result = spawnSync(process.execPath, [
  '--require', join(__dirname, 'support', 'register-ets.cjs'),
  '--test', '--test-reporter=tap', ...process.argv.slice(2), ...files.map(name => join(__dirname, 'unit', name))
], { stdio: 'inherit' });
if (result.error) { throw result.error; }
process.exitCode = result.status ?? 1;
