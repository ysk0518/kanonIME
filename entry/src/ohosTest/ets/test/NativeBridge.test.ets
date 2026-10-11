import { beforeAll, beforeEach, describe, expect, it, TestType } from '@ohos/hypium';
import AbilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import fs from '@ohos.file.fs';
import { NativeMozcBridge } from '../../../main/ets/kanon/NativeMozcBridge';
import { MozcEngine } from '../../../main/ets/kanon/MozcEngine';
import { CandidateLabel } from '../../../main/ets/kanon/ImeCoordinator';

interface NativeCandidate { id: number; value: string; }
interface NativeOutput {
  ok: boolean;
  preedit: string;
  preedit_len: number;
  caret_utf16: number;
  ncand: number;
  candidates: NativeCandidate[];
  result?: string;
}

const bridge: NativeMozcBridge = new NativeMozcBridge();
async function call(operation: string, text: string = '', id: number = 0): Promise<NativeOutput> {
  const raw: string = await bridge.executeAsync(operation, text, id);
  const out: NativeOutput = JSON.parse(raw) as NativeOutput;
  if (out.ok !== true) { throw new Error(`Native operation failed: ${operation}`); }
  expect(out.ok).assertTrue();
  expect(typeof out.preedit).assertEqual('string');
  expect(Number.isInteger(out.preedit_len)).assertTrue();
  expect(Number.isInteger(out.caret_utf16)).assertTrue();
  expect(out.caret_utf16 >= 0 && out.caret_utf16 <= out.preedit.length).assertTrue();
  expect(out.ncand).assertEqual(out.candidates.length);
  for (const candidate of out.candidates) {
    expect(Number.isInteger(candidate.id)).assertTrue();
    expect(typeof candidate.value).assertEqual('string');
  }
  return out;
}
function candidateId(out: NativeOutput, value: string): number {
  const candidate: NativeCandidate | undefined = out.candidates.find((item: NativeCandidate) => item.value === value);
  if (candidate === undefined) { throw new Error('Required fixture candidate missing'); }
  expect(candidate !== undefined).assertTrue();
  return candidate.id;
}
function noCommit(out: NativeOutput): void { expect(out.result ?? '').assertEqual(''); }


export default function nativeBridgeTest(): void {
  describe('KanonNativeBridge', () => {

    beforeAll(async () => {
      const context = AbilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const directory: string = `${context.filesDir}/native-contract-${Date.now()}`;
      fs.mkdirSync(directory);
      bridge.configureProfile(directory);
      expect(await bridge.prepare()).assertTrue();
    });
    beforeEach(async () => { await call('reset'); });

    it('N01_roman_and_json_units', TestType.FUNCTION, async () => {
      const consonant: NativeOutput = await call('convert', 'k');
      expect(consonant.preedit).assertEqual('ｋ');
      noCommit(consonant);
      const kana: NativeOutput = await call('convert', 'i');
      expect(kana.preedit).assertEqual('き');
      expect(kana.preedit_len).assertEqual(3);
      expect(kana.caret_utf16).assertEqual(1);
      noCommit(kana);
    });
    it('N02_conversion_candidate_id_and_restart', TestType.FUNCTION, async () => {
      await call('convert', 'nihongo');
      const converted: NativeOutput = await call('space');
      expect(converted.ncand > 1).assertTrue();
      const committed: NativeOutput = await call('submitCandidate', '', candidateId(converted, '日本語'));
      expect(committed.result).assertEqual('日本語');
      expect(committed.preedit).assertEqual('');
      const next: NativeOutput = await call('convert', 'ki');
      expect(next.preedit).assertEqual('き');
      noCommit(next);
    });
    it('N03_symbol_candidate_and_session_survival', TestType.FUNCTION, async () => {
      await call('convert', 'ten');
      let converted: NativeOutput = await call('space');
      // Native JSON exports a page, while the host fixture searches all words.
      // Traverse pages via real Space operations; do not hard-code a candidate rank.
      let advances: number = 0;
      while (!converted.candidates.some((item: NativeCandidate) => item.value === '・') && advances < 160) {
        noCommit(converted);
        converted = await call('space');
        advances++;
      }
      const committed: NativeOutput = await call('submitCandidate', '', candidateId(converted, '・'));
      expect(committed.result).assertEqual('・');
      expect(committed.preedit).assertEqual('');
      expect((await call('convert', 'ki')).preedit).assertEqual('き');
    });
    it('N04_literal_punctuation_stays_composing', TestType.FUNCTION, async () => {
      await call('convert', 'ki');
      const punctuation: NativeOutput = await call('literal', '？');
      expect(punctuation.preedit).assertEqual('き？');
      noCommit(punctuation);
      const appended: NativeOutput = await call('convert', 'ku');
      expect(appended.preedit).assertEqual('き？く');
      noCommit(appended);
    });
    it('N05_insert_at_composing_cursor', TestType.FUNCTION, async () => {
      await call('convert', 'kaki');
      expect((await call('arrowLeft')).caret_utf16).assertEqual(1);
      const inserted: NativeOutput = await call('convert', 'sa');
      expect(inserted.preedit).assertEqual('かさき');
      noCommit(inserted);
    });
    it('N06_resize_partial_commit_and_remaining_input', TestType.FUNCTION, async () => {
      await call('convert', 'kyouha');
      await call('space');
      const resized: NativeOutput = await call('arrowLeft');
      const partial: NativeOutput = await call('submitCandidate', '', candidateId(resized, '今日'));
      expect(partial.result).assertEqual('今日');
      expect(partial.preedit).assertEqual('は');
      await call('reset');
      await call('literal', partial.preedit);
      const appended: NativeOutput = await call('convert', 'ga');
      expect(appended.preedit).assertEqual('はが');
      noCommit(appended);
    });
    it('N07_non_bmp_json_units_and_delete', TestType.FUNCTION, async () => {
      const emoji: NativeOutput = await call('literal', '😀');
      expect(emoji.preedit).assertEqual('😀');
      expect(emoji.preedit_len).assertEqual(4);
      expect(emoji.caret_utf16).assertEqual(2);
      const removed: NativeOutput = await call('backspace');
      expect(removed.preedit).assertEqual('');
      noCommit(removed);
    });
    it('N08_reset_does_not_restore_previous_text', TestType.FUNCTION, async () => {
      await call('convert', 'ki');
      await call('reset');
      const next: NativeOutput = await call('convert', 'sa');
      expect(next.preedit).assertEqual('さ');
      noCommit(next);
    });
    it('N09_real_engine_qwerty_delete', TestType.FUNCTION, async () => {
      const engine: MozcEngine = new MozcEngine(bridge);
      await engine.dispatch('native-test', 1, 1, { kind: 'text', text: 'k' });
      await engine.dispatch('native-test', 1, 2, { kind: 'text', text: 'i' });
      expect(engine.getPreedit()).assertEqual('き');
      const deleted = await engine.dispatch('native-test', 1, 3, { kind: 'backspace' });
      expect(deleted.errorCode).assertEqual(0);
      expect(engine.getPreedit()).assertEqual('');
    });
    it('N10_real_engine_partial_commit_and_continue', TestType.FUNCTION, async () => {
      const engine: MozcEngine = new MozcEngine(bridge);
      let sequence: number = 0;
      for (const kana of ['き', 'ょ', 'う', 'は']) {
        const typed = await engine.dispatch('native-test', 1, ++sequence, { kind: 'kana', text: kana });
        expect(typed.errorCode).assertEqual(0);
      }
      await engine.dispatch('native-test', 1, ++sequence, { kind: 'convert' });
      const resized = await engine.dispatch('native-test', 1, ++sequence, { kind: 'compositionArrow', text: 'left' });
      expect(resized.errorCode).assertEqual(0);
      const selected: CandidateLabel | undefined = resized.candidates.find((item: CandidateLabel) => item.label === '今日');
      if (selected === undefined) { throw new Error('Required partial fixture candidate missing'); }
      const committed = await engine.dispatch('native-test', 1, ++sequence,
        { kind: 'select', candidateId: selected.id, expectedRevision: resized.candidateRevision });
      expect(committed.errorCode).assertEqual(0);
      expect(committed.effects.length).assertEqual(1);
      expect(committed.effects[0].text).assertEqual('今日');
      expect(engine.getPreedit()).assertEqual('は');
      const continued = await engine.dispatch('native-test', 1, ++sequence, { kind: 'kana', text: 'が' });
      expect(continued.errorCode).assertEqual(0);
      expect(continued.effects.length).assertEqual(0);
      expect(engine.getPreedit()).assertEqual('はが');
    });
  });
}
