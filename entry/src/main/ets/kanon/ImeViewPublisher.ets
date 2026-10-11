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
    this.port.number('kanonTick', view.tick);
    this.port.string('kanonMode', view.mode);
    this.port.string('kanonState', view.state);
    this.port.boolean('kanonJapaneseComposing', view.japaneseComposing);
    this.port.string('kanonConversionReading', view.conversionReading);
    this.port.string('kanonCompositionCursor', view.compositionCursor);
    this.port.boolean('kanonEnglishComposing', view.englishComposing);
    this.port.string('kanonErr', view.error);
    this.port.boolean('kanonNeedsRecovery', view.needsRecovery);
    this.port.number('kanonCand', view.candidateCount);
    this.port.number('kanonRev', view.candidateRevision);
    try {
      this.port.strings('kanonList', view.labels);
      this.port.numbers('kanonIdList', view.ids);
    } catch (error) {
    }
    try {
      this.port.string('kanonLens', view.nativeCandidateLengths);
      this.port.string('kanonIds', view.diagnosticIds);
      this.port.string('kanonLens2', view.diagnosticLengths);
      this.port.number('kanonSeg', view.segmentCount);
      this.port.number('kanonSel', view.selectedIndex);
    } catch (error) {
    }
  }
}
