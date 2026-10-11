const test = require('node:test');
const assert = require('node:assert/strict');
const { resolve } = require('node:path');
const { selectTestFiles, testArguments } = require('../support/test-arguments.cjs');

test('T02: the normal suite selects every test file without a group filter', () => {
  assert.deepEqual(selectTestFiles([{ filename: 'a' }, { filename: 'b' }]), ['a', 'b']);
});

test('T02: a mutation group includes all matching files and excludes other prefixes', () => {
  const files = [
    { filename: 'a', source: "test('P24: first')" },
    { filename: 'b', source: "test('P240: unrelated')" },
    { filename: 'c', source: "test('P24: another')" },
    { filename: 'd', source: "test('P25: other')" }
  ];
  assert.deepEqual(selectTestFiles(files, 'P24'), ['a', 'c']);
});

test('T02: missing and malformed mutation groups fail instead of running an empty suite', () => {
  assert.throws(() => selectTestFiles([], 'P24'), /No test files for group: P24/);
  for (const group of ['', 'P24:', 'P24|P25', '../unit']) {
    assert.throws(() => selectTestFiles([], group), /Invalid test group/);
  }
});

test('T02: the newer Node runner has a deadline while DevEco Node keeps compatible options', () => {
  const root = resolve(__dirname, '..');
  const old = testArguments(root, [], undefined, '18.20.1');
  const current = testArguments(root, [], undefined, '24.17.0');
  assert.equal(old.includes('--test-timeout=30000'), false);
  assert.equal(current.includes('--test-timeout=30000'), true);
  assert.deepEqual(current.filter(arg => arg !== '--test-timeout=30000'), old);
  assert.equal(old.includes('--test-reporter=tap'), true);
});

test('T02: a grouped run retains the loader and name filter and includes only matching files', () => {
  const root = resolve(__dirname, '..');
  const args = testArguments(root, ['--test-name-pattern', 'P24:'], 'P24', '18.20.1');
  assert.equal(args[0], '--require');
  assert.equal(args[1], resolve(root, 'support/register-ets.cjs'));
  assert.equal(args.includes('P24:'), true);
  assert.equal(args.includes(resolve(root, 'unit/direct-english-input.test.cjs')), true);
  assert.equal(args.includes(resolve(root, 'unit/space-gesture.test.cjs')), false);
});
