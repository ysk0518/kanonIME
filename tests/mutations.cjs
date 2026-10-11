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
for (const [mutation, testId] of [['suggestion', 'R02'], ['modifier', 'R06'], ['preview', 'R08'],
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
  ['presentationDiagnosticSource', 'P27'], ['presentationTargetEpoch', 'P27'], ['regressionLayoutReset', 'P28']]) {
  const result = run({ ...env, KANON_TEST_MUTATION: mutation }, ['--test-name-pattern', `${testId}:`], testId);
  const matchingFailure = new RegExp(`not ok \\d+ - ${testId}:`).test(result.output);
  if (result.status === 0 || !matchingFailure || !result.output.includes('AssertionError')) {
    process.stderr.write(result.output);
    throw new Error(`Mutation was not detected by the expected assertion: ${mutation}`);
  }
  console.log(`${testId}: detected ${mutation}`);
}
