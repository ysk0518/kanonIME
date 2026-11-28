const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { FakeEditor, deferred, update } = require('../support/fakes.cjs');
const { drawPachinko, drawPachinkoColor, enqueuePachinko, consumePachinkoHold, pachinkoIdleRemaining, pachinkoStops,
  adjacentPachinkoDigit, buildPachinkoScript, drawPachinkoWeight, pachinkoRushAfter, pachinkoReplayHolds,
  parsePachinkoReplay, PACHINKO_TABLES: Tables, PACHINKO_COLORS: Colors, PachinkoColor: Color, PachinkoResult: Result,
  PachinkoReplay: Replay, PachinkoStageKind: Stage, ImeCommitNotifications, imeCommitNotifications } =
  require('../../entry/src/main/ets/common/PachinkoModel.ets');
const { GAMING_EFFECTS, gamingSpeedEnabled } = require('../../entry/src/main/ets/common/GamingEffectModel.ets');
const { KeyboardSettingsRecord, KeyboardSettingsSnapshot, applySettingsPatch, decodeSettingsRecord,
  mergeSettingsPatch, validSettingsPatch } = require('../../entry/src/main/ets/common/KeyboardSettingsModel.ets');
const { settingsGamingSummary } = require('../../entry/src/main/ets/common/SettingsMenuModel.ets');
const { ImeCoordinator } = require('../../entry/src/main/ets/kanon/ImeCoordinator.ets');
const { EnglishEngine } = require('../../entry/src/main/ets/kanon/EnglishEngine.ets');
const { EnglishPrediction } = require('../../entry/src/main/ets/kanon/EnglishPrediction.ets');

test('P58c: one injected roll gives jackpot priority and exact probability boundaries', () => {
  let calls = 0;
  assert.equal(drawPachinko(() => { calls++; return 0; }), Result.Jackpot);
  assert.equal(calls, 1);
  const epsilon = Number.EPSILON;
  assert.equal(drawPachinko(() => 1 / 64 - epsilon), Result.Jackpot);
  assert.equal(drawPachinko(() => 1 / 64), Result.Reach);
  assert.equal(drawPachinko(() => 9 / 64 - epsilon), Result.Reach);
  assert.equal(drawPachinko(() => 9 / 64), Result.Miss);
  const outcomes = Array.from({ length: 64 }, (_, i) => drawPachinko(() => i / 64));
  assert.equal(outcomes.filter(outcome => outcome === Result.Reach).length, 8);
  assert.equal(outcomes.filter(outcome => outcome === Result.Jackpot).length, 1);
});

test('P58d: each of the first four commits immediately draws a hold and the fifth is discarded', () => {
  const inputs = [0, 0.8, 0.59, 6 / 9, 0.10, 0.80, 0.60, 0.50, 0.10, 0, 0.95, 0, 1 / 9];
  const expectedCalls = [4, 7, 9, 13];
  let calls = 0;
  const random = () => inputs[calls++];
  let holds = Object.freeze([]);
  for (let i = 1; i <= 4; i++) {
    holds = enqueuePachinko(Object.freeze(holds), random);
    assert.equal(holds.length, i);
    assert.equal(calls, expectedCalls[i - 1]);
  }
  assert.equal(enqueuePachinko(holds, random), holds);
  assert.equal(calls, 13);
  assert.deepEqual(holds, [
    { result: Result.Jackpot, trueColor: Color.Gold, displayColor: Color.Gold, digit: 7 },
    { result: Result.Reach, trueColor: Color.Green, displayColor: Color.White, digit: 0 },
    { result: Result.Miss, trueColor: Color.White, displayColor: Color.White, digit: 0 },
    { result: Result.Jackpot, trueColor: Color.Rainbow, displayColor: Color.Rainbow, digit: 2 }
  ]);
});

test('P58d: hold colors use the result-specific probability table', () => {
  const cases = [
    [Result.Miss, [0.92, 0.99]],
    [Result.Reach, [0.54, 0.79, 0.94, 0.99]],
    [Result.Jackpot, [0.25, 0.40, 0.55, 0.80, 0.95]]
  ];
  for (const [result, thresholds] of cases) {
    assert.equal(drawPachinkoColor(result, () => 0), Color.White);
    thresholds.forEach((threshold, index) => {
      assert.equal(drawPachinkoColor(result, () => threshold - Number.EPSILON), Colors[index]);
      assert.equal(drawPachinkoColor(result, () => threshold), Colors[index + 1]);
    });
    assert.equal(drawPachinkoColor(result, () => 1 - Number.EPSILON), Colors[thresholds.length]);
  }
});

test('P58d: consumption waits 800 ms from the last activity and uses FIFO order', () => {
  let holds = [];
  for (const draw of [0.1, 0.5, 0]) {
    holds = enqueuePachinko(holds, () => draw);
  }
  assert.equal(pachinkoIdleRemaining(1799, 1000), 1);
  assert.equal(consumePachinkoHold(holds, 1799, 1000), undefined);
  assert.equal(pachinkoIdleRemaining(1800, 1100), 100);
  assert.equal(consumePachinkoHold(holds, 1800, 1100), undefined);
  assert.equal(consumePachinkoHold(holds, 1800, 1000).hold, holds[0]);
  for (const result of [Result.Reach, Result.Miss, Result.Jackpot]) {
    const consumed = consumePachinkoHold(Object.freeze(holds), 1900, 1100);
    assert.equal(consumed.hold.result, result);
    assert.deepEqual(consumed.remaining, holds.slice(1));
    holds = consumed.remaining;
  }
  assert.equal(consumePachinkoHold(holds, 2500, 1100), undefined);
});

test('P58d: reel stops give distinct misses adjacent near misses and uniform jackpots', () => {
  for (let left = 0; left < 9; left++) {
    const reach = pachinkoStops(Result.Reach, rolls([left / 9, 0]));
    assert.equal(reach.left, left + 1);
    assert.equal(reach.right, reach.left);
    assert.ok(reach.middle >= 1 && reach.middle <= 9);
    assert.equal(reach.middle, (left + 8) % 9 + 1);
    assert.deepEqual(pachinkoStops(Result.Jackpot, () => left / 9),
      { left: left + 1, middle: left + 1, right: left + 1 });
    for (let right = 0; right < 8; right++) {
      for (let middle = 0; middle < 7; middle++) {
        const rolls = [left / 9, right / 8, middle / 7];
        const stops = pachinkoStops(Result.Miss, () => rolls.shift());
        const digits = [stops.left, stops.middle, stops.right];
        assert.equal(new Set(digits).size, 3);
        assert.ok(digits.every(digit => digit >= 1 && digit <= 9));
      }
    }
  }
});

function rolls(values) {
  let index = 0;
  return () => {
    assert.ok(index < values.length, 'unexpected random draw');
    return values[index++];
  };
}

function fixedHold(result, digit = 0, trueColor = Color.White, displayColor = trueColor) {
  return Object.freeze({ result, digit, trueColor, displayColor });
}

test('P58e: probability tables sum to 100 percent and injected rolls follow every boundary', () => {
  assert.deepEqual(Tables.outcome, [[1, 8, 55], [2, 3, 7]]);
  assert.deepEqual(Tables.reach, [[], [70, 25, 5, 0, 0], [8, 30, 50, 4, 8]]);
  assert.deepEqual(Tables.step, [[90, 7, 3, 0, 0, 0], [40, 20, 20, 15, 5, 0], [15, 5, 10, 25, 30, 15]]);
  assert.deepEqual(Tables.pseudo, [[97, 3, 0], [70, 25, 5], [30, 35, 35]]);
  assert.deepEqual(Tables.cutIn, [[], [50, 35, 15, 0, 0], [5, 15, 45, 30, 5]]);
  assert.deepEqual(Tables.reveal, [60, 40]);
  for (const row of [...Tables.color, ...Tables.reach, ...Tables.step, ...Tables.pseudo, ...Tables.cutIn, Tables.reveal]) {
    if (row.length > 0) assert.equal(row.reduce((sum, weight) => sum + weight, 0), 100);
  }
  for (const row of [...Tables.outcome, ...Tables.color, ...Tables.reach, ...Tables.step,
    ...Tables.pseudo, ...Tables.cutIn, Tables.reveal]) {
    const total = row.reduce((sum, weight) => sum + weight, 0);
    if (!total) continue;
    let boundary = 0;
    for (const [index, weight] of row.entries()) {
      if (!weight) continue;
      assert.equal(drawPachinkoWeight(row, rolls([boundary / total])), index);
      boundary += weight;
      assert.equal(drawPachinkoWeight(row, rolls([boundary / total - Number.EPSILON])), index);
    }
  }
  assert.equal(drawPachinko(rolls([1 / 6 - Number.EPSILON]), 8), Result.Jackpot);
  assert.equal(drawPachinko(rolls([1 / 6]), 8), Result.Reach);
  assert.equal(drawPachinko(rolls([5 / 12 - Number.EPSILON]), 8), Result.Reach);
  assert.equal(drawPachinko(rolls([5 / 12]), 8), Result.Miss);
});

test('P58e: normal reach and hold confidence agree with the documented estimates', () => {
  const [jackpot, reach, miss] = Tables.outcome[0];
  const confidence = (table, index) => {
    const wins = jackpot * table[Result.Jackpot][index];
    return 100 * wins / (wins + reach * table[Result.Reach][index] + miss * (table[Result.Miss][index] ?? 0));
  };
  assert.deepEqual([0, 1, 2].map(index => Math.round(confidence(Tables.reach, index))), [1, 13, 56]);
  assert.deepEqual([3, 4, 5].map(index => Math.round(confidence(Tables.color, index))), [38, 65, 100]);
  assert.equal(Math.round(100 * (1 - (5 / 6) ** 8)), 77);
});

test('P58e: RUSH enters on odd jackpots expires after eight misses and resets on any win', () => {
  assert.equal(pachinkoRushAfter(0, Result.Jackpot, 2), 0);
  let remaining = pachinkoRushAfter(0, Result.Jackpot, 3);
  assert.equal(remaining, 8);
  for (let spin = 1; spin <= 8; spin++) {
    remaining = pachinkoRushAfter(remaining, spin % 2 ? Result.Miss : Result.Reach, 7);
    assert.equal(remaining, 8 - spin);
  }
  assert.equal(pachinkoRushAfter(0, Result.Reach, 7), 0);
  assert.equal(pachinkoRushAfter(1, Result.Jackpot, 8), 8);
  assert.equal(pachinkoRushAfter(4, Result.Jackpot, 7), 8);
  const queued = enqueuePachinko([], () => 0.1);
  assert.equal(queued[0].result, Result.Reach);
  assert.equal(buildPachinkoScript(queued[0], 8, 1, () => 0).result, Result.Reach);
  assert.equal(enqueuePachinko(queued, () => 0.1, 8)[1].result, Result.Jackpot);
});

test('P58e: miss timelines shorten with three holds and use the RUSH length during ST', () => {
  for (const [remaining, holdCount, duration] of [[0, 1, 1200], [0, 2, 1200], [0, 3, 600], [0, 4, 600],
    [1, 1, 800], [8, 4, 800]]) {
    const script = buildPachinkoScript(fixedHold(Result.Miss), remaining, holdCount, rolls([0, 0, 0, 0, 0]));
    assert.equal(script.duration, duration);
    assert.deepEqual(script.stages.map(phase => phase.kind), [Stage.Spin, Stage.Miss]);
    assert.equal(script.stages[0].duration, 400);
    assert.ok(script.leftStop < script.rightStop && script.rightStop < script.middleStop && script.middleStop < duration);
  }
  const notices = buildPachinkoScript(fixedHold(Result.Miss), 0, 3, rolls([0, 0, 0, 0.99, 0.99]));
  assert.equal(notices.duration, 600 + 3 * 300);
});

test('P58e: hold changes reveal a hidden color first without rerolling or mutating the hold', () => {
  const visible = enqueuePachinko([], rolls([0, 0.99, 0.60 - Number.EPSILON, 0]))[0];
  const hidden = enqueuePachinko([], rolls([0, 0.99, 0.60, 0]))[0];
  assert.equal(visible.displayColor, Color.Rainbow);
  assert.equal(hidden.displayColor, Color.White);
  assert.equal(hidden.trueColor, Color.Rainbow);
  const hold = Object.freeze(hidden);
  const script = buildPachinkoScript(hold, 0, 1, rolls([0, 0, 0]));
  assert.deepEqual(script.stages[0], { kind: Stage.Reveal, start: 0, duration: 300, level: 0, color: Color.Rainbow });
  assert.equal(script.stages[1].kind, Stage.Spin);
  assert.equal(hold.displayColor, Color.White);
  assert.deepEqual(script.stops, { left: 1, middle: 1, right: 1 });
  assert.equal(buildPachinkoScript(visible, 0, 1, rolls([0, 0, 0])).stages[0].kind, Stage.Spin);
});

test('P58e: near misses wrap both directions and full rotation and revival require a jackpot', () => {
  assert.equal(adjacentPachinkoDigit(9, () => 0.5), 1);
  assert.equal(adjacentPachinkoDigit(1, () => 0.49), 9);
  const nearMiss = buildPachinkoScript(fixedHold(Result.Reach), 0, 1, rolls([8 / 9, 0.5, 0, 0, 0]));
  assert.deepEqual(nearMiss.stops, { left: 9, middle: 1, right: 9 });
  for (let roll = 0; roll < 100; roll++) {
    const script = buildPachinkoScript(fixedHold(Result.Reach), 0, 1, () => roll / 100);
    assert.ok(!script.stages.some(phase => [Stage.FullRotation, Stage.Revival, Stage.Jackpot].includes(phase.kind)));
  }
  const full = buildPachinkoScript(fixedHold(Result.Jackpot, 7), 0, 1, rolls([0, 0, 0.88]));
  assert.deepEqual(full.stages.map(phase => phase.kind), [Stage.Spin, Stage.Tenpai, Stage.FullRotation, Stage.Jackpot]);
  assert.equal(full.stages[2].duration, 3000);
  const revived = buildPachinkoScript(fixedHold(Result.Jackpot, 9), 0, 1, rolls([0, 0, 0.92, 0.5]));
  assert.deepEqual(revived.stages.map(phase => phase.kind), [Stage.Spin, Stage.Tenpai, Stage.Normal, Stage.Revival, Stage.Jackpot]);
  assert.equal(revived.stages[2].duration, 1500);
  assert.equal(revived.stages[3].duration, 1500);
  assert.equal(revived.revivalDigit, 1);
  assert.equal(revived.stops.middle, 9);
});

test('P58e: notices advance through every step and pseudo count on an ordered timeline', () => {
  const script = buildPachinkoScript(fixedHold(Result.Jackpot, 7), 0, 1, rolls([0.99, 0.99, 0.5, 0.95]));
  const stages = script.stages;
  assert.deepEqual(stages.filter(stage => stage.kind === Stage.Step).map(stage => stage.level), [1, 2, 3, 4, 5]);
  assert.deepEqual(stages.filter(stage => stage.kind === Stage.Pseudo).map(stage => stage.level), [2, 3]);
  assert.deepEqual(stages.slice(-5).map(stage => stage.kind), [Stage.Tenpai, Stage.SPSP, Stage.CutIn, Stage.Push, Stage.Jackpot]);
  assert.equal(stages.at(-3).color, Color.Rainbow);
  assert.deepEqual(stages.slice(-5).map(stage => stage.duration), [500, 3600, 450, 450, 2000]);
  let end = 0;
  for (const stage of stages) {
    assert.equal(stage.start, end);
    assert.ok(stage.duration > 0);
    if (stage.kind === Stage.Step || stage.kind === Stage.Pseudo) assert.equal(stage.duration, 300);
    end += stage.duration;
  }
  assert.equal(end, script.duration);
  const sp = buildPachinkoScript(fixedHold(Result.Reach), 0, 1, rolls([0, 0, 0, 0, 0.7, 0.5]));
  assert.deepEqual(sp.stages.map(stage => [stage.kind, stage.duration]),
    [[Stage.Spin, 400], [Stage.Tenpai, 500], [Stage.SP, 2550], [Stage.CutIn, 450], [Stage.Result, 600]]);
  assert.equal(sp.stages.at(-2).color, Color.Green);
  assert.ok(sp.middleStop <= sp.duration - 600, 'the near miss stays on screen');
});

test('P58e: all seven debug requests prepare their selected preview', () => {
  const replays = [[Replay.Normal, Stage.Normal], [Replay.SP, Stage.SP], [Replay.SPSP, Stage.SPSP],
    [Replay.FullRotation, Stage.FullRotation], [Replay.Revival, Stage.Revival], [Replay.Rush, Stage.Jackpot]];
  for (const [replay, expected] of replays) {
    assert.equal(parsePachinkoReplay(replay), replay);
    const holds = pachinkoReplayHolds(replay);
    assert.equal(holds.length, 1);
    const script = buildPachinkoScript(holds[0], 0, 1, () => 0, replay);
    assert.ok(script.stages.some(stage => stage.kind === expected));
    if (replay === Replay.Rush) assert.equal(pachinkoRushAfter(0, script.result, script.stops.middle), 8);
  }
  assert.equal(parsePachinkoReplay(Replay.FourHolds), Replay.FourHolds);
  assert.equal(parsePachinkoReplay('unknown'), undefined);
  const holds = pachinkoReplayHolds(Replay.FourHolds);
  assert.equal(holds.length, 4);
  assert.deepEqual(holds.map(hold => hold.trueColor), [Color.White, Color.Blue, Color.Red, Color.Rainbow]);
});

test('P58c: commit signal delivers only to the current listener and isolates listener failures', () => {
  const signal = new ImeCommitNotifications();
  const notices = [];
  const previous = () => notices.push('old');
  const current = (...args) => notices.push(args);
  signal.listen(previous);
  signal.listen(current);
  signal.unlisten(previous);
  assert.equal(signal.emit(), undefined);
  signal.unlisten(current);
  signal.emit();
  assert.deepEqual(notices, [[]]);
  signal.listen(() => { throw new Error('visual feedback failure'); });
  assert.doesNotThrow(() => signal.emit());
});

test('P58c: Japanese notifications follow successful nonempty writes exactly once', async () => {
  const editor = new FakeEditor();
  const coordinator = new ImeCoordinator(editor);
  const notices = [];
  const listen = (...args) => notices.push({ args, text: editor.text });
  const inserted = deferred();
  const started = deferred();
  const originalInsert = editor.insert.bind(editor);
  editor.insert = async text => {
    if (text === '候補') {
      started.resolve();
      await inserted.promise;
    }
    return originalInsert(text);
  };
  coordinator.setEngine({ dispatch: (s, e, n, event) => {
    if (event.kind === 'kana') { return update(s, e, n, { preeditLen: 2 }); }
    const effects = event.kind === 'select' ? [{ effectId: 'candidate', text: '候補' }] :
      [{ effectId: 'empty', text: '' }, { effectId: 'submit', text: '確定' }];
    return update(s, e, n, { effects });
  } });
  const select = () => coordinator.postEvent({
    kind: 'select', candidateId: 1, expectedRevision: coordinator.getSnapshot().revision
  });
  imeCommitNotifications.listen(listen);
  try {
    await coordinator.postEvent({ kind: 'kana', text: 'こうほ' });
    assert.deepEqual(notices, []);
    const first = select();
    assert.equal(await Promise.race([started.promise.then(() => 'writing'), first.then(() => 'finished')]), 'writing');
    assert.deepEqual(notices, []);
    inserted.resolve();
    await first;
    await select();
    await coordinator.postEvent({ kind: 'kana', text: 'かくてい' });
    await coordinator.postEvent({ kind: 'enter' });
    assert.deepEqual(notices, [{ args: [], text: '候補' }, { args: [], text: '候補確定' }]);
    editor.failInsert = true;
    coordinator.setEngine({ dispatch: (s, e, n) => update(s, e, n, {
      effects: [{ effectId: 'failed', text: '失敗' }]
    }) });
    await select();
    assert.equal(coordinator.getSnapshot().lastError, 'commit-fail');
    assert.equal(notices.length, 2);
  } finally {
    imeCommitNotifications.unlisten(listen);
  }
});

test('P58c: English space, Enter and direct typing notify on success and skip stale writes', async () => {
  const editor = new FakeEditor();
  const coordinator = new ImeCoordinator(editor);
  const prediction = new EnglishPrediction({ undoChanged() {}, cleared() {}, selectionAbandoned() {} });
  coordinator.setEnglishEngine(new EnglishEngine(prediction));
  await coordinator.loadPreviewSupport();
  await coordinator.postEvent({ kind: 'mode', text: 'EN' });
  const notices = [];
  const listen = () => notices.push(editor.text);
  imeCommitNotifications.listen(listen);
  try {
    await coordinator.postEvent({ kind: 'text', text: 'zzzz' });
    assert.deepEqual(notices, []);
    await coordinator.postEvent({ kind: 'convert' });
    await coordinator.postEvent({ kind: 'text', text: 'word' });
    await coordinator.postEvent({ kind: 'enter' });
    coordinator.setPreviewUnsupported();
    await coordinator.postEvent({ kind: 'text', text: '!' });
    assert.deepEqual(notices, ['zzzz ', 'zzzz word', 'zzzz word!']);
    editor.insert = async () => { editor.epoch++; return { ok: true, code: 0 }; };
    await coordinator.postEvent({ kind: 'text', text: 'stale' });
    assert.equal(notices.length, 3);
  } finally {
    imeCommitNotifications.unlisten(listen);
  }
});

test('P58c: settings accept pachinko in order and normalize unknown values to off', () => {
  assert.deepEqual(GAMING_EFFECTS, ['off', 'flow', 'wave', 'ripple', 'pachinko']);
  assert.deepEqual(GAMING_EFFECTS.map(gamingSpeedEnabled), [false, true, true, true, false]);
  const defaults = new KeyboardSettingsSnapshot();
  const record = new KeyboardSettingsRecord();
  for (const [value, expected] of [['pachinko', 'pachinko'], ['invalid', 'off']]) {
    const patch = { gamingEffect: value };
    assert.equal(validSettingsPatch(patch), true);
    assert.equal(applySettingsPatch(defaults, patch).gamingEffect, expected);
    assert.equal(mergeSettingsPatch({ gamingEffect: 'flow' }, patch).gamingEffect, expected);
    record.snapshot.gamingEffect = value;
    assert.equal(decodeSettingsRecord(JSON.stringify(record)).snapshot.gamingEffect, expected);
  }
});

test('P58c: the renamed settings menu and title share a label and summarize pachinko', () => {
  for (const [locale, title, unlocked] of [
    ['base', 'ドパガキ', 'ドパガキモード解放 🎰'],
    ['en_US', 'Dopamine kid', 'Dopamine kid mode unlocked 🎰'],
    ['zh_CN', '多巴胺小孩', '多巴胺小孩模式已解锁 🎰']
  ]) {
    const { string: strings } = require(`../../entry/src/main/resources/${locale}/element/string.json`);
    const label = name => strings.find(entry => entry.name === `settings_${name}`).value;
    assert.equal(label('menu_gaming'), title);
    assert.equal(label('gaming_unlocked'), unlocked);
    const labels = ['off', 'flow', 'ripple', 'wave', 'pachinko'].map(effect => label(`gaming_${effect}`));
    assert.equal(settingsGamingSummary('pachinko', ...labels), label('gaming_pachinko'));
    if (locale === 'base') {
      assert.equal(labels[4], 'フィーバーモード');
      assert.equal(label('gaming_taps_left'), 'あと%d回');
    }
  }
  const view = readFileSync(require.resolve('../../entry/src/main/ets/components/KeyboardSettings.ets'), 'utf8');
  assert.match(view, /case SettingsPageId\.Gaming: return \$r\('app\.string\.settings_menu_gaming'\)/);
  assert.match(view, /pageTitle\(row\.page\)/);
  assert.match(view, /SettingsHeader\([^\n]*pageTitle\(this\.page\)/);
});
