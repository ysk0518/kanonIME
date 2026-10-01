// Order: tap, left, up, right, down. Empty directions insert nothing.
const NUMBER_KEYS: string[][] = [
  ['1', '@', '#', '¥', '°'], ['2', '+', '-', '×', '÷'], ['3', '/', '%', '=', '\\'],
  ['4', '(', '[', '{', '<'], ['5', ')', ']', '}', '>'], ['6', ':', ';', '_', '&'],
  ['7', "'", '"', '`', '|'], ['8', '$', '€', '£', '¢'], ['9', '?', '!', '~', '^'],
  ['.', ',', ':', ';', '…'], ['0', '°', '℃', '%', '∞'], [',', '?', '!', '"', "'"]
];

export function numberFlickKeys(kind: string): string[][] {
  if (kind === 'general') { return NUMBER_KEYS; }
  const digits: string[][] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '']
    .map((value: string) => [value, '', '', '', '']);
  if (kind === 'phone') {
    digits[9] = ['*', '', '', '', ''];
    digits[10] = ['0', '+', '', '', ''];
    digits[11] = ['#', '', '', '', ''];
  } else if (kind === 'number') {
    digits[9] = ['.', '', '', '', ''];
    digits[11] = ['-', '', '', '', ''];
  }
  return digits;
}
