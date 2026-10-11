import { CandidateLabel, ImeSnapshot } from './ImeCoordinator';
import { EnglishPrediction } from './EnglishPrediction';
import { ImeViewSource } from './ImeViewModel';
import { ImeViewPublisher } from './ImeViewPublisher';

export interface ImeCandidateSource {
  getEpoch: () => number;
  usesEnglishComposition: () => boolean;
  getCandidateView: () => CandidateLabel[];
  getCandidateRevision: () => number;
}
export interface ImeJapaneseViewSource {
  getConversionReading: () => string;
  getCursorPreview: () => string;
  getLastLens: () => string;
  getSelIdx: () => number;
}

/** Gather engine display inputs without dispatching any editor operation. */
export class ImePresentation {
  private coordinator: ImeCandidateSource;
  private prediction: EnglishPrediction;
  private japanese: ImeJapaneseViewSource;
  private publisher: ImeViewPublisher;
  constructor(coordinator: ImeCandidateSource, prediction: EnglishPrediction,
    japanese: ImeJapaneseViewSource, publisher: ImeViewPublisher) {
    this.coordinator = coordinator;
    this.prediction = prediction;
    this.japanese = japanese;
    this.publisher = publisher;
  }
  publish(snapshot: ImeSnapshot, epoch: number = this.coordinator.getEpoch()): boolean {
    if (epoch !== this.coordinator.getEpoch()) { return false; }
    const englishComposition: boolean = this.coordinator.usesEnglishComposition();
    const directEnglish: boolean = snapshot.mode === 'EN' && !englishComposition;
    const diagnostics: CandidateLabel[] = this.coordinator.getCandidateView();
    const source: ImeViewSource = {
      englishComposition: englishComposition,
      englishPrefixLength: this.prediction.getPrefix().length,
      candidates: directEnglish ? this.prediction.getItems() : diagnostics,
      candidateRevision: directEnglish ? this.prediction.getRevision() : this.coordinator.getCandidateRevision(),
      conversionReading: this.japanese.getConversionReading(),
      cursorPreview: this.japanese.getCursorPreview(),
      nativeCandidateLengths: this.japanese.getLastLens(),
      diagnosticCandidates: diagnostics,
      selectedIndex: snapshot.mode === 'EN' ? this.prediction.getSelectedIndex() : this.japanese.getSelIdx()
    };
    this.publisher.publish(snapshot, source);
    return true;
  }
  getCandidates(mode: string): CandidateLabel[] {
    try {
      return mode === 'EN' && !this.coordinator.usesEnglishComposition() ?
        this.prediction.getItems() : this.coordinator.getCandidateView();
    } catch (error) { return []; }
  }
  getCandidateLabelAt(index: number): string {
    try { return this.coordinator.getCandidateView()[index]?.label ?? ''; }
    catch (error) { return ''; }
  }
  getCandidateIdAt(index: number): number {
    try { return this.coordinator.getCandidateView()[index]?.id ?? -1; }
    catch (error) { return -1; }
  }
  getCandidateSlotCount(): number {
    try { return Math.min(this.coordinator.getCandidateView().length, 20); }
    catch (error) { return 0; }
  }
  getCandidateIds(): string {
    try { return this.coordinator.getCandidateView().map((item: CandidateLabel) => item.id.toString()).join(','); }
    catch (error) { return ''; }
  }
  getCandidateLens2(): string {
    try {
      const items: CandidateLabel[] = this.coordinator.getCandidateView();
      return `${items.length}:${items.map((item: CandidateLabel) => item.label.length.toString()).join(',')}`;
    } catch (error) { return 'e'; }
  }
}
