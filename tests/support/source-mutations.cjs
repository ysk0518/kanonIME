const mutations = {
  gamingTapGap: {
    file: 'common/GamingEffectModel.ets',
    before: 'now - this.lastTap >= 2000',
    after: 'now - this.lastTap > 2000'
  },
  gamingResetLocks: {
    file: 'common/SettingsMenuModel.ets',
    before: 'gamingEffect: defaults.gamingEffect',
    after: 'gamingEffect: defaults.gamingEffect, gamingUnlocked: false'
  },
  gamingMenuWithoutUnlock: {
    file: 'common/SettingsMenuModel.ets',
    before: 'group.styleHeading && gamingUnlocked',
    after: 'group.styleHeading'
  },
  gamingRippleEvictsNewest: {
    file: 'common/GamingEffectModel.ets',
    before: 'this.rings.shift();',
    after: 'this.rings.pop();'
  },
  shortcutMovePastEnd: {
    file: 'common/ShortcutConfigValues.ets',
    before: 'next >= 0 && next < order.length;',
    after: 'next >= 0 && next <= order.length;'
  },
  settingsHeightIgnoresSlider: {
    file: 'common/SettingsMenuModel.ets',
    before: 'case SettingsNumber.Height: return { heightPercent: keyboardHeightPercent(value) };',
    after: 'case SettingsNumber.Height: return { heightPercent: keyboardHeightPercent(100) };'
  },
  themeDraftIgnoresHorizontalOffset: {
    file: 'common/BackgroundAppearance.ets',
    before: 'draft.zoom !== saved.zoom || draft.x !== saved.x || draft.y !== saved.y ||',
    after: 'draft.zoom !== saved.zoom || draft.y !== saved.y ||'
  },
  ignoreEmojiSuggestionsSetting: {
    file: 'kanon/MozcEngine.ets',
    before: ' &&\n      this.emojiSuggestionsEnabled()) {',
    after: ') {'
  },
  ignoreAutoCapitalizeSetting: {
    file: 'kanon/ImeRuntimeBindings.ets',
    before: '(this.port.readBoolean(KANON_AUTO_CAPITALIZE) ?? DEFAULT_AUTO_CAPITALIZE) &&\n      ',
    after: ''
  },
  ignoreDoubleSpacePeriodSetting: {
    file: 'kanon/ImeRuntimeBindings.ets',
    before: 'this.port.readBoolean(KANON_DOUBLE_SPACE_PERIOD) ?? DEFAULT_DOUBLE_SPACE_PERIOD',
    after: 'true'
  },
  settingsMenuThemeRoute: {
    file: 'common/SettingsMenuModel.ets',
    before: 'open(SettingsPageId.Theme), open(SettingsPageId.Size)',
    after: 'open(SettingsPageId.Layout), open(SettingsPageId.Size)'
  },
  settingsMenuLastLanguage: {
    file: 'common/SettingsMenuModel.ets',
    before: ' || (!enabled && languages.length === 1)',
    after: ''
  },
  settingsMenuResetHeight: {
    file: 'common/SettingsMenuModel.ets',
    before: 'heightPercent: defaults.heightPercent',
    after: 'heightPercent: undefined'
  },
  emojiDuringConversion: {
    file: 'kanon/MozcEngine.ets',
    before: "includeEmoji && this.phase === 'composing' && this.caretPosition(out) === out.preedit.length",
    after: 'includeEmoji && this.caretPosition(out) === out.preedit.length'
  },
  emojiAtInteriorCaret: {
    file: 'kanon/MozcEngine.ets',
    before: "includeEmoji && this.phase === 'composing' && this.caretPosition(out) === out.preedit.length",
    after: "includeEmoji && this.phase === 'composing'"
  },
  duplicateEmojiSuggestion: {
    file: 'kanon/MozcEngine.ets',
    before: 'if (!ordered.some((c: Cand): boolean => c.value === emoji)) {',
    after: 'if (true) {'
  },
  omitDeferredEmoji: {
    file: 'kanon/MozcEngine.ets',
    before: `if (out.preedit_len === 0) { this.phase = 'empty'; }
    this.revision++;
    return this.fromOut(sessionId, epoch, seq, out, []);`,
    after: `if (out.preedit_len === 0) { this.phase = 'empty'; }
    this.revision++;
    return this.fromOut(sessionId, epoch, seq, out, [], false);`
  },
  commitEmojiOnFailedReset: {
    file: 'kanon/MozcEngine.ets',
    before: 'if (emoji !== undefined && !parseOut(reset).ok) {',
    after: 'if (false) {'
  },
  forgetNextWord: {
    file: 'kanon/MozcEngine.ets',
    before: "    this.nextWord = true;\n",
    after: ''
  },
  keepNextWordAfterDelete: {
    file: 'kanon/ImeCoordinator.ets',
    before: "    this.candidateItems = [];\n    this.candidateCount = 0;\n  }\n\n  private async applyUpdate(",
    after: "  }\n\n  private async applyUpdate("
  },
  periodWithoutWord: {
    file: 'kanon/SentenceInput.ets',
    before: 'return WORD_END.test(before.slice(0, -1));',
    after: 'return true;'
  },
  noSentenceStart: {
    file: 'kanon/SentenceInput.ets',
    before: 'return /[.!?]',
    after: 'return false && /[.!?]'
  },
  suggestRomanOnlyWord: {
    file: 'kanon/MozcEngine.ets',
    before: 'endsWithRomanKey(out.preedit, romanKey) && hasKana(out.preedit)',
    after: 'endsWithRomanKey(out.preedit, romanKey)'
  },
  duplicateRecentEmoji: {
    file: 'common/EmojiHistory.ets',
    before: 'recent.filter((item: string) => item !== value)',
    after: 'recent'
  },
  playKeySoundWhenOff: {
    file: 'common/KeyboardSound.ets',
    before: 'if (level === 0) { return; }',
    after: ''
  },
  qwertyEntersNumberMode: {
    file: 'model/KeyboardModes.ets',
    before: "if (flick && mode === 'EN') { return 'NUMBER'; }",
    after: "if (mode === 'EN') { return 'NUMBER'; }"
  },
  deleteAnyCandidateId: {
    file: 'kanon/MozcEngine.ets',
    before: 'if (id !== 0 && target?.deletable !== true) {',
    after: 'if (false) {'
  },
  refreshAfterNoLearnedEntry: {
    file: 'kanon/MozcEngine.ets',
    before: `const update: EngineUpdate = this.errUpdate(sessionId, epoch, seq, true);
        update.candidateNotLearned = true;
        return update;`,
    after: 'return this.acceptComposingOutput(sessionId, epoch, seq, this.lastOut);'
  },
  omitCandidateDeleteNotice: {
    file: 'components/CandidateBar.ets',
    before: 'if (request === this.deleteNoticeRequest) { this.showDeleteNotice(result); }',
    after: ''
  },
  toggleDoesNotWrap: {
    file: 'kanon/ToggleInput.ets',
    before: '(this.index + offset + this.cycle.length) % this.cycle.length',
    after: 'offset > 0 ? Math.min(this.index + offset, this.cycle.length - 1) : (this.index + offset + this.cycle.length) % this.cycle.length'
  },
  toggleRightMovesCursor: {
    file: 'kanon/ImeSession.ets',
    before: "return active ? this.coord.getSnapshot() : this.routeRequest({ kind: 'move', direction: 'right' }, epoch);",
    after: "return this.routeRequest({ kind: 'move', direction: 'right' }, epoch);"
  },
  swappedSymbolKeys: {
    file: 'model/KeyboardKeyData.ets',
    before: "['+', '×', '÷',",
    after: "['+', '÷', '×',"
  },
  invertedUrlInputPattern: {
    file: 'model/KeyboardKeyLabels.ets',
    before: 'return inputPattern === TEXT_INPUT_TYPE_URL;',
    after: 'return inputPattern !== TEXT_INPUT_TYPE_URL;'
  },
  swappedNumberFlickDirections: {
    file: 'model/NumberFlickData.ets',
    before: "['3', '+', '×', '÷', '-']",
    after: "['3', '÷', '×', '+', '-']"
  },
  japaneseUndoMatch: {
    file: 'kanon/ImeCoordinator.ets',
    before: 'cursor !== commit.cursor || !before.endsWith(commit.text) ||',
    after: 'cursor !== commit.cursor ||'
  },
  japaneseUndoOffset: {
    file: 'kanon/ImeCoordinator.ets',
    before: 'length <= 0 || update.deletionOffset !== -length ||',
    after: 'length <= 0 ||'
  },
  japaneseUndoWidth: {
    file: 'kanon/ImeCoordinator.ets',
    before: ' || !this.matchesDeletionWidth(before, commit.text, length)',
    after: ''
  },
  japaneseUndoEpoch: {
    file: 'kanon/ImeCoordinator.ets',
    before: "const cursor: number = await this.editor.queryCursor();\n    if (epoch !== this.editor.getEpoch()) { this.lastError = 'stale-epoch'; return false; }\n    if (this.lastJapaneseCommit",
    after: "const cursor: number = await this.editor.queryCursor();\n    if (this.lastJapaneseCommit"
  },
  japaneseUndoOrigin: {
    file: 'kanon/ImeSession.ets',
    before: 'if (origin >= 0) { this.preview.restore(origin); }',
    after: 'if (origin < 0) { this.preview.restore(origin); }'
  },
  japaneseUndoMove: {
    file: 'kanon/ImeCoordinator.ets',
    before: "if (event.kind !== 'undo' && event.kind !== 'deleteCandidate') { this.forgetJapaneseCommit(); }",
    after: "if (event.kind !== 'undo' && event.kind !== 'deleteCandidate' && event.kind !== 'move') { this.forgetJapaneseCommit(); }"
  },
  japaneseUndoSelection: {
    file: 'kanon/ImeCoordinator.ets',
    before: 'if (commit !== undefined && (begin !== commit.cursor || end !== commit.cursor)) {',
    after: 'if (false) {'
  },
  japaneseUndoAbsent: {
    file: 'kanon/ImeCoordinator.ets',
    before: "if (event.kind === 'undo' && (this.mode !== 'JP' || this.lastJapaneseCommit === undefined)) { return; }",
    after: "if (event.kind === 'undo' && this.mode !== 'JP') { return; }"
  },
  flickUndoEnglish: {
    file: 'kanon/ImeSession.ets',
    before: "if (request.kind === 'undo' && this.mode === 'EN') {",
    after: "if (false) {"
  },
  flickModeConvert: {
    file: 'components/ModeCycleItem.ets',
    before: 'if (this.converts()) { await kanonIme.keySpace(); return; }',
    after: 'if (this.converts()) { return; }'
  },
  unknownCompositionStart: {
    file: 'kanon/CompositionPosition.ets',
    before: 'return base >= 0 ? base + commitLength : -1;',
    after: 'return (base >= 0 ? base : 0) + commitLength;'
  },
  unknownCompositionRestoration: {
    file: 'kanon/CompositionPreview.ets',
    before: 'if (start < 0) { return false; }',
    after: 'if (false) { return false; }'
  },
  graphemeRegionalPair: {
    file: 'kanon/GraphemeDelete.ets',
    before: 'if (isRegionalIndicator(text.codePointAt(previous) ?? 0)) { start = previous; }',
    after: 'if (false) { start = previous; }'
  },
  directDeleteGrapheme: {
    file: 'kanon/ImeCoordinator.ets',
    before: "if (epoch !== this.editor.getEpoch()) { return { ok: false, code: -4 }; }\n      if (before !== undefined",
    after: "if (before !== undefined"
  },
  englishDeleteGrapheme: {
    file: 'kanon/EnglishEngine.ets',
    before: 'const width: number = lastGraphemeLength(this.buffer);',
    after: 'const width: number = 1;'
  },
  directEnglishRevertSelection: {
    file: 'kanon/DirectEnglishInput.ets',
    before: 'if (this.prediction.getSelectedIndex() < 0) { return false; }',
    after: 'return false;'
  },
  mozcBackspaceHighlight: {
    file: 'kanon/MozcEngine.ets',
    before: "return this.phase === 'converting' ? this.selIdx : -1;",
    after: 'return this.selIdx;'
  },
  revertConversionGuard: {
    file: 'kanon/ImeSession.ets',
    before: "if (snapshot.state === 'JP_CONVERTING' || snapshot.state === 'EN_CONVERTING') {",
    after: 'if (true) {'
  },
  inputBehaviorDecision: {
    file: 'docs/INPUT_BEHAVIOR.md',
    before: '| Q1 | 合意 |',
    after: '| Q1 | 提案 |'
  },
  duplicateAppStorageKey: {
    file: 'common/AppStorageKeys.ets',
    before: "export const KANON_LENS2: string = 'kanonLens2';",
    after: "export const KANON_LENS2: string = 'kanonLens';"
  },
  missingStorageDecoratorKey: {
    file: 'common/AppStorageKeys.ets',
    before: "export const SUBMENU_TYPE: string = 'submenuType';",
    after: "export const SUBMENU_TYPE: string = 'subMenuType';"
  },
  coreAppStorageDependency: {
    file: 'kanon/ImeViewPublisher.ets',
    before: 'this.port.number(KANON_TICK, view.tick);',
    after: 'AppStorage.setOrCreate(KANON_TICK, view.tick);'
  },
  sessionEpochDuringAdmission: {
    file: 'kanon/ImeSession.ets',
    before: "if (requestEpoch !== this.ports.editor.getEpoch()) { return this.stopAdmission(); }\n    if (!await this.synchronizeExternalEditor())",
    after: "if (!await this.synchronizeExternalEditor())"
  },
  sessionObsoleteComposition: {
    file: 'kanon/ImeSession.ets',
    before: "if (generation !== this.compositionGeneration &&",
    after: "if (false &&"
  },
  sessionCursorBypass: {
    file: 'kanon/ImeSession.ets',
    before: "if (request.kind !== 'cancel' && request.kind !== 'cycle' && request.kind !== 'config' &&",
    after: "if ("
  },
  sessionCursorFailure: {
    file: 'kanon/ImeSession.ets',
    before: "!await this.synchronizeCompositionCursor()) { return this.stopAdmission(); }",
    after: "!await this.synchronizeCompositionCursor()) { /* Continue after sync failure. */ }"
  },
  sessionExternalReadFailure: {
    file: 'kanon/ImeSession.ets',
    before: "if (result === 'failed' || result === 'stale') { return false; }\n    if (result !== 'empty')",
    after: "if (result !== 'empty')"
  },
  sessionPrepareUndo: {
    file: 'kanon/ImeSession.ets',
    before: "if (request.kind === 'prepare') {\n      return this.localRequests.handle(request, requestEpoch);",
    after: "if (request.kind === 'prepare') {\n      this.ports.prediction.dropUndo();\n      return this.localRequests.handle(request, requestEpoch);"
  },
  sessionStaleUndoPublish: {
    file: 'kanon/ImeSession.ets',
    before: "if (result !== 'stale') { this.publish(snapshot, requestEpoch); }",
    after: "this.publish(snapshot, requestEpoch);"
  },
  sessionDirectConvertSpace: {
    file: 'kanon/ImeSession.ets',
    before: "if (result === 'space') { return await this.postSerial({ kind: 'text', text: ' ' }); }",
    after: "if (result === 'space') { return this.coord.getSnapshot(); }"
  },
  sessionPastePrecommit: {
    file: 'kanon/ImeSession.ets',
    before: "if (kind === 'paste' && !await this.localRequests.beforePaste(requestEpoch)) {\n      return this.coord.getSnapshot();",
    after: "if (kind === 'paste' && !await this.localRequests.beforePaste(requestEpoch)) {\n      // Incorrectly continue to Coordinator."
  },
  sessionHandledBackspace: {
    file: 'kanon/ImeSession.ets',
    before: "if (result === 'handled') {\n        const snapshot: ImeSnapshot = this.coord.getSnapshot();",
    after: "if (false) {\n        const snapshot: ImeSnapshot = this.coord.getSnapshot();"
  },
  sessionDirectCommands: {
    file: 'kanon/ImeSession.ets',
    before: "if (this.isDirectEnglish() && (kind === 'select' || kind === 'cancel' || kind === 'enter'))",
    after: "if (false)"
  },
  sessionEnterAction: {
    file: 'kanon/ImeSession.ets',
    before: " && s.lastError === 'empty-submit') {\n      await this.sendEnterAction(epoch);",
    after: ") {\n      await this.sendEnterAction(epoch);"
  },
  sessionExceptionPublish: {
    file: 'kanon/ImeSession.ets',
    before: "} catch (e) {\n      this.toggleRun = undefined;\n      const s: ImeSnapshot = this.coord.getSnapshot();\n      this.publish(s, requestEpoch);",
    after: "} catch (e) {\n      this.toggleRun = undefined;\n      const s: ImeSnapshot = this.coord.getSnapshot();"
  },
  sessionDiscardExternalHints: {
    file: 'kanon/ImeSession.ets',
    before: "if (reason === 'discard') { this.editorSync.reset(); }",
    after: "// Incorrectly keep external editor hints after discard."
  },
  sessionAdmissionStop: {
    file: 'kanon/ImeSession.ets',
    before: "if (admission.kind === 'stop') { this.toggleRun = undefined; return admission.snapshot; }",
    after: "if (admission.kind === 'stop') { this.toggleRun = undefined; }"
  },
  panelAdjustmentCanvas: {
    file: 'common/KeyboardPanelGeometry.ets',
    before: 'const panelPercent: number = adjusting ? MAX_KEYBOARD_HEIGHT_PERCENT : percent;',
    after: 'const panelPercent: number = percent;'
  },
  panelStyleRows: {
    file: 'common/KeyboardPanelGeometry.ets',
    before: 'const rows: number = initialHeightVp - twoRows >= 160 ? settings.candidateRows : 1;',
    after: 'const rows: number = settings.candidateRows;'
  },
  hardKeyShiftChord: {
    file: 'model/HardKeyInput.ets',
    before: 'if (shiftHeld && keyCodes.length === 2 && !isKeyCodeAZ(keyCode, codes)) {',
    after: 'if (false) {'
  },
  hardKeyFunctionRelease: {
    file: 'model/HardKeyInput.ets',
    before: 'const handled: boolean = releasedFunctionKey || !state.specialKeyPress;',
    after: 'const handled: boolean = !state.specialKeyPress;'
  },
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
    before: 'if (epoch === this.port.getEpoch()) { this.port.number(KANON_CURSOR, position); }',
    after: 'this.port.number(KANON_CURSOR, position);'
  },
  runtimeStoredConfirmation: {
    file: 'kanon/ImeRuntimeBindings.ets',
    before: 'return this.port.readString(KANON_LAYOUT_ORDER) === order;',
    after: 'return this.configuredOrder() === order;'
  },
  runtimeLayoutHistory: {
    file: 'kanon/ImeRuntimeBindings.ets',
    before: 'this.port.string(KANON_LAST_LAYOUT, layout);',
    after: "this.port.string(KANON_LAST_LAYOUT, 'jp_flick');"
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
    before: 'i < source.candidates.length && i < MAX_DISPLAY_CANDIDATES',
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
    before: 'return base >= 0 ? base + commitLength : -1;',
    after: 'return base >= 0 ? base : -1;'
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
