const test = require('node:test');
const assert = require('node:assert/strict');
const { decodeInputEvent, resolveInputMovement } = require('../../entry/src/main/ets/kanon/InputEventContract.ets');
const { fromEditorDirection, toEditorDirection } = require('../../entry/src/main/ets/kanon/EditorDirectionMap.ets');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { FakeEditor, update, deferred } = require('../support/fakes.cjs');

test('P23: SDK direction mapping uses supplied named constants in both directions', () => {
  for (const sdk of [{left:3,right:4,up:1,down:2}, {left:40,right:30,up:20,down:10}]) {
    for (const direction of ['left','right','up','down']) {
      assert.equal(fromEditorDirection(sdk[direction], sdk), direction);
      assert.equal(toEditorDirection(direction, sdk), sdk[direction]);
    }
    for (const invalid of [0, -1, 1.5, NaN, Infinity, undefined]) {
      assert.equal(fromEditorDirection(invalid, sdk), undefined);
    }
    for (const invalid of ['sideways','',0,undefined]) {
      assert.equal(toEditorDirection(invalid, sdk), undefined);
    }
  }
});

test('P23: numeric and ambiguous movements cannot enter the required-payload protocol', () => {
  for (const request of [{kind:'move',direction:0}, {kind:'move',direction:3},
    {kind:'selectMove',direction:4}, {kind:'move',direction:'left',edge:'begin'},
    {kind:'selectMove',direction:'right',edge:'end'}, {kind:'selectEdge',edge:'begin',direction:'left'},
    {kind:'move',direction:'sideways'}]) {
    assert.equal(decodeInputEvent(request), undefined);
  }
});

test('P23: decoding retains all required payloads including zero and signed candidate IDs', () => {
  for (const request of [{kind:'text',text:''}, {kind:'kana',text:'あ'}, {kind:'paste',text:'😀'},
    {kind:'select',candidateId:-1,expectedRevision:0}, {kind:'partial',expectedRevision:0},
    {kind:'compositionCursor',cursor:0}, {kind:'undoCompletion',text:'hello',cursor:5,prefixLength:0},
    {kind:'mode',text:'JP'}, {kind:'compositionArrow',text:'right'}, {kind:'move',edge:'end'},
    {kind:'selectEdge',edge:'begin'}, {kind:'selectMove',direction:'up'}, {kind:'enter'}]) {
    const event = decodeInputEvent(request);
    assert.deepEqual(event, request); assert.notEqual(event, request);
  }
});

test('P23: decoding detaches caller-owned data before an asynchronous engine uses it', async () => {
  const started = deferred(), proceed = deferred(); const seen = [];
  const coordinator = new ImeCoordinator(new FakeEditor());
  coordinator.setEngine({dispatch:async(s,e,n,event)=>{
    started.resolve(); await proceed.promise; seen.push({...event}); return update(s,e,n);
  }});
  const request = {kind:'select',candidateId:-1,expectedRevision:0};
  const pending = coordinator.postEvent(request); await started.promise;
  request.kind = 'text'; request.candidateId = 999; request.expectedRevision = 999; request.text = 'changed';
  proceed.resolve(); await pending;
  assert.deepEqual(seen, [{kind:'select',candidateId:-1,expectedRevision:0}]);
});

test('P23: malformed movement cannot commit an existing composition or call EditorPort', async () => {
  const editor = new FakeEditor(); const coordinator = new ImeCoordinator(editor); let dispatched=0;
  coordinator.setEngine({dispatch:(s,e,n)=>{dispatched++;return update(s,e,n,{preeditLen:1});}});
  await coordinator.loadPreviewSupport(); await coordinator.postEvent({kind:'text',text:'あ'});
  await coordinator.refreshPreview('あ',0,0,1); const count=editor.calls.length;
  for (const request of [{kind:'move',direction:3}, {kind:'move',direction:'right',edge:'begin'}]) {
    await coordinator.postEvent(request);
    assert.equal(coordinator.getSnapshot().lastError,'invalid-event');
  }
  assert.equal(dispatched,1); assert.equal(editor.calls.length,count); assert.equal(editor.text,'あ');
});

test('P23: all four semantic directions reach the correct editor operation once', async () => {
  for (const kind of ['move','selectMove']) {
    const editor = new FakeEditor(); const coordinator = new ImeCoordinator(editor);
    for (const direction of ['left','right','up','down']) {
      await coordinator.postEvent({kind,direction}); assert.equal(coordinator.getSnapshot().lastError,'ok');
    }
    assert.deepEqual(editor.calls, ['left','right','up','down'].map(direction=>({
      operation:kind==='move'?'moveCursor':'selectByMovement', direction
    })));
  }
});

test('P23: document movement submits the existing composition before moving', async () => {
  const editor = new FakeEditor(); const coordinator = new ImeCoordinator(editor); const seen=[];
  coordinator.setEngine({dispatch:(s,e,n,event)=>{seen.push(event.kind);return update(s,e,n,
    event.kind==='submit'?{effects:[{effectId:'fixed',text:'あ'}]}:{preeditLen:1});}});
  await coordinator.postEvent({kind:'text',text:'あ'}); await coordinator.postEvent({kind:'move',direction:'down'});
  assert.deepEqual(seen,['text','submit']);
  assert.deepEqual(editor.calls,[{operation:'insert',text:'あ'},{operation:'moveCursor',direction:'down'}]);
});

test('P23: semantic movement resolves Japanese composition without platform numeric arguments', () => {
  const sdk={left:40,right:30,up:20,down:10};
  for (const direction of ['left','right']) {
    const raw={kind:'move',direction:fromEditorDirection(sdk[direction],sdk)};
    assert.deepEqual(decodeInputEvent(resolveInputMovement(raw,'JP',1)),{kind:'compositionArrow',text:direction});
  }
});

test('P23: cursor placement uses required verification instead of an unverified range selection', async () => {
  const editor = new FakeEditor(); const coordinator = new ImeCoordinator(editor);
  await coordinator.loadPreviewSupport(); await coordinator.refreshPreview('かき',0,0,1);
  assert.equal(editor.count('previewCaret'),1); assert.equal(editor.count('selectRange'),0);
  assert.equal(coordinator.isPreviewCaretAligned(),true);
  editor.caretMatches=false; await coordinator.refreshPreview('かき',0,2,0);
  assert.equal(editor.count('previewCaret'),2); assert.equal(editor.count('selectRange'),0);
  assert.equal(coordinator.isPreviewCaretAligned(),false);
  assert.equal(coordinator.getSnapshot().lastError,'preview-caret--7');
});
