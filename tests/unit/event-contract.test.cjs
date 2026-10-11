const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const ts = require('typescript');

// Compile the actual exported contract declarations; do not maintain duplicate types.
const protocolPath = resolve(__dirname, '../../entry/src/main/ets/kanon/InputEventTypes.ets');
const protocol = ts.createSourceFile(protocolPath, readFileSync(protocolPath, 'utf8'), ts.ScriptTarget.ES2020, true);
const coordinatorPath = resolve(__dirname, '../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const coordinator = ts.createSourceFile(coordinatorPath, readFileSync(coordinatorPath, 'utf8'), ts.ScriptTarget.ES2020, true);
const coreNames = new Set(['ImeUiState', 'OpResult', 'TextReadResult', 'EditorPort', 'EngineUpdate',
  'EnginePort', 'CompositionPhase', 'CandidateLabel', 'CommitEffect']);
const declarations = coordinator.statements.filter(statement => coreNames.has(statement.name?.text));
assert.equal(declarations.length, coreNames.size);
const contract = protocol.statements.filter(statement => ts.isInterfaceDeclaration(statement) ||
  ts.isTypeAliasDeclaration(statement)).map(statement => statement.getText(protocol)).join('\n') + '\n' +
  declarations.map(statement => statement.getText(coordinator)).join('\n');

function check(fixture) {
  const filename = resolve(__dirname, 'event-contract-fixture.ts');
  const options = { strict: true, noEmit: true, target: ts.ScriptTarget.ES2020, types: [] };
  const host = ts.createCompilerHost(options);
  const original = host.getSourceFile.bind(host);
  host.getSourceFile = (path, languageVersion, onError, shouldCreateNewSourceFile) =>
    resolve(path) === filename ? ts.createSourceFile(path, contract + '\n' + fixture, languageVersion, true) :
      original(path, languageVersion, onError, shouldCreateNewSourceFile);
  return ts.getPreEmitDiagnostics(ts.createProgram([filename], options, host));
}

test('P04: event contracts accept declared operations and reject typos and request-only operations', () => {
  assert.deepEqual(check("const events: UiEvent[] = [{ kind: 'kana', text: 'あ' }, " +
    "{ kind: 'move', edge: 'begin' }, { kind: 'partial', expectedRevision: 1 }, { kind: 'undoCompletion' }];" +
    "const state: ImeUiState = 'JP_COMPOSING';"), []);
  for (const fixture of ["const event: UiEvent = { kind: 'converrt' };",
    "const event: UiEvent = { kind: 'prepare' };",
    "const event: UiEvent = { kind: 'config' };",
    "const event: UiEvent = { kind: 'cycle' };",
    "const event: UiEvent = { kind: 'undoEnglish' };",
    "const event: UiEvent = { kind: 'move', edge: 'middle' };",
    "const state: ImeUiState = 'JP_PREDICTING';"]) {
    const diagnostics = check(fixture);
    assert.equal(diagnostics.length, 1, fixture);
    assert.equal(diagnostics[0].category, ts.DiagnosticCategory.Error, fixture);
    assert.ok([2322, 2820].includes(diagnostics[0].code), fixture);
  }
});

test('P23: the engine protocol accepts every complete payload shape', () => {
  assert.deepEqual(check(`const events: InputEvent[] = [
    {kind:'text',text:''}, {kind:'kana',text:'あ'}, {kind:'paste',text:'😀'},
    {kind:'compositionArrow',text:'left'}, {kind:'compositionCursor',cursor:0},
    {kind:'mode',text:'EN'}, {kind:'select',candidateId:-1,expectedRevision:0},
    {kind:'partial',expectedRevision:0}, {kind:'move',direction:'up'}, {kind:'move',edge:'begin'},
    {kind:'selectMove',direction:'down'}, {kind:'selectEdge',edge:'end'},
    {kind:'undoCompletion',text:'hello',cursor:5,prefixLength:1}, {kind:'enter'}, {kind:'reset'}
  ];`), []);
});

test('P23: required engine payloads cannot be omitted or replaced by fallback values', () => {
  const invalid = ["{kind:'text'}", "{kind:'kana'}", "{kind:'paste'}", "{kind:'select',candidateId:0}",
    "{kind:'select',expectedRevision:0}", "{kind:'partial'}", "{kind:'compositionArrow'}",
    "{kind:'compositionCursor'}", "{kind:'mode'}", "{kind:'move'}", "{kind:'selectMove'}",
    "{kind:'selectEdge'}", "{kind:'undoCompletion',text:'hello',cursor:5}",
    "{kind:'undoCompletion',text:'hello',prefixLength:1}", "{kind:'undoCompletion',cursor:5,prefixLength:1}",
    "{kind:'move',direction:3}", "{kind:'move',direction:'sideways'}",
    "{kind:'move',edge:'begin',direction:'left'}", "{kind:'selectMove',direction:'left',edge:'begin'}",
    "{kind:'selectEdge',edge:'end',direction:'right'}", "{kind:'mode',text:'invalid'}",
    "{kind:'compositionArrow',text:'up'}"];
  const diagnostics = check(invalid.map((event,i)=>`const event${i}: InputEvent = ${event};`).join('\n'));
  assert.equal(diagnostics.length, invalid.length);
  const lineOffset = contract.split('\n').length;
  const lines = diagnostics.map(d=>{
    assert.equal(d.category,ts.DiagnosticCategory.Error);
    return d.file.getLineAndCharacterOfPosition(d.start).line-lineOffset;
  });
  assert.deepEqual(lines, invalid.map((_,i)=>i), 'Every invalid declaration must be rejected');
});

test('P23: an unvalidated request cannot cross EnginePort', () => {
  const diagnostics = check(`function send(engine: EnginePort, request: UiEvent) {
    engine.dispatch('fixed',1,1,request);
  }`);
  assert.equal(diagnostics.length, 1);
  assert.equal(diagnostics[0].code, 2345);
});

test('P23: EditorPort requires preview position verification and semantic directions', () => {
  const methods = `getEpoch:()=>1, hasSelection:()=>false,
    setPreview:async()=>({ok:true,code:0}), finishPreview:async()=>({ok:true,code:0}),
    insert:async()=>({ok:true,code:0}), deleteForward:async()=>({ok:true,code:0}),
    deleteBackward:async()=>({ok:true,code:0}), moveCursor:async()=>({ok:true,code:0}),
    selectByMovement:async()=>({ok:true,code:0}), selectAll:async()=>({ok:true,code:0}),
    selectRange:async()=>({ok:true,code:0}), queryPreviewSupported:async()=>true,
    queryCursor:async()=>0, queryBefore:async()=>'', queryBeforeResult:async()=>({ok:true,code:0,value:''})`;
  assert.deepEqual(check(`const port:EditorPort={${methods},previewCaret:async()=>({ok:true,code:0})};
    port.moveCursor('left'); port.selectByMovement('down');`), []);
  const missing = check(`const port:EditorPort={${methods}};`);
  assert.equal(missing.length, 1); assert.equal(missing[0].code, 2741);
  assert.match(ts.flattenDiagnosticMessageText(missing[0].messageText, '\n'), /previewCaret/);
  for (const fixture of ["function move(port:EditorPort){port.moveCursor(3);}",
    "function select(port:EditorPort){port.selectByMovement(4);}"]) {
    assert.equal(check(fixture)[0].code, 2345);
  }
});
