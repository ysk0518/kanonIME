const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { mutate } = require('../support/source-mutations.cjs');

test('P34: the Gboard decisions and their acceptance rows are recorded', () => {
  const path = 'docs/INPUT_BEHAVIOR.md';
  const source = readFileSync(resolve(__dirname, '../..', path), 'utf8');
  const mutation = process.env.KANON_TEST_MUTATION;
  const doc = mutation ? mutate(path, source, mutation) : source;
  assert.match(doc, /更新: 2026-11-25。入力操作の基準は Gboard/);
  const heading = '## 9. 決定済みの項目';
  assert.ok(doc.includes(heading));
  const decisions = doc.slice(doc.indexOf(heading));
  for (const id of ['Q1', 'Q2', 'Q3', 'Q4', 'Q6', 'Q8']) {
    assert.ok(decisions.includes(`| ${id} | 合意 |`), id);
  }
  assert.ok(decisions.includes('| Q5 | 方針決定・native観測済み |'));
  assert.ok(decisions.includes('| Q7 | 内部処理の決定 |'));
  for (const id of ['JP-04', 'JP-19', 'JP-20', 'EN-10', 'EN-13', 'DE-07', 'CM-06', 'CM-07']) {
    assert.match(doc, new RegExp(`^\\| ${id} \\|.*\\| 合意 \\|$`, 'm'), id);
  }
});
