import { CandidateLabel, ImeSnapshot } from './ImeCoordinator';
import { EnglishCompletionUndo, EnglishPrediction } from './EnglishPrediction';
import { InputEvent, UiEventKind } from './InputEventTypes';

export interface EnglishCompletionPort {
  getEpoch: () => number;
  predictionAllowed: () => boolean;
  usesComposition: () => boolean;
  snapshot: () => ImeSnapshot;
  dispatch: (event: InputEvent) => Promise<void>;
  restorePreview: (start: number) => void;
  refreshPreview: (snapshot: ImeSnapshot) => Promise<void>;
}

export interface EnglishCompletionContext {
  kind: UiEventKind;
  prefix: string;
  word: string | undefined;
  start: number;
  epoch: number;
}

export type EnglishUndoResult = 'continue' | 'handled' | 'stale';

/** Completion metadata and restoration; editor mutations remain in Coordinator. */
export class EnglishCompletionLifecycle {
  private prediction: EnglishPrediction;
  private port: EnglishCompletionPort;
  constructor(prediction: EnglishPrediction, port: EnglishCompletionPort) {
    this.prediction = prediction;
    this.port = port;
  }

  capture(kind: UiEventKind, id: number | undefined, prefix: string, start: number,
    epoch: number): EnglishCompletionContext {
    const item: CandidateLabel | undefined = kind === 'select' ? this.prediction.getItems().find(
      (candidate: CandidateLabel) => candidate.id === id) :
      this.prediction.getSelectedItem();
    return { kind: kind, prefix: prefix, word: item === undefined ? undefined : item.label,
      start: start, epoch: epoch };
  }

  remember(context: EnglishCompletionContext, snapshot: ImeSnapshot): void {
    const word: string | undefined = context.word;
    if (context.epoch !== this.port.getEpoch() || (context.kind !== 'enter' && context.kind !== 'select') ||
      snapshot.lastError !== 'ok' || snapshot.commitLength <= 0 || context.start < 0 ||
      !/^[A-Za-z]+$/.test(context.prefix) || word === undefined ||
      !word.startsWith(context.prefix) || word.length <= context.prefix.length) { return; }
    this.prediction.rememberCompletion(context.prefix, word, context.start + snapshot.commitLength, context.epoch);
  }

  /** A stale explicit Undo is never replaced with ordinary Backspace. */
  async undo(kind: 'backspace' | 'undoEnglish', epoch: number): Promise<EnglishUndoResult> {
    if (epoch !== this.port.getEpoch()) { return 'stale'; }
    if (this.port.snapshot().mode === 'EN') {
      const undo: EnglishCompletionUndo | undefined = this.prediction.takeUndo();
      if (undo !== undefined && undo.epoch === epoch && this.port.predictionAllowed()) {
        this.prediction.editing = true;
        try {
          await this.port.dispatch({ kind: 'undoCompletion', text: undo.word,
            cursor: undo.cursor, prefixLength: undo.prefix.length });
        } finally { this.prediction.editing = false; }
        const snapshot: ImeSnapshot = this.port.snapshot();
        if (epoch !== this.port.getEpoch()) { this.prediction.clear(); return 'stale'; }
        if (snapshot.lastError === 'ok') {
          if (this.port.usesComposition()) {
            this.port.restorePreview(undo.cursor - undo.word.length);
            this.prediction.editing = true;
            try { await this.port.refreshPreview(snapshot); }
            finally { this.prediction.editing = false; }
            if (epoch !== this.port.getEpoch()) { this.prediction.clear(); return 'stale'; }
          } else {
            this.prediction.restorePrefix(undo.prefix, undo.cursor - undo.word.length + undo.prefix.length);
          }
        }
        if (snapshot.lastError !== 'undo-stale') { return 'handled'; }
      }
    }
    if (kind === 'undoEnglish') {
      if (this.port.snapshot().mode === 'EN' && this.port.snapshot().lastError === 'undo-stale') {
        await this.port.dispatch({ kind: 'cancel' });
      }
      return 'handled';
    }
    return 'continue';
  }
}
