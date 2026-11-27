const { spawnSync } = require('node:child_process');
const { testArguments } = require('./support/test-arguments.cjs');

function run(env, args = [], group) {
  const result = spawnSync(process.execPath, testArguments(__dirname, args, group), {
    env, encoding: 'utf8'
  });
  if (result.error) { throw result.error; }
  return { status: result.status, output: result.stdout + result.stderr };
}

const env = { ...process.env };
delete env.KANON_TEST_MUTATION;
const baseline = run(env);
if (baseline.status !== 0) {
  process.stderr.write(baseline.output);
  throw new Error('Baseline tests must pass before checking mutations');
}
console.log('Baseline: passed');
for (const [mutation, testId, caseName] of [['suggestion', 'R02'], ['modifier', 'R06'], ['preview', 'R08'],
  ['anchor', 'R05'], ['releaseTap', 'R11'], ['staleMovement', 'R12'], ['candidatePhase', 'P02'],
  ['reviveHistory', 'P03'], ['displayLimit', 'P05'], ['previewGeneration', 'P06'],
  ['eventValidation', 'P07'], ['emptyMovement', 'P07'], ['queueEpoch', 'P08'], ['queueOrder', 'P08'],
  ['englishSelection', 'P09'], ['englishDelete', 'P09'], ['settingsGap', 'P10'], ['settingsPreservation', 'P10'],
  ['settingsHead', 'P11'], ['settingsAck', 'P11'], ['settingsFlush', 'P11'],
  ['requestReceiptRange', 'P12'], ['retryBudget', 'P12'], ['receiptSettlement', 'P12'],
  ['applicationRetry', 'P13'], ['applicationWait', 'P13'], ['localApplicationGeneration', 'P13'],
  ['previewCancellationFinish', 'P16'], ['previewCancellationEpoch', 'P16'],
  ['editorCompletionEpoch', 'P17'], ['editorDeadlineSettlement', 'P17'],
  ['editorUnresolvedWrite', 'P17'], ['editorAttachQueue', 'P17'],
  ['selectionEditingGuard', 'P18'], ['selectionCollapse', 'P18'],
  ['cursorSyncEpoch', 'P20'], ['cursorSyncOrigin', 'P20'], ['cursorSyncNotify', 'P20'],
  ['previewReceiptOrder', 'P20'], ['previewReceiptPosition', 'P20'], ['nativeCaretVerification', 'P20'],
  ['cursorSyncUnconfirmed', 'P21'], ['previewCaretConfirmation', 'P21'],
  ['previewCaretReadback', 'P22'], ['previewCaretCancel', 'P22'], ['previewCaretEpoch', 'P22'],
  ['directionMapping', 'P23'], ['eventPayloadOwnership', 'P23'], ['movementPayload', 'P23'],
  ['previewCaretBypass', 'P23'], ['directEnglishSuffix', 'P24'], ['directEnglishRevision', 'P24'],
  ['directEnglishCursorEpoch', 'P24'], ['directEnglishUndoSuccess', 'P24'], ['directEnglishEnter', 'P24'],
  ['directEnglishSeedEpoch', 'P24'], ['directEnglishCandidateReceipt', 'P24'],
  ['directEnglishSeedSelection', 'P24'], ['undoExplicitDelete', 'P25'], ['undoRestoreOrigin', 'P25'],
  ['undoTargetAfterDispatch', 'P25'], ['undoCommitLength', 'P25'], ['undoRefreshGuard', 'P25'],
  ['undoRefreshRelease', 'P25'], ['localLayoutFailure', 'P26'], ['localLayoutEpoch', 'P26'],
  ['localLayoutPublish', 'P26'], ['localCycleFlick', 'P26'], ['localPasteSubmit', 'P26'],
  ['localPasteFailure', 'P26'], ['localPasteEpoch', 'P26'], ['runtimePasswordPolicy', 'P27'],
  ['runtimeCursorEpoch', 'P27'], ['runtimeStoredConfirmation', 'P27'], ['runtimeLayoutHistory', 'P27'],
  ['presentationCandidateSource', 'P27'], ['presentationCandidateRevision', 'P27'],
  ['presentationDiagnosticSource', 'P27'], ['presentationTargetEpoch', 'P27'], ['regressionLayoutReset', 'P28'],
  ['queueEpoch', 'P29', 'R-01'],
  ['sessionEpochDuringAdmission', 'P29', 'R-01'],
  ['sessionObsoleteComposition', 'P29', 'R-02'],
  ['sessionCursorBypass', 'P29', 'R-03'],
  ['sessionCursorFailure', 'P29', 'R-03'],
  ['sessionExternalReadFailure', 'P29', 'R-04'],
  ['sessionPrepareUndo', 'P29', 'R-05'],
  ['sessionStaleUndoPublish', 'P29', 'R-06'],
  ['sessionDirectConvertSpace', 'P29', 'R-07'],
  ['sessionPastePrecommit', 'P29', 'R-08'],
  ['sessionHandledBackspace', 'P29', 'R-09'],
  ['sessionDirectCommands', 'P29', 'R-10'],
  ['sessionEnterAction', 'P29', 'R-11'],
  ['sessionExceptionPublish', 'P29', 'R-12'],
  ['sessionDiscardExternalHints', 'P29', 'reset:'],
  ['sessionAdmissionStop', 'P29', 'R-04'],
  ['panelAdjustmentCanvas', 'P31'], ['panelStyleRows', 'P31'], ['hardKeyShiftChord', 'P31'],
  ['hardKeyFunctionRelease', 'P31'],
  ['duplicateAppStorageKey', 'P32', 'AppStorage key values are unique'],
  ['missingStorageDecoratorKey', 'P32', 'storage decorator keys are defined in AppStorageKeys'],
  ['coreAppStorageDependency', 'P32', 'SDK-free kanon modules load without AppStorage'],
  ['inputBehaviorDecision', 'P34'], ['mozcBackspaceHighlight', 'P35'], ['revertConversionGuard', 'P35'],
  ['directEnglishRevertSelection', 'P36', 'direct English Delete'],
  ['graphemeRegionalPair', 'P37', 'regional indicators'], ['directDeleteGrapheme', 'P37', 'an editor change during the grapheme read'],
  ['englishDeleteGrapheme', 'P37', 'English composition Delete'],
  ['unknownCompositionStart', 'P38', 'unknown origin'], ['unknownCompositionRestoration', 'P38', 'partial commit'],
  ['japaneseUndoMatch', 'P40', 'a different committed string'],
  ['japaneseUndoOffset', 'P40', 'a nonadjacent deletion offset'],
  ['japaneseUndoWidth', 'P40', 'a Mozc range that spans fewer Harmony graphemes'],
  ['japaneseUndoEpoch', 'P40', 'an editor change during the final undo cursor check'],
  ['japaneseUndoOrigin', 'P40', 'undo places the restored preview at the commit start'],
  ['japaneseUndoMove', 'P40', 'arrow invalidates Japanese undo'],
  ['japaneseUndoSelection', 'P40', 'selection notification invalidates Japanese undo'],
  ['japaneseUndoAbsent', 'P40', 'Japanese undo without a commit'],
  ['flickUndoEnglish', 'P40', '↺ uses English completion undo'],
  ['flickModeConvert', 'P40', 'the 12-key 変換 and 候補 controls'],
  ['swappedNumberFlickDirections', 'P41', 'general number keys follow'],
  ['swappedSymbolKeys', 'P42', 'both symbol pages follow'],
  ['invertedUrlInputPattern', 'P42', 'only the IME URL input pattern'],
  ['toggleDoesNotWrap', 'P43', 'every 12-key cycle'],
  ['toggleRightMovesCursor', 'P43', 'Right ends the cycle without moving'],
  ['deleteAnyCandidateId', 'P44', 'no learned entry preserves conversion and selection'],
  ['refreshAfterNoLearnedEntry', 'P44', 'no learned entry preserves conversion and selection'],
  ['omitCandidateDeleteNotice', 'P44', 'deletion results appear as timed keyboard text'],
  ['qwertyEntersNumberMode', 'P45', 'QWERTY cycles between Japanese and English'],
  ['playKeySoundWhenOff', 'P46', 'off never calls playback'],
  ['duplicateRecentEmoji', 'P47', 'recents move to the front'],
  ['suggestRomanOnlyWord', 'P51', 'the first roman letters of a word are not suggested'],
  ['periodWithoutWord', 'P52', 'a word and one space end with a period on the second space'],
  ['noSentenceStart', 'P52', 'the shift keys follow sentence starts in English text fields'],
  ['settingsMenuThemeRoute', 'P55', 'the menu groups route'],
  ['settingsMenuLastLanguage', 'P55', 'language switches preserve'],
  ['settingsMenuResetHeight', 'P55', 'confirmed reset restores'],
  ['emojiDuringConversion', 'P53', 'converting, an interior caret and a nonmatching reading exclude emoji'],
  ['emojiAtInteriorCaret', 'P53', 'converting, an interior caret and a nonmatching reading exclude emoji'],
  ['duplicateEmojiSuggestion', 'P53', 'emoji follow the first Mozc candidate'],
  ['omitDeferredEmoji', 'P53', 'deferred suggest inserts emoji'],
  ['commitEmojiOnFailedReset', 'P53', 'failed reset leaves the emoji uncommitted'],
  ['forgetNextWord', 'P54', 'a selected candidate commits and shows Mozc next-word predictions'],
  ['keepNextWordAfterDelete', 'P54', 'deleting committed text drops the next-word predictions'],
  ['ignoreEmojiSuggestionsSetting', 'P56', 'disabling emoji'],
  ['ignoreAutoCapitalizeSetting', 'P56', 'disabling automatic capitals'],
  ['ignoreDoubleSpacePeriodSetting', 'P56', 'disabling double-space periods'],
  ['shortcutMovePastEnd', 'P57', 'shortcut arrows disable'],
  ['settingsHeightIgnoresSlider', 'P57', 'size slider writes'],
  ['themeDraftIgnoresHorizontalOffset', 'P57', 'theme drafts compare']]) {
  const label = caseName === undefined ? `${testId}:` : `${testId}: ${caseName}`;
  const result = run({ ...env, KANON_TEST_MUTATION: mutation }, ['--test-name-pattern', label], testId);
  const matchingFailure = new RegExp(`not ok \\d+ - ${label}`).test(result.output);
  if (result.status === 0 || !matchingFailure || !result.output.includes('AssertionError')) {
    process.stderr.write(result.output);
    throw new Error(`Mutation was not detected by the expected assertion: ${mutation}`);
  }
  console.log(`${testId}: detected ${mutation}`);
}
