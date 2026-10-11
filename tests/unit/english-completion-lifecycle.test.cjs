const test = require('node:test');
const assert = require('node:assert/strict');
const { EnglishCompletionLifecycle } = require('../../entry/src/main/ets/kanon/EnglishCompletionLifecycle.ets');
const { EnglishPrediction } = require('../../entry/src/main/ets/kanon/EnglishPrediction.ets');
const { EnglishEngine } = require('../../entry/src/main/ets/kanon/EnglishEngine.ets');
const { DirectEnglishInput } = require('../../entry/src/main/ets/kanon/DirectEnglishInput.ets');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { CompositionPreview } = require('../../entry/src/main/ets/kanon/CompositionPreview.ets');
const { InputOperationQueue } = require('../../entry/src/main/ets/kanon/InputOperationQueue.ets');
const { FakeEditor, deferred } = require('../support/fakes.cjs');

async function rig(composing=true,origin='') {
  const prediction=new EnglishPrediction({undoChanged:()=>{},cleared:()=>{},selectionAbandoned:()=>{}});
  const editor=new FakeEditor(origin);editor.supported=composing;
  const coordinator=new ImeCoordinator(editor),engine=new EnglishEngine(prediction);
  coordinator.setEnglishEngine(engine);await coordinator.loadPreviewSupport();
  await coordinator.postEvent({kind:'mode',text:'EN'});
  const preview=new CompositionPreview({getEpoch:()=>editor.epoch,queryCursor:()=>editor.queryCursor(),
    clearPreview:async()=>{},refreshPreview:(...args)=>coordinator.refreshPreview(...args),
    disableJapanesePreview:()=>{},englishCursor:p=>prediction.setCompositionCursor(p)});
  const hooks={},state={allowed:true},calls=[];
  const port={getEpoch:()=>editor.epoch,predictionAllowed:()=>state.allowed,
    usesComposition:()=>coordinator.usesEnglishComposition(),snapshot:()=>coordinator.getSnapshot(),
    dispatch:async event=>{calls.push(['dispatch',{...event},prediction.editing]);
      if(hooks.dispatch){await hooks.dispatch(event);}else{await coordinator.postEvent(event);}},
    restorePreview:start=>{calls.push(['restore',start]);preview.restore(start);},
    refreshPreview:async snapshot=>{calls.push(['refresh',prediction.editing]);
      if(hooks.refresh){await hooks.refresh(snapshot);}
      else{await preview.refresh(snapshot,engine.getPreedit(),coordinator.usesEnglishComposition());}}
  };
  const lifecycle=new EnglishCompletionLifecycle(prediction,port);
  const direct=new DirectEnglishInput(prediction,{getEpoch:()=>editor.epoch,predictionAllowed:()=>state.allowed,
    queryCursor:()=>editor.queryCursor(),queryBefore:n=>editor.queryBefore(n),
    dispatch:event=>coordinator.postEvent(event),lastError:()=>coordinator.getSnapshot().lastError,enterAction:async()=>{}});
  async function completed(kind='enter') {
    if(composing) {
      await coordinator.postEvent({kind:'text',text:'he'});
      await preview.refresh(coordinator.getSnapshot(),engine.getPreedit(),true);
      await coordinator.postEvent({kind:'convert'});
      await preview.refresh(coordinator.getSnapshot(),engine.getPreedit(),true);
      const id=prediction.getItems()[0].id;
      const context=lifecycle.capture(kind,id,engine.getTypedText(),preview.getStart(),editor.epoch);
      await coordinator.postEvent(kind==='select'?{kind,candidateId:id,expectedRevision:coordinator.getCandidateRevision()}:{kind});
      lifecycle.remember(context,coordinator.getSnapshot());
      await preview.reconcile(coordinator.getSnapshot(),kind,'EN');
    } else {
      await coordinator.postEvent({kind:'text',text:'he'});prediction.text('he',origin.length);
      await direct.convert(editor.epoch);await direct.handle('enter');
    }
    assert.equal(editor.text,origin+'hello');assert.equal(preview.getStart(),-1);
  }
  return {prediction,editor,coordinator,engine,preview,hooks,state,calls,port,lifecycle,completed};
}

test('P25: composition completion undo restores prefix and preview at its original document position',async()=>{
  for(const origin of ['', 'say ', '😀 ']) {
    const r=await rig(true,origin);await r.completed();
    assert.equal(await r.lifecycle.undo('backspace',1),'handled');
    assert.equal(r.editor.text,origin+'he');assert.equal(r.engine.getPreedit(),'he');
    assert.equal(r.preview.getStart(),origin.length);assert.equal(r.prediction.getCursor(),origin.length+2);
    assert.deepEqual(r.calls,[['dispatch',{kind:'undoCompletion',text:'hello',cursor:origin.length+5,prefixLength:2},true],
      ['restore',origin.length],['refresh',true]]);
    assert.equal(r.prediction.editing,false);assert.equal(r.prediction.takeUndo(),undefined);
    assert.equal(r.editor.count('insert'),1);
  }
});

test('P25: candidate tap completion is remembered before its prediction is cleared',async()=>{
  const r=await rig();await r.completed('select');
  assert.equal(await r.lifecycle.undo('undoEnglish',1),'handled');assert.equal(r.editor.text,'he');
  assert.equal(r.engine.getPreedit(),'he');assert.equal(r.preview.getLength(),2);
});

test('P25: direct completion undo restores prediction without creating a platform preview',async()=>{
  const r=await rig(false,'say ');await r.completed();
  assert.equal(await r.lifecycle.undo('backspace',1),'handled');
  assert.equal(r.editor.text,'say he');assert.equal(r.prediction.getPrefix(),'he');assert.equal(r.prediction.getCursor(),6);
  assert.equal(r.engine.getPreedit(),'');assert.equal(r.preview.getStart(),-1);
  assert.equal(r.calls.filter(c=>c[0]==='restore'||c[0]==='refresh').length,0);
  assert.equal(r.editor.count('setPreview'),0);assert.equal(r.prediction.editing,false);
});

test('P25: a second ordinary Delete is processed normally after the completion undo is consumed',async()=>{
  const r=await rig();await r.completed();await r.lifecycle.undo('backspace',1);
  assert.equal(await r.lifecycle.undo('backspace',1),'continue');
  await r.coordinator.postEvent({kind:'backspace'});
  await r.preview.refresh(r.coordinator.getSnapshot(),r.engine.getPreedit(),true);
  assert.equal(r.editor.text,'h');assert.equal(r.engine.getPreedit(),'h');
  assert.equal(r.calls.filter(c=>c[0]==='dispatch'&&c[1].kind==='undoCompletion').length,1);
});

test('P25: stale explicit Undo cancels the stale context but never deletes ordinary text',async()=>{
  const r=await rig(false);await r.completed();r.editor.cursor=4;
  assert.equal(await r.lifecycle.undo('undoEnglish',1),'handled');assert.equal(r.editor.text,'hello');
  assert.deepEqual(r.calls.map(c=>c[1].kind),['undoCompletion','cancel']);
  assert.equal(r.editor.count('deleteForward'),0);assert.equal(r.editor.count('selectRange'),0);
});

test('P25: stale automatic undo lets Backspace continue through its ordinary path',async()=>{
  const r=await rig(false);await r.completed();r.editor.cursor=4;
  assert.equal(await r.lifecycle.undo('backspace',1),'continue');
  assert.equal(r.calls.length,1);assert.equal(r.calls[0][1].kind,'undoCompletion');
  assert.equal(r.editor.text,'hello');assert.equal(r.editor.count('deleteForward'),0);
});

test('P25: missing, old-target, selected and disabled undo cannot issue an undo operation',async()=>{
  for(const scenario of ['missing','old','selection','disabled']) {
    const r=await rig(false);await r.completed();
    if(scenario==='missing'){r.prediction.dropUndo();}
    if(scenario==='old'){r.editor.epoch=2;}
    if(scenario==='selection'){r.prediction.selectionChanged(0,5);}
    if(scenario==='disabled'){r.state.allowed=false;}
    assert.equal(await r.lifecycle.undo('backspace',r.editor.epoch),'continue',scenario);
    assert.deepEqual(r.calls,[]);assert.equal(r.editor.text,'hello');assert.equal(r.prediction.takeUndo(),undefined);
  }
});

test('P25: explicit Undo without valid metadata is handled without falling through to Delete',async()=>{
  for(const composing of [true,false]) {
    const r=await rig(composing);assert.equal(await r.lifecycle.undo('undoEnglish',1),'handled');
    assert.deepEqual(r.calls,[]);assert.equal(r.editor.text,'');
  }
});

test('P25: Japanese mode does not consume English completion metadata or issue English undo',async()=>{
  const r=await rig(false);await r.completed();await r.coordinator.postEvent({kind:'mode',text:'JP'});
  assert.equal(await r.lifecycle.undo('undoEnglish',1),'handled');assert.deepEqual(r.calls,[]);
  assert.ok(r.prediction.takeUndo());assert.equal(r.editor.text,'hello');
});

test('P25: an old request cannot consume the current input target undo',async()=>{
  const r=await rig(false);await r.completed();r.editor.epoch=2;
  r.prediction.rememberCompletion('he','hello',5,2);
  assert.equal(await r.lifecycle.undo('backspace',1),'stale');assert.deepEqual(r.calls,[]);
  assert.equal(r.prediction.takeUndo().epoch,2);
});

test('P25: input target change during undo skips preview and prediction restoration',async()=>{
  const r=await rig();await r.completed();r.hooks.dispatch=async()=>{r.editor.epoch++;};
  assert.equal(await r.lifecycle.undo('backspace',1),'stale');
  assert.equal(r.calls.length,1);assert.equal(r.prediction.getPrefix(),'');assert.equal(r.prediction.editing,false);
});

test('P25: a target change during preview refresh is reported stale and releases editing protection',async()=>{
  const r=await rig();await r.completed();r.hooks.refresh=async()=>{r.editor.epoch++;};
  assert.equal(await r.lifecycle.undo('backspace',1),'stale');assert.equal(r.prediction.getPrefix(),'');
  assert.equal(r.prediction.editing,false);assert.equal(r.editor.count('deleteForward'),1);
});

test('P25: failed undo is handled without restoring a prefix, falling through or retrying',async()=>{
  const r=await rig(false);await r.completed();r.editor.selectRange=async()=>({ok:false,code:-2});
  assert.equal(await r.lifecycle.undo('backspace',1),'handled');assert.equal(r.editor.text,'hello');
  assert.equal(r.coordinator.getSnapshot().lastError,'edit--2');assert.equal(r.calls.length,1);
  assert.equal(r.prediction.getPrefix(),'');assert.equal(r.editor.count('deleteForward'),0);
});

test('P25: thrown dispatch and preview refresh release protection and do not retry',async()=>{
  for(const phase of ['dispatch','refresh']) {
    const r=await rig();await r.completed();const error=new Error('fixed restoration failure');
    r.hooks[phase]=async()=>{throw error;};
    await assert.rejects(r.lifecycle.undo('backspace',1),e=>e===error);
    assert.equal(r.prediction.editing,false);assert.equal(r.prediction.takeUndo(),undefined);
    assert.equal(r.calls.filter(c=>c[0]===phase).length,1);
  }
});

test('P25: completion capture selects the requested candidate ID and copies its label',async()=>{
  const r=await rig();r.prediction.updateComposition('he');const item=r.prediction.getItems()[1];
  const context=r.lifecycle.capture('select',item.id,'he',3,1),word=item.label;
  item.label='changed';r.prediction.clear();
  assert.equal(context.word,word);r.lifecycle.remember(context,{lastError:'ok',commitLength:word.length});
  assert.deepEqual(r.prediction.takeUndo(),{prefix:'he',word,cursor:3+word.length,epoch:1});
});

test('P25: invalid or incomplete commit metadata cannot create completion undo',async()=>{
  const r=await rig();r.prediction.updateComposition('he');await r.coordinator.postEvent({kind:'text',text:'he'});
  const context={kind:'enter',prefix:'he',word:'hello',start:0,epoch:1};
  for(const [changed,snapshot] of [[{kind:'submit'},{lastError:'ok',commitLength:5}],
    [{kind:'text'},{lastError:'ok',commitLength:5}], [{},{lastError:'edit--2',commitLength:5}],
    [{},{lastError:'ok',commitLength:0}], [{start:-1},{lastError:'ok',commitLength:5}],
    [{prefix:''},{lastError:'ok',commitLength:5}], [{prefix:'say he'},{lastError:'ok',commitLength:5}],
    [{word:undefined},{lastError:'ok',commitLength:5}], [{word:'help',prefix:'heL'},{lastError:'ok',commitLength:4}],
    [{word:'he'},{lastError:'ok',commitLength:2}], [{epoch:2},{lastError:'ok',commitLength:5}]]) {
    r.lifecycle.remember({...context,...changed},snapshot);assert.equal(r.prediction.takeUndo(),undefined);
  }
});

test('P25 provisional: undo endpoint uses the actual commit length rather than the typed prefix length',async()=>{
  const r=await rig();r.lifecycle.remember({kind:'enter',prefix:'he',word:'hello',start:3,epoch:1},
    {lastError:'ok',commitLength:5});assert.equal(r.prediction.takeUndo().cursor,8);
});

test('P25: the existing queue keeps a following Delete behind preview restoration',async()=>{
  const r=await rig();await r.completed();const started=deferred(),finish=deferred();
  r.hooks.refresh=async snapshot=>{started.resolve();await finish.promise;
    await r.preview.refresh(snapshot,r.engine.getPreedit(),true);};
  const queue=new InputOperationQueue(()=>r.editor.epoch,()=> 'stale');
  const first=queue.enqueue(()=>r.lifecycle.undo('backspace',1));
  const second=queue.enqueue(async()=>{assert.equal(r.prediction.editing,false);
    assert.equal(await r.lifecycle.undo('backspace',1),'continue');await r.coordinator.postEvent({kind:'backspace'});});
  await started.promise;assert.equal(r.prediction.editing,true);assert.equal(r.engine.getPreedit(),'he');
  finish.resolve();assert.equal(await first,'handled');await second;assert.equal(r.engine.getPreedit(),'h');
});

test('P25: the editor contract model replaces a selected prefix when creating a new preview',async()=>{
  const editor=new FakeEditor('say he');await editor.selectRange(4,6);await editor.setPreview('he',-1,-1);
  assert.equal(editor.text,'say he');assert.deepEqual(editor.preview,{start:4,end:6});assert.equal(editor.hasSelection(),false);
  await editor.setPreview('h',-1,-1);assert.equal(editor.text,'say h');
});
