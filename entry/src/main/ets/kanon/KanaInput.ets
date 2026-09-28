/* Flick keys feed complete roman units into the existing Mozc session. */
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

export function kanaRoman(kana: string): string {
  const index: number = KANA.indexOf(kana);
  return index < 0 ? '' : ROMAN[index];
}

export function modifiedKana(kana: string): string {
  for (const group of MODIFIER_GROUPS) {
    const index: number = group.indexOf(kana);
    if (index >= 0 && kana.length === 1) { return group[(index + 1) % group.length]; }
  }
  return kana;
}
