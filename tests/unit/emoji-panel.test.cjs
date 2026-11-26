const test = require('node:test');
const assert = require('node:assert/strict');
const { EMOJI_CATEGORIES } = require('../../entry/src/main/ets/model/EmojiData.ets');
const { EmojiHistory } = require('../../entry/src/main/ets/common/EmojiHistory.ets');
const { KANON_EMOJI_HISTORY } = require('../../entry/src/main/ets/common/AppStorageKeys.ets');
const { lastGraphemeLength } = require('../../entry/src/main/ets/kanon/GraphemeDelete.ets');

const values = EMOJI_CATEGORIES.flatMap(category => category.values);

test('P47: the catalog contains unique single-grapheme emoji in every category', () => {
  assert.deepEqual(EMOJI_CATEGORIES.map(category => category.id),
    ['recent', 'faces', 'people', 'nature', 'food', 'travel', 'activities', 'objects', 'symbols', 'flags']);
  assert.deepEqual(EMOJI_CATEGORIES[0].values, []);
  for (const category of EMOJI_CATEGORIES.slice(1)) {
    assert.ok(category.values.length >= 30 && category.values.length <= 100, category.id);
  }
  assert.ok(values.length >= 550 && values.length <= 675);
  assert.equal(new Set(values).size, values.length);
  const segmenter = new Intl.Segmenter('ja', { granularity: 'grapheme' });
  for (const value of values) {
    assert.equal([...segmenter.segment(value)].length, 1, value);
    assert.doesNotMatch(value, /[\u200D\u{1F3FB}-\u{1F3FF}]/u);
    assert.equal(lastGraphemeLength(`😀${value}`), value.length, value);
  }
  const flags = EMOJI_CATEGORIES.find(category => category.id === 'flags');
  for (const flag of flags.values) { assert.match(flag, /^\p{Regional_Indicator}{2}$/u); }
});

function storageRig() {
  const saved = new Map();
  function launch() {
    const live = new Map();
    const persistent = new Set();
    const history = new EmojiHistory({
      persist: (key, initial) => {
        persistent.add(key);
        live.set(key, saved.get(key) ?? initial);
      },
      read: key => live.get(key),
      write: (key, value) => {
        live.set(key, value);
        if (persistent.has(key)) { saved.set(key, value); }
      }
    });
    history.initialize();
    return history;
  }
  return { saved, launch };
}

test('P47: recents move to the front without duplicates and persist at most 32', () => {
  const { saved, launch } = storageRig();
  const history = launch();
  assert.deepEqual(history.getRecent(), []);
  for (const value of values.slice(0, 34)) { history.remember(value); }
  const repeated = values[10];
  history.remember(repeated);
  history.remember(repeated);
  history.remember('arbitrary typed text');
  const expected = [repeated, ...values.slice(2, 34).reverse().filter(value => value !== repeated)];
  assert.deepEqual(JSON.parse(saved.get(KANON_EMOJI_HISTORY)), expected);
  assert.deepEqual(launch().getRecent(), expected);
});

test('P47: damaged history is filtered and clearing survives relaunch', () => {
  const { saved, launch } = storageRig();
  saved.set(KANON_EMOJI_HISTORY, 'invalid JSON');
  assert.deepEqual(launch().getRecent(), []);
  saved.set(KANON_EMOJI_HISTORY, JSON.stringify(['🇯🇵', false, '🇯🇵', 'hello', '❤️']));
  const history = launch();
  assert.deepEqual(history.getRecent(), ['🇯🇵', '❤️']);
  history.clear();
  assert.deepEqual(history.getRecent(), []);
  assert.deepEqual(launch().getRecent(), []);
});
