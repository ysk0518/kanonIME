/** A selection notification is a hint to read the current client, never its origin. */
export interface CompositionCursorContext {
  composing: boolean;
  /** False when our previous caret placement was not confirmed by the editor. */
  cursorAligned: boolean;
  start: number;
  previewLength: number;
  text: string;
  caret: number;
}

export interface CompositionCursorPort {
  getEpoch: () => number;
  hasSelection: () => boolean;
  queryCursor: () => Promise<number>;
  alignCursor: (position: number) => Promise<boolean>;
}

interface OwnCaret {
  position: number;
  at: number;
}

/** How long a caret our own preview write placed may still be echoed back late by the editor. */
export const OWN_CARET_ECHO_MS: number = 600;

export type CompositionCursorResult = 'ignored' | 'unchanged' | 'aligned' | 'retry' | 'failed' | 'stale';

/** UTF-16 positions reached by single code-point moves. Never split a surrogate pair. */
export function compositionCaretPath(text: string, from: number, to: number): number[] | undefined {
  if (!Number.isSafeInteger(from) || !Number.isSafeInteger(to)) { return undefined; }
  const boundaries: number[] = [0];
  for (let offset: number = 0; offset < text.length;) {
    offset += (text.codePointAt(offset) ?? 0) > 0xffff ? 2 : 1;
    boundaries.push(offset);
  }
  const first: number = boundaries.indexOf(from);
  const last: number = boundaries.indexOf(to);
  if (first < 0 || last < 0) { return undefined; }
  const path: number[] = [];
  const direction: number = last > first ? 1 : -1;
  for (let index: number = first; index !== last;) {
    index += direction;
    path.push(boundaries[index]);
  }
  return path;
}

/** Called inside the whole-input queue, after the previous preview update finishes. */
export class CompositionCursorSync {
  private port: CompositionCursorPort;
  private pendingEpoch: number = -1;
  private version: number = 0;
  private now: () => number;
  private own: OwnCaret[] = [];

  constructor(port: CompositionCursorPort, now: () => number = (): number => Date.now()) {
    this.port = port;
    this.now = now;
  }

  /** Records the absolute caret a preview write of ours placed in the editor. */
  wrote(position: number): void {
    const at: number = this.now();
    this.own = this.own.filter((item: OwnCaret): boolean => at - item.at < OWN_CARET_ECHO_MS);
    this.own.push({ position: position, at: at });
  }

  // Fast typing writes "s" then "sy"; the editor may still report the caret after "s"
  // once "sy" is shown. That echo is not the user tapping inside the composition.
  private ownEcho(position: number): boolean {
    const at: number = this.now();
    return this.own.some((item: OwnCaret): boolean => item.position === position && at - item.at < OWN_CARET_ECHO_MS);
  }

  notify(epoch: number): void { this.pendingEpoch = epoch; this.version++; }
  reset(): void { this.pendingEpoch = -1; this.version++; }

  async reconcile(context: CompositionCursorContext): Promise<CompositionCursorResult> {
    const epoch: number = this.port.getEpoch();
    if (this.pendingEpoch !== epoch) { return 'ignored'; }
    if (!context.composing || !context.cursorAligned || context.start < 0 || context.previewLength === 0 ||
      context.previewLength !== context.text.length || this.port.hasSelection()) {
      // A focus/selection hint from an empty or different composition is not
      // evidence about the caret of the composition that will be created next.
      this.pendingEpoch = -1;
      return 'ignored';
    }
    const version: number = this.version;
    let position: number;
    try { position = await this.port.queryCursor(); }
    catch (error) { return epoch === this.port.getEpoch() ? 'failed' : 'stale'; }
    if (epoch !== this.port.getEpoch()) { return 'stale'; }
    if (version !== this.version) { return 'retry'; }
    if (!Number.isSafeInteger(position) || position < 0) { return 'failed'; }
    this.pendingEpoch = -1;
    if (this.port.hasSelection() || position < context.start || position > context.start + context.text.length) {
      return 'ignored';
    }
    const target: number = position - context.start;
    if (target === context.caret) { return 'unchanged'; }
    if (this.ownEcho(position)) { return 'ignored'; }
    if (compositionCaretPath(context.text, context.caret, target) === undefined) {
      this.pendingEpoch = epoch;
      return 'failed';
    }
    let aligned: boolean;
    try { aligned = await this.port.alignCursor(target); }
    catch (error) { aligned = false; }
    if (epoch !== this.port.getEpoch()) { return 'stale'; }
    if (!aligned) { this.pendingEpoch = epoch; return 'failed'; }
    return version === this.version ? 'aligned' : 'retry';
  }
}
