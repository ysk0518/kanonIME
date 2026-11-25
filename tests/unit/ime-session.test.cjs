const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { ImeSession } = require('../../entry/src/main/ets/kanon/ImeSession.ets');
const { EnglishPrediction } = require('../../entry/src/main/ets/kanon/EnglishPrediction.ets');
const { MozcEngine } = require('../../entry/src/main/ets/kanon/MozcEngine.ets');
const { ImeRuntimeBindings } = require('../../entry/src/main/ets/kanon/ImeRuntimeBindings.ets');
const { ImeViewPublisher } = require('../../entry/src/main/ets/kanon/ImeViewPublisher.ets');
const { cancelEditorPreview } = require('../../entry/src/main/ets/kanon/PreviewLifecycle.ets');
const { FakeEditor, ScriptedBridge, response, deferred } = require('../support/fakes.cjs');
const { mutate } = require('../support/source-mutations.cjs');

function rig({ mode = 'EN', supported = true, origin = '', steps = [] } = {}) {
  const editor = new FakeEditor(origin);
  editor.supported = supported;
  const bridge = new ScriptedBridge(steps);
  const trace = [];
  const prediction = new EnglishPrediction({
    undoChanged: value => trace.push(['undo', value]),
    cleared: () => {},
    selectionAbandoned: () => {}
  });
  const store = new Map([
    ['kanonLayout', mode === 'EN' ? 'en_qwerty' : 'jp_qwerty'],
    ['kanonLayoutOrder', 'jp_qwerty,en_qwerty']
  ]);
  const writes = [];
  const write = (key, value) => {
    writes.push([key, value]);
    store.set(key, value);
  };
  const bindings = new ImeRuntimeBindings({
    readString: key => store.get(key), readNumber: key => store.get(key),
    string: write, number: write, boolean: write, flickEnabled: () => true,
    saveLayoutOrder: async order => write('kanonLayoutOrder', order),
    getEpoch: () => editor.epoch, queryCursor: () => editor.queryCursor()
  }, { normal: 0, password: 8, numberPassword: 9, newPassword: 11 });
  const hooks = {
    queryEmpty: async () => ({ ok: true, code: 0, value: editor.text === '' }),
    enterKeyAction: async () => {}
  };
  const view = new ImeViewPublisher({
    string: write, number: write, boolean: write, strings: write, numbers: write
  });
  const session = new ImeSession({
    editor, queryEmpty: () => hooks.queryEmpty(),
    cancelPreview: () => cancelEditorPreview(editor),
    bindings, prediction, viewPublisher: view, engine: new MozcEngine(bridge),
    enterKeyAction: async epoch => {
      trace.push(['enter', epoch]);
      await hooks.enterKeyAction();
    },
    log: (_tag, message) => trace.push(['log', message])
  });
  return {
    session, editor, prediction, bridge, hooks, trace, store, view,
    send: request => session.postRequest(request),
    published: () => writes.filter(([key]) => key === 'kanonTick').length
  };
}

// Observe the real collaborators at dispatch boundaries, including calls that
// would otherwise be masked by a downstream guard. Every observed call still runs.
function observe(owner, method, record) {
  const original = owner[method];
  owner[method] = function (...args) {
    record(...args);
    return original.apply(this, args);
  };
}

function recordDispatch(session) {
  const kinds = [];
  observe(session.coord, 'postEvent', event => kinds.push(event.kind));
  return kinds;
}

function replaceEditorText(editor, text) {
  editor.text = text;
  editor.cursor = text.length;
  editor.preview = null;
}

async function completedWord(r) {
  await r.session.keyText('hel');
  await r.session.keySpace();
  await r.session.keyReturn();
  assert.equal(r.editor.text, 'hello');
}

async function japaneseCommit({ converting = false, origin = '前', reading = 'き', committed = 'き',
  steps = [], supported = true } = {}) {
  const conversion = { focused_id: 1, focused_reading: reading, candidates: [{ id: 1, value: committed }] };
  const r = rig({ mode: 'JP', origin, supported, steps: [
    { operation: 'literal', text: reading, output: response(reading) },
    ...(converting ? [
      { operation: 'space', output: response(committed, conversion) },
      { operation: 'submitCandidate', candidateId: 1, output: response('', { result: committed }) }
    ] : [{ operation: 'submitReading', output: response('', { result: committed }) }]),
    ...steps
  ] });
  await r.session.keyText(reading);
  if (converting) { await r.session.keySpace(); }
  await r.session.keyReturn();
  assert.equal(r.editor.text, origin + committed);
  assert.equal(r.editor.preview, null);
  return { ...r, conversion };
}

function undoStep(preedit, deletionLength, deletionOffset = -deletionLength, options = {}) {
  return { operation: 'undo', output: response(preedit, {
    deletion_offset: deletionOffset, deletion_length: deletionLength, ...options
  }) };
}

test('P40: Japanese undo deletes the range before restoring the conversion preview', async () => {
  const r = await japaneseCommit({ converting: true, reading: 'きょう', committed: '今日', steps: [
    undoStep('今日', 2, -2, { focused_id: 1, focused_reading: 'きょう', candidates: [{ id: 1, value: '今日' }] })
  ] });
  r.session.selectionChanged(3, 3); // The IME's commit notification matches the recorded end.
  r.editor.calls.length = 0;
  await r.session.keyUndo();
  assert.deepEqual(r.editor.calls, [
    { operation: 'deleteForward', length: 2 },
    { operation: 'setPreview', text: '今日', start: -1, end: -1 }
  ]);
  assert.deepEqual(r.editor.preview, { start: 1, end: 3 });
  assert.equal(r.editor.text, '前今日');
  assert.equal(r.store.get('kanonState'), 'JP_CONVERTING');
  assert.equal(r.store.get('kanonSel'), 0);
  await r.session.keyUndo();
  assert.equal(r.editor.count('deleteForward'), 1);
  r.bridge.assertDone();
});

test('P40: undo places the restored preview at the commit start even if the cursor read is stale', async () => {
  // Device 2026-11-26: right after deleteForward the platform can still report
  // the old cursor. A preview placed there shifted later edits by one character.
  const r = await japaneseCommit({ converting: true, reading: 'きょう', committed: '今日', steps: [
    undoStep('今日', 2, -2, { focused_id: 1, focused_reading: 'きょう', candidates: [{ id: 1, value: '今日' }] }),
    { operation: 'backspace', output: response('きょう') }
  ] });
  r.session.selectionChanged(3, 3);
  const realQuery = r.editor.queryCursor.bind(r.editor);
  let deleted = false;
  r.editor.deleteForward = async length => {
    assert.equal(length, 2);
    r.editor.text = '前';
    r.editor.cursor = 1;
    deleted = true;
    return { ok: true, code: 0 };
  };
  // The platform inserts at the real cursor but the read still reports the old one.
  r.editor.queryCursor = async () => deleted ? 3 : realQuery();
  await r.session.keyUndo();
  assert.deepEqual(r.editor.preview, { start: 1, end: 3 });
  assert.equal(r.editor.text, '前今日');
  // Caret and composition-cursor mapping use this origin (device: a stale origin of 3
  // turned the next Delete into deleting the first reading character).
  assert.equal(r.session.preview.getStart(), 1);
  // The next edit replaces the tracked range; an origin of 3 would leave 今日 behind.
  r.editor.queryCursor = realQuery;
  await r.session.keyDelete();
  assert.equal(r.editor.text, '前きょう');
  assert.deepEqual(r.editor.preview, { start: 1, end: 4 });
  r.bridge.assertDone();
});

test('P40: undo restores unconverted reading without using UTF-16 width for deleteForward', async () => {
  const r = await japaneseCommit({ reading: '😀', committed: '😀', steps: [undoStep('😀', 1)] });
  r.editor.deleteForward = async length => {
    assert.equal(length, 1);
    r.editor.text = '前';
    r.editor.cursor = 1;
    return { ok: true, code: 0 };
  };
  await r.session.keyUndo();
  assert.equal(r.editor.text, '前😀');
  assert.deepEqual(r.editor.preview, { start: 1, end: 3 });
  assert.equal(r.store.get('kanonState'), 'JP_COMPOSING');
  r.bridge.assertDone();
});

test('P40: a different committed string resets Japanese undo without deleting anything', async () => {
  const r = await japaneseCommit({ steps: [undoStep('き', 1), { operation: 'reset', output: response() }] });
  replaceEditorText(r.editor, '前他');
  r.editor.calls.length = 0;
  await r.session.keyUndo();
  assert.equal(r.editor.text, '前他');
  assert.deepEqual(r.editor.calls, []);
  assert.equal(r.bridge.calls.at(-1).operation, 'reset');
  r.bridge.assertDone();
});

test('P40: a nonadjacent deletion offset resets Japanese undo without writing to the editor', async () => {
  const r = await japaneseCommit({ steps: [undoStep('き', 1, -2), { operation: 'reset', output: response() }] });
  r.editor.calls.length = 0;
  await r.session.keyUndo();
  assert.equal(r.editor.text, '前き');
  assert.deepEqual(r.editor.calls, []);
  assert.equal(r.bridge.calls.at(-1).operation, 'reset');
  r.bridge.assertDone();
});

test('P40: a Mozc range that spans fewer Harmony graphemes never deletes preceding text', async () => {
  const r = await japaneseCommit({ reading: '🇯🇵', committed: '🇯🇵',
    steps: [undoStep('🇯🇵', 2), { operation: 'reset', output: response() }] });
  r.editor.calls.length = 0;
  await r.session.keyUndo();
  assert.equal(r.editor.text, '前🇯🇵');
  assert.deepEqual(r.editor.calls, []);
  assert.equal(r.bridge.calls.at(-1).operation, 'reset');
  r.bridge.assertDone();
});

test('P40: an editor change during the undo response leaves the new field untouched', async () => {
  const started = deferred(), release = deferred();
  const r = await japaneseCommit({ steps: [
    { operation: 'undo', output: () => { started.resolve(); return release.promise; } }
  ] });
  const pending = r.session.keyUndo();
  await started.promise;
  replaceEditorText(r.editor, '新しい入力欄');
  r.editor.epoch++;
  r.editor.calls.length = 0;
  release.resolve(undoStep('き', 1).output);
  await pending;
  assert.equal(r.editor.text, '新しい入力欄');
  assert.deepEqual(r.editor.calls, []);
  r.bridge.assertDone();
});

test('P40: an editor change during the final undo cursor check blocks deletion', async () => {
  const r = await japaneseCommit({ steps: [undoStep('き', 1)] });
  r.editor.calls.length = 0;
  let checks = 0;
  r.editor.queryCursor = async () => {
    if (++checks === 2) { r.editor.epoch++; }
    return r.editor.cursor;
  };
  await r.session.keyUndo();
  assert.equal(r.editor.text, '前き');
  assert.deepEqual(r.editor.calls, []);
  r.bridge.assertDone();
});

for (const action of ['arrow', 'selection notification', 'paste', 'language switch', 'next input']) {
  test(`P40: ${action} invalidates Japanese undo before dispatch`, async () => {
    const r = await japaneseCommit({ steps: action === 'next input' ? [
      { operation: 'literal', text: 'う', output: response('う') }
    ] : [] });
    if (action === 'arrow') { await r.session.keyMove('left'); }
    if (action === 'selection notification') {
      r.session.selectionChanged(1, 1);
      r.session.selectionChanged(2, 2);
    }
    if (action === 'paste') { await r.session.keyPaste('!'); }
    if (action === 'language switch') {
      await r.session.switchMode();
      await r.session.switchMode();
    }
    if (action === 'next input') { await r.session.keyText('う'); }
    r.editor.calls.length = 0;
    await r.session.keyUndo();
    assert.equal(r.bridge.calls.some(call => call.operation === 'undo'), false);
    assert.deepEqual(r.editor.calls, []);
    r.bridge.assertDone();
  });
}

test('P40: Japanese undo without a commit never rewinds pending input', async () => {
  const r = rig({ mode: 'JP', steps: [{ operation: 'literal', text: 'き', output: response('き') }] });
  await r.session.keyText('き');
  r.editor.calls.length = 0;
  await r.session.keyUndo();
  assert.equal(r.editor.text, 'き');
  assert.deepEqual(r.editor.calls, []);
  assert.deepEqual(r.bridge.calls.map(call => call.operation), ['literal']);
  r.bridge.assertDone();
});

test('P40: Japanese undo skips a partial commit when its remaining preview follows the boundary', async () => {
  const r = rig({ mode: 'JP', origin: '前', steps: [
    { operation: 'literal', text: 'きょうは', output: response('きょうは') },
    { operation: 'space', output: response('今日は', { focused_id: 1, candidates: [{ id: 1, value: '今日' }] }) },
    { operation: 'submitCandidate', candidateId: 1, output: response('は', { result: '今日' }) }
  ] });
  await r.session.keyText('きょうは');
  await r.session.keySpace();
  await r.session.keyReturn();
  assert.deepEqual(r.editor.preview, { start: 3, end: 4 });
  r.editor.calls.length = 0;
  await r.session.keyUndo();
  assert.equal(r.editor.text, '前今日は');
  assert.deepEqual(r.editor.calls, []);
  assert.equal(r.bridge.calls.some(call => call.operation === 'undo'), false);
  r.bridge.assertDone();
});

test('P40: a native undo response without a deletion range leaves the editor alone', async () => {
  const r = await japaneseCommit({ steps: [{ operation: 'undo', output: response() }] });
  r.editor.calls.length = 0;
  await r.session.keyUndo();
  await r.session.keyUndo();
  assert.equal(r.editor.text, '前き');
  assert.deepEqual(r.editor.calls, []);
  assert.equal(r.bridge.calls.filter(call => call.operation === 'undo').length, 1);
  r.bridge.assertDone();
});

for (const supported of [true, false]) {
  test(`P40: ↺ uses English completion undo with preview support ${supported}`, async () => {
    const r = rig({ supported });
    await completedWord(r);
    const kinds = recordDispatch(r.session);
    await r.session.keyUndo();
    assert.equal(r.editor.text, 'hel');
    assert.equal(r.editor.count('deleteForward'), 1);
    assert.deepEqual(kinds, ['undoCompletion']);
    assert.deepEqual(r.bridge.calls, []);
  });
}

test('P40: the 12-key 変換 and 候補 controls route through Space', async () => {
  function component(name) {
    const path = `components/${name}.ets`;
    const source = readFileSync(resolve(__dirname, '../../entry/src/main/ets', path), 'utf8');
    const mutation = process.env.KANON_TEST_MUTATION;
    return mutation ? mutate(path, source, mutation) : source;
  }
  for (const name of ['FlickMenu', 'NumberFlickMenu']) {
    assert.match(component(name), /ModeCycleItem\(\{[^}]*flick: true/);
  }
  const modeKey = component('ModeCycleItem');
  assert.match(modeKey, /if \(this\.converts\(\)\) \{\s*Text\(\$r\('app\.string\.keyboard_convert'\)\)/);
  assert.match(modeKey, /if \(this\.converts\(\)\) \{ await kanonIme\.keySpace\(\); return; \}/);
  const candidateKey = component('ConvertSpaceItem');
  assert.match(candidateKey, /this\.japaneseComposing \? \$r\('app\.string\.keyboard_candidates'\)/);
  assert.match(candidateKey, /kanonIme\.keySpace\(\)/);
  const r = rig({ mode: 'JP', steps: [
    { operation: 'literal', text: 'き', output: response('き') },
    { operation: 'space', output: response('木', { candidates: [{ id: 1, value: '木' }], focused_id: 1 }) }
  ] });
  await r.session.keyText('き');
  await r.session.keySpace();
  assert.equal(r.store.get('kanonState'), 'JP_CONVERTING');
  r.bridge.assertDone();
});

for (const converting of [false, true]) {
  test(`P35: candidate cancel closes the list while ${converting ? 'reverting conversion' : 'preserving input'}`, async () => {
    const candidates = [{ id: 1, value: 'きょう' }];
    const steps = [{ operation: 'literal', text: 'きょ', output: response('きょ', { candidates }) }];
    if (converting) {
      steps.push({ operation: 'space', output: response('今日', {
        focused_reading: 'きょ', focused_id: 2, candidates: [{ id: 2, value: '今日' }]
      }) }, { operation: 'backspace', output: response('きょ', { candidates }) });
    }
    const r = rig({ mode: 'JP', origin: 'A', steps: [...steps, { operation: 'reset', output: response() }] });
    await r.session.keyText('きょ');
    if (converting) { await r.session.keySpace(); }
    r.store.set('kanonCandidatesExpanded', true);
    const kinds = recordDispatch(r.session);
    await r.session.revertConversion();
    assert.equal(r.store.get('kanonCandidatesExpanded'), false);
    assert.equal(r.editor.text, 'Aきょ');
    assert.equal(r.store.get('kanonState'), 'JP_COMPOSING');
    assert.equal(r.store.get('kanonSel'), -1);
    assert.deepEqual(kinds, converting ? ['backspace'] : []);
    assert.equal(r.editor.count('insert'), 0);
    await r.session.cancelCompose();
    assert.equal(r.editor.text, 'A');
    assert.equal(kinds.at(-1), 'cancel');
    r.bridge.assertDone();
  });
}

for (const action of ['Delete', 'candidate cancel']) {
  test(`P36: direct English ${action} clears the highlight before the next Delete edits the field`, async () => {
    const r = rig({ supported: false });
    await r.session.keyText('he');
    await r.session.keySpace();
    assert.ok(r.prediction.getSelectedIndex() >= 0);
    const candidates = r.prediction.getItems();
    const kinds = recordDispatch(r.session);
    if (action === 'Delete') { await r.session.keyDelete(); }
    else { await r.session.revertConversion(); }
    assert.equal(r.editor.text, 'he');
    assert.equal(r.prediction.getPrefix(), 'he');
    assert.deepEqual(r.prediction.getItems(), candidates);
    assert.equal(r.store.get('kanonSel'), -1);
    assert.deepEqual(kinds, []);
    assert.equal(r.editor.count('deleteForward'), 0);
    await r.session.keyDelete();
    assert.equal(r.editor.text, 'h');
    assert.equal(r.prediction.getPrefix(), 'h');
    assert.deepEqual(kinds, ['backspace']);
    assert.equal(r.editor.count('deleteForward'), 1);
  });
}

test('P39: direct English Delete uses the same one-character request as Japanese confirmed text', async () => {
  // HarmonyOS counts deleteForward in characters (device D25); the fake editor does not.
  const r = rig({ supported: false, origin: 'Ae\u0301' });
  await r.session.keyDelete();
  assert.deepEqual(r.editor.calls, [{ operation: 'deleteForward', length: 1 }]);
});

test('P38: session does not retry preview placement after an unknown partial-commit origin', async () => {
  const r = rig({ mode: 'JP', origin: 'A', steps: [
    { operation: 'literal', text: 'きょうは', output: response('きょうは') },
    { operation: 'space', output: response('今日は', {
      focused_id: 1, candidates: [{ id: 1, value: '今日' }]
    }) },
    { operation: 'submitCandidate', candidateId: 1, output: response('は', { result: '今日' }) }
  ] });
  await r.session.keyText('きょうは');
  await r.session.keySpace();
  r.session.preview.reset();
  let queries = 0;
  r.editor.queryCursor = async () => ++queries === 1 ? -1 : r.editor.cursor;
  const previews = r.editor.count('setPreview');
  await r.session.keyReturn();
  assert.equal(r.editor.text, 'A今日');
  assert.equal(r.session.coord.getSnapshot().preeditLen, 1);
  assert.equal(r.session.preview.getStart(), -1);
  assert.equal(queries, 1);
  assert.equal(r.editor.count('setPreview'), previews);
  r.bridge.assertDone();
});

test('P29: R-01: requests queued for the old editor return the latest snapshot without dispatch', async () => {
  const r = rig({ mode: 'JP' });
  const started = deferred(), release = deferred();
  r.editor.queryPreviewSupported = async () => {
    started.resolve();
    return release.promise;
  };
  const first = r.send({ kind: 'prepare' });
  await started.promise;
  const queued = r.send({ kind: 'text', text: 'k' });
  r.editor.epoch++;
  release.resolve(true);
  await first;
  assert.deepEqual(await queued, r.session.coord.getSnapshot());
  assert.deepEqual(r.bridge.calls, []);
  assert.deepEqual(r.editor.calls, []);
});

test('P29: R-01: an editor change during admission stops the running request', async () => {
  const r = rig({ mode: 'JP' });
  const started = deferred(), release = deferred();
  r.editor.queryPreviewSupported = async () => {
    started.resolve();
    return release.promise;
  };
  const externalReads = [];
  observe(r.session.editorSync, 'reconcile', () => externalReads.push('reconcile'));
  const pending = r.send({ kind: 'text', text: 'k' });
  await started.promise;
  r.editor.epoch++;
  release.resolve(true);
  assert.deepEqual(await pending, r.session.coord.getSnapshot());
  assert.deepEqual(r.bridge.calls, []);
  assert.deepEqual(externalReads, []);
  assert.equal(r.published(), 0);
});

for (const kind of ['select', 'partial', 'undoEnglish']) {
  test('P29: R-02: ' + kind + ' queued before discard is obsolete', async () => {
    const r = rig({ steps: [{ operation: 'reset', output: response() }] });
    await r.session.keyText('hel');
    const kinds = recordDispatch(r.session);
    const undo = [];
    observe(r.session.completion, 'undo', request => undo.push(request));
    const discard = r.session.discardTypingText();
    const pending = r.send({ kind, candidateId: 0, expectedRevision: r.session.coord.getCandidateRevision() });
    await discard;
    assert.deepEqual(await pending, r.session.coord.getSnapshot());
    assert.deepEqual(kinds, []);
    assert.deepEqual(undo, []);
    assert.equal(r.published(), 2);
    r.bridge.assertDone();
  });
}

async function japaneseCursorRig(steps = []) {
  const r = rig({ mode: 'JP', origin: 'A', steps: [
    { operation: 'convert', text: 'k', output: response('ｋ') }, ...steps
  ] });
  await r.session.keyText('k');
  assert.equal(r.session.coord.isPreviewCaretAligned(), true);
  r.session.selectionChanged(1, 1);
  r.editor.queryCursor = async () => -1;
  return r;
}

for (const kind of ['cancel', 'cycle', 'config']) {
  test('P29: R-03: ' + kind + ' bypasses pending composition cursor synchronization', async () => {
    const operation = kind === 'cancel' ? 'reset' : 'submitReading';
    const r = await japaneseCursorRig([{ operation, output: response('', { result: kind === 'cancel' ? '' : 'ｋ' }) }]);
    const calls = [];
    observe(r.session.cursorSync, 'reconcile', () => calls.push('reconcile'));
    const snapshot = await r.send({ kind, layoutOrder: 'jp_flick,en_flick' });
    assert.deepEqual(calls, []);
    assert.equal(snapshot.lastError, 'ok');
    assert.deepEqual(r.bridge.calls.map(call => call.operation), ['convert', operation]);
    r.bridge.assertDone();
  });
}

test('P29: R-03: cursor synchronization failure blocks ordinary and prepare requests', async () => {
  const r = await japaneseCursorRig();
  const kinds = recordDispatch(r.session);
  for (const request of [{ kind: 'text', text: 'i' }, { kind: 'prepare' }]) {
    const count = r.published();
    const snapshot = await r.send(request);
    assert.equal(snapshot.lastError, 'cursor-sync');
    assert.equal(snapshot.preeditLen, 1);
    assert.equal(r.published(), count + 1);
  }
  assert.deepEqual(kinds, []);
  assert.equal(r.bridge.calls.length, 1);
  assert.equal(r.editor.text, 'Aｋ');
});

for (const outcome of ['failed', 'stale']) {
  test('P29: R-04: external editor ' + outcome + ' read stops the request without reset or publish', async () => {
    const r = rig();
    await r.session.keyText('hel');
    // Leave a real notification pending for the router, independently of the
    // public notification handler's background queue, which is covered below.
    r.session.editorSync.textChanged(r.editor.epoch, true);
    r.hooks.queryEmpty = async () => {
      if (outcome === 'stale') { r.editor.epoch++; }
      return { ok: outcome === 'stale', code: -1, value: true };
    };
    const kinds = recordDispatch(r.session);
    const snapshot = await r.send({ kind: 'text', text: 'p' });
    assert.equal(snapshot.preeditLen, 3);
    assert.equal(r.session.preview.getLength(), 3);
    assert.equal(r.prediction.getPrefix(), 'hel');
    assert.equal(r.published(), 1);
    assert.deepEqual(kinds, []);
    assert.deepEqual(r.bridge.calls, []);
  });
}

for (const kind of ['prepare', 'cycle', 'config']) {
  test('P29: R-05: ' + kind + ' reaches local requests with the expected Undo ordering', async () => {
    const r = rig();
    await r.session.prepare();
    r.prediction.rememberCompletion('hel', 'hello', 5, r.editor.epoch);
    r.trace.length = 0;
    observe(r.session.localRequests, 'handle', (request, epoch) => r.trace.push(['local', request.kind, epoch]));
    await r.send({ kind, layoutOrder: 'jp_flick,en_flick' });
    const local = ['local', kind, r.editor.epoch];
    assert.deepEqual(r.trace.slice(0, kind === 'prepare' ? 1 : 2),
      kind === 'prepare' ? [local] : [['undo', false], local]);
    assert.equal(r.prediction.takeUndo()?.word, kind === 'prepare' ? 'hello' : undefined);
    assert.equal(r.store.get('kanonLayout'), { prepare: 'en_qwerty', cycle: 'jp_qwerty', config: 'en_flick' }[kind]);
  });
}

test('P29: R-06: explicit Undo that goes stale during editor validation never calls publish', async () => {
  const r = rig({ supported: false });
  await completedWord(r);
  const started = deferred(), release = deferred();
  r.editor.queryBefore = async () => {
    started.resolve();
    return release.promise;
  };
  const publications = [];
  observe(r.session, 'publish', snapshot => publications.push(snapshot));
  const pending = r.send({ kind: 'undoEnglish' });
  assert.equal(await Promise.race([started.promise.then(() => true), pending.then(() => false)]), true);
  r.editor.epoch++;
  release.resolve('hello');
  assert.deepEqual(await pending, r.session.coord.getSnapshot());
  assert.deepEqual(publications, []);
  assert.equal(r.editor.text, 'hello');
});

test('P29: R-07: direct English convert selects a prediction or re-enters the router with ASCII space', async () => {
  const r = rig({ supported: false });
  await r.session.prepare();
  const events = [];
  observe(r.session.coord, 'postEvent', event => events.push(event));
  await r.session.keySpace();
  assert.deepEqual(events.map(({ kind, text }) => [kind, text]), [['text', ' ']]);
  assert.equal(r.editor.text, ' ');
  assert.equal(r.published(), 1);
  await r.session.keyText('hel');
  await r.session.keySpace();
  assert.equal(r.prediction.getSelectedItem().label, 'hello');
  assert.equal(r.editor.text, ' hel');
  assert.equal(r.published(), 3);
});

test('P29: R-08: failed precommit returns the snapshot without dispatching paste', async () => {
  const r = rig();
  await r.session.keyText('he');
  const kinds = recordDispatch(r.session);
  r.editor.failInsert = true;
  assert.equal(await r.session.keyPaste('ABC'), false);
  assert.deepEqual(kinds, ['submit']);
  assert.equal(r.editor.text, 'he');
  assert.notEqual(r.store.get('kanonErr'), 'ok');
  assert.deepEqual(r.editor.calls.filter(call => call.operation === 'insert').map(call => call.text), ['he']);
});

test('P29: R-09: handled completion Undo consumes backspace before ordinary dispatch', async () => {
  const r = rig();
  await completedWord(r);
  const kinds = recordDispatch(r.session);
  await r.session.keyDelete();
  assert.deepEqual(kinds, ['undoCompletion']);
  assert.equal(r.editor.text, 'hel');
  assert.equal(r.store.get('kanonEnglishComposing'), true);
});

for (const kind of ['select', 'cancel', 'enter']) {
  test('P29: R-10: directly typed English routes ' + kind + ' through DirectEnglishInput', async () => {
    const r = rig({ supported: false });
    await r.session.keyText('hel');
    await r.session.keySpace();
    const kinds = recordDispatch(r.session);
    const handled = [];
    observe(r.session.directEnglish, 'handle', request => handled.push(request));
    const count = r.published();
    if (kind === 'select') { await r.session.selectCandidate(r.prediction.getSelectedItem().id); }
    if (kind === 'cancel') { await r.session.cancelCompose(); }
    if (kind === 'enter') { await r.session.keyReturn(); }
    assert.deepEqual(handled, [kind]);
    assert.deepEqual(kinds, [kind === 'cancel' ? 'cancel' : 'text']);
    assert.equal(r.editor.text, kind === 'cancel' ? 'hel' : 'hello');
    assert.equal(r.prediction.getPrefix(), '');
    assert.equal(r.published(), count + 1);
  });
}

test('P29: R-11: normal Enter action requires empty-submit; direct Enter uses the prefix rule', async () => {
  const composing = rig();
  await composing.session.keyText('he');
  assert.equal((await composing.send({ kind: 'enter' })).lastError, 'ok');
  assert.deepEqual(composing.trace.filter(([op]) => op === 'enter'), []);
  assert.equal((await composing.send({ kind: 'enter' })).lastError, 'empty-submit');
  assert.deepEqual(composing.trace.filter(([op]) => op === 'enter'), [['enter', 1]]);
  assert.equal((await composing.send({ kind: 'submit' })).lastError, 'empty-submit');
  assert.deepEqual(composing.trace.filter(([op]) => op === 'enter'), [['enter', 1], ['enter', 1]]);

  const direct = rig({ supported: false });
  await direct.session.keyText('he');
  await direct.session.keyReturn();
  assert.deepEqual(direct.trace.filter(([op]) => op === 'enter'), []);
  await direct.session.keyReturn();
  assert.deepEqual(direct.trace.filter(([op]) => op === 'enter'), [['enter', 1]]);
  assert.equal((await direct.send({ kind: 'submit' })).lastError, 'en-ignore');
  assert.deepEqual(direct.trace.filter(([op]) => op === 'enter'), [['enter', 1]]);
  assert.equal(direct.editor.text, 'he');
});

test('P29: R-12: a thrown port call publishes the snapshot and the queued next key succeeds', async () => {
  const r = rig();
  r.hooks.enterKeyAction = async () => { throw new Error('editor action failed'); };
  const failed = r.send({ kind: 'enter' });
  const next = r.send({ kind: 'text', text: 'he' });
  assert.equal((await failed).lastError, 'empty-submit');
  assert.equal((await next).lastError, 'ok');
  assert.equal(r.editor.text, 'he');
  assert.equal(r.published(), 2);
});

function recordReset(r) {
  const order = [];
  const s = r.session;
  const originalGeneration = s.compositionGeneration;
  const calls = [
    [s.editorSync, 'reset', 'external-sync'],
    [s.coord, 'onEditorChanged', 'coordinator'],
    [s.engine, 'resetLocal', 'mozc'],
    [s.englishEngine, 'resetLocal', 'english'],
    [r.prediction, 'clear', 'prediction'],
    [s.coord, 'loadPreviewSupport', 'load-support'],
    [s.preview, 'reset', 'preview'],
    [s.cursorSync, 'reset', 'cursor-sync'],
    [s.ports, 'cancelPreview', 'cancel-preview'],
    [r.view, 'publish', 'publish']
  ];
  for (const [owner, method, label] of calls) {
    observe(owner, method, () => {
      order.push(label);
      assert.equal(s.compositionGeneration, originalGeneration + 1);
    });
  }
  observe(s.ports, 'log', (_tag, message) => {
    order.push(message.split(' ')[1]);
  });
  return order;
}

function assertReset(r) {
  assert.equal(r.session.coord.getSnapshot().preeditLen, 0);
  assert.equal(r.session.englishEngine.getPreedit(), '');
  assert.deepEqual([r.session.preview.getStart(), r.session.preview.getLength()], [-1, 0]);
  assert.equal(r.prediction.getPrefix(), '');
  assert.deepEqual(r.prediction.getItems(), []);
  assert.deepEqual(r.store.get('kanonList'), []);
  assert.equal(r.store.get('kanonEnglishComposing'), false);
  assert.equal(r.published(), 2);
  r.bridge.assertDone();
}

test('P29: reset: an epoch change resets markers before engines and reloads preview support before clearing the range', async () => {
  const r = rig({ origin: 'A', steps: [{ operation: 'reset', output: response() }] });
  await r.session.keyText('hel');
  const order = recordReset(r);
  r.editor.epoch++;
  r.editor.supported = false;
  replaceEditorText(r.editor, 'B');
  await r.session.prepare();
  assert.deepEqual(order, ['external-sync', 'coordinator', 'mozc', 'english', 'prediction',
    'prediction', 'load-support', 'preview', 'cursor-sync', 'publish']);
  assertReset(r);
  assert.equal(r.session.coord.usesEnglishComposition(), false);
  assert.equal(r.editor.text, 'B');
});

test('P29: reset: explicit discard clears the editor preview first and resets external hints last', async () => {
  const r = rig({ origin: 'A', steps: [{ operation: 'reset', output: response() }] });
  await r.session.keyText('hel');
  const order = recordReset(r);
  await r.session.discardTypingText();
  assert.deepEqual(order, ['editor-discard', 'cancel-preview', 'discard-preview', 'coordinator', 'mozc',
    'english', 'prediction', 'prediction', 'preview', 'cursor-sync', 'external-sync', 'publish']);
  assertReset(r);
  assert.equal(r.editor.text, 'A');
  assert.deepEqual(r.editor.calls.slice(-2).map(call => call.operation), ['setPreview', 'finishPreview']);
});

test('P29: R-04: confirmed external empty resets and publishes without cancelling preview or resetting external hints', async () => {
  const r = rig({ origin: 'A', steps: [{ operation: 'reset', output: response() }] });
  await r.session.keyText('hel');
  const order = recordReset(r);
  const editorCalls = r.editor.calls.length;
  replaceEditorText(r.editor, '');
  r.session.textChanged(true);
  // Queue a prepare after the scheduled reconciliation to wait for its completion.
  await r.session.prepare();
  assert.deepEqual(order, ['coordinator', 'mozc', 'english', 'prediction', 'prediction',
    'preview', 'cursor-sync', 'editor-reset', 'publish']);
  assertReset(r);
  assert.equal(r.editor.calls.length, editorCalls);
  assert.equal(r.editor.text, '');
});
