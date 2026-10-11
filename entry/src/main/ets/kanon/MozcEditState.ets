import { CompositionPhase } from './ImeCoordinator';

type HistoryOwnership = 'replayable' | 'native';
type ConversionScope = 'all' | 'segment';

/** Editing policy only: preedit, candidates and cursor remain owned by Mozc. */
export class MozcEditState {
  private history: HistoryOwnership = 'replayable';
  private scope: ConversionScope = 'all';

  canReplay(): boolean { return this.history === 'replayable'; }

  scopesCandidate(phase: CompositionPhase): boolean {
    return phase === 'composing' || (this.scope === 'segment' && phase === 'converting');
  }

  reset(): void {
    this.history = 'replayable';
    this.scope = 'all';
  }

  afterInput(rebuiltConversion: boolean, committed: boolean, hasPreedit: boolean): void {
    if (rebuiltConversion || committed || !hasPreedit) { this.history = 'replayable'; }
    this.scope = 'all';
  }

  afterBackspace(hasPreedit: boolean): void {
    this.history = hasPreedit ? 'native' : 'replayable';
    this.scope = 'all';
  }

  afterArrow(phase: CompositionPhase): void {
    if (phase === 'converting') { this.scope = 'segment'; }
    else if (phase === 'composing') { this.history = 'native'; }
  }

  afterPartialCommit(hasPreedit: boolean): void {
    if (!hasPreedit) { this.reset(); return; }
    this.history = 'native';
    // Preserve a manually adjusted boundary for the remaining conversion.
  }
}
