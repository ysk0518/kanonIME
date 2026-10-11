const test=require('node:test');
const assert=require('node:assert/strict');
const {ImePresentation}=require('../../entry/src/main/ets/kanon/ImePresentation.ets');
const {ImeViewPublisher}=require('../../entry/src/main/ets/kanon/ImeViewPublisher.ets');
const {ImeCoordinator}=require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const {EnglishPrediction}=require('../../entry/src/main/ets/kanon/EnglishPrediction.ets');
const {EnglishEngine}=require('../../entry/src/main/ets/kanon/EnglishEngine.ets');
const {MozcEngine}=require('../../entry/src/main/ets/kanon/MozcEngine.ets');
const {FakeEditor,ScriptedBridge,response}=require('../support/fakes.cjs');

function sink(){const values=new Map(),writes=[];const write=(key,value)=>{values.set(key,value);writes.push([key,value]);};
  return {values,writes,port:{string:write,number:write,boolean:write,strings:write,numbers:write}};}
function candidatePort(coordinator,editor){return {getEpoch:()=>editor.epoch,
  usesEnglishComposition:()=>coordinator.usesEnglishComposition(),getCandidateView:()=>coordinator.getCandidateView(),
  getCandidateRevision:()=>coordinator.getCandidateRevision()};}
function rig(){const display=sink(),editor=new FakeEditor(),prediction=new EnglishPrediction({undoChanged:()=>{},cleared:()=>{},selectionAbandoned:()=>{}});
  const state={composing:false,candidates:[{id:11,label:'亜'},{id:12,label:'😀'}],revision:6};
  const reads=[];const coordinator={getEpoch:()=>editor.epoch,usesEnglishComposition:()=>state.composing,
    getCandidateView:()=>{reads.push('candidates');return state.candidates;},getCandidateRevision:()=>state.revision};
  const japanese={getConversionReading:()=> 'あ',getCursorPreview:()=> 'あ│',getLastLens:()=> '3,4',getSelIdx:()=> 1};
  const presentation=new ImePresentation(coordinator,prediction,japanese,new ImeViewPublisher(display.port));
  const snapshot=values=>({...new ImeCoordinator(editor).getSnapshot(),...values});
  return {display,editor,prediction,state,reads,coordinator,japanese,presentation,snapshot};}

test('P27: Japanese presentation gathers reading, selection and coordinator candidates together',()=>{
  const r=rig();r.presentation.publish(r.snapshot({preeditLen:1,candidateCount:2,state:'JP_COMPOSING'}));
  assert.deepEqual(r.display.values.get('kanonList'),['亜','😀']);assert.deepEqual(r.display.values.get('kanonIdList'),[11,12]);
  assert.equal(r.display.values.get('kanonRev'),6);assert.equal(r.display.values.get('kanonConversionReading'),'あ');
  assert.equal(r.display.values.get('kanonCompositionCursor'),'あ│');assert.equal(r.display.values.get('kanonSel'),1);
  assert.equal(r.display.values.get('kanonJapaneseComposing'),true);assert.deepEqual(r.reads,['candidates']);assert.deepEqual(r.editor.calls,[]);
});

test('P27: direct English presentation uses prediction candidates and revision while diagnostics use coordinator data',()=>{
  const r=rig();r.prediction.text('he',0);const items=r.prediction.getItems();r.prediction.selectNext();
  r.presentation.publish(r.snapshot({mode:'EN',state:'DIRECT_EN'}));
  assert.deepEqual(r.display.values.get('kanonList'),items.slice(0,20).map(item=>item.label));
  assert.deepEqual(r.display.values.get('kanonIdList'),items.slice(0,20).map(item=>item.id));
  assert.equal(r.display.values.get('kanonRev'),r.prediction.getRevision());assert.equal(r.display.values.get('kanonCand'),items.length);
  assert.equal(r.display.values.get('kanonSel'),r.prediction.getSelectedIndex());
  assert.equal(r.display.values.get('kanonIds'),'11,12');assert.equal(r.display.values.get('kanonLens2'),'2:1,2');
  assert.equal(r.display.values.get('kanonEnglishComposing'),true);assert.equal(r.display.values.get('kanonConversionReading'),'');
});

test('P27: preview English presentation retains coordinator candidates instead of a stale direct prediction',()=>{
  const r=rig();r.state.composing=true;r.prediction.text('he',0);
  r.presentation.publish(r.snapshot({mode:'EN',state:'EN_COMPOSING',preeditLen:2,candidateCount:2}));
  assert.deepEqual(r.display.values.get('kanonList'),['亜','😀']);assert.equal(r.display.values.get('kanonRev'),6);
  assert.equal(r.display.values.get('kanonEnglishComposing'),true);assert.equal(r.display.values.get('kanonCompositionCursor'),'');
});

test('P27: candidate access preserves language-specific source while compatibility slots remain coordinator-based',()=>{
  const r=rig();r.prediction.text('he',0);
  assert.deepEqual(r.presentation.getCandidates('EN'),r.prediction.getItems());
  assert.deepEqual(r.presentation.getCandidates('JP'),r.state.candidates);r.state.composing=true;
  assert.deepEqual(r.presentation.getCandidates('EN'),r.state.candidates);
  assert.equal(r.presentation.getCandidateLabelAt(0),'亜');assert.equal(r.presentation.getCandidateIdAt(1),12);
});

test('P27: compatibility candidate access retains empty, negative and signed ID policies',()=>{
  const r=rig();r.state.candidates=[{id:-9,label:''},{id:0,label:'a'}];
  assert.equal(r.presentation.getCandidateIdAt(0),-9);assert.equal(r.presentation.getCandidateIdAt(1),0);
  for(const index of [-1,2,100,0.5,NaN]){assert.equal(r.presentation.getCandidateLabelAt(index),'');assert.equal(r.presentation.getCandidateIdAt(index),-1);}
  assert.equal(r.presentation.getCandidateLabelAt(0),'');assert.equal(r.presentation.getCandidateLabelAt(1),'a');
});

test('P27: compatibility slots cap at twenty while diagnostic IDs and lengths retain all candidates',()=>{
  const r=rig();r.state.candidates=Array.from({length:25},(_,i)=>({id:i,label:'😀'}));
  assert.equal(r.presentation.getCandidateSlotCount(),20);assert.equal(r.presentation.getCandidateIds(),Array.from({length:25},(_,i)=>i).join(','));
  assert.equal(r.presentation.getCandidateLens2(),'25:'+Array(25).fill('2').join(','));
  r.state.candidates=[];assert.equal(r.presentation.getCandidateSlotCount(),0);assert.equal(r.presentation.getCandidateIds(),'');
  assert.equal(r.presentation.getCandidateLens2(),'0:');
});

test('P27: compatibility access failures return the existing defaults without editing',()=>{
  const r=rig();r.coordinator.getCandidateView=()=>{throw new Error('view unavailable');};
  assert.deepEqual(r.presentation.getCandidates('JP'),[]);assert.equal(r.presentation.getCandidateLabelAt(0),'');
  assert.equal(r.presentation.getCandidateIdAt(0),-1);assert.equal(r.presentation.getCandidateSlotCount(),0);
  assert.equal(r.presentation.getCandidateIds(),'');assert.equal(r.presentation.getCandidateLens2(),'e');assert.deepEqual(r.editor.calls,[]);
});

test('P27: presenting repeated snapshots advances display tick without mutating snapshot or engine candidates',()=>{
  const r=rig(),snapshot=r.snapshot({candidateCount:2}),before=JSON.stringify(snapshot),candidates=JSON.stringify(r.state.candidates);
  r.presentation.publish(snapshot);r.presentation.publish(snapshot);assert.equal(r.display.values.get('kanonTick'),2);
  assert.equal(JSON.stringify(snapshot),before);assert.equal(JSON.stringify(r.state.candidates),candidates);
  r.display.values.get('kanonList')[0]='changed';assert.equal(r.state.candidates[0].label,'亜');
});

test('P27: late presentation from another input target does not collect sources, write or advance the display tick',()=>{
  const r=rig();assert.equal(r.presentation.publish(r.snapshot({candidateCount:2}),1),true);
  const before=[...r.display.values],writeCount=r.display.writes.length;r.reads.length=0;r.editor.epoch=2;
  assert.equal(r.presentation.publish(r.snapshot({mode:'EN',state:'DIRECT_EN'}),1),false);
  assert.deepEqual([...r.display.values],before);assert.equal(r.display.writes.length,writeCount);assert.deepEqual(r.reads,[]);
  assert.equal(r.presentation.publish(r.snapshot({mode:'EN',state:'DIRECT_EN'}),2),true);
  assert.equal(r.display.values.get('kanonTick'),2);assert.equal(r.display.values.get('kanonMode'),'EN');
});

test('P27: clearing direct English prediction clears visible candidates and composing state',()=>{
  const r=rig();r.prediction.text('he',0);r.presentation.publish(r.snapshot({mode:'EN',state:'DIRECT_EN'}));
  r.prediction.clear();r.presentation.publish(r.snapshot({mode:'EN',state:'DIRECT_EN'}));
  assert.deepEqual(r.display.values.get('kanonList'),[]);assert.deepEqual(r.display.values.get('kanonIdList'),[]);
  assert.equal(r.display.values.get('kanonEnglishComposing'),false);assert.equal(r.display.values.get('kanonSel'),-1);
});

test('P27: real Japanese engine updates are gathered through coordinator into display without extra bridge calls',async()=>{
  const editor=new FakeEditor(),bridge=new ScriptedBridge([{operation:'convert',text:'k',output:response('ｋ')},
    {operation:'convert',text:'i',output:response('き',{candidates:[{id:31,value:'木'}]})}]);
  const engine=new MozcEngine(bridge),coordinator=new ImeCoordinator(editor),display=sink();
  coordinator.setEngine(engine);await coordinator.loadPreviewSupport();
  const prediction=new EnglishPrediction({undoChanged:()=>{},cleared:()=>{},selectionAbandoned:()=>{}});
  const presentation=new ImePresentation(candidatePort(coordinator,editor),prediction,engine,new ImeViewPublisher(display.port));
  await coordinator.postEvent({kind:'text',text:'k'});presentation.publish(coordinator.getSnapshot());
  assert.equal(display.values.get('kanonJapaneseComposing'),true);
  await coordinator.postEvent({kind:'text',text:'i'});presentation.publish(coordinator.getSnapshot());
  assert.deepEqual(display.values.get('kanonList'),['木']);assert.deepEqual(display.values.get('kanonIdList'),[31]);
  assert.equal(display.values.get('kanonRev'),coordinator.getCandidateRevision());assert.equal(display.values.get('kanonTick'),2);
  assert.deepEqual(editor.calls,[]);bridge.assertDone();
});

test('P27: real English composing and direct paths gather current candidates across conversion and commit',async()=>{
  for(const supported of [true,false]){
    const editor=new FakeEditor();editor.supported=supported;const coordinator=new ImeCoordinator(editor),display=sink();
    const prediction=new EnglishPrediction({undoChanged:()=>{},cleared:()=>{},selectionAbandoned:()=>{}}),engine=new EnglishEngine(prediction);
    coordinator.setEnglishEngine(engine);await coordinator.loadPreviewSupport();await coordinator.postEvent({kind:'mode',text:'EN'});
    const japanese={getConversionReading:()=>'',getCursorPreview:()=>'',getLastLens:()=>'',getSelIdx:()=>-1};
    const presentation=new ImePresentation(candidatePort(coordinator,editor),prediction,japanese,new ImeViewPublisher(display.port));
    await coordinator.postEvent({kind:'text',text:'he'});if(!supported){prediction.text('he',0);}
    presentation.publish(coordinator.getSnapshot());assert.equal(display.values.get('kanonEnglishComposing'),true);
    assert.ok(display.values.get('kanonList').includes('hello'));
    if(supported){await coordinator.postEvent({kind:'convert'});presentation.publish(coordinator.getSnapshot());
      assert.equal(display.values.get('kanonSel'),prediction.getSelectedIndex());
      await coordinator.postEvent({kind:'enter'});
    }else{prediction.clear();}
    presentation.publish(coordinator.getSnapshot());assert.equal(display.values.get('kanonEnglishComposing'),false);
    assert.deepEqual(display.values.get('kanonList'),[]);
  }
});
