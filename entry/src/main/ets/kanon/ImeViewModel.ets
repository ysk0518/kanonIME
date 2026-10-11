import { CandidateLabel, ImeSnapshot, ImeUiState } from './ImeCoordinator';

/** Display inputs gathered at the composition root; no UI/global access. */
export interface ImeViewSource {
  englishComposition: boolean;
  englishPrefixLength: number;
  candidates: CandidateLabel[];
  candidateRevision: number;
  conversionReading: string;
  cursorPreview: string;
  nativeCandidateLengths: string;
  diagnosticCandidates: CandidateLabel[];
  selectedIndex: number;
}

/** Text fields are transient display data and must not be logged or persisted. */
export interface ImeViewModel {
  tick: number;
  mode: string;
  state: ImeUiState;
  japaneseComposing: boolean;
  englishComposing: boolean;
  conversionReading: string;
  compositionCursor: string;
  error: string;
  needsRecovery: boolean;
  candidateCount: number;
  candidateRevision: number;
  labels: string[];
  ids: number[];
  nativeCandidateLengths: string;
  diagnosticIds: string;
  diagnosticLengths: string;
  segmentCount: number;
  selectedIndex: number;
}

export function createImeViewModel(snapshot: ImeSnapshot, source: ImeViewSource, tick: number): ImeViewModel {
  const directEnglish: boolean = snapshot.mode === 'EN' && !source.englishComposition;
  const labels: string[] = [];
  const ids: number[] = [];
  for (let i: number = 0; i < source.candidates.length && i < 20; i++) {
    labels.push(source.candidates[i].label);
    ids.push(source.candidates[i].id);
  }
  const diagnosticIds: string[] = [];
  const diagnosticLengths: string[] = [];
  for (const item of source.diagnosticCandidates) {
    diagnosticIds.push(item.id.toString());
    diagnosticLengths.push(item.label.length.toString());
  }
  return {
    tick: tick, mode: snapshot.mode, state: snapshot.state,
    japaneseComposing: snapshot.mode === 'JP' && snapshot.preeditLen > 0,
    englishComposing: snapshot.mode === 'EN' && (source.englishComposition ?
      snapshot.preeditLen > 0 : source.englishPrefixLength > 0),
    conversionReading: snapshot.mode === 'JP' ? source.conversionReading : '',
    compositionCursor: snapshot.mode === 'JP' && snapshot.preeditLen > 0 ? source.cursorPreview : '',
    error: snapshot.lastError, needsRecovery: snapshot.needsRecovery,
    candidateCount: directEnglish ? source.candidates.length : snapshot.candidateCount,
    candidateRevision: source.candidateRevision, labels: labels, ids: ids,
    nativeCandidateLengths: source.nativeCandidateLengths,
    diagnosticIds: diagnosticIds.join(','),
    diagnosticLengths: `${source.diagnosticCandidates.length}:${diagnosticLengths.join(',')}`,
    segmentCount: snapshot.segCount, selectedIndex: source.selectedIndex
  };
}
