const test = require('node:test');
const assert = require('node:assert/strict');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { MozcEngine } = require('../../entry/src/main/ets/kanon/MozcEngine.ets');
const { FakeEditor, ScriptedBridge, response, update } = require('../support/fakes.cjs');

test('P02: suggestions remain composing even when candidates are visible', async () => {
  const editor = new FakeEditor();
  const coordinator = new ImeCoordinator(editor);
  coordinator.setEngine({ dispatch: (s, e, n) => update(s, e, n, {
    phase: 'composing', preeditLen: 1, candidateCount: 1, candidates: [{ id: 1, label: '亜' }]
  }) });
  await coordinator.postEvent({ kind: 'kana', text: 'あ' });
  assert.equal(coordinator.getSnapshot().state, 'JP_COMPOSING');
  assert.equal(coordinator.getSnapshot().candidateCount, 1);
});

test('P02: conversion state survives a temporarily empty candidate list', async () => {
  const coordinator = new ImeCoordinator(new FakeEditor());
  coordinator.setEngine({ dispatch: (s, e, n) => update(s, e, n, {
    phase: 'converting', preeditLen: 1, candidateCount: 0
  }) });
  await coordinator.postEvent({ kind: 'convert' });
  assert.equal(coordinator.getSnapshot().state, 'JP_CONVERTING');
});

test('P02: Mozc reports suggestion, conversion and remaining composition explicitly', async () => {
  const bridge = new ScriptedBridge([
    { operation: 'convert', text: 'a', output: response('あ', { candidates: [{ id: 1, value: '亜' }] }) },
    { operation: 'convert', text: 'u', output: response('あう') },
    { operation: 'space', output: response('亜雨', {
      focused_id: 1, candidates: [{ id: 1, value: '亜' }] }) },
    { operation: 'submitCandidate', candidateId: 1, output: response('う', { result: '亜' }) },
    { operation: 'reset', output: response() }
  ]);
  const engine = new MozcEngine(bridge); let sequence = 0;
  const send = event => engine.dispatch('phase-test', 1, ++sequence, event);
  assert.equal((await send({ kind: 'kana', text: 'あ' })).phase, 'composing');
  await send({ kind: 'kana', text: 'う' });
  assert.equal((await send({ kind: 'convert' })).phase, 'converting');
  const partial = await send({ kind: 'enter' });
  assert.equal(partial.phase, 'composing');
  assert.equal(partial.effects[0].text, '亜');
  assert.equal(engine.getPreedit(), 'う');
  assert.equal((await send({ kind: 'cancel' })).phase, 'empty');
  bridge.assertDone();
});

test('P02: Japanese coordinator follows Mozc phase through prediction, conversion and cancel', async () => {
  const bridge = new ScriptedBridge([
    { operation: 'convert', text: 'a', output: response('あ', { candidates: [{ id: 1, value: '亜' }] }) },
    { operation: 'space', output: response('亜', { focused_id: 1, candidates: [{ id: 1, value: '亜' }] }) },
    { operation: 'reset', output: response() }
  ]);
  const coordinator = new ImeCoordinator(new FakeEditor());
  coordinator.setEngine(new MozcEngine(bridge));
  await coordinator.postEvent({ kind: 'kana', text: 'あ' });
  assert.equal(coordinator.getSnapshot().state, 'JP_COMPOSING');
  assert.deepEqual(coordinator.getCandidateView(), [{ id: 1, label: '亜' }]);
  await coordinator.postEvent({ kind: 'convert' });
  assert.equal(coordinator.getSnapshot().state, 'JP_CONVERTING');
  await coordinator.postEvent({ kind: 'cancel' });
  assert.equal(coordinator.getSnapshot().state, 'JP_EMPTY');
  assert.equal(coordinator.getSnapshot().candidateCount, 0);
  bridge.assertDone();
});

test('P02: English coordinator uses the same phase contract', async () => {
  const coordinator = new ImeCoordinator(new FakeEditor());
  await coordinator.loadPreviewSupport();
  coordinator.setEnglishEngine({ dispatch: (s, e, n, event) => update(s, e, n, {
    preeditLen: event.kind === 'enter' ? 0 : 2,
    phase: event.kind === 'enter' ? 'empty' : event.kind === 'convert' ? 'converting' : 'composing',
    candidateCount: event.kind === 'text' ? 1 : 0,
    candidates: event.kind === 'text' ? [{ id: 1, label: 'hello' }] : [],
    effects: event.kind === 'enter' ? [{ effectId: 'english-completion', text: 'hello' }] : []
  }) });
  await coordinator.postEvent({ kind: 'mode', text: 'EN' });
  assert.equal(coordinator.getSnapshot().state, 'EN_EMPTY');
  await coordinator.postEvent({ kind: 'text', text: 'he' });
  assert.equal(coordinator.getSnapshot().state, 'EN_COMPOSING');
  await coordinator.postEvent({ kind: 'convert' });
  assert.equal(coordinator.getSnapshot().state, 'EN_CONVERTING');
  await coordinator.postEvent({ kind: 'enter' });
  assert.equal(coordinator.getSnapshot().state, 'EN_EMPTY');
});

test('P02: unavailable English preview keeps direct input and bypasses the engine', async () => {
  const editor = new FakeEditor(); editor.supported = false;
  const coordinator = new ImeCoordinator(editor);
  await coordinator.loadPreviewSupport();
  coordinator.setEnglishEngine({ dispatch: () => { throw new Error('Unexpected engine call'); } });
  await coordinator.postEvent({ kind: 'mode', text: 'EN' });
  await coordinator.postEvent({ kind: 'text', text: 'a' });
  assert.equal(coordinator.getSnapshot().state, 'DIRECT_EN');
  assert.equal(editor.text, 'a');
});

test('P02: empty preedit closes composition despite a stale candidate list', async () => {
  const coordinator = new ImeCoordinator(new FakeEditor());
  coordinator.setEngine({ dispatch: (s, e, n) => update(s, e, n, {
    phase: 'empty', preeditLen: 0, candidateCount: 1, candidates: [{ id: 1, label: 'fixture' }]
  }) });
  await coordinator.postEvent({ kind: 'text', text: 'fixture' });
  assert.equal(coordinator.getSnapshot().state, 'JP_EMPTY');
});

test('P02: a recoverable failure preserves the last accepted phase', async () => {
  const coordinator = new ImeCoordinator(new FakeEditor());
  coordinator.setEngine({ dispatch: (s, e, n, event) => update(s, e, n,
    event.kind === 'convert' ? { phase: 'empty', errorCode: 1 } : {
      phase: 'composing', preeditLen: 1, candidateCount: 1, candidates: [{ id: 1, label: '亜' }]
    }) });
  await coordinator.postEvent({ kind: 'kana', text: 'あ' });
  await coordinator.postEvent({ kind: 'convert' });
  assert.equal(coordinator.getSnapshot().state, 'JP_COMPOSING');
  assert.equal(coordinator.getSnapshot().preeditLen, 1);
  assert.equal(coordinator.getSnapshot().lastError, 'engine-1');
});
