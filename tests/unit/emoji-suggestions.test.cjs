const test = require('node:test');
const assert = require('node:assert/strict');
const { emojiForReading } = require('../../entry/src/main/ets/kanon/EmojiSuggestions.ets');

test('P53: known readings return up to three emoji', () => {
  assert.deepEqual(emojiForReading('こんにちは'), ['✨', '😃', '❗']);
  assert.deepEqual(emojiForReading('すし'), ['🍣']);
  assert.deepEqual(emojiForReading('ぴーす'), ['✌️']);
  const readings = 'こんにちは おはよう こんばんは おやすみ ありがとう ごめん ごめんなさい おめでとう たんじょうび ' +
    'すき だいすき わらい かなしい なく おこる びっくり ねこ いぬ はーと ほし はな さくら あめ ゆき はれ ' +
    'くも たいよう つき ごはん らーめん すし びーる こーひー けーき おつかれ がんばれ おっけー いいね ぴーす ぱーてぃー';
  for (const reading of readings.split(' ')) {
    const emoji = emojiForReading(reading);
    assert.ok(emoji.length >= 1 && emoji.length <= 3, reading);
  }
});

test('P53: readings match exactly and results cannot change the table', () => {
  for (const reading of ['', 'こんにち', 'こんにちは！', 'こんにちは ', 'コンニチハ', 'konnichiha']) {
    assert.deepEqual(emojiForReading(reading), []);
  }
  emojiForReading('さくら').pop();
  assert.deepEqual(emojiForReading('さくら'), ['🌸']);
});
