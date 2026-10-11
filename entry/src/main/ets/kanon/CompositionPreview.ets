import { ImeSnapshot } from './ImeCoordinator';
import { UiEventKind } from './InputEventTypes';
import { advanceCompositionStart } from './CompositionPosition';

export interface CompositionPreviewPort {
  getEpoch: () => number;
  queryCursor: () => Promise<number>;
  clearPreview: () => Promise<void>;
  refreshPreview: (text: string, start: number, end: number, caret: number) => Promise<boolean>;
  disableJapanesePreview: () => void;
  englishCursor: (position: number) => void;
}

/** Owns document origin/length; Coordinator owns the text actually sent to OS. */
export class CompositionPreview {
  private start: number = -1;
  private length: number = 0;
  private generation: number = 0;
  private port: CompositionPreviewPort;

  constructor(port: CompositionPreviewPort) { this.port = port; }
  getStart(): number { return this.start; }
  getLength(): number { return this.length; }

  reset(): void {
    this.generation++;
    this.start = -1;
    this.length = 0;
  }

  restore(start: number): void {
    this.reset();
    this.start = start;
  }

  private current(generation: number, epoch: number): boolean {
    return generation === this.generation && epoch === this.port.getEpoch();
  }

  async reconcile(snapshot: ImeSnapshot, kind: UiEventKind, previousMode: string): Promise<void> {
    const generation: number = this.generation;
    const epoch: number = this.port.getEpoch();
    if (snapshot.mode === 'JP' && snapshot.preeditLen > 0 &&
      snapshot.lastError === 'ok' && snapshot.commitLength > 0) {
      // Prefer tracked origin over a potentially stale cursor after insertText.
      const base: number = this.start >= 0 ? this.start : await this.port.queryCursor();
      if (!this.current(generation, epoch)) { return; }
      this.restore(advanceCompositionStart(this.start, base, snapshot.commitLength));
    }
    if (snapshot.preeditLen !== 0 || this.start < 0) { return; }
    const alreadyCommitted: boolean = (snapshot.lastError === 'ok' && snapshot.commitLength > 0) ||
      kind === 'submit' || kind === 'enter' || kind === 'select' || kind === 'move' ||
      kind === 'selectMove' || kind === 'selectEdge' || kind === 'selectAll' || kind === 'forwardDelete' ||
      kind === 'partial' || (kind === 'mode' && snapshot.mode !== previousMode);
    if (!alreadyCommitted) {
      try { await this.port.clearPreview(); } catch (error) { }
    }
    if (this.current(generation, epoch)) { this.reset(); }
  }

  async refresh(snapshot: ImeSnapshot, text: string, englishComposition: boolean): Promise<void> {
    if ((snapshot.mode !== 'JP' && !englishComposition) || snapshot.preeditLen === 0) {
      this.reset();
      return;
    }
    if (snapshot.state !== 'JP_COMPOSING' && snapshot.state !== 'JP_CONVERTING' &&
      snapshot.state !== 'EN_COMPOSING' && snapshot.state !== 'EN_CONVERTING') { return; }
    if (text.length === 0) { return; }
    const generation: number = this.generation;
    const epoch: number = this.port.getEpoch();
    if (this.start < 0) {
      const cursor: number = await this.port.queryCursor();
      if (!this.current(generation, epoch)) { return; }
      this.start = cursor;
      this.length = 0;
    }
    if (this.start < 0) { return; }
    if (snapshot.mode === 'EN') { this.port.englishCursor(this.start + text.length); }
    const ok: boolean = await this.port.refreshPreview(text, this.start, this.start + this.length, snapshot.caretUtf16);
    if (!this.current(generation, epoch)) { return; }
    if (ok) { this.length = text.length; }
    if (!ok && snapshot.mode === 'JP') { this.port.disableJapanesePreview(); }
  }
}
