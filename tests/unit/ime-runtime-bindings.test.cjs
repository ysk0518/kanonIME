const test=require('node:test');
const assert=require('node:assert/strict');
const {ImeRuntimeBindings}=require('../../entry/src/main/ets/kanon/ImeRuntimeBindings.ets');
const {ImeLocalRequests}=require('../../entry/src/main/ets/kanon/ImeLocalRequests.ets');
const {ImeCoordinator}=require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const {EnglishPrediction}=require('../../entry/src/main/ets/kanon/EnglishPrediction.ets');
const {EnglishEngine}=require('../../entry/src/main/ets/kanon/EnglishEngine.ets');
const {InputOperationQueue}=require('../../entry/src/main/ets/kanon/InputOperationQueue.ets');
const {FakeEditor,deferred}=require('../support/fakes.cjs');

function rig(patterns={normal:0,password:8,numberPassword:9,newPassword:11}) {
  const store=new Map(),calls=[],hooks={};const state={epoch:1,flick:true,cursor:3};
  const port={readString:key=>store.get(key),readNumber:key=>store.get(key),
    string:(key,value)=>{calls.push(['string',key,value]);store.set(key,value);},
    number:(key,value)=>{calls.push(['number',key,value]);store.set(key,value);},
    boolean:(key,value)=>{calls.push(['boolean',key,value]);store.set(key,value);},
    flickEnabled:()=>state.flick,
    saveLayoutOrder:async order=>{calls.push(['save',order]);if(hooks.save){await hooks.save(order);}else{store.set('kanonLayoutOrder',order);}},
    getEpoch:()=>state.epoch,queryCursor:async()=>{calls.push(['query']);return hooks.query?hooks.query():state.cursor;}};
  return {bindings:new ImeRuntimeBindings(port,patterns),store,calls,hooks,state,port};
}

test('P27: missing runtime values use existing defaults without writing them',()=>{
  const r=rig();assert.equal(r.bindings.currentLayout(),'jp_flick');
  assert.equal(r.bindings.configuredOrder(),'jp_flick,en_flick');assert.equal(r.bindings.displayedMode('EN'),'EN');
  assert.equal(r.bindings.predictionAllowed(),true);assert.deepEqual(r.calls,[]);assert.equal(r.store.size,0);
});

test('P27: runtime reads use the latest stored values and retain the existing empty-string policy',()=>{
  const r=rig();r.store.set('kanonLayout','en_qwerty');r.store.set('kanonLayoutOrder','en_qwerty');r.store.set('kanonMode','JP');
  assert.equal(r.bindings.currentLayout(),'en_qwerty');assert.equal(r.bindings.configuredOrder(),'en_qwerty');
  assert.equal(r.bindings.displayedMode('EN'),'JP');r.store.set('kanonLayout','');r.store.set('kanonLayoutOrder','');
  assert.equal(r.bindings.currentLayout(),'');assert.equal(r.bindings.configuredOrder(),'');
});

test('P27: a fallback layout order is not mistaken for a confirmed stored configuration',()=>{
  const r=rig(),order='jp_flick,en_flick';assert.equal(r.bindings.configuredOrder(),order);
  assert.equal(r.bindings.matchesConfiguredOrder(order),false);r.store.set('kanonLayoutOrder',order);
  assert.equal(r.bindings.matchesConfiguredOrder(order),true);assert.equal(r.bindings.matchesConfiguredOrder('en_flick'),false);
});

test('P27: flick enablement reads effective settings rather than a stale display property',()=>{
  const r=rig();r.store.set('kanonFlickEnabled',true);r.state.flick=false;
  assert.equal(r.bindings.flickEnabled(),false);r.state.flick=true;assert.equal(r.bindings.flickEnabled(),true);
});

test('P27: supplied SDK pattern values block all three password variants and allow ordinary fields',()=>{
  for(const patterns of [{normal:0,password:8,numberPassword:9,newPassword:11},
    {normal:40,password:15,numberPassword:2,newPassword:33}]) {
    const r=rig(patterns);
    for(const pattern of [patterns.password,patterns.numberPassword,patterns.newPassword]) {
      r.store.set('inputPattern',pattern);assert.equal(r.bindings.predictionAllowed(),false,`pattern ${pattern}`);
    }
    for(const pattern of [patterns.normal,100,-1]) {
      r.store.set('inputPattern',pattern);assert.equal(r.bindings.predictionAllowed(),true);
    }
  }
});

test('P27: pattern mapping is captured by value and cannot be changed by the caller later',()=>{
  const patterns={normal:0,password:8,numberPassword:9,newPassword:11},r=rig(patterns);
  patterns.password=100;r.store.set('inputPattern',8);assert.equal(r.bindings.predictionAllowed(),false);
});

test('P27: applying a layout updates current, last and expanded state in the existing order',()=>{
  const r=rig();r.bindings.applyLayout('en_qwerty');
  assert.deepEqual(r.calls,[['string','kanonLayout','en_qwerty'],['string','kanonLastLayout','en_qwerty'],
    ['boolean','kanonCandidatesExpanded',false]]);assert.equal(r.bindings.currentLayout(),'en_qwerty');
  assert.equal(r.store.has('kanonLayoutOrder'),false);assert.equal(r.store.has('kanonMode'),false);
});

test('P27: layout persistence waits for the existing save port without changing layout itself',async()=>{
  const r=rig(),started=deferred(),finish=deferred();r.hooks.save=async order=>{started.resolve();await finish.promise;r.store.set('kanonLayoutOrder',order);};
  const pending=r.bindings.saveOrder('en_qwerty');await started.promise;
  assert.equal(r.bindings.matchesConfiguredOrder('en_qwerty'),false);assert.equal(r.bindings.currentLayout(),'jp_flick');
  finish.resolve();await pending;assert.equal(r.bindings.matchesConfiguredOrder('en_qwerty'),true);
  assert.deepEqual(r.calls,[['save','en_qwerty']]);
});

test('P27: layout persistence errors propagate without retry or fabricated stored confirmation',async()=>{
  const r=rig();r.hooks.save=async()=>{throw new Error('failed save');};
  await assert.rejects(r.bindings.saveOrder('en_qwerty'),/failed save/);
  assert.equal(r.bindings.matchesConfiguredOrder('en_qwerty'),false);assert.deepEqual(r.calls,[['save','en_qwerty']]);
});

test('P27: cursor display preserves stable positions including the existing unknown value',async()=>{
  const r=rig();for(const position of [0,3,-1]){r.state.cursor=position;await r.bindings.updateCursor();assert.equal(r.store.get('kanonCursor'),position);}
  assert.equal(r.calls.filter(c=>c[0]==='query').length,3);
});

test('P27: cursor results from an old input target cannot overwrite the new display',async()=>{
  const r=rig(),started=deferred(),finish=deferred();r.hooks.query=async()=>{started.resolve();return finish.promise;};
  const pending=r.bindings.updateCursor();await started.promise;r.state.epoch=2;r.store.set('kanonCursor',40);
  finish.resolve(3);await pending;assert.equal(r.store.get('kanonCursor'),40);assert.deepEqual(r.calls,[['query']]);
  delete r.hooks.query;r.state.cursor=8;await r.bindings.updateCursor();assert.equal(r.store.get('kanonCursor'),8);
});

test('P27: failed cursor reads retain the display without writing, deleting or retrying',async()=>{
  const r=rig();r.store.set('kanonCursor',4);r.hooks.query=async()=>{throw new Error('query failed');};
  await r.bindings.updateCursor();assert.equal(r.store.get('kanonCursor'),4);assert.deepEqual(r.calls,[['query']]);
});

test('P27: runtime bindings connect local layout requests with the real coordinator and shared queue',async()=>{
  const r=rig(),editor=new FakeEditor();r.port.getEpoch=()=>editor.epoch;
  const prediction=new EnglishPrediction({undoChanged:()=>{},cleared:()=>{},selectionAbandoned:()=>{}});
  const coordinator=new ImeCoordinator(editor);coordinator.setEnglishEngine(new EnglishEngine(prediction));
  await coordinator.loadPreviewSupport();
  const local=new ImeLocalRequests({getEpoch:()=>editor.epoch,snapshot:()=>coordinator.getSnapshot(),
    configuredOrder:()=>r.bindings.configuredOrder(),currentLayout:()=>r.bindings.currentLayout(),
    flickEnabled:()=>r.bindings.flickEnabled(),dispatch:event=>coordinator.postEvent(event),
    submit:async()=>{await coordinator.postEvent({kind:'submit'});return coordinator.getSnapshot();},
    resetComposition:()=>prediction.clear(),applyLayout:id=>r.bindings.applyLayout(id),
    saveOrder:order=>r.bindings.saveOrder(order),publish:()=>{}});
  const queue=new InputOperationQueue(()=>editor.epoch,()=>coordinator.getSnapshot());
  r.state.flick=false;
  await queue.enqueue(()=>local.handle({kind:'config',layoutOrder:'en_flick,jp_flick'},editor.epoch));
  assert.equal(r.bindings.currentLayout(),'jp_qwerty');assert.equal(r.bindings.matchesConfiguredOrder('en_qwerty,jp_qwerty'),true);
  await queue.enqueue(()=>local.handle({kind:'cycle'},editor.epoch));assert.equal(r.bindings.currentLayout(),'en_qwerty');
  assert.equal(coordinator.getSnapshot().mode,'EN');assert.equal(r.store.get('kanonCandidatesExpanded'),false);
  assert.deepEqual(r.calls.filter(c=>c[0]==='save'),[['save','en_qwerty,jp_qwerty']]);
});
