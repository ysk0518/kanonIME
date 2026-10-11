const mutations = {
  regressionLayoutReset: {
    file: 'kanon/ImeLocalRequests.ets',
    before: 'this.port.resetComposition();',
    after: '// Regression control: keep the previous preview origin.'
  },
  presentationTargetEpoch: {
    file: 'kanon/ImePresentation.ets',
    before: 'if (epoch !== this.coordinator.getEpoch()) { return false; }',
    after: 'if (false) { return false; }'
  },
  runtimePasswordPolicy: {
    file: 'kanon/ImeRuntimeBindings.ets',
    before: 'return pattern !== this.password && pattern !== this.numberPassword && pattern !== this.newPassword;',
    after: 'return pattern !== this.password;'
  },
  runtimeCursorEpoch: {
    file: 'kanon/ImeRuntimeBindings.ets',
    before: "if (epoch === this.port.getEpoch()) { this.port.number('kanonCursor', position); }",
    after: "this.port.number('kanonCursor', position);"
  },
  runtimeStoredConfirmation: {
    file: 'kanon/ImeRuntimeBindings.ets',
    before: "return this.port.readString('kanonLayoutOrder') === order;",
    after: 'return this.configuredOrder() === order;'
  },
  runtimeLayoutHistory: {
    file: 'kanon/ImeRuntimeBindings.ets',
    before: "this.port.string('kanonLastLayout', layout);",
    after: "this.port.string('kanonLastLayout', 'jp_flick');"
  },
  presentationCandidateSource: {
    file: 'kanon/ImePresentation.ets',
    before: 'candidates: directEnglish ? this.prediction.getItems() : diagnostics,',
    after: 'candidates: diagnostics,'
  },
  presentationCandidateRevision: {
    file: 'kanon/ImePresentation.ets',
    before: 'candidateRevision: directEnglish ? this.prediction.getRevision() : this.coordinator.getCandidateRevision(),',
    after: 'candidateRevision: this.coordinator.getCandidateRevision(),'
  },
  presentationDiagnosticSource: {
    file: 'kanon/ImePresentation.ets',
    before: 'diagnosticCandidates: diagnostics,',
    after: 'diagnosticCandidates: this.prediction.getItems(),'
  },
  localLayoutFailure: {
    file: 'kanon/ImeLocalRequests.ets',
    before: "if (snapshot.lastError !== 'ok' || snapshot.mode !== layoutLanguage(target)) {",
    after: 'if (false) {'
  },
  localLayoutEpoch: {
    file: 'kanon/ImeLocalRequests.ets',
    before: 'if (epoch !== this.port.getEpoch()) { return snapshot; }',
    after: 'if (false) { return snapshot; }'
  },
  localLayoutPublish: {
    file: 'kanon/ImeLocalRequests.ets',
    before: 'if (epoch === this.port.getEpoch()) { this.port.publish(snapshot); }',
    after: 'this.port.publish(snapshot);'
  },
  localCycleFlick: {
    file: 'kanon/ImeLocalRequests.ets',
    before: "nextLanguageLayout(order.join(','), current)",
    after: 'nextLanguageLayout(configured, current)'
  },
  localPasteSubmit: {
    file: 'kanon/ImeLocalRequests.ets',
    before: 'const committed: ImeSnapshot = await this.port.submit();',
    after: 'const committed: ImeSnapshot = this.port.snapshot();'
  },
  localPasteFailure: {
    file: 'kanon/ImeLocalRequests.ets',
    before: "return committed.lastError === 'ok' && epoch === this.port.getEpoch();",
    after: 'return epoch === this.port.getEpoch();'
  },
  localPasteEpoch: {
    file: 'kanon/ImeLocalRequests.ets',
    before: "return committed.lastError === 'ok' && epoch === this.port.getEpoch();",
    after: "return committed.lastError === 'ok';"
  },
  undoExplicitDelete: {
    file: 'kanon/EnglishCompletionLifecycle.ets',
    before: "if (kind === 'undoEnglish') {",
    after: 'if (false) {'
  },
  undoRestoreOrigin: {
    file: 'kanon/EnglishCompletionLifecycle.ets',
    before: 'this.port.restorePreview(undo.cursor - undo.word.length);',
    after: 'this.port.restorePreview(undo.cursor);'
  },
  undoTargetAfterDispatch: {
    file: 'kanon/EnglishCompletionLifecycle.ets',
    before: "const snapshot: ImeSnapshot = this.port.snapshot();\n        if (epoch !== this.port.getEpoch())",
    after: 'const snapshot: ImeSnapshot = this.port.snapshot();\n        if (false)'
  },
  undoCommitLength: {
    file: 'kanon/EnglishCompletionLifecycle.ets',
    before: 'context.start + snapshot.commitLength',
    after: 'context.start + context.prefix.length'
  },
  undoRefreshGuard: {
    file: 'kanon/EnglishCompletionLifecycle.ets',
    before: 'this.port.restorePreview(undo.cursor - undo.word.length);\n            this.prediction.editing = true;',
    after: 'this.port.restorePreview(undo.cursor - undo.word.length);'
  },
  undoRefreshRelease: {
    file: 'kanon/EnglishCompletionLifecycle.ets',
    before: 'finally { this.prediction.editing = false; }\n            if (epoch !== this.port.getEpoch())',
    after: 'finally {}\n            if (epoch !== this.port.getEpoch())'
  },
  directEnglishCandidateReceipt: {
    file: 'kanon/DirectEnglishInput.ets',
    before: 'return revision === this.prediction.getRevision() && prefix === this.prediction.getPrefix() &&\n      this.prediction.canSeed() && this.port.predictionAllowed();',
    after: 'return true;'
  },
  directEnglishSeedSelection: {
    file: 'kanon/DirectEnglishInput.ets',
    before: 'word !== null && epoch === this.port.getEpoch() &&\n        this.prediction.canSeed() && this.port.predictionAllowed()',
    after: 'word !== null && epoch === this.port.getEpoch() && this.port.predictionAllowed()'
  },
  directEnglishSuffix: {
    file: 'kanon/DirectEnglishInput.ets',
    before: "text: item.label.substring(prefix.length)",
    after: 'text: item.label'
  },
  directEnglishRevision: {
    file: 'kanon/DirectEnglishInput.ets',
    before: 'revision !== this.prediction.getRevision()',
    after: 'false'
  },
  directEnglishCursorEpoch: {
    file: 'kanon/DirectEnglishInput.ets',
    before: 'epoch !== this.port.getEpoch() || cursor !== expected',
    after: 'cursor !== expected'
  },
  directEnglishUndoSuccess: {
    file: 'kanon/DirectEnglishInput.ets',
    before: 'if (completed && end <= 4096)',
    after: 'if (end <= 4096)'
  },
  directEnglishEnter: {
    file: 'kanon/DirectEnglishInput.ets',
    before: "if (kind === 'enter' && this.prediction.getPrefix().length > 0)",
    after: 'if (false)'
  },
  directEnglishSeedEpoch: {
    file: 'kanon/DirectEnglishInput.ets',
    before: 'word !== null && epoch === this.port.getEpoch()',
    after: 'word !== null'
  },
  directionMapping: {
    file: 'kanon/EditorDirectionMap.ets',
    before: "if (value === sdk.left) { return 'left'; }",
    after: "if (value === sdk.left) { return 'right'; }"
  },
  eventPayloadOwnership: {
    file: 'kanon/InputEventContract.ets',
    before: 'return copy as InputEvent;',
    after: 'return request as InputEvent;'
  },
  movementPayload: {
    file: 'kanon/InputEventContract.ets',
    before: "return value === 'left' || value === 'right' || value === 'up' || value === 'down';",
    after: 'return true;'
  },
  previewCaretBypass: {
    file: 'kanon/ImeCoordinator.ets',
    before: 'const moved: OpResult = await this.editor.previewCaret(position, start, text);',
    after: 'const moved: OpResult = await this.editor.selectRange(position, position);'
  },
  previewCaretReadback: {
    file: 'kanon/PreviewCaretPlacement.ets',
    before: 'actual !== expected',
    after: 'false'
  },
  previewCaretCancel: {
    file: 'kanon/PreviewCaretPlacement.ets',
    before: 'generation === this.generation',
    after: 'true'
  },
  previewCaretEpoch: {
    file: 'kanon/PreviewCaretPlacement.ets',
    before: 'epoch === port.getEpoch()',
    after: 'true'
  },
  previewReceiptOrder: {
    file: 'kanon/PreviewSelectionReceipt.ets',
    before: 'return wait === undefined || await wait.ready;',
    after: 'return true;'
  },
  previewReceiptPosition: {
    file: 'kanon/PreviewSelectionReceipt.ets',
    before: 'end !== pending.position',
    after: 'false'
  },
  nativeCaretVerification: {
    file: 'kanon/MozcEngine.ets',
    before: 'this.caretPosition(out) !== position',
    after: 'false'
  },
  cursorSyncEpoch: {
    file: 'kanon/CompositionCursorSync.ets',
    before: "if (epoch !== this.port.getEpoch()) { return 'stale'; }\n    if (version !== this.version)",
    after: "if (false) { return 'stale'; }\n    if (version !== this.version)"
  },
  cursorSyncOrigin: {
    file: 'kanon/CompositionCursorSync.ets',
    before: 'const target: number = position - context.start;',
    after: 'const target: number = position;'
  },
  cursorSyncUnconfirmed: {
    file: 'kanon/CompositionCursorSync.ets',
    before: '!context.cursorAligned || ',
    after: ''
  },
  previewCaretConfirmation: {
    file: 'kanon/ImeCoordinator.ets',
    before: 'this.previewCaretAligned = moved.ok;',
    after: 'this.previewCaretAligned = true;'
  },
  cursorSyncNotify: {
    file: 'kanon/CompositionCursorSync.ets',
    before: "if (version !== this.version) { return 'retry'; }",
    after: "if (false) { return 'retry'; }"
  },
  selectionEditingGuard: {
    file: 'kanon/EnglishSelectionPolicy.ets',
    before: 'const clearPrediction: boolean = !context.editing &&',
    after: 'const clearPrediction: boolean ='
  },
  selectionCollapse: {
    file: 'kanon/EnglishSelectionPolicy.ets',
    before: 'const collapsed: boolean = begin === end;',
    after: 'const collapsed: boolean = true;'
  },
  editorCompletionEpoch: {
    file: 'kanon/EditorOperationQueue.ets',
    before: 'private current(epoch: number): boolean { return epoch === this.editorEpoch; }',
    after: 'private current(epoch: number): boolean { return true; }'
  },
  editorDeadlineSettlement: {
    file: 'kanon/EditorOperationQueue.ets',
    before: "if (settled) { return; }\n        settled = true;\n        this.runtime.log(op, 'timeout', '');",
    after: "settled = true;\n        this.runtime.log(op, 'timeout', '');"
  },
  editorUnresolvedWrite: {
    file: 'kanon/EditorOperationQueue.ets',
    before: 'this.unresolvedWriteEpoch = epoch;',
    after: 'this.unresolvedWriteEpoch = -1;'
  },
  editorAttachQueue: {
    file: 'kanon/EditorOperationQueue.ets',
    before: 'this.queue = Promise.resolve();',
    after: '// Deliberately keep the old unresolved tail.'
  },
  previewCancellationFinish: {
    file: 'kanon/PreviewLifecycle.ets',
    before: 'const finished: OpResult = await editor.finishPreview();',
    after: 'const finished: OpResult = { ok: true, code: 0 };'
  },
  previewCancellationEpoch: {
    file: 'kanon/PreviewLifecycle.ets',
    before: 'if (!cleared.ok) { return cleared; }\n  if (epoch !== editor.getEpoch()) { return { ok: false, code: -4 }; }',
    after: 'if (!cleared.ok) { return cleared; }'
  },
  localApplicationGeneration: {
    file: 'common/SettingsSyncCore.ets',
    before: 'if (this.applicationPending) {',
    after: 'if (false) {'
  },
  applicationRetry: {
    file: 'common/SettingsSyncCore.ets',
    before: 'if (this.applicationPending || this.ports.nextSettingsChange() !== undefined)',
    after: 'if (this.ports.nextSettingsChange() !== undefined)'
  },
  applicationWait: {
    file: 'common/SettingsSyncCore.ets',
    before: 'await this.onApplied(applied, this.pendingHeight, true);',
    after: 'this.onApplied(applied, this.pendingHeight, true).catch(() => {});'
  },
  requestReceiptRange: {
    file: 'common/SettingsAckPolicy.ets',
    before: 'sequence >= 0 && sequence <= lastIssued',
    after: 'sequence >= 0'
  },
  retryBudget: {
    file: 'common/SettingsRetryTimer.ets',
    before: 'this.count >= 3',
    after: 'this.count >= 4'
  },
  receiptSettlement: {
    file: 'common/SettingsReceiptState.ets',
    before: 'if (waiter.settled) { return; }',
    after: 'if (false) { return; }'
  },
  settingsHead: {
    file: 'common/SettingsRecordPolicy.ets',
    before: 'const tail: KeyboardSettingsChange = next.pending[1];',
    after: 'const tail: KeyboardSettingsChange = next.pending[0];'
  },
  settingsAck: {
    file: 'common/SettingsRecordPolicy.ets',
    before: 'change.sequence > sequence',
    after: 'change.sequence >= sequence'
  },
  settingsFlush: {
    file: 'common/SettingsPersistence.ets',
    before: 'port.flush();',
    after: '// Deliberately omit flush for the negative test.'
  },
  settingsGap: {
    file: 'common/KeyboardSettingsModel.ets',
    before: 'if (copy.keyGap === undefined) { copy.keyGap = DEFAULT_KEY_GAP; }',
    after: 'if (false) { copy.keyGap = DEFAULT_KEY_GAP; }'
  },
  settingsPreservation: {
    file: 'common/KeyboardSettingsModel.ets',
    before: 'const next: KeyboardSettingsSnapshot = copySettings(snapshot);',
    after: 'const next: KeyboardSettingsSnapshot = new KeyboardSettingsSnapshot();'
  },
  englishSelection: {
    file: 'kanon/EnglishEngine.ets',
    before: 'this.prediction.selectNext();',
    after: 'this.prediction.clear();'
  },
  englishDelete: {
    file: 'kanon/EnglishEngine.ets',
    before: 'if (this.prediction.getSelectedIndex() >= 0) {',
    after: 'if (false) {'
  },
  queueEpoch: {
    file: 'kanon/InputOperationQueue.ets',
    before: 'if (epoch !== this.getEpoch()) {',
    after: 'if (false) {'
  },
  queueOrder: {
    file: 'kanon/InputOperationQueue.ets',
    before: 'const run: Promise<T> = this.tail.then(',
    after: 'const run: Promise<T> = Promise.resolve().then('
  },
  eventValidation: {
    file: 'kanon/InputEventContract.ets',
    before: 'if (!validInputEvent(request)) {',
    after: 'if (false) {'
  },
  emptyMovement: {
    file: 'kanon/InputEventContract.ets',
    before: "mode === 'JP' && preeditLength > 0 &&",
    after: "mode === 'JP' &&"
  },
  previewGeneration: {
    file: 'kanon/CompositionPreview.ets',
    before: 'return generation === this.generation && epoch === this.port.getEpoch();',
    after: 'return epoch === this.port.getEpoch();'
  },
  displayLimit: {
    file: 'kanon/ImeViewModel.ets',
    before: 'i < source.candidates.length && i < 20',
    after: 'i < source.candidates.length'
  },
  reviveHistory: {
    file: 'kanon/MozcEditState.ets',
    before: 'if (!hasPreedit) { this.reset(); return; }',
    after: 'if (hasPreedit) { this.reset(); return; }'
  },
  candidatePhase: {
    file: 'kanon/ImeCoordinator.ets',
    before: "} else if (update.phase === 'converting') {",
    after: '} else if (update.candidateCount > 0) {'
  },
  suggestion: {
    file: 'kanon/MozcEditState.ets',
    before: "return phase === 'composing' || (this.scope === 'segment' && phase === 'converting');",
    after: "return this.scope === 'segment' && phase === 'converting';"
  },
  modifier: {
    file: 'kanon/MozcEngine.ets',
    before: "if (this.phase !== 'composing') {",
    after: "if (this.phase !== 'composing' || !this.editing.canReplay()) {"
  },
  anchor: {
    file: 'kanon/CompositionPosition.ets',
    before: 'return (base >= 0 ? base : 0) + commitLength;',
    after: 'return (base >= 0 ? base : 0);'
  },
  releaseTap: {
    file: 'kanon/SpaceGesture.ets',
    before: 'const tap: boolean = !this.dragging && this.pressing;',
    after: 'const tap: boolean = this.pressing;'
  },
  staleMovement: {
    file: 'kanon/SpaceGesture.ets',
    before: 'if (generation === this.generation) { this.cancel(); }',
    after: 'this.cancel();'
  },
  preview: {
    file: 'kanon/ImeCoordinator.ets',
    before: 'const unchanged: boolean = this.previewShown && this.previewStart === start && this.previewText === text;',
    after: 'const unchanged: boolean = false;'
  }
};

// Change only the source passed to the test compiler. Never edit product files.
exports.mutate = (filename, source, name) => {
  const mutation = mutations[name];
  if (!mutation) { throw new Error(`Unknown mutation: ${name}`); }
  if (filename.replace(/\\/g, '/') !== mutation.file) { return source; }
  // Git checkouts can use CRLF on Windows. Match mutations against LF in memory.
  source = source.replace(/\r\n/g, '\n');
  if (source.split(mutation.before).length !== 2) {
    throw new Error(`Mutation must match exactly once: ${name}`);
  }
  return source.replace(mutation.before, mutation.after);
};
