import {
  KANON_CAND, KANON_COMPOSITION_CURSOR, KANON_CONVERSION_READING, KANON_ENGLISH_COMPOSING, KANON_ERR,
  KANON_IDS, KANON_ID_LIST, KANON_JAPANESE_COMPOSING, KANON_LENS, KANON_LENS2, KANON_LIST, KANON_MODE,
  KANON_NEEDS_RECOVERY, KANON_REV, KANON_SEG, KANON_SEL, KANON_STATE, KANON_TICK
} from '../common/AppStorageKeys';
import { ImeSnapshot } from './ImeCoordinator';
import { createImeViewModel, ImeViewModel, ImeViewSource } from './ImeViewModel';

export interface ImeViewPort {
  number(key: string, value: number): void;
  string(key: string, value: string): void;
  boolean(key: string, value: boolean): void;
  strings(key: string, value: string[]): void;
  numbers(key: string, value: number[]): void;
}

/** Publish display state only. Does not dispatch input or edit the editor. */
export class ImeViewPublisher {
  private tick: number = 0;
  private port: ImeViewPort;
  constructor(port: ImeViewPort) { this.port = port; }

  publish(snapshot: ImeSnapshot, source: ImeViewSource): void {
    const view: ImeViewModel = createImeViewModel(snapshot, source, ++this.tick);
    this.port.number(KANON_TICK, view.tick);
    this.port.string(KANON_MODE, view.mode);
    this.port.string(KANON_STATE, view.state);
    this.port.boolean(KANON_JAPANESE_COMPOSING, view.japaneseComposing);
    this.port.string(KANON_CONVERSION_READING, view.conversionReading);
    this.port.string(KANON_COMPOSITION_CURSOR, view.compositionCursor);
    this.port.boolean(KANON_ENGLISH_COMPOSING, view.englishComposing);
    this.port.string(KANON_ERR, view.error);
    this.port.boolean(KANON_NEEDS_RECOVERY, view.needsRecovery);
    this.port.number(KANON_CAND, view.candidateCount);
    this.port.number(KANON_REV, view.candidateRevision);
    try {
      this.port.strings(KANON_LIST, view.labels);
      this.port.numbers(KANON_ID_LIST, view.ids);
    } catch (error) {
    }
    try {
      this.port.string(KANON_LENS, view.nativeCandidateLengths);
      this.port.string(KANON_IDS, view.diagnosticIds);
      this.port.string(KANON_LENS2, view.diagnosticLengths);
      this.port.number(KANON_SEG, view.segmentCount);
      this.port.number(KANON_SEL, view.selectedIndex);
    } catch (error) {
    }
  }
}
