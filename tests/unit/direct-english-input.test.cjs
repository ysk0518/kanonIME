const test = require('node:test');
const assert = require('node:assert/strict');
const { DirectEnglishInput } = require('../../entry/src/main/ets/kanon/DirectEnglishInput.ets');
const { EnglishPrediction } = require('../../entry/src/main/ets/kanon/EnglishPrediction.ets');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { InputOperationQueue } = require('../../entry/src/main/ets/kanon/InputOperationQueue.ets');
const { FakeEditor, deferred } = require('../support/fakes.cjs');

async function rig(text = 'he', prefix = 'he') {
  const editor = new FakeEditor(text); editor.supported = false;
  const coordinator = new ImeCoordinator(editor);
  await coordinator.loadPreviewSupport(); await coordinator.postEvent({kind:'mode',text:'EN'});
  const notices=[];
  const prediction = new EnglishPrediction({undoChanged:value=>notices.push(['undo',value]),
    cleared:()=>notices.push(['clear']), selectionAbandoned:()=>notices.push(['abandoned'])});
  if (prefix) { prediction.text(prefix,text.length-prefix.length); }
  const state={allowed:true}; const calls=[]; const hooks={};
  const port={
    getEpoch:()=>editor.getEpoch(), predictionAllowed:()=>state.allowed,
    queryCursor:async()=>{calls.push(['cursor']);return hooks.cursor?hooks.cursor():editor.queryCursor();},
    queryBefore:async length=>{calls.push(['before',length]);return hooks.before?hooks.before(length):editor.queryBefore(length);},
    dispatch:async event=>{
      calls.push(['dispatch',{...event},prediction.editing]);
      if(hooks.dispatch){await hooks.dispatch(event);}else{await coordinator.postEvent(event);}
    },
    lastError:()=>coordinator.getSnapshot().lastError,
    enterAction:async epoch=>{calls.push(['enter',epoch]);}
  };
  return {editor,coordinator,prediction,notices,state,calls,hooks,port,input:new DirectEnglishInput(prediction,port)};
}

test('P24: direct Space cycles suggestions without editing the prefix already in the editor',async()=>{
  const r=await rig(); const count=r.prediction.getItems().length;
  for(let i=0;i<=count;i++) {
    assert.equal(await r.input.convert(r.editor.epoch),'handled');
    assert.equal(r.prediction.getSelectedIndex(),i%count); assert.equal(r.editor.text,'he');
  }
  assert.equal(r.editor.calls.length,0); assert.equal(r.calls.filter(c=>c[0]==='dispatch').length,0);
});

test('P24: candidate completion inserts only the suffix once through Coordinator and remembers undo',async()=>{
  const r=await rig('say he','he');const item=r.prediction.getItems()[0];
  await r.input.complete(item.id,r.prediction.getRevision());
  assert.equal(r.editor.text,'say hello'); assert.equal(r.editor.count('insert'),1);
  assert.deepEqual(r.calls,[['cursor'],['before',6],['dispatch',{kind:'text',text:'llo'},true]]);
  assert.equal(r.prediction.editing,false); assert.equal(r.prediction.getPrefix(),'');
  assert.deepEqual(r.prediction.takeUndo(),{prefix:'he',word:'hello',cursor:9,epoch:1});
  assert.equal(r.prediction.takeUndo(),undefined);
});

test('P24: repeated taps with the old revision cannot complete twice',async()=>{
  const r=await rig();const item=r.prediction.getItems()[0],revision=r.prediction.getRevision();
  await r.input.handle('select',item.id,revision);await r.input.handle('select',item.id,revision);
  assert.equal(r.editor.text,'hello');assert.equal(r.editor.count('insert'),1);
  assert.equal(r.calls.filter(c=>c[0]==='cursor').length,1);
});

test('P24: denied prediction, old revision and unknown candidate make no editor calls',async()=>{
  for(const scenario of ['disabled','revision','candidate','missing']) {
    const r=await rig(),item=r.prediction.getItems()[0];
    if(scenario==='disabled'){r.state.allowed=false;}
    await r.input.handle('select',scenario==='missing'?undefined:scenario==='candidate'?-1:item.id,
      scenario==='missing'?undefined:r.prediction.getRevision()+(scenario==='revision'?1:0));
    assert.deepEqual(r.calls,[]);assert.equal(r.editor.text,'he');assert.equal(r.prediction.getPrefix(),'he');
  }
});

test('P24: unknown cursor and cursor mismatch reject completion before reading the word',async()=>{
  for(const cursor of [-1,0,4097]) {
    const r=await rig();r.hooks.cursor=()=>cursor;
    await r.input.complete(r.prediction.getItems()[0].id,r.prediction.getRevision());
    assert.deepEqual(r.calls,[['cursor']]);assert.equal(r.editor.text,'he');assert.equal(r.prediction.getPrefix(),'');
  }
});

test('P24: a mismatching editor prefix cannot be destructively replaced or completed',async()=>{
  const r=await rig();r.hooks.before=()=> 'ha';
  await r.input.complete(r.prediction.getItems()[0].id,r.prediction.getRevision());
  assert.deepEqual(r.calls,[['cursor'],['before',2]]);assert.equal(r.editor.text,'he');
  assert.equal(r.editor.count('insert'),0);assert.equal(r.editor.count('deleteForward'),0);
  assert.equal(r.editor.count('selectRange'),0);assert.equal(r.prediction.getPrefix(),'');
});

test('P24: input target change during cursor read prevents reading the new target',async()=>{
  for(const action of ['convert','complete','beforeText']) {
    const r=await rig(action==='beforeText'?'he':'he',action==='beforeText'?'':'he');
    r.hooks.cursor=()=>{r.editor.epoch++;return 2;};
    if(action==='convert'){assert.equal(await r.input.convert(1),'stale');}
    else if(action==='complete'){await r.input.complete(r.prediction.getItems()[0].id,r.prediction.getRevision());}
    else {assert.equal(await r.input.beforeText('l',1),2);assert.equal(r.prediction.getPrefix(),'');}
    assert.deepEqual(r.calls,[['cursor']]);assert.equal(r.editor.text,'he');
  }
});

test('P24: input target change during word read prevents seeding, selection and suffix insertion',async()=>{
  for(const action of ['convert','complete','beforeText']) {
    const r=await rig('he',action==='beforeText'?'':'he');
    r.hooks.before=()=>{r.editor.epoch++;return 'he';};
    if(action==='convert'){assert.equal(await r.input.convert(1),'stale');}
    else if(action==='complete'){await r.input.complete(r.prediction.getItems()[0].id,r.prediction.getRevision());}
    else {await r.input.beforeText('l',1);}
    assert.deepEqual(r.calls,[['cursor'],['before',2]]);assert.equal(r.prediction.getPrefix(),'');
    assert.equal(r.prediction.getSelectedIndex(),-1);assert.equal(r.editor.count('insert'),0);
  }
});

test('P24: failed insertion is reported by Coordinator and never remembered or retried',async()=>{
  const r=await rig();r.editor.failInsert=true;
  await r.input.complete(r.prediction.getItems()[0].id,r.prediction.getRevision());
  assert.equal(r.coordinator.getSnapshot().lastError,'edit-12800003');
  assert.equal(r.editor.text,'he');assert.equal(r.editor.count('insert'),1);
  assert.equal(r.prediction.takeUndo(),undefined);assert.equal(r.prediction.editing,false);
});

test('P24: rejected dispatch propagates but releases the editing guard and prediction in finally',async()=>{
  const r=await rig();const error=new Error('fixed dispatch failure');r.hooks.dispatch=async()=>{throw error;};
  await assert.rejects(r.input.complete(r.prediction.getItems()[0].id,r.prediction.getRevision()),e=>e===error);
  assert.equal(r.prediction.editing,false);assert.equal(r.prediction.getPrefix(),'');
  assert.equal(r.prediction.takeUndo(),undefined);assert.equal(r.calls.filter(c=>c[0]==='dispatch').length,1);
});

test('P24: target change during suffix insertion cannot leave an undo entry for the new target',async()=>{
  const r=await rig();r.hooks.dispatch=async event=>{await r.coordinator.postEvent(event);r.editor.epoch++;};
  await r.input.complete(r.prediction.getItems()[0].id,r.prediction.getRevision());
  assert.equal(r.editor.text,'hello');assert.equal(r.prediction.takeUndo(),undefined);
  assert.equal(r.prediction.editing,false);
});

test('P24: selection or prediction changes during editor reads invalidate the pending candidate',async()=>{
  for(const phase of ['cursor','before']) {
    for(const change of ['selection','revision','policy']) {
      const r=await rig();const item=r.prediction.getItems()[0],revision=r.prediction.getRevision();
      const mutate=()=>{
        if(change==='selection'){r.prediction.selectionChanged(0,2);}
        if(change==='revision'){r.prediction.updateComposition('he');}
        if(change==='policy'){r.state.allowed=false;}
      };
      if(phase==='cursor'){r.hooks.cursor=()=>{mutate();return 2;};}
      else{r.hooks.before=()=>{mutate();return 'he';};}
      await r.input.complete(item.id,revision);
      assert.equal(r.editor.text,'he',`${phase}/${change}`);
      assert.equal(r.calls.filter(c=>c[0]==='dispatch').length,0,`${phase}/${change}`);
      if(phase==='cursor'){assert.deepEqual(r.calls,[['cursor']]);}
    }
  }
});

test('P24: a range selection arriving during a word read prevents seeding obsolete text',async()=>{
  const r=await rig('he','');r.hooks.before=()=>{r.prediction.selectionChanged(0,2);return 'he';};
  await r.input.beforeText('l',1);
  assert.equal(r.prediction.getPrefix(),'');assert.equal(r.prediction.canSeed(),false);
});

test('P24 provisional: completion beyond the existing 4096 cursor limit is inserted without undo',async()=>{
  const r=await rig('x'.repeat(4093)+'he','he');
  await r.input.complete(r.prediction.getItems()[0].id,r.prediction.getRevision());
  assert.equal(r.editor.text.length,4098);assert.ok(r.editor.text.endsWith('hello'));
  assert.equal(r.prediction.takeUndo(),undefined);assert.equal(r.editor.count('insert'),1);
});

test('P24: Enter completes the selected word, then the next Enter sends only the field action',async()=>{
  const r=await rig();await r.input.convert(1);await r.input.handle('enter');
  assert.equal(r.editor.text,'hello');assert.equal(r.calls.filter(c=>c[0]==='enter').length,0);
  await r.input.handle('enter');
  assert.equal(r.editor.text,'hello');assert.equal(r.editor.count('insert'),1);
  assert.deepEqual(r.calls.filter(c=>c[0]==='enter'),[['enter',1]]);
});

test('P24: Enter without a selected suggestion retains the typed word and defers the field action',async()=>{
  const r=await rig();await r.input.handle('enter');
  assert.equal(r.editor.text,'he');assert.equal(r.prediction.getPrefix(),'');assert.deepEqual(r.calls,[]);
  await r.input.handle('enter');assert.deepEqual(r.calls,[['enter',1]]);
});

test('P24: cancel clears suggestions and uses the coordinator cancel path without deleting typed text',async()=>{
  const r=await rig();await r.input.convert(1);await r.input.handle('cancel');
  assert.equal(r.editor.text,'he');assert.equal(r.prediction.getPrefix(),'');
  assert.deepEqual(r.calls.filter(c=>c[0]==='dispatch'),[['dispatch',{kind:'cancel'},false]]);
  assert.equal(r.editor.count('deleteForward'),0);assert.equal(r.calls.filter(c=>c[0]==='enter').length,0);
});

test('P24: no suggestions and disabled prediction request the existing ordinary-space route',async()=>{
  for(const scenario of ['empty','disabled','unknown']) {
    const r=await rig(scenario==='unknown'?'qqqq':'',scenario==='unknown'?'qqqq':'');
    if(scenario==='disabled'){r.state.allowed=false;}
    assert.equal(await r.input.convert(1),'space');assert.deepEqual(r.calls,[]);
  }
});

test('P24: stale editor position or word clears conversion without inserting a space',async()=>{
  for(const scenario of ['cursor','word']) {
    const r=await rig();if(scenario==='cursor'){r.hooks.cursor=()=>1;}else{r.hooks.before=()=> 'ha';}
    assert.equal(await r.input.convert(1),'handled');assert.equal(r.prediction.getPrefix(),'');
    assert.equal(r.editor.text,'he');assert.equal(r.calls.filter(c=>c[0]==='dispatch').length,0);
  }
});

test('P24: seeding reads only the trailing ASCII word from the current editor',async()=>{
  const r=await rig('say He','');
  assert.equal(await r.input.beforeText('l',1),6);assert.equal(r.prediction.getPrefix(),'He');
  assert.equal(r.prediction.getCursor(),6);assert.deepEqual(r.calls,[['cursor'],['before',6]]);
  await r.coordinator.postEvent({kind:'text',text:'l'});r.input.afterEvent('text','l',6,true);
  assert.equal(r.editor.text,'say Hel');assert.equal(r.prediction.getPrefix(),'Hel');
  assert.equal(r.prediction.getItems()[0].label,'Hello');
});

test('P24: tracked prefix bypasses repeated editor reads before each additional letter',async()=>{
  const r=await rig();assert.equal(await r.input.beforeText('l',1),2);assert.deepEqual(r.calls,[]);
  await r.coordinator.postEvent({kind:'text',text:'l'});r.input.afterEvent('text','l',2,true);
  assert.equal(r.editor.text,'hel');assert.equal(r.prediction.getCursor(),3);
});

test('P24: punctuation, password policy, selection and unknown cursor cannot seed a previous word',async()=>{
  for(const scenario of ['punctuation','disabled','selection','cursor','large-cursor','non-word','long-word']) {
    const r=await rig('he','');let text='l';
    if(scenario==='punctuation'){text='!';}
    if(scenario==='disabled'){r.state.allowed=false;}
    if(scenario==='selection'){r.prediction.selectionChanged(0,2);}
    if(scenario==='cursor'){r.hooks.cursor=()=>-1;}
    if(scenario==='large-cursor'){r.hooks.cursor=()=>4097;}
    if(scenario==='non-word'){r.hooks.before=()=> 'he!';}
    if(scenario==='long-word'){r.hooks.before=()=> 'a'.repeat(41);r.hooks.cursor=()=>41;}
    await r.input.beforeText(text,1);assert.equal(r.prediction.getPrefix(),'');
    if(!['non-word','long-word'].includes(scenario)){assert.deepEqual(r.calls,[['cursor']]);}
  }
});

test('P24: prediction follows successful ordinary text and Delete and clears for other operations',async()=>{
  const r=await rig();r.input.afterEvent('text','l',2,true);assert.equal(r.prediction.getPrefix(),'hel');
  r.input.afterEvent('backspace',undefined,3,true);assert.equal(r.prediction.getPrefix(),'he');
  r.input.afterEvent('move',undefined,2,true);assert.equal(r.prediction.getPrefix(),'');
  r.input.afterEvent('text','!',2,true);assert.equal(r.prediction.getPrefix(),'');
});

test('P24: failed ordinary edits and disabled prediction cannot retain stale suggestions',async()=>{
  for(const scenario of ['failed','disabled']) {
    const r=await rig();if(scenario==='disabled'){r.state.allowed=false;}
    r.input.afterEvent('text','l',2,scenario!=='failed');assert.equal(r.prediction.getPrefix(),'');
    assert.deepEqual(r.prediction.getItems(),[]);
  }
});

test('P24: query failures propagate without edits, silent retries or a stuck editing guard',async()=>{
  for(const action of ['convert','complete','beforeText']) {
    const r=await rig('he',action==='beforeText'?'':'he'),error=new Error('fixed read failure');
    r.hooks.before=async()=>{throw error;};
    const pending=action==='convert'?r.input.convert(1):action==='beforeText'?r.input.beforeText('l',1):
      r.input.complete(r.prediction.getItems()[0].id,r.prediction.getRevision());
    await assert.rejects(pending,e=>e===error);assert.deepEqual(r.calls,[['cursor'],['before',2]]);
    assert.equal(r.prediction.editing,false);assert.equal(r.editor.text,'he');
  }
});

test('P24: completion undo still uses the real coordinator suffix deletion and restores direct prefix',async()=>{
  const r=await rig();await r.input.convert(1);await r.input.handle('enter');
  const undo=r.prediction.takeUndo();assert.ok(undo);
  await r.coordinator.postEvent({kind:'undoCompletion',text:undo.word,cursor:undo.cursor,prefixLength:undo.prefix.length});
  assert.equal(r.coordinator.getSnapshot().lastError,'ok');assert.equal(r.editor.text,'he');
  r.prediction.restorePrefix(undo.prefix,undo.cursor-undo.word.length+undo.prefix.length);
  assert.equal(r.prediction.getPrefix(),'he');assert.equal(r.prediction.getCursor(),2);
});

test('P24: the existing operation queue keeps a following Enter behind pending completion',async()=>{
  const r=await rig(),started=deferred(),finish=deferred();await r.input.convert(1);
  const queue=new InputOperationQueue(()=>r.editor.getEpoch(),()=> 'stale');
  r.hooks.dispatch=async event=>{started.resolve();await finish.promise;await r.coordinator.postEvent(event);};
  const first=queue.enqueue(()=>r.input.handle('enter'));
  const second=queue.enqueue(()=>r.input.handle('enter'));
  try {
    const entered=await Promise.race([started.promise.then(()=>true),first.then(()=>false)]);
    assert.equal(entered,true,'completion must start before the first Enter finishes');
    assert.equal(r.prediction.editing,true);assert.equal(r.calls.filter(c=>c[0]==='enter').length,0);
    finish.resolve();await first;await second;
    assert.equal(r.editor.text,'hello');assert.equal(r.editor.count('insert'),1);
    assert.deepEqual(r.calls.filter(c=>c[0]==='enter'),[['enter',1]]);assert.equal(r.prediction.editing,false);
  } finally {
    finish.resolve();await Promise.allSettled([first,second]);
  }
});
