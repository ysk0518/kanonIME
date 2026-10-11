const test = require('node:test');
const assert = require('node:assert/strict');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { createImeViewModel } = require('../../entry/src/main/ets/kanon/ImeViewModel.ets');
const { ImeViewPublisher } = require('../../entry/src/main/ets/kanon/ImeViewPublisher.ets');
const { FakeEditor } = require('../support/fakes.cjs');

function snapshot(values = {}) {
  return { ...new ImeCoordinator(new FakeEditor()).getSnapshot(), ...values };
}
function source(values = {}) {
  return { englishComposition: false, englishPrefixLength: 0,
    candidates: [], candidateRevision: 7, conversionReading: '', cursorPreview: '',
    nativeCandidateLengths: '', diagnosticCandidates: [], selectedIndex: -1, ...values };
}
function sink() {
  const calls = []; const store = new Map();
  const record = (type, key, value) => { calls.push({ type, key, value }); store.set(key, value); };
  return { calls, store, port: {
    number: (key, value) => record('number', key, value),
    string: (key, value) => record('string', key, value),
    boolean: (key, value) => record('boolean', key, value),
    strings: (key, value) => record('strings', key, value),
    numbers: (key, value) => record('numbers', key, value)
  } };
}

test('P05: Japanese predictions preserve composing state and visible candidates', () => {
  const view = createImeViewModel(snapshot({ preeditLen: 1, candidateCount: 1, state: 'JP_COMPOSING' }),
    source({ candidates: [{ id: 11, label: '亜' }], cursorPreview: 'あ│' }), 1);
  assert.equal(view.state, 'JP_COMPOSING');
  assert.equal(view.japaneseComposing, true);
  assert.equal(view.englishComposing, false);
  assert.equal(view.compositionCursor, 'あ│');
  assert.deepEqual(view.labels, ['亜']);
  assert.deepEqual(view.ids, [11]);
});

test('P05: conversion reading and error status are carried without changing engine state', () => {
  const s = snapshot({ preeditLen: 2, state: 'JP_CONVERTING', needsRecovery: true, lastError: 'commit-fail' });
  const before = { ...s };
  const view = createImeViewModel(s, source({ conversionReading: 'きょう' }), 2);
  assert.equal(view.conversionReading, 'きょう');
  assert.equal(view.state, 'JP_CONVERTING');
  assert.equal(view.needsRecovery, true);
  assert.equal(view.error, 'commit-fail');
  assert.deepEqual(s, before);
});

test('P05: direct English uses prediction count and revision without Japanese display text', () => {
  const view = createImeViewModel(snapshot({ mode: 'EN', state: 'DIRECT_EN', candidateCount: 0 }),
    source({ englishPrefixLength: 2, candidates: [{ id: 2, label: 'hello' }],
      candidateRevision: 12, conversionReading: '古い読み', cursorPreview: '古い│' }), 3);
  assert.equal(view.englishComposing, true);
  assert.equal(view.japaneseComposing, false);
  assert.equal(view.candidateCount, 1);
  assert.equal(view.candidateRevision, 12);
  assert.equal(view.conversionReading, '');
  assert.equal(view.compositionCursor, '');
});

test('P05: English composition is based on preedit rather than stale direct prefix', () => {
  const context = source({ englishComposition: true, englishPrefixLength: 5, candidates: [{ id: 2, label: 'hello' }] });
  const empty = createImeViewModel(snapshot({ mode: 'EN', state: 'EN_EMPTY' }), context, 1);
  assert.equal(empty.englishComposing, false);
  assert.equal(empty.candidateCount, 0);
  const composing = createImeViewModel(snapshot({ mode: 'EN', state: 'EN_COMPOSING', preeditLen: 2 }), context, 2);
  assert.equal(composing.englishComposing, true);
});

test('P05: empty Japanese composition clears cursor guidance', () => {
  const view = createImeViewModel(snapshot(), source({ cursorPreview: '古い│' }), 1);
  assert.equal(view.japaneseComposing, false);
  assert.equal(view.compositionCursor, '');
});

test('P05: display candidates are capped at twenty while count remains untruncated', () => {
  const items = Array.from({ length: 25 }, (_, i) => ({ id: i + 100, label: `candidate-${i}` }));
  const view = createImeViewModel(snapshot({ candidateCount: 25 }), source({ candidates: items }), 1);
  assert.equal(view.candidateCount, 25);
  assert.equal(view.labels.length, 20);
  assert.equal(view.ids.length, 20);
  assert.equal(view.ids[19], 119);
  assert.equal(items.length, 25);
});

test('P05: published candidate arrays do not alias the engine input arrays', () => {
  const items = [{ id: 11, label: '亜' }];
  const view = createImeViewModel(snapshot(), source({ candidates: items }), 1);
  view.labels[0] = '変更'; view.ids[0] = 99;
  assert.deepEqual(items, [{ id: 11, label: '亜' }]);
});

test('P05: diagnostic candidate metadata contains only IDs and UTF-16 lengths', () => {
  const view = createImeViewModel(snapshot(), source({ diagnosticCandidates: [
    { id: 11, label: '秘密' }, { id: 12, label: '😀' }
  ] }), 1);
  assert.equal(view.diagnosticIds, '11,12');
  assert.equal(view.diagnosticLengths, '2:2,2');
  assert.equal(view.diagnosticLengths.includes('秘密'), false);
});

test('P05: publisher preserves the eighteen existing storage keys and per-instance tick', () => {
  const r = sink(); const publisher = new ImeViewPublisher(r.port);
  publisher.publish(snapshot(), source());
  assert.deepEqual([...r.store.keys()], ['kanonTick', 'kanonMode', 'kanonState', 'kanonJapaneseComposing',
    'kanonConversionReading', 'kanonCompositionCursor', 'kanonEnglishComposing', 'kanonErr',
    'kanonNeedsRecovery', 'kanonCand', 'kanonRev', 'kanonList', 'kanonIdList', 'kanonLens',
    'kanonIds', 'kanonLens2', 'kanonSeg', 'kanonSel']);
  assert.equal(r.store.get('kanonTick'), 1);
  publisher.publish(snapshot(), source());
  assert.equal(r.store.get('kanonTick'), 2);
  const other = sink(); new ImeViewPublisher(other.port).publish(snapshot(), source());
  assert.equal(other.store.get('kanonTick'), 1);
});

test('P05: candidate display failure does not prevent diagnostic publishing', () => {
  const r = sink(); r.port.strings = () => { throw new Error('Display write failed'); };
  assert.doesNotThrow(() => new ImeViewPublisher(r.port).publish(snapshot(), source()));
  assert.equal(r.store.get('kanonList'), undefined);
  assert.equal(r.store.get('kanonSeg'), 0);
});

test('P05: platform storage adapter remains outside PC test targets', () => {
  assert.throws(() => require('../../entry/src/main/ets/kanon/AppStorageImeView.ets'),
    /Platform global in unit-test target: AppStorage/);
});
