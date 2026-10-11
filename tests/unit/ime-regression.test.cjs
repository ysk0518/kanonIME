const test=require('node:test');
const assert=require('node:assert/strict');
const {ImeCoordinator}=require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const {EnglishPrediction}=require('../../entry/src/main/ets/kanon/EnglishPrediction.ets');
const {EnglishEngine}=require('../../entry/src/main/ets/kanon/EnglishEngine.ets');
const {MozcEngine}=require('../../entry/src/main/ets/kanon/MozcEngine.ets');
const {CompositionPreview}=require('../../entry/src/main/ets/kanon/CompositionPreview.ets');
const {EnglishCompletionLifecycle}=require('../../entry/src/main/ets/kanon/EnglishCompletionLifecycle.ets');
const {DirectEnglishInput}=require('../../entry/src/main/ets/kanon/DirectEnglishInput.ets');
const {ImeLocalRequests}=require('../../entry/src/main/ets/kanon/ImeLocalRequests.ets');
const {ImeRuntimeBindings}=require('../../entry/src/main/ets/kanon/ImeRuntimeBindings.ets');
const {ImePresentation}=require('../../entry/src/main/ets/kanon/ImePresentation.ets');
const {ImeViewPublisher}=require('../../entry/src/main/ets/kanon/ImeViewPublisher.ets');
const {InputOperationQueue}=require('../../entry/src/main/ets/kanon/InputOperationQueue.ets');
const {FakeEditor,ScriptedBridge,response,deferred}=require('../support/fakes.cjs');

// Connect product modules, using explicit scenario events rather than copying
// KanonIme's router or stubbing its Harmony imports.
async function rig({mode='EN',supported=true,origin='',steps=[]}={}){
  const editor=new FakeEditor(origin);editor.supported=supported;
  const prediction=new EnglishPrediction({undoChanged:()=>{},cleared:()=>{},selectionAbandoned:()=>{}});
  const english=new EnglishEngine(prediction),bridge=new ScriptedBridge(steps),japanese=new MozcEngine(bridge);
  const coordinator=new ImeCoordinator(editor);coordinator.setEngine(japanese);coordinator.setEnglishEngine(english);
  await coordinator.loadPreviewSupport();await coordinator.postEvent({kind:'mode',text:mode});
  const store=new Map([['kanonLayout',mode==='EN'?'en_qwerty':'jp_qwerty'],['kanonLayoutOrder','jp_qwerty,en_qwerty']]);
  const writes=[],hooks={},pasteDispatches=[];
  const write=(key,value)=>{writes.push([key,value]);store.set(key,value);};
  const bindings=new ImeRuntimeBindings({readString:key=>store.get(key),readNumber:key=>store.get(key),
    string:write,number:write,boolean:write,flickEnabled:()=>true,
    saveLayoutOrder:async order=>{if(hooks.save){await hooks.save(order);}store.set('kanonLayoutOrder',order);},
    getEpoch:()=>editor.epoch,queryCursor:()=>editor.queryCursor()},
    {normal:0,password:8,numberPassword:9,newPassword:11});
  const presentation=new ImePresentation({getEpoch:()=>editor.epoch,
    usesEnglishComposition:()=>coordinator.usesEnglishComposition(),getCandidateView:()=>coordinator.getCandidateView(),
    getCandidateRevision:()=>coordinator.getCandidateRevision()},prediction,
    {getConversionReading:()=>japanese.getConversionReading(),getCursorPreview:()=>japanese.getCursorPreview(),
      getLastLens:()=>japanese.getLastLens(),getSelIdx:()=>japanese.getSelIdx()},
    new ImeViewPublisher({string:write,number:write,boolean:write,strings:write,numbers:write}));
  const preview=new CompositionPreview({getEpoch:()=>editor.epoch,queryCursor:()=>editor.queryCursor(),clearPreview:async()=>{},
    refreshPreview:(...args)=>coordinator.refreshPreview(...args),disableJapanesePreview:()=>coordinator.setPreviewUnsupported(),
    englishCursor:position=>prediction.setCompositionCursor(position)});
  async function render(kind,previousMode=mode,epoch=editor.epoch){
    const snapshot=coordinator.getSnapshot();await preview.reconcile(snapshot,kind,previousMode);
    await preview.refresh(snapshot,snapshot.mode==='EN'?english.getPreedit():japanese.getPreedit(),coordinator.usesEnglishComposition());
    presentation.publish(coordinator.getSnapshot(),epoch);return coordinator.getSnapshot();
  }
  async function send(event){const epoch=editor.epoch,previous=coordinator.getSnapshot().mode;
    await coordinator.postEvent(event);return render(event.kind,previous,epoch);}
  const completion=new EnglishCompletionLifecycle(prediction,{getEpoch:()=>editor.epoch,predictionAllowed:()=>bindings.predictionAllowed(),
    usesComposition:()=>coordinator.usesEnglishComposition(),snapshot:()=>coordinator.getSnapshot(),
    dispatch:event=>coordinator.postEvent(event),restorePreview:start=>preview.restore(start),
    refreshPreview:snapshot=>preview.refresh(snapshot,english.getPreedit(),coordinator.usesEnglishComposition())});
  const direct=new DirectEnglishInput(prediction,{getEpoch:()=>editor.epoch,predictionAllowed:()=>bindings.predictionAllowed(),
    queryCursor:()=>editor.queryCursor(),queryBefore:n=>editor.queryBefore(n),dispatch:event=>coordinator.postEvent(event),
    lastError:()=>coordinator.getSnapshot().lastError,enterAction:async()=>{}});
  const local=new ImeLocalRequests({getEpoch:()=>editor.epoch,snapshot:()=>coordinator.getSnapshot(),
    configuredOrder:()=>bindings.configuredOrder(),currentLayout:()=>bindings.currentLayout(),flickEnabled:()=>bindings.flickEnabled(),
    dispatch:event=>coordinator.postEvent(event),submit:()=>send({kind:'submit'}),
    resetComposition:()=>{preview.reset();prediction.clear();},applyLayout:id=>bindings.applyLayout(id),
    saveOrder:order=>bindings.saveOrder(order),publish:snapshot=>presentation.publish(snapshot)});
  const queue=new InputOperationQueue(()=>editor.epoch,()=>coordinator.getSnapshot());
  async function paste(value,epoch=editor.epoch){if(!await local.beforePaste(epoch)){return false;}
    pasteDispatches.push(value);await send({kind:'paste',text:value});return coordinator.getSnapshot().lastError==='ok';}
  return {editor,prediction,english,japanese,bridge,coordinator,store,writes,hooks,bindings,presentation,preview,
    completion,direct,local,queue,send,render,paste,pasteDispatches};
}

test('P28: completion Undo restores the prefix before paste commits it and appends literal text',async()=>{
  const r=await rig({origin:'say '});for(const text of 'hel'){await r.send({kind:'text',text});}
  await r.send({kind:'convert'});assert.equal(r.editor.text,'say hello');
  const context=r.completion.capture('enter',undefined,r.english.getTypedText(),r.preview.getStart(),1);
  await r.coordinator.postEvent({kind:'enter'});r.completion.remember(context,r.coordinator.getSnapshot());await r.render('enter');
  assert.equal(await r.completion.undo('backspace',1),'handled');r.presentation.publish(r.coordinator.getSnapshot(),1);
  assert.equal(r.editor.text,'say hel');assert.equal(r.preview.getStart(),4);assert.equal(r.store.get('kanonEnglishComposing'),true);
  assert.equal(await r.paste('!?'),true);assert.equal(r.editor.text,'say hel!?');assert.equal(r.preview.getStart(),-1);
  assert.deepEqual(r.editor.calls.filter(c=>c.operation==='insert').map(c=>c.text),['hello','hel','!?']);
  assert.deepEqual(r.pasteDispatches,['!?']);assert.equal(r.store.get('kanonEnglishComposing'),false);
  assert.deepEqual(r.store.get('kanonList'),[]);
});

test('P28: layout commit resets the preview origin and following text waits for settings persistence',async()=>{
  const r=await rig(),started=deferred(),finish=deferred();await r.send({kind:'text',text:'he'});
  r.hooks.save=async()=>{started.resolve();await finish.promise;};
  const change=r.queue.enqueue(()=>r.local.handle({kind:'config',layoutOrder:'jp_flick,en_flick'},1));
  const next=r.queue.enqueue(()=>r.send({kind:'text',text:'a'}));await started.promise;
  assert.equal(r.editor.text,'he');assert.equal(r.preview.getStart(),-1);assert.equal(r.english.getPreedit(),'');
  assert.equal(r.bindings.currentLayout(),'en_flick');assert.equal(r.bindings.matchesConfiguredOrder('jp_flick,en_flick'),false);
  finish.resolve();await change;await next;assert.equal(r.editor.text,'hea');assert.equal(r.preview.getStart(),2);
  assert.equal(r.editor.cursor,3);assert.equal(r.store.get('kanonEnglishComposing'),true);
  assert.equal(r.bindings.matchesConfiguredOrder('jp_flick,en_flick'),true);assert.equal(r.store.get('kanonLastLayout'),'en_flick');
  assert.deepEqual(r.editor.calls.filter(c=>c.operation==='insert').map(c=>c.text),['he']);
});

test('P28: direct completion Undo and literal paste never create a preview or retain old predictions',async()=>{
  const r=await rig({supported:false});for(const text of 'hel'){
    const cursor=await r.direct.beforeText(text,1);await r.coordinator.postEvent({kind:'text',text});
    r.direct.afterEvent('text',text,cursor,r.coordinator.getSnapshot().lastError==='ok');r.presentation.publish(r.coordinator.getSnapshot(),1);
  }
  assert.equal(await r.direct.convert(1),'handled');assert.ok(r.prediction.getSelectedIndex()>=0);await r.direct.handle('enter');
  assert.equal(r.editor.text,'hello');assert.equal(await r.completion.undo('backspace',1),'handled');
  r.presentation.publish(r.coordinator.getSnapshot(),1);assert.equal(r.editor.text,'hel');assert.equal(r.store.get('kanonEnglishComposing'),true);
  assert.equal(await r.paste('!?'),true);r.direct.afterEvent('paste','!?',3,true);r.presentation.publish(r.coordinator.getSnapshot(),1);
  assert.equal(r.editor.text,'hel!?');assert.deepEqual(r.store.get('kanonList'),[]);assert.equal(r.store.get('kanonEnglishComposing'),false);
  assert.equal(r.editor.count('setPreview'),0);assert.equal(r.preview.getStart(),-1);assert.equal(r.prediction.takeUndo(),undefined);
});

test('P28: Japanese symbol composition survives paste precommit and subsequent input gets a new origin',async()=>{
  const r=await rig({mode:'JP',steps:[{operation:'convert',text:'k',output:response('ｋ')},
    {operation:'convert',text:'i',output:response('き')},{operation:'literal',text:'？',output:response('き？')},
    {operation:'reset',output:response()},{operation:'convert',text:'k',output:response('ｋ')},
    {operation:'convert',text:'i',output:response('き')}]});
  for(const text of ['k','i','？']){await r.send({kind:'text',text});}
  assert.equal(r.editor.text,'き？');assert.equal(r.store.get('kanonJapaneseComposing'),true);
  assert.equal(await r.paste('ABC'),true);assert.equal(r.editor.text,'き？ABC');assert.equal(r.store.get('kanonJapaneseComposing'),false);
  await r.send({kind:'text',text:'k'});await r.send({kind:'text',text:'i'});
  assert.equal(r.editor.text,'き？ABCき');assert.equal(r.preview.getStart(),5);assert.equal(r.editor.cursor,6);r.bridge.assertDone();
  assert.deepEqual(r.editor.calls.filter(c=>c.operation==='insert').map(c=>c.text),['き？','ABC']);
});

test('P28: old settings completion and queued text cannot write into a newly attached field',async()=>{
  const r=await rig(),started=deferred(),finish=deferred();await r.send({kind:'text',text:'he'});
  r.hooks.save=async()=>{started.resolve();await finish.promise;};
  const change=r.queue.enqueue(()=>r.local.handle({kind:'config',layoutOrder:'jp_flick,en_flick'},1));
  let obsoleteRan=false;const obsolete=r.queue.enqueue(async()=>{obsoleteRan=true;return r.send({kind:'text',text:'w'});});
  await started.promise;r.editor.epoch=2;r.editor.text='';r.editor.cursor=0;r.editor.preview=null;r.coordinator.onEditorChanged();
  r.prediction.clear();r.store.set('kanonList',['new-field-sentinel']);const writeCount=r.writes.length;
  finish.resolve();await change;await obsolete;assert.equal(obsoleteRan,false);assert.equal(r.editor.text,'');
  assert.equal(r.writes.length,writeCount);assert.deepEqual(r.store.get('kanonList'),['new-field-sentinel']);
  await r.queue.enqueue(()=>r.send({kind:'text',text:'a'}));assert.equal(r.editor.text,'a');
  assert.equal(r.store.get('kanonEnglishComposing'),true);assert.notDeepEqual(r.store.get('kanonList'),['new-field-sentinel']);
});

test('P28: failed precommit keeps the composing text and stops paste before dispatching it',async()=>{
  const r=await rig();await r.send({kind:'text',text:'he'});r.editor.failInsert=true;
  assert.equal(await r.paste('ABC'),false);assert.equal(r.editor.text,'he');assert.deepEqual(r.pasteDispatches,[]);
  assert.equal(r.store.get('kanonNeedsRecovery'),true);assert.notEqual(r.store.get('kanonErr'),'ok');
  assert.deepEqual(r.editor.calls.filter(c=>c.operation==='insert').map(c=>c.text),['he']);
});
