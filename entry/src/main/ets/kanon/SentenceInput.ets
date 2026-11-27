/** English sentence helpers, as in Samsung Keyboard: double-space period and automatic capitals. */

/** A second space within this time after the first one ends the sentence. */
export const DOUBLE_SPACE_MS: number = 1000;

const WORD_END: RegExp = /[A-Za-z0-9)\]"']$/;

/** The text before the caret is a word followed by the one space just typed. */
export function doubleSpacePeriod(before: string): boolean {
  if (!before.endsWith(' ') || before.endsWith('  ')) { return false; }
  return WORD_END.test(before.slice(0, -1));
}

/** The next letter starts a sentence: an empty field, a new line, or after . ! ? and a space. */
export function sentenceStart(before: string): boolean {
  if (before.trim().length === 0) { return true; }
  if (/\n[ \t]*$/.test(before)) { return true; }
  return /[.!?]["')\]]*\s+$/.test(before);
}

/** Text fields that hold sentences (TEXT, MULTILINE); not URLs, e-mail, numbers or passwords. */
export function autoCapitalField(inputPattern: number): boolean {
  return inputPattern === 0 || inputPattern === 1;
}
