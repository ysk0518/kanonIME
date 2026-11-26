const JAPANESE_CYCLES: string[] = [
  'あいうえおぁぃぅぇぉ', 'かきくけこ', 'さしすせそ', 'たちつてとっ', 'なにぬねの',
  'はひふへほ', 'まみむめも', 'やゆよゃゅょ', 'らりるれろ', 'わをんゎー', '、。？！…'
];
const ENGLISH_CYCLES: string[] = ['@/:~', 'abc', 'def', 'ghi', 'jkl', 'mno', 'pqrs', 'tuv', 'wxyz', '-#', '.,?!'];

export function toggleCycle(key: string, english: boolean, uppercase: boolean): string {
  const cycle: string = (english ? ENGLISH_CYCLES : JAPANESE_CYCLES)
    .find((group: string): boolean => group.charAt(0) === key) ?? '';
  return english && uppercase ? cycle.toUpperCase() : cycle;
}

export const TOGGLE_WINDOW_MS: number = 1000;

export class ToggleRun {
  key: string;
  cycle: string;
  index: number;
  time: number;
  cursor: number;

  constructor(key: string, cycle: string, index: number, time: number, cursor: number) {
    this.key = key;
    this.cycle = cycle;
    this.index = index;
    this.time = time;
    this.cursor = cursor;
  }

  activeAt(time: number): boolean { return time >= this.time && time - this.time <= TOGGLE_WINDOW_MS; }
  character(): string { return this.cycle.charAt(this.index); }
  step(offset: number, time: number): ToggleRun {
    const index: number = (this.index + offset + this.cycle.length) % this.cycle.length;
    return new ToggleRun(this.key, this.cycle, index, time, this.cursor);
  }
}
