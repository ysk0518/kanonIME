const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { mutate } = require('../support/source-mutations.cjs');

const filename = 'kanon/PreviewLifecycle.ets';
const mutation = 'previewCancellationEpoch';
const source = readFileSync(resolve(__dirname, '../../entry/src/main/ets', filename), 'utf8')
  .replace(/\r\n/g, '\n');

test('T01: multiline mutations apply equally to LF and CRLF source', () => {
  const lf = mutate(filename, source, mutation);
  const crlf = mutate(filename.replace(/\//g, '\\'), source.replace(/\n/g, '\r\n'), mutation);
  assert.notEqual(lf, source);
  assert.equal(crlf, lf);
  assert.equal(lf.includes('if (!cleared.ok) { return cleared; }\n  if (epoch'), false);
  assert.equal(lf.includes('const finished: OpResult = await editor.finishPreview();'), true);
});

test('T01: mutation matching rejects missing targets for either newline format', () => {
  for (const text of ['unrelated\nsource', 'unrelated\r\nsource']) {
    assert.throws(() => mutate(filename, text, mutation), /Mutation must match exactly once/);
  }
});

test('T01: mutation matching rejects duplicate targets for either newline format', () => {
  for (const newline of ['\n', '\r\n']) {
    const duplicate = (source + source).replace(/\n/g, newline);
    assert.throws(() => mutate(filename, duplicate, mutation), /Mutation must match exactly once/);
  }
});

test('T01: unrelated source retains its original CRLF text', () => {
  const text = source.replace(/\n/g, '\r\n');
  assert.equal(mutate('kanon/OtherModule.ets', text, mutation), text);
});

test('T01: unknown mutations fail explicitly', () => {
  assert.throws(() => mutate(filename, source, 'unknownMutation'), /Unknown mutation/);
});
