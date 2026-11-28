const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { FakeEditor, deferred, update } = require('../support/fakes.cjs');
const { drawPachinko, drawPachinkoColor, enqueuePachinko, consumePachinkoHold, pachinkoIdleRemaining, pachinkoStops,
  PachinkoColor: Color, PachinkoResult: Result, ImeCommitNotifications, imeCommitNotifications } =
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
  const inputs = [0, 0.29, 0.10, 0.20, 0.50, 0.10, 0, 0.79];
  let calls = 0;
  const random = () => inputs[calls++];
  let holds = Object.freeze([]);
  for (let i = 1; i <= 4; i++) {
    holds = enqueuePachinko(Object.freeze(holds), random);
    assert.equal(holds.length, i);
    assert.equal(calls, i * 2);
  }
  assert.equal(enqueuePachinko(holds, random), holds);
  assert.equal(calls, 8);
  assert.deepEqual(holds, [
    { result: Result.Jackpot, color: Color.Gold },
    { result: Result.Reach, color: Color.Green },
    { result: Result.Miss, color: Color.Blue },
    { result: Result.Jackpot, color: Color.Red }
  ]);
  const forced = enqueuePachinko(holds.slice(1), () => 0.8, Result.Jackpot);
  assert.deepEqual(forced[3], { result: Result.Jackpot, color: Color.Green });
});

test('P58d: hold colors use the result-specific probability table', () => {
  const cases = [
    [Result.Jackpot, [[0.3, Color.Gold, Color.Red], [0.8, Color.Red, Color.Green]]],
    [Result.Reach, [[0.2, Color.Red, Color.Green], [0.6, Color.Green, Color.Blue]]],
    [Result.Miss, [[0.1, Color.Green, Color.Blue]]]
  ];
  for (const [result, boundaries] of cases) {
    for (const [threshold, before, at] of boundaries) {
      assert.equal(drawPachinkoColor(result, () => threshold - Number.EPSILON), before);
      assert.equal(drawPachinkoColor(result, () => threshold), at);
    }
  }
});

test('P58d: consumption waits 800 ms from the last activity and uses FIFO order', () => {
  let holds = [];
  for (const result of [Result.Reach, Result.Miss, Result.Jackpot]) {
    holds = enqueuePachinko(holds, () => 0, result);
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

test('P58d: reel stops give distinct misses adjacent near misses and jackpot 777', () => {
  for (let left = 0; left < 9; left++) {
    const reach = pachinkoStops(Result.Reach, () => left / 9);
    assert.equal(reach.left, left + 1);
    assert.equal(reach.right, reach.left);
    assert.ok(reach.middle >= 1 && reach.middle <= 9);
    assert.equal(Math.abs(reach.middle - reach.left), 1);
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
  assert.deepEqual(pachinkoStops(Result.Jackpot, () => assert.fail('jackpot must always use 777')),
    { left: 7, middle: 7, right: 7 });
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
      assert.equal(labels[4], 'パチンコ演出');
      assert.equal(label('gaming_taps_left'), 'あと%d回');
    }
  }
  const view = readFileSync(require.resolve('../../entry/src/main/ets/components/KeyboardSettings.ets'), 'utf8');
  assert.match(view, /case SettingsPageId\.Gaming: return \$r\('app\.string\.settings_menu_gaming'\)/);
  assert.match(view, /pageTitle\(row\.page\)/);
  assert.match(view, /SettingsHeader\([^\n]*pageTitle\(this\.page\)/);
});
