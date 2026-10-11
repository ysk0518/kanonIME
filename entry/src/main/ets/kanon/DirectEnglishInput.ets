import { CandidateLabel } from './ImeCoordinator';
import { EnglishPrediction } from './EnglishPrediction';
import { InputEvent, UiEventKind } from './InputEventTypes';

/** Calls are made inside the existing IME input queue; this class owns no queue. */
export interface DirectEnglishPort {
  getEpoch: () => number;
  predictionAllowed: () => boolean;
  queryCursor: () => Promise<number>;
  queryBefore: (length: number) => Promise<string>;
  dispatch: (event: InputEvent) => Promise<void>;
  lastError: () => string;
  enterAction: (epoch: number) => Promise<void>;
}

export type DirectEnglishConversion = 'handled' | 'space' | 'stale';

/** Prediction around text already in the editor, when platform preview is unavailable. */
export class DirectEnglishInput {
  private prediction: EnglishPrediction;
  private port: DirectEnglishPort;

  constructor(prediction: EnglishPrediction, port: DirectEnglishPort) {
    this.prediction = prediction;
    this.port = port;
  }

  private candidateCurrent(revision: number, prefix: string): boolean {
    return revision === this.prediction.getRevision() && prefix === this.prediction.getPrefix() &&
      this.prediction.canSeed() && this.port.predictionAllowed();
  }

  async convert(epoch: number): Promise<DirectEnglishConversion> {
    if (!this.port.predictionAllowed() || this.prediction.getItems().length === 0) { return 'space'; }
    const expected: number = this.prediction.getCursor();
    const cursor: number = await this.port.queryCursor();
    if (epoch !== this.port.getEpoch()) { this.prediction.clear(); return 'stale'; }
    const before: string = cursor >= 0 && cursor <= 4096 ? await this.port.queryBefore(cursor) : '';
    if (epoch !== this.port.getEpoch()) { this.prediction.clear(); return 'stale'; }
    if (cursor === expected && before.endsWith(this.prediction.getPrefix())) {
      this.prediction.selectNext();
    } else { this.prediction.clear(); }
    return 'handled';
  }

  async complete(id: number, revision: number): Promise<void> {
    if (!this.port.predictionAllowed() || revision !== this.prediction.getRevision()) { return; }
    const item: CandidateLabel | undefined = this.prediction.getItems().find(
      (candidate: CandidateLabel) => candidate.id === id);
    if (item === undefined) { return; }
    const prefix: string = this.prediction.getPrefix();
    const expected: number = this.prediction.getCursor();
    const epoch: number = this.port.getEpoch();
    const cursor: number = await this.port.queryCursor();
    if (epoch !== this.port.getEpoch() || cursor !== expected || cursor < 0 || cursor > 4096) {
      this.prediction.clear(); return;
    }
    if (!this.candidateCurrent(revision, prefix)) { return; }
    const before: string = await this.port.queryBefore(cursor);
    if (epoch !== this.port.getEpoch() || !before.endsWith(prefix)) { this.prediction.clear(); return; }
    if (!this.candidateCurrent(revision, prefix)) { return; }
    // The prefix is already in the editor. Append only the remaining letters.
    this.prediction.editing = true;
    let completed: boolean = false;
    try {
      await this.port.dispatch({ kind: 'text', text: item.label.substring(prefix.length) });
      completed = this.port.lastError() === 'ok' && epoch === this.port.getEpoch();
    } finally {
      this.prediction.editing = false;
      this.prediction.clear();
    }
    const end: number = expected + item.label.length - prefix.length;
    if (completed && end <= 4096) { this.prediction.rememberCompletion(prefix, item.label, end, epoch); }
  }

  async handle(kind: 'select' | 'cancel' | 'enter', id?: number, revision?: number): Promise<void> {
    if (kind === 'select') { await this.complete(id ?? -1, revision ?? -1); return; }
    if (kind === 'enter' && this.prediction.getPrefix().length > 0) {
      const selected: CandidateLabel | undefined = this.prediction.getSelectedItem();
      if (selected !== undefined) { await this.complete(selected.id, this.prediction.getRevision()); }
      else { this.prediction.clear(); }
      return;
    }
    const epoch: number = this.port.getEpoch();
    this.prediction.clear();
    if (kind === 'cancel') { await this.port.dispatch({ kind: 'cancel' }); }
    else { await this.port.enterAction(epoch); }
  }

  /** Return the pre-insertion cursor; seed only from the same input target. */
  async beforeText(text: string, epoch: number): Promise<number> {
    const cursor: number = this.prediction.getPrefix().length === 0 ?
      await this.port.queryCursor() : this.prediction.getCursor();
    if (epoch !== this.port.getEpoch()) { return cursor; }
    if (/^[A-Za-z]+$/.test(text) && this.port.predictionAllowed() &&
      this.prediction.getPrefix().length === 0 && this.prediction.canSeed() && cursor > 0 && cursor <= 4096) {
      const before: string = await this.port.queryBefore(cursor);
      const word: RegExpMatchArray | null = before.match(/[A-Za-z]+$/);
      if (word !== null && epoch === this.port.getEpoch() &&
        this.prediction.canSeed() && this.port.predictionAllowed()) { this.prediction.seed(word[0], cursor); }
    }
    return cursor;
  }

  afterEvent(kind: UiEventKind, text: string | undefined, cursor: number, successful: boolean): void {
    if (successful && this.port.predictionAllowed()) {
      if (kind === 'text') { this.prediction.text(text ?? '', cursor); }
      else if (kind === 'backspace') { this.prediction.backspace(); }
      else { this.prediction.clear(); }
    } else { this.prediction.clear(); }
  }
}
