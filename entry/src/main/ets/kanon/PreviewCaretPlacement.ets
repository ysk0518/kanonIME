import { compositionCaretPath } from './CompositionCursorSync';

export interface PreviewCaretContext {
  text: string;
  start: number;
  position: number;
}

export interface PreviewCaretPort {
  getEpoch: () => number;
  queryCursor: () => Promise<number>;
  /** -1 is one code point left; +1 is one code point right. */
  /** Resolve after the SDK reply and an observation of expectedPosition. */
  moveCursor: (direction: number, expectedPosition: number) => Promise<void>;
}

/** Moves only inside the known preview and confirms every code-point step. */
export class PreviewCaretPlacement {
  private generation: number = 0;

  cancel(): void { this.generation++; }

  async place(port: PreviewCaretPort, context: PreviewCaretContext): Promise<boolean> {
    const end: number = context.start + context.text.length;
    if (!Number.isSafeInteger(context.start) || context.start < 0 || context.text.length === 0 ||
      !Number.isSafeInteger(end) || !Number.isSafeInteger(context.position) ||
      context.position < context.start || context.position > end ||
      compositionCaretPath(context.text, 0, context.position - context.start) === undefined) { return false; }
    const generation: number = ++this.generation;
    const epoch: number = port.getEpoch();
    const current: () => boolean = (): boolean =>
      generation === this.generation && epoch === port.getEpoch();
    let actual: number = await port.queryCursor();
    if (!current()) { return false; }
    const path: number[] | undefined = compositionCaretPath(context.text,
      actual - context.start, context.position - context.start);
    if (path === undefined) { return false; }
    for (const offset of path) {
      if (!current()) { return false; }
      const expected: number = context.start + offset;
      await port.moveCursor(expected < actual ? -1 : 1, expected);
      if (!current()) { return false; }
      actual = await port.queryCursor();
      if (!current() || actual !== expected) { return false; }
    }
    return current() && actual === context.position;
  }
}
