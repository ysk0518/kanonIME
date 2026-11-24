const test = require('node:test');
const assert = require('node:assert/strict');
const { readdirSync, readFileSync } = require('node:fs');
const { join, relative } = require('node:path');
const keys = require('../../entry/src/main/ets/common/AppStorageKeys.ets');

const sourceRoot = join(__dirname, '../../entry/src/main/ets');

function* etsFiles(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const filename = join(directory, entry.name);
    if (entry.isDirectory()) {
      yield* etsFiles(filename);
    } else if (entry.name.endsWith('.ets')) {
      yield filename;
    }
  }
}

test('P32: AppStorage key values are unique', () => {
  const namesByValue = new Map();
  for (const [name, value] of Object.entries(keys)) {
    assert.equal(typeof value, 'string', name);
    assert.ok(!namesByValue.has(value), `${name} duplicates ${namesByValue.get(value)} (${value})`);
    namesByValue.set(value, name);
  }
});

test('P32: storage decorator keys are defined in AppStorageKeys', () => {
  const values = new Set(Object.values(keys));
  for (const filename of etsFiles(sourceRoot)) {
    const source = readFileSync(filename, 'utf8');
    for (const match of source.matchAll(/@Storage(?:Link|Prop)\b(?:\s*\(\s*(['"])([^'"\r\n]+)\1\s*\))?/g)) {
      const line = source.slice(0, match.index).split('\n').length;
      const location = `${relative(sourceRoot, filename)}:${line}`;
      assert.ok(match[2], `${location}: expected a literal storage decorator key`);
      assert.ok(values.has(match[2]), `${location}: unknown storage decorator key ${match[2]}`);
    }
  }
});
