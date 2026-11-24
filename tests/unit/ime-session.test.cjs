const test = require('node:test');
const assert = require('node:assert/strict');
const { ImeSession } = require('../../entry/src/main/ets/kanon/ImeSession.ets');
const { EnglishPrediction } = require('../../entry/src/main/ets/kanon/EnglishPrediction.ets');
const { MozcEngine } = require('../../entry/src/main/ets/kanon/MozcEngine.ets');
const { ImeRuntimeBindings } = require('../../entry/src/main/ets/kanon/ImeRuntimeBindings.ets');
const { ImeViewPublisher } = require('../../entry/src/main/ets/kanon/ImeViewPublisher.ets');
const { cancelEditorPreview } = require('../../entry/src/main/ets/kanon/PreviewLifecycle.ets');
const { FakeEditor, ScriptedBridge, response, deferred } = require('../support/fakes.cjs');

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

test('P37: direct English Delete uses the same grapheme deletion as Japanese confirmed text', async () => {
  const r = rig({ supported: false, origin: 'Ae\u0301' });
  await r.session.keyDelete();
  assert.equal(r.editor.text, 'A');
  assert.deepEqual(r.editor.calls, [{ operation: 'deleteForward', length: 2 }]);
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
    const r = await japaneseCursorRig([{ operation: 'reset', output: response() }]);
    const calls = [];
    observe(r.session.cursorSync, 'reconcile', () => calls.push('reconcile'));
    const snapshot = await r.send({ kind, layoutOrder: 'jp_flick,en_flick' });
    assert.deepEqual(calls, []);
    assert.equal(snapshot.lastError, 'ok');
    assert.deepEqual(r.bridge.calls.map(call => call.operation), ['convert', 'reset']);
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
