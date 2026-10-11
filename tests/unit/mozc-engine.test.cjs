const test = require('node:test');
const assert = require('node:assert/strict');
const { MozcEngine } = require('../../entry/src/main/ets/kanon/MozcEngine.ets');
const { ScriptedBridge, response } = require('../support/fakes.cjs');

function rig(steps) {
  const bridge = new ScriptedBridge(steps);
  const engine = new MozcEngine(bridge);
  let sequence = 0;
  return { bridge, engine, async send(event) {
    const result = await engine.dispatch('test-session', 1, ++sequence, event);
    assert.equal(result.errorCode, 0);
    return result;
  } };
}

function partialSuggestionSteps() {
  return [
    { operation: 'convert', text: 'a', output: response('あ', { caret_utf16: 1 }) },
    { operation: 'convert', text: 'u', output: response('あう', { caret_utf16: 2 }) },
    { operation: 'arrowLeft', output: response('あう', { caret_utf16: 1 }) },
    { operation: 'convert', text: 'i', output: response('あいう', {
      caret_utf16: 2, candidates: [{ id: 11, value: '愛' }] }) },
    { operation: 'submitCandidate', candidateId: 11, output: response('う', {
      result: '愛', caret_utf16: 1, candidates: [{ id: 12, value: '宇' }] }) }
  ];
}

async function selectEditedPrefix(state) {
  await state.send({ kind: 'kana', text: 'あ' });
  await state.send({ kind: 'kana', text: 'う' });
  await state.send({ kind: 'compositionArrow', text: 'left' });
  await state.send({ kind: 'kana', text: 'い' });
  return state.send({ kind: 'select', candidateId: 11 });
}

test('R01: Japanese QWERTY Delete uses native backspace instead of replaying k', async () => {
  const state = rig([
    { operation: 'convert', text: 'k', output: response('ｋ') },
    { operation: 'convert', text: 'i', output: response('き') },
    { operation: 'backspace', output: response() }
  ]);
  await state.send({ kind: 'text', text: 'k' });
  await state.send({ kind: 'text', text: 'i' });
  const result = await state.send({ kind: 'backspace' });
  assert.equal(result.hasPreedit, false);
  assert.equal(state.engine.getPreedit(), '');
  assert.deepEqual(result.effects, []);
  state.bridge.assertDone();
});

test('R02: tapping a partial suggestion keeps text after the insertion cursor', async () => {
  const state = rig(partialSuggestionSteps());
  const result = await selectEditedPrefix(state);
  assert.equal(result.effects.length, 1);
  assert.equal(result.effects[0].text, '愛');
  assert.equal(state.engine.getPreedit(), 'う');
  assert.equal(result.preeditLen, 1);
  assert.equal(result.caretUtf16, 1);
  assert.equal(state.engine.getConversionReading(), '', 'Suggestions are not conversion');
  state.bridge.assertDone();
});

test('R06: voiced and semi-voiced kana remain editable after partial commit', async () => {
  const state = rig([...partialSuggestionSteps(),
    { operation: 'convert', text: 'ha', output: response('うは', { caret_utf16: 2 }) },
    { operation: 'backspace', output: response('う', { caret_utf16: 1 }) },
    { operation: 'convert', text: 'ba', output: response('うば', { caret_utf16: 2 }) },
    { operation: 'backspace', output: response('う', { caret_utf16: 1 }) },
    { operation: 'convert', text: 'pa', output: response('うぱ', { caret_utf16: 2 }) }
  ]);
  await selectEditedPrefix(state);
  await state.send({ kind: 'kana', text: 'は' });
  const voiced = await state.send({ kind: 'modifyKana' });
  assert.equal(state.engine.getPreedit(), 'うば');
  assert.deepEqual(voiced.effects, []);
  const semiVoiced = await state.send({ kind: 'modifyKana' });
  assert.equal(state.engine.getPreedit(), 'うぱ');
  assert.deepEqual(semiVoiced.effects, []);
  state.bridge.assertDone();
});

test('R07: modifying kana before the cursor preserves the following suffix', async () => {
  const state = rig([...partialSuggestionSteps(),
    { operation: 'convert', text: 'ya', output: response('うや', { caret_utf16: 2 }) },
    { operation: 'convert', text: 'u', output: response('うやう', { caret_utf16: 3 }) },
    { operation: 'arrowLeft', output: response('うやう', { caret_utf16: 2 }) },
    { operation: 'backspace', output: response('うう', { caret_utf16: 1 }) },
    { operation: 'convert', text: 'lya', output: response('うゃう', { caret_utf16: 2 }) }
  ]);
  await selectEditedPrefix(state);
  await state.send({ kind: 'kana', text: 'や' });
  await state.send({ kind: 'kana', text: 'う' });
  await state.send({ kind: 'compositionArrow', text: 'left' });
  await state.send({ kind: 'modifyKana' });
  assert.equal(state.engine.getPreedit(), 'うゃう');
  assert.equal(state.engine.getCursorPreview(), 'うゃ│う');
  state.bridge.assertDone();
});

test('R03/R04: resizing and tapping a candidate commits only the selected segment', async () => {
  const state = rig([
    { operation: 'convert', text: 'a', output: response('あ') },
    { operation: 'convert', text: 'u', output: response('あう') },
    { operation: 'space', output: response('亜雨', { focused_reading: 'あう', focused_id: 21,
      candidates: [{ id: 21, value: '亜雨' }] }) },
    { operation: 'arrowLeft', output: response('亜雨', { focused_reading: 'あ', focused_id: 22,
      candidates: [{ id: 22, value: '亜' }, { id: 23, value: '阿' }] }) },
    { operation: 'submitCandidate', candidateId: 23, output: response('雨', {
      result: '阿', focused_reading: 'う', focused_id: 24 }) },
    { operation: 'highlightCandidate', candidateId: 24, output: response('雨', {
      focused_reading: 'う', focused_id: 24, candidates: [{ id: 24, value: '雨' }] }) }
  ]);
  await state.send({ kind: 'kana', text: 'あ' });
  await state.send({ kind: 'kana', text: 'う' });
  await state.send({ kind: 'convert' });
  const resized = await state.send({ kind: 'compositionArrow', text: 'left' });
  assert.equal(resized.candidateCount, 2);
  assert.equal(state.engine.getConversionReading(), 'あ');
  const selected = await state.send({ kind: 'select', candidateId: 23 });
  assert.equal(selected.effects[0].text, '阿');
  assert.equal(state.engine.getPreedit(), '雨');
  assert.equal(selected.candidateCount, 1);
  state.bridge.assertDone();
});

test('partial commit effect survives failure to refresh remaining candidates', async () => {
  const state = rig([
    { operation: 'convert', text: 'a', output: response('あ') },
    { operation: 'convert', text: 'u', output: response('あう') },
    { operation: 'space', output: response('亜雨', { focused_id: 7, candidates: [{ id: 7, value: '亜' }] }) },
    { operation: 'submitCandidate', candidateId: 7, output: response('う', { result: '亜', focused_id: 8 }) },
    { operation: 'highlightCandidate', error: new Error('Refresh unavailable') }
  ]);
  await state.send({ kind: 'kana', text: 'あ' });
  await state.send({ kind: 'kana', text: 'う' });
  await state.send({ kind: 'convert' });
  const result = await state.send({ kind: 'enter' });
  assert.equal(result.effects[0].text, '亜');
  assert.equal(state.engine.getPreedit(), 'う');
  state.bridge.assertDone();
});

test('C06: UTF-16 cursor metadata does not split a non-BMP literal', async () => {
  const state = rig([
    { operation: 'literal', text: '😀', output: response('😀', { caret_utf16: 2 }) },
    { operation: 'convert', text: 'a', output: response('😀あ', { caret_utf16: 3 }) },
    { operation: 'arrowLeft', output: response('😀あ', { caret_utf16: 2 }) }
  ]);
  await state.send({ kind: 'text', text: '😀' });
  await state.send({ kind: 'kana', text: 'あ' });
  const result = await state.send({ kind: 'compositionArrow', text: 'left' });
  assert.equal(result.caretUtf16, 2);
  assert.equal(state.engine.getCursorPreview(), '😀│あ');
  state.bridge.assertDone();
});

test('unavailable bridge preparation is reported without executing commands', async () => {
  const bridge = new ScriptedBridge([], false);
  const result = await new MozcEngine(bridge).dispatch('s', 1, 1, { kind: 'kana', text: 'あ' });
  assert.notEqual(result.errorCode, 0);
  assert.equal(result.errorRecoverable, false);
  assert.deepEqual(bridge.calls, []);
});
