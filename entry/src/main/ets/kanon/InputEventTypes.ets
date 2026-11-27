/** SDK-free input protocol. UiEvent is untrusted until the queue validates it. */
export type UiEventKind = 'text' | 'kana' | 'modifyKana' | 'replaceToggle' | 'paste' | 'backspace' | 'convert' |
  'compositionArrow' | 'compositionCursor' | 'submit' | 'enter' | 'cancel' | 'move' | 'selectMove' | 'selectEdge' |
  'selectAll' | 'forwardDelete' | 'select' | 'deleteCandidate' | 'partial' | 'reset' | 'mode' | 'undo' | 'undoCompletion' |
  'suggest';
export type EditorEdge = 'begin' | 'end';
export type EditorDirection = 'left' | 'right' | 'up' | 'down';
export type KanaModifier = 'cycle' | 'voiced' | 'size' | 'semiVoiced';

export interface UiEvent {
  kind: UiEventKind;
  text?: string;
  previous?: string;
  candidateId?: number;
  expectedRevision?: number;
  direction?: EditorDirection;
  edge?: EditorEdge;
  /** compositionCursor: relative UTF-16; undoCompletion and direct replaceToggle: document UTF-16. */
  cursor?: number;
  prefixLength?: number;
}

export interface TextInputEvent extends UiEvent { kind: 'text' | 'kana' | 'paste'; text: string; }
export interface ModifyKanaInputEvent extends UiEvent { kind: 'modifyKana'; text?: KanaModifier; }
export interface ReplaceToggleEvent extends UiEvent { kind: 'replaceToggle'; text: string; previous: string; }
export interface CompositionArrowEvent extends UiEvent { kind: 'compositionArrow'; text: 'left' | 'right'; }
export interface CompositionCursorEvent extends UiEvent { kind: 'compositionCursor'; cursor: number; }
export interface ModeInputEvent extends UiEvent { kind: 'mode'; text: 'JP' | 'EN'; }
export interface CandidateInputEvent extends UiEvent {
  kind: 'select' | 'deleteCandidate'; candidateId: number; expectedRevision: number;
}
export interface PartialInputEvent extends UiEvent { kind: 'partial'; expectedRevision: number; }
export interface DirectionInputEvent extends UiEvent {
  kind: 'move' | 'selectMove'; direction: EditorDirection; edge?: undefined;
}
export interface EdgeInputEvent extends UiEvent { kind: 'move' | 'selectEdge'; edge: EditorEdge; direction?: undefined; }
export interface UndoCompletionEvent extends UiEvent {
  kind: 'undoCompletion'; text: string; cursor: number; prefixLength: number;
}
export interface SimpleInputEvent extends UiEvent {
  kind: 'backspace' | 'convert' | 'submit' | 'enter' | 'cancel' | 'suggest' |
    'selectAll' | 'forwardDelete' | 'reset' | 'undo';
}

/** Only validated events may reach the engines or internal editing methods. */
export type InputEvent = TextInputEvent | CompositionArrowEvent | CompositionCursorEvent | ModeInputEvent |
  CandidateInputEvent | PartialInputEvent | DirectionInputEvent | EdgeInputEvent | UndoCompletionEvent |
  ModifyKanaInputEvent | ReplaceToggleEvent | SimpleInputEvent;
