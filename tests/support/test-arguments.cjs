const { readdirSync, readFileSync } = require('node:fs');
const { join } = require('node:path');

function selectTestFiles(files, group) {
  if (group === undefined) { return files.map(file => file.filename); }
  if (!/^[A-Z]\d+$/.test(group)) { throw new Error(`Invalid test group: ${group}`); }
  // Keep every file containing the same literal prefix used by the name filter.
  const selected = files.filter(file => file.source.includes(`${group}:`))
    .map(file => file.filename);
  if (selected.length === 0) { throw new Error(`No test files for group: ${group}`); }
  return selected;
}

function testArguments(root, args = [], group, nodeVersion = process.versions.node) {
  const files = readdirSync(join(root, 'unit')).filter(name => name.endsWith('.test.cjs')).sort()
    .map(name => {
      const filename = join(root, 'unit', name);
      return { filename, source: group === undefined ? '' : readFileSync(filename, 'utf8') };
    });
  if (files.length === 0) { throw new Error('No unit tests found'); }
  // Node 18 cancels an unresolved test when its event loop ends; Node 24 can keep
  // waiting. Bound tests on the newer runner, including deliberately broken ones.
  const timeout = Number(nodeVersion.split('.')[0]) >= 24 ? ['--test-timeout=30000'] : [];
  return ['--require', join(root, 'support', 'register-ets.cjs'), '--test',
    '--test-reporter=tap', ...timeout, ...args, ...selectTestFiles(files, group)];
}

module.exports = { selectTestFiles, testArguments };
