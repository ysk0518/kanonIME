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

for (const scenario of ['conversion', 'resized conversion', 'remaining conversion after partial commit']) {
  test(`P35: Backspace cancels ${scenario} before deleting the next character`, async () => {
    const candidates = [{ id: 21, value: '今日' }, { id: 22, value: '京' }];
    const conversion = { focused_reading: 'きょう', focused_id: 22, candidates, segcount: 2 };
    const steps = [
      { operation: 'literal', text: 'きょうは', output: response('きょうは') },
      { operation: 'space', output: response('京は', conversion) }
    ];
    if (scenario !== 'conversion') {
      steps.push({ operation: 'arrowLeft', output: response('木ょうは', {
        focused_reading: 'き', focused_id: 23, candidates: [{ id: 23, value: '木' }], segcount: 2
      }) });
    }
    const partial = scenario === 'remaining conversion after partial commit';
    if (partial) {
      const remaining = { focused_reading: 'ょうは', focused_id: 24, candidates: [{ id: 24, value: 'ょう派' }] };
      steps.push({ operation: 'submitCandidate', candidateId: 23, output: response('ょう派', { ...remaining, result: '木' }) },
        { operation: 'highlightCandidate', candidateId: 24, output: response('ょう派', remaining) });
    }
    const reading = partial ? 'ょうは' : 'きょうは';
    // MS-IME keymap: Conversion Backspace Cancel, then Composition Backspace Delete.
    steps.push({ operation: 'backspace', output: response(reading, {
      candidates: [{ id: 25, value: reading }]
    }) }, { operation: 'backspace', output: response(reading.slice(0, -1)) });
    const state = rig(steps);
    await state.send({ kind: 'text', text: 'きょうは' });
    let previous = await state.send({ kind: 'convert' });
    assert.equal(state.engine.getSelIdx(), 1);
    if (scenario !== 'conversion') {
      previous = await state.send({ kind: 'compositionArrow', text: 'left' });
    }
    if (partial) {
      previous = await state.send({ kind: 'enter' });
      assert.equal(previous.effects[0].text, '木');
    }
    assert.equal(previous.phase, 'converting');
    const reverted = await state.send({ kind: 'backspace' });
    assert.equal(reverted.phase, 'composing');
    assert.equal(reverted.revision, previous.revision + 1);
    assert.equal(reverted.candidateRevision, reverted.revision);
    assert.equal(state.engine.getPreedit(), reading);
    assert.equal(state.engine.getConversionReading(), '');
    assert.equal(state.engine.getSelIdx(), -1);
    assert.deepEqual(reverted.candidates, [{ id: 25, label: reading }]);
    assert.deepEqual(reverted.effects, []);
    await state.send({ kind: 'backspace' });
    assert.equal(state.engine.getPreedit(), reading.slice(0, -1));
    state.bridge.assertDone();
  });
}

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

test('P41: explicit kana modifiers replace the last kana and unsupported modifiers do not edit', async () => {
  for (const [kana, input, modifier, expected, replacement] of [
    ['つ', 'tsu', 'voiced', 'づ', 'du'],
    ['は', 'ha', 'semiVoiced', 'ぱ', 'pa'],
    ['ぱ', 'pa', 'voiced', 'ば', 'ba'],
    ['ば', 'ba', 'semiVoiced', 'ぱ', 'pa'],
    ['う', 'u', 'size', 'ぅ', 'lu'],
    ['っ', 'ltsu', 'size', 'つ', 'tsu'],
    ['な', 'na', 'voiced', 'な'],
    ['か', 'ka', 'semiVoiced', 'か'],
    ['ば', 'ba', 'size', 'ば'],
    ['が', 'ga', 'voiced', 'が']
  ]) {
    const steps = [{ operation: 'convert', text: input, output: response(kana) }];
    if (replacement !== undefined) {
      steps.push({ operation: 'reset', output: response() },
        { operation: 'convert', text: replacement, output: response(expected) });
    }
    const state = rig(steps);
    const before = await state.send({ kind: 'kana', text: kana });
    const after = await state.send({ kind: 'modifyKana', text: modifier });
    assert.equal(state.engine.getPreedit(), expected);
    assert.equal(after.revision, before.revision + (replacement === undefined ? 0 : 1));
    assert.deepEqual(after.effects, []);
    assert.equal(state.bridge.calls.length, steps.length);
    state.bridge.assertDone();
  }
});

test('P41: an explicit modifier edits at the live cursor after partial commit', async () => {
  const state = rig([...partialSuggestionSteps(),
    { operation: 'convert', text: 'ha', output: response('あは', { caret_utf16: 2 }) },
    { operation: 'convert', text: 'u', output: response('あはう', { caret_utf16: 3 }) },
    { operation: 'arrowLeft', output: response('あはう', { caret_utf16: 2 }) },
    { operation: 'backspace', output: response('あう', { caret_utf16: 1 }) },
    { operation: 'convert', text: 'pa', output: response('あぱう', { caret_utf16: 2 }) }
  ]);
  await selectEditedPrefix(state);
  await state.send({ kind: 'kana', text: 'は' });
  await state.send({ kind: 'kana', text: 'う' });
  await state.send({ kind: 'compositionArrow', text: 'left' });
  const before = await state.send({ kind: 'modifyKana', text: 'size' });
  assert.equal(state.engine.getPreedit(), 'あはう');
  assert.equal(state.bridge.calls.at(-1).operation, 'arrowLeft');
  const after = await state.send({ kind: 'modifyKana', text: 'semiVoiced' });
  assert.equal(after.revision, before.revision + 1);
  assert.equal(state.engine.getCursorPreview(), 'あぱ│う');
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

function deferredRig(steps) {
  const bridge = new ScriptedBridge(steps);
  const engine = new MozcEngine(bridge, true);
  let sequence = 0;
  return { bridge, engine, send: event => engine.dispatch('test-session', 1, ++sequence, event) };
}

test('P49: deferred keys update only the preedit; suggest fetches candidates for complete kana', async () => {
  const r = deferredRig([
    { operation: 'convert', text: 'k', candidateId: 1, output: response('ｋ') },
    { operation: 'convert', text: 'a', candidateId: 1, output: response('か') },
    { operation: 'suggest', text: '', candidateId: 1, output: response('か', { candidates: [{ id: 0, value: '蚊' }] }) }
  ]);
  const k = await r.send({ kind: 'text', text: 'k' });
  assert.equal(k.preeditLen, 1);
  const a = await r.send({ kind: 'text', text: 'a' });
  assert.equal(r.engine.needsSuggestion(), true);
  assert.deepEqual(a.candidates, []);
  const s = await r.send({ kind: 'suggest' });
  assert.deepEqual(s.candidates, [{ id: 0, label: '蚊' }]);
  assert.equal(s.candidateRevision, s.revision);
  assert.equal(r.engine.needsSuggestion(), false);
  r.bridge.assertDone();
});

test('P50: a pending roman letter is suggested by retyping it, not by moving the cursor', async () => {
  const r = deferredRig([
    { operation: 'convert', text: 'a', candidateId: 1, output: response('あ') },
    { operation: 'suggest', text: '', candidateId: 1, output: response('あ', { candidates: [{ id: 0, value: '亜' }] }) },
    { operation: 'convert', text: 'h', candidateId: 1, output: response('あｈ') },
    // MOVE_CURSOR would split "h" from the next vowel; the bridge deletes and retypes it.
    { operation: 'suggest', text: 'h', output: response('あｈ', { candidates: [{ id: 0, value: 'あは' }] }) },
    { operation: 'convert', text: 'a', candidateId: 1, output: response('あは') }
  ]);
  await r.send({ kind: 'text', text: 'a' });
  await r.send({ kind: 'suggest' });
  const h = await r.send({ kind: 'text', text: 'h' });
  assert.equal(r.engine.needsSuggestion(), true);
  // The candidates for "あ" stay shown, stale, until the retype answers.
  assert.deepEqual(h.candidates, [{ id: 0, label: '亜' }]);
  assert.ok(h.revision > h.candidateRevision);
  const s = await r.send({ kind: 'suggest' });
  assert.deepEqual(s.candidates, [{ id: 0, label: 'あは' }]);
  assert.equal(s.candidateRevision, s.revision);
  const ha = await r.send({ kind: 'text', text: 'a' });
  assert.equal(ha.preeditLen, 2);
  r.bridge.assertDone();
});

test('P50: a retype that changed the composition shows what Mozc holds', async () => {
  const r = deferredRig([
    { operation: 'convert', text: 'a', candidateId: 1, output: response('あ') },
    { operation: 'convert', text: 'k', candidateId: 1, output: response('あｋ') },
    { operation: 'suggest', text: 'k', output: response('あｋｋ', { candidates: [{ id: 0, value: 'あkk' }] }) }
  ]);
  await r.send({ kind: 'text', text: 'a' });
  await r.send({ kind: 'text', text: 'k' });
  const s = await r.send({ kind: 'suggest' });
  assert.equal(s.preeditLen, 3);
  assert.deepEqual(s.candidates, [{ id: 0, label: 'あkk' }]);
  r.bridge.assertDone();
});

test('P51: the first roman letters of a word are not suggested', async () => {
  // Predicting from "s" or "sh" takes 100-300 ms on the device and delays the next key.
  const r = deferredRig([
    { operation: 'convert', text: 's', candidateId: 1, output: response('ｓ') },
    { operation: 'convert', text: 'h', candidateId: 1, output: response('ｓｈ') },
    { operation: 'convert', text: 'i', candidateId: 1, output: response('し') }
  ]);
  const s = await r.send({ kind: 'text', text: 's' });
  assert.equal(r.engine.needsSuggestion(), false);
  assert.deepEqual(s.candidates, []);
  await r.send({ kind: 'text', text: 'h' });
  assert.equal(r.engine.needsSuggestion(), false);
  await r.send({ kind: 'text', text: 'i' });
  assert.equal(r.engine.needsSuggestion(), true);
  r.bridge.assertDone();
});

test('P50: a tail that is not the letter just typed is not suggested', async () => {
  const r = deferredRig([
    { operation: 'convert', text: 'x', candidateId: 1, output: response('あ!') }
  ]);
  await r.send({ kind: 'text', text: 'x' });
  assert.equal(r.engine.needsSuggestion(), false);
  r.bridge.assertDone();
});

test('P49: the previous candidates stay shown but stale until the suggestion arrives', async () => {
  const r = deferredRig([
    { operation: 'convert', text: 'a', candidateId: 1, output: response('あ') },
    { operation: 'suggest', candidateId: 1, output: response('あ', { candidates: [{ id: 0, value: '亜' }] }) },
    { operation: 'convert', text: 'i', candidateId: 1, output: response('あい') }
  ]);
  await r.send({ kind: 'text', text: 'a' });
  const shown = await r.send({ kind: 'suggest' });
  const typed = await r.send({ kind: 'text', text: 'i' });
  assert.deepEqual(typed.candidates, [{ id: 0, label: '亜' }]);
  // The coordinator rejects a tap whose candidate revision is older than the composition.
  assert.equal(typed.candidateRevision, shown.revision);
  assert.ok(typed.revision > typed.candidateRevision);
  r.bridge.assertDone();
});

test('P49: suggest without a pending suggestion or after the preedit changed leaves the composition', async () => {
  const r = deferredRig([
    { operation: 'convert', text: 'a', candidateId: 1, output: response('あ') },
    { operation: 'suggest', candidateId: 1, output: response('ア') }
  ]);
  const none = await r.send({ kind: 'suggest' });
  assert.equal(none.hasPreedit, false);
  await r.send({ kind: 'text', text: 'a' });
  const changed = await r.send({ kind: 'suggest' });
  assert.equal(changed.hasPreedit, true);
  assert.equal(changed.preeditLen, 1);
  r.bridge.assertDone();
});

test('P49: a caret moved inside the composition keeps suggestions with the key', async () => {
  const r = deferredRig([
    { operation: 'convert', text: 'a', candidateId: 1, output: response('あ') },
    { operation: 'convert', text: 'u', candidateId: 1, output: response('あう') },
    { operation: 'arrowLeft', output: response('あう', { caret_utf16: 1 }) },
    { operation: 'convert', text: 'i', candidateId: 0, output: response('あいう', {
      caret_utf16: 2, candidates: [{ id: 3, value: '愛' }] }) }
  ]);
  await r.send({ kind: 'text', text: 'a' });
  await r.send({ kind: 'text', text: 'u' });
  await r.send({ kind: 'compositionArrow', text: 'left' });
  const typed = await r.send({ kind: 'text', text: 'i' });
  assert.deepEqual(typed.candidates, [{ id: 3, label: '愛' }]);
  r.bridge.assertDone();
});
