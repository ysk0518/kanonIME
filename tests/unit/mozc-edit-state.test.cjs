const test = require('node:test');
const assert = require('node:assert/strict');
const { MozcEditState } = require('../../entry/src/main/ets/kanon/MozcEditState.ets');

test('P03: ordinary input retains replay history and full conversion commit', () => {
  const state = new MozcEditState();
  state.afterInput(false, false, true);
  assert.equal(state.canReplay(), true);
  assert.equal(state.scopesCandidate('composing'), true);
  assert.equal(state.scopesCandidate('converting'), false);
  assert.equal(state.scopesCandidate('empty'), false);
});

test('P03: deleting in native composition invalidates replay while ordinary input cannot restore it', () => {
  const state = new MozcEditState();
  state.afterBackspace(true);
  state.afterInput(false, false, true);
  assert.equal(state.canReplay(), false);
  assert.equal(state.scopesCandidate('converting'), false);
});

test('P03: insertion cursor invalidates history without changing conversion commit scope', () => {
  const state = new MozcEditState();
  state.afterArrow('composing');
  assert.equal(state.canReplay(), false);
  assert.equal(state.scopesCandidate('composing'), true);
  assert.equal(state.scopesCandidate('converting'), false);
});

test('P03: resizing conversion affects commit scope without discarding replay history', () => {
  const state = new MozcEditState();
  state.afterArrow('converting');
  assert.equal(state.canReplay(), true);
  assert.equal(state.scopesCandidate('converting'), true);
});

test('P03: partial commit keeps remaining composition native and retains adjusted boundary', () => {
  const state = new MozcEditState();
  state.afterArrow('converting');
  state.afterPartialCommit(true);
  assert.equal(state.canReplay(), false);
  assert.equal(state.scopesCandidate('converting'), true);
  assert.equal(state.scopesCandidate('composing'), true);
});

test('P03: rebuilding displayed conversion or committing starts replayable input', () => {
  for (const [rebuilt, committed] of [[true, false], [false, true]]) {
    const state = new MozcEditState();
    state.afterPartialCommit(true);
    state.afterArrow('converting');
    state.afterInput(rebuilt, committed, true);
    assert.equal(state.canReplay(), true);
    assert.equal(state.scopesCandidate('converting'), false);
  }
});

test('P03: empty transitions and reset clear both editing policies', () => {
  for (const clear of [state => state.reset(), state => state.afterPartialCommit(false),
    state => state.afterBackspace(false), state => state.afterInput(false, false, false)]) {
    const state = new MozcEditState();
    state.afterPartialCommit(true); state.afterArrow('converting'); clear(state);
    assert.equal(state.canReplay(), true);
    assert.equal(state.scopesCandidate('converting'), false);
  }
});

test('P03: input and Delete clear manual boundary without reviving consumed history', () => {
  for (const edit of [state => state.afterInput(false, false, true), state => state.afterBackspace(true)]) {
    const state = new MozcEditState();
    state.afterPartialCommit(true); state.afterArrow('converting'); edit(state);
    assert.equal(state.canReplay(), false);
    assert.equal(state.scopesCandidate('converting'), false);
  }
});
