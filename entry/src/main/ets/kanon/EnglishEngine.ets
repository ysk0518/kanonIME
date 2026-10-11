import { CandidateLabel, CommitEffect, EnginePort, EngineUpdate } from './ImeCoordinator';
import { InputEvent, TextInputEvent } from './InputEventTypes';
import { EnglishPrediction } from './EnglishPrediction';

/** English composition shares the Coordinator's preview and commit effects with Japanese. */
export class EnglishEngine implements EnginePort {
  private prediction: EnglishPrediction;
  constructor(prediction: EnglishPrediction) { this.prediction = prediction; }
  private buffer: string = '';
  private revision: number = 0;

  getTypedText(): string { return this.buffer; }
  getPreedit(): string {
    const selected: CandidateLabel | undefined = this.prediction.getSelectedItem();
    const prefix: string = this.prediction.getPrefix();
    return selected === undefined || prefix.length === 0 ? this.buffer :
      this.buffer.substring(0, this.buffer.length - prefix.length) + selected.label;
  }

  resetLocal(): void {
    this.buffer = '';
    this.prediction.clear();
    this.prediction.takeCompositionAbandoned();
    this.revision = 0;
  }

  async dispatch(sessionId: string, editorEpoch: number, sequence: number, event: InputEvent): Promise<EngineUpdate> {
    const effects: CommitEffect[] = [];
    let errorCode: number = 0;
    const kind: string = event.kind;
    if (kind === 'reset' || kind === 'cancel') {
      this.buffer = '';
      this.prediction.clear();
    } else if (kind === 'text') {
      this.buffer = this.getPreedit() + (event as TextInputEvent).text;
      this.prediction.updateComposition(this.buffer);
    } else if (kind === 'backspace') {
      if (this.prediction.getSelectedIndex() >= 0) {
        this.prediction.updateComposition(this.buffer);
      } else {
        const last: number = this.buffer.charCodeAt(this.buffer.length - 1);
        const width: number = last >= 0xDC00 && last <= 0xDFFF && this.buffer.length > 1 ? 2 : 1;
        this.buffer = this.buffer.substring(0, Math.max(0, this.buffer.length - width));
        this.prediction.updateComposition(this.buffer);
      }
    } else if (kind === 'convert' && this.prediction.getItems().length > 0) {
      this.prediction.selectNext();
    } else if (kind === 'select' || kind === 'enter' || kind === 'submit' || kind === 'convert') {
      let text: string = this.getPreedit();
      if (kind === 'select') {
        const item: CandidateLabel | undefined = this.prediction.getItems().find(
          (candidate: CandidateLabel) => candidate.id === event.candidateId);
        if (item === undefined) { errorCode = 2; }
        else {
          text = this.buffer.substring(0, this.buffer.length - this.prediction.getPrefix().length) + item.label;
        }
      }
      if (kind === 'convert') { text += ' '; }
      if (errorCode === 0) {
        if (text.length > 0) { effects.push({ effectId: `en${sequence}`, text: text }); }
        this.buffer = '';
        this.prediction.clear();
      }
    }
    this.revision++;
    const preedit: string = this.getPreedit();
    const items: CandidateLabel[] = this.prediction.getItems();
    return {
      sessionId: sessionId, editorEpoch: editorEpoch, sequence: sequence, revision: this.revision,
      phase: preedit.length === 0 ? 'empty' : this.prediction.getSelectedIndex() >= 0 ? 'converting' : 'composing',
      consumed: errorCode === 0, hasPreedit: preedit.length > 0, preeditLen: preedit.length,
      caretUtf16: preedit.length, segCount: preedit.length > 0 ? 1 : 0,
      candidateCount: items.length, candidateRevision: this.revision, candidates: items,
      effects: effects, errorCode: errorCode, errorRecoverable: true
    };
  }
}
