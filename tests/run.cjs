const { spawnSync } = require('node:child_process');
const { testArguments } = require('./support/test-arguments.cjs');

const result = spawnSync(process.execPath, testArguments(__dirname, process.argv.slice(2)),
  { stdio: 'inherit' });
if (result.error) { throw result.error; }
process.exitCode = result.status ?? 1;
