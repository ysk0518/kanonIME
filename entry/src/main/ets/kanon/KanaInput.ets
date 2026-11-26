/* Flick keys feed complete roman units into the existing Mozc session. */
import { KanaModifier } from './InputEventTypes';

// Order: tap, left, up, right, down.
export const KANA_MODIFIER_FLICKS: (KanaModifier | undefined)[] = ['cycle', 'voiced', 'size', 'semiVoiced', undefined];

const KANA: string[] = 'あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんがぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽぁぃぅぇぉゃゅょっゎゔー'.split('');
const ROMAN: string[] = ('a i u e o ka ki ku ke ko sa shi su se so ta chi tsu te to na ni nu ne no ' +
  'ha hi fu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wo nn ' +
  'ga gi gu ge go za ji zu ze zo da di du de do ba bi bu be bo pa pi pu pe po ' +
  'la li lu le lo lya lyu lyo ltsu lwa vu -').split(' ');
const MODIFIER_GROUPS: string[] = [
  'あぁ', 'いぃ', 'うぅゔ', 'えぇ', 'おぉ', 'かが', 'きぎ', 'くぐ', 'けげ', 'こご',
  'さざ', 'しじ', 'すず', 'せぜ', 'そぞ', 'ただ', 'ちぢ', 'つっづ', 'てで', 'とど',
  'はばぱ', 'ひびぴ', 'ふぶぷ', 'へべぺ', 'ほぼぽ', 'やゃ', 'ゆゅ', 'よょ', 'わゎ'
];
const VOICEABLE: string = 'うかきくけこさしすせそたちつてとはひふへほ';
const VOICED: string = 'ゔがぎぐげござじずぜぞだぢづでどばびぶべぼ';
const SEMI_VOICED: string = 'ぱぴぷぺぽ';
const FULL_SIZE: string = 'あいうえおつやゆよわ';
const SMALL_SIZE: string = 'ぁぃぅぇぉっゃゅょゎ';

export function kanaRoman(kana: string): string {
  const index: number = KANA.indexOf(kana);
  return index < 0 ? '' : ROMAN[index];
}

export function modifiedKana(kana: string, modifier: KanaModifier = 'cycle'): string {
  if (kana.length !== 1) { return kana; }
  if (modifier === 'size') {
    const full: number = FULL_SIZE.indexOf(kana);
    if (full >= 0) { return SMALL_SIZE[full]; }
    const small: number = SMALL_SIZE.indexOf(kana);
    return small >= 0 ? FULL_SIZE[small] : kana;
  }
  if (modifier === 'voiced') {
    const semi: number = SEMI_VOICED.indexOf(kana);
    if (semi >= 0) { return 'ばびぶべぼ'.charAt(semi); }
    const plain: number = VOICEABLE.indexOf(kana);
    return plain >= 0 ? VOICED[plain] : kana;
  }
  if (modifier === 'semiVoiced') {
    const index: number = 'はひふへほばびぶべぼ'.indexOf(kana);
    return index >= 0 ? SEMI_VOICED[index % SEMI_VOICED.length] : kana;
  }
  for (const group of MODIFIER_GROUPS) {
    const index: number = group.indexOf(kana);
    if (index >= 0) { return group[(index + 1) % group.length]; }
  }
  return kana;
}
