/** Replayable input: kana keys retain their roman spelling; literals retain UTF-16 text. */
export class CompositionInput {
  text: string;
  kana: string;
  literal: boolean;

  constructor(text: string, kana: string = '', literal: boolean = false) {
    this.text = text;
    this.kana = kana;
    this.literal = literal;
  }
}

/** Never split a surrogate pair while rebuilding literal input. */
export function literalInputs(text: string): CompositionInput[] {
  const units: CompositionInput[] = [];
  for (let i: number = 0; i < text.length; i++) {
    let width: number = 1;
    const high: number = text.charCodeAt(i);
    if (high >= 0xD800 && high <= 0xDBFF && i + 1 < text.length) {
      const low: number = text.charCodeAt(i + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) { width = 2; }
    }
    units.push(new CompositionInput(text.slice(i, i + width), '', true));
    i += width - 1;
  }
  return units;
}
