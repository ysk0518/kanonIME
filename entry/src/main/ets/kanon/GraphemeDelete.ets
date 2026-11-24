const JOINER: number = 0x200D;

function previousCodePointStart(text: string, end: number): number {
  const last: number = text.charCodeAt(end - 1);
  if (last >= 0xDC00 && last <= 0xDFFF && end > 1) {
    const first: number = text.charCodeAt(end - 2);
    if (first >= 0xD800 && first <= 0xDBFF) { return end - 2; }
  }
  return end - 1;
}

function isExtension(point: number): boolean {
  return (point >= 0x0300 && point <= 0x036F) ||
    (point >= 0x1AB0 && point <= 0x1AFF) ||
    (point >= 0x1DC0 && point <= 0x1DFF) ||
    (point >= 0x20D0 && point <= 0x20FF) || // Includes keycap U+20E3.
    (point >= 0x3099 && point <= 0x309A) ||
    (point >= 0xFE00 && point <= 0xFE0F) ||
    (point >= 0xFE20 && point <= 0xFE2F) ||
    (point >= 0x1F3FB && point <= 0x1F3FF) ||
    (point >= 0xE0020 && point <= 0xE007F) ||
    (point >= 0xE0100 && point <= 0xE01EF);
}

function previousPartStart(text: string, end: number): number {
  let start: number = previousCodePointStart(text, end);
  while (start > 0 && isExtension(text.codePointAt(start) ?? 0)) {
    start = previousCodePointStart(text, start);
  }
  return start;
}

function isRegionalIndicator(point: number): boolean {
  return point >= 0x1F1E6 && point <= 0x1F1FF;
}

/** UTF-16 width of the last grapheme within the text available to the IME. */
export function lastGraphemeLength(text: string): number {
  if (text.length === 0) { return 0; }
  let start: number = previousPartStart(text, text.length);
  let point: number = text.codePointAt(start) ?? 0;
  if (start > 0 && isRegionalIndicator(point)) {
    // Delete indicators in pairs from the end, even for an odd run.
    const previous: number = previousCodePointStart(text, start);
    if (isRegionalIndicator(text.codePointAt(previous) ?? 0)) { start = previous; }
  }
  if (point === 0x0A && start > 0 && text.charCodeAt(start - 1) === 0x0D) { start--; }

  while (start > 0) {
    if (point === JOINER) {
      start = previousPartStart(text, start);
      point = text.codePointAt(start) ?? 0;
    } else if (text.charCodeAt(start - 1) === JOINER) {
      start--;
      point = JOINER;
    } else { break; }
  }
  return text.length - start;
}
