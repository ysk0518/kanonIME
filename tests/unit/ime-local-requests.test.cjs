const test = require('node:test');
const assert = require('node:assert/strict');
const { ImeLocalRequests } = require('../../entry/src/main/ets/kanon/ImeLocalRequests.ets');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { EnglishPrediction } = require('../../entry/src/main/ets/kanon/EnglishPrediction.ets');
const { EnglishEngine } = require('../../entry/src/main/ets/kanon/EnglishEngine.ets');
const { MozcEngine } = require('../../entry/src/main/ets/kanon/MozcEngine.ets');
const { CompositionPreview } = require('../../entry/src/main/ets/kanon/CompositionPreview.ets');
const { InputOperationQueue } = require('../../entry/src/main/ets/kanon/InputOperationQueue.ets');
const { FakeEditor, ScriptedBridge, response, deferred } = require('../support/fakes.cjs');

async function rig(options={}) {
  const editor=new FakeEditor(options.origin??'');
  const coordinator=new ImeCoordinator(editor);
  const prediction=new EnglishPrediction({undoChanged:()=>{},cleared:()=>{},selectionAbandoned:()=>{}});
  const english=new EnglishEngine(prediction),bridge=new ScriptedBridge(options.steps??[]);
  const japanese=new MozcEngine(bridge);
  coordinator.setEnglishEngine(english);coordinator.setEngine(japanese);await coordinator.loadPreviewSupport();
  if(options.mode==='EN'){await coordinator.postEvent({kind:'mode',text:'EN'});}
  const state={order:options.order??'jp_flick,en_flick',layout:options.layout??'jp_flick',flick:options.flick??true};
  const hooks={},calls=[];
  const preview=new CompositionPreview({getEpoch:()=>editor.epoch,queryCursor:()=>editor.queryCursor(),
    clearPreview:async()=>{},refreshPreview:(...args)=>coordinator.refreshPreview(...args),
    disableJapanesePreview:()=>coordinator.setPreviewUnsupported(),englishCursor:p=>prediction.setCompositionCursor(p)});
  async function publishPreview(kind) {
    const snapshot=coordinator.getSnapshot();
    await preview.reconcile(snapshot,kind,snapshot.mode);
    await preview.refresh(snapshot,snapshot.mode==='EN'?english.getPreedit():japanese.getPreedit(),coordinator.usesEnglishComposition());
    return coordinator.getSnapshot();
  }
  const port={getEpoch:()=>editor.epoch,snapshot:()=>coordinator.getSnapshot(),
    configuredOrder:()=>state.order,currentLayout:()=>state.layout,flickEnabled:()=>state.flick,
    dispatch:async event=>{calls.push(['dispatch',{...event}]);
      if(hooks.dispatch){await hooks.dispatch(event);}else{await coordinator.postEvent(event);}},
    submit:async()=>{calls.push(['submit']);
      if(hooks.submit){return hooks.submit();}
      await coordinator.postEvent({kind:'submit'});return publishPreview('submit');},
    resetComposition:()=>{calls.push(['reset']);preview.reset();prediction.clear();},
    applyLayout:layout=>{calls.push(['layout',layout]);state.layout=layout;},
    saveOrder:async order=>{calls.push(['save',order]);if(hooks.save){await hooks.save(order);}else{state.order=order;}},
    publish:snapshot=>{calls.push(['publish',snapshot.mode,snapshot.lastError]);}
  };
  const local=new ImeLocalRequests(port);
  async function text(value) {await coordinator.postEvent({kind:'text',text:value});return publishPreview('text');}
  const pasteDispatches=[];
  async function paste(value,epoch=editor.epoch) {
    if(!await local.beforePaste(epoch)){return false;}
    pasteDispatches.push(value);
    await coordinator.postEvent({kind:'paste',text:value});return coordinator.getSnapshot().lastError==='ok';
  }
  return {editor,coordinator,prediction,english,japanese,bridge,state,hooks,calls,preview,port,local,text,paste,pasteDispatches};
}

test('P26: prepare preserves an enabled language and layout without dispatching or saving',async()=>{
  for(const [mode,layout,order] of [['JP','jp_qwerty','en_flick,jp_qwerty'],['EN','en_flick','jp_flick,en_flick']]) {
    const r=await rig({mode,layout,order});await r.local.handle({kind:'prepare'},1);
    assert.equal(r.state.layout,layout);assert.deepEqual(r.calls,[]);
  }
});

test('P26: prepare switches to the first available language when the current language is disabled',async()=>{
  const r=await rig({order:'en_qwerty'});await r.local.handle({kind:'prepare'},1);
  assert.equal(r.state.layout,'en_qwerty');assert.equal(r.coordinator.getSnapshot().mode,'EN');
  assert.deepEqual(r.calls.map(c=>c[0]),['dispatch','reset','layout','publish']);
});

test('P26: prepare corrects a coordinator mode mismatch even when the layout ID already matches',async()=>{
  const r=await rig({mode:'EN'});await r.local.handle({kind:'prepare'},1);
  assert.equal(r.coordinator.getSnapshot().mode,'JP');assert.equal(r.state.layout,'jp_flick');
  assert.equal(r.calls.filter(c=>c[0]==='dispatch').length,1);
});

test('P26: disabling flick maps prepare and cycle to QWERTY while preserving language order',async()=>{
  const r=await rig({flick:false,order:'en_flick,jp_flick'});
  await r.local.handle({kind:'prepare'},1);assert.equal(r.state.layout,'jp_qwerty');
  assert.equal(r.state.order,'en_qwerty,jp_qwerty');
  await r.local.handle({kind:'cycle'},1);assert.equal(r.state.layout,'en_qwerty');
  assert.equal(r.coordinator.getSnapshot().mode,'EN');
});

test('P26: cycle never selects a flick layout from an old configured order when flick is disabled',async()=>{
  const r=await rig({flick:false,layout:'jp_qwerty'});await r.local.handle({kind:'cycle'},1);
  assert.equal(r.state.layout,'en_qwerty');assert.equal(r.state.order,'jp_flick,en_flick');
  assert.equal(r.calls.some(c=>c[0]==='save'),false);
});

test('P26: cycling a single enabled language does not switch its layout or write settings',async()=>{
  const r=await rig({order:'jp_qwerty',layout:'jp_qwerty'});await r.local.handle({kind:'cycle'},1);
  assert.deepEqual(r.calls,[['publish','JP','ok']]);assert.equal(r.state.layout,'jp_qwerty');
});

test('P26: config normalizes duplicate languages and retains the current language',async()=>{
  const r=await rig({mode:'EN',layout:'en_flick'});
  await r.local.handle({kind:'config',layoutOrder:'jp_qwerty,en_qwerty,en_flick,unknown'},1);
  assert.equal(r.state.order,'jp_qwerty,en_qwerty');assert.equal(r.state.layout,'en_qwerty');
  assert.deepEqual(r.calls,[['dispatch',{kind:'mode',text:'EN'}],['reset'],['layout','en_qwerty'],
    ['save','jp_qwerty,en_qwerty'],['publish','EN','ok']]);
});

test('P26: unchanged configuration does not dispatch, reset composition or save again',async()=>{
  const r=await rig();await r.local.handle({kind:'config',layoutOrder:r.state.order},1);
  assert.deepEqual(r.calls,[['publish','JP','ok']]);
});

test('P26: disabled language configuration falls back to the first enabled language',async()=>{
  const r=await rig();await r.local.handle({kind:'config',layoutOrder:'en_flick'},1);
  assert.equal(r.state.layout,'en_flick');assert.equal(r.state.order,'en_flick');assert.equal(r.coordinator.getSnapshot().mode,'EN');
});

test('P26: switching layouts commits the English preedit once before changing layout and clearing prediction',async()=>{
  const r=await rig({mode:'EN',layout:'en_flick',origin:'say '});await r.text('hel');
  assert.equal(r.editor.text,'say hel');await r.local.handle({kind:'config',layoutOrder:'jp_qwerty,en_qwerty'},1);
  assert.equal(r.editor.text,'say hel');assert.equal(r.editor.count('insert'),1);assert.equal(r.editor.preview,null);
  assert.equal(r.preview.getStart(),-1);assert.equal(r.coordinator.getSnapshot().preeditLen,0);
  assert.equal(r.prediction.getPrefix(),'');assert.equal(r.state.layout,'en_qwerty');
});

test('P26: failed commit cannot switch layouts, reset composition or save settings',async()=>{
  const r=await rig({mode:'EN',layout:'en_flick'});await r.text('hel');r.editor.failInsert=true;
  const result=await r.local.handle({kind:'config',layoutOrder:'jp_qwerty,en_qwerty'},1);
  assert.notEqual(result.lastError,'ok');assert.equal(r.state.layout,'en_flick');assert.equal(r.state.order,'jp_flick,en_flick');
  assert.deepEqual(r.calls.map(c=>c[0]),['dispatch','publish']);assert.equal(r.editor.count('insert'),1);
  assert.equal(r.preview.getStart(),0);
});

test('P26: a mode result with the wrong language cannot change the layout or save its order',async()=>{
  const r=await rig();r.hooks.dispatch=async()=>{};await r.local.handle({kind:'config',layoutOrder:'en_qwerty'},1);
  assert.equal(r.state.layout,'jp_flick');assert.deepEqual(r.calls.map(c=>c[0]),['dispatch','publish']);
});

test('P26: an obsolete request cannot issue local effects',async()=>{
  const r=await rig();r.editor.epoch=2;
  await r.local.handle({kind:'config',layoutOrder:'en_qwerty'},1);assert.deepEqual(r.calls,[]);
  assert.equal(await r.local.beforePaste(1),false);assert.deepEqual(r.calls,[]);
});

test('P26: changing input targets during mode dispatch cannot apply layout, reset or publish',async()=>{
  const r=await rig();r.hooks.dispatch=async()=>{r.editor.epoch++;};
  await r.local.handle({kind:'config',layoutOrder:'en_qwerty'},1);
  assert.deepEqual(r.calls,[['dispatch',{kind:'mode',text:'EN'}]]);assert.equal(r.state.layout,'jp_flick');
});

test('P26: a late settings save may finish globally but must not publish to a new input target',async()=>{
  const r=await rig();r.hooks.save=async order=>{r.state.order=order;r.editor.epoch++;};
  await r.local.handle({kind:'config',layoutOrder:'jp_qwerty,en_qwerty'},1);
  assert.equal(r.state.order,'jp_qwerty,en_qwerty');assert.equal(r.calls.some(c=>c[0]==='publish'),false);
});

test('P26: a settings save throw is not retried and does not publish success',async()=>{
  const r=await rig();r.hooks.save=async()=>{throw new Error('save failed');};
  await assert.rejects(r.local.handle({kind:'config',layoutOrder:'jp_qwerty,en_qwerty'},1),/save failed/);
  assert.equal(r.calls.filter(c=>c[0]==='save').length,1);assert.equal(r.calls.some(c=>c[0]==='publish'),false);
});

test('P26: toggle preserves language order and flips both layouts together',async()=>{
  for(const [layout,order,expected] of [['en_flick','en_flick,jp_flick','en_qwerty,jp_qwerty'],
    ['jp_qwerty','jp_qwerty,en_qwerty','jp_flick,en_flick']]) {
    const r=await rig({layout,order});assert.equal(r.local.toggleOrder(),expected);assert.deepEqual(r.calls,[]);
  }
});

test('P26: disabled flick rejects toggling without layout or editor effects',async()=>{
  const r=await rig({flick:false});assert.equal(r.local.toggleOrder(),'');assert.deepEqual(r.calls,[]);
});

test('P26: consecutive toggles resolve against the previous completed layout inside the queue',async()=>{
  const r=await rig();const queue=new InputOperationQueue(()=>r.editor.epoch,()=>r.coordinator.getSnapshot());
  const toggle=()=>queue.enqueue(()=>r.local.handle({kind:'config',layoutOrder:r.local.toggleOrder()},r.editor.epoch));
  await Promise.all([toggle(),toggle()]);assert.equal(r.state.layout,'jp_flick');assert.equal(r.state.order,'jp_flick,en_flick');
  assert.deepEqual(r.calls.filter(c=>c[0]==='layout').map(c=>c[1]),['jp_qwerty','jp_flick']);
});

test('P26: paste commits and reconciles English composition before inserting literal text',async()=>{
  const r=await rig({mode:'EN',layout:'en_qwerty',origin:'say '});await r.text('hel');
  assert.equal(await r.paste('😀!?'),true);assert.equal(r.editor.text,'say hel😀!?');
  assert.deepEqual(r.editor.calls.filter(c=>c.operation==='insert').map(c=>c.text),['hel','😀!?']);
  assert.equal(r.preview.getStart(),-1);assert.deepEqual(r.calls,[['submit']]);
});

test('P26: Japanese paste preserves the composing kana and inserts the clipboard exactly once',async()=>{
  const r=await rig({steps:[{operation:'convert',text:'k',output:response('ｋ')},
    {operation:'convert',text:'i',output:response('き')},{operation:'reset',output:response()}]});
  await r.text('k');await r.text('i');assert.equal(r.editor.text,'き');assert.equal(await r.paste('ABC!?'),true);
  assert.equal(r.editor.text,'きABC!?');assert.equal(r.preview.getStart(),-1);
  assert.deepEqual(r.editor.calls.filter(c=>c.operation==='insert').map(c=>c.text),['き','ABC!?']);r.bridge.assertDone();
});

test('P26: paste without composition issues no submit and inserts at the current position',async()=>{
  const r=await rig({origin:'abc'});r.editor.cursor=1;
  assert.equal(await r.paste('XYZ'),true);assert.equal(r.editor.text,'aXYZbc');assert.deepEqual(r.calls,[]);
});

test('P26: failed precommit prevents paste and does not retry the failed write',async()=>{
  const r=await rig({mode:'EN'});await r.text('hel');r.editor.failInsert=true;
  assert.equal(await r.paste('XYZ'),false);assert.equal(r.editor.text,'hel');
  assert.deepEqual(r.pasteDispatches,[]);
  assert.deepEqual(r.editor.calls.filter(c=>c.operation==='insert').map(c=>c.text),['hel']);
});

test('P26: a target change during paste precommit prevents the clipboard reaching the new field',async()=>{
  const r=await rig({mode:'EN'});await r.text('hel');
  r.hooks.submit=async()=>{await r.coordinator.postEvent({kind:'submit'});r.editor.epoch++;return r.coordinator.getSnapshot();};
  assert.equal(await r.paste('XYZ',1),false);assert.equal(r.editor.text,'hel');assert.equal(r.editor.count('insert'),1);
  assert.deepEqual(r.pasteDispatches,[]);
});

test('P26: paste precommit throw is propagated without a paste or retry',async()=>{
  const r=await rig({mode:'EN'});await r.text('hel');r.hooks.submit=async()=>{throw new Error('submit failed');};
  await assert.rejects(r.paste('XYZ'),/submit failed/);assert.equal(r.editor.count('insert'),0);assert.deepEqual(r.calls,[['submit']]);
});

test('P26: following text waits for layout persistence within the shared operation queue',async()=>{
  const r=await rig(),started=deferred(),finish=deferred();
  r.hooks.save=async order=>{started.resolve();await finish.promise;r.state.order=order;};
  const queue=new InputOperationQueue(()=>r.editor.epoch,()=>r.coordinator.getSnapshot());
  const first=queue.enqueue(()=>r.local.handle({kind:'config',layoutOrder:'en_qwerty,jp_qwerty'},1));
  const second=queue.enqueue(async()=>{assert.equal(r.state.order,'en_qwerty,jp_qwerty');
    await r.local.handle({kind:'cycle'},1);await r.text('a');return r.coordinator.getSnapshot();});
  await started.promise;assert.equal(r.editor.count('insert'),0);assert.equal(r.calls.some(c=>c[0]==='publish'),false);
  finish.resolve();await first;await second;assert.equal(r.editor.text,'a');assert.equal(r.state.layout,'en_qwerty');
});
