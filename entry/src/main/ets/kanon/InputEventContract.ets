import { EditorDirection, EditorEdge, InputEvent, UiEvent, UiEventKind } from './InputEventTypes';

/** Assemble once; validation is performed at the Coordinator boundary. */
export function createInputEvent(kind: UiEventKind, text?: string, candidateId?: number,
  expectedRevision?: number, direction?: EditorDirection, edge?: EditorEdge): UiEvent {
  const event: UiEvent = { kind: kind };
  if (text !== undefined) { event.text = text; }
  if (candidateId !== undefined) { event.candidateId = candidateId; }
  if (expectedRevision !== undefined) { event.expectedRevision = expectedRevision; }
  if (direction !== undefined) { event.direction = direction; }
  if (edge !== undefined) { event.edge = edge; }
  return event;
}

function integer(value: number | undefined): boolean {
  return value !== undefined && Number.isSafeInteger(value);
}

function nonnegativeInteger(value: number | undefined): boolean {
  return integer(value) && (value as number) >= 0;
}

function validDirection(value: EditorDirection | undefined): boolean {
  return value === 'left' || value === 'right' || value === 'up' || value === 'down';
}

/** No editor text in errors; rejects malformed operations before any side effect. */
export function validInputEvent(event: UiEvent): boolean {
  switch (event.kind) {
    case 'text': case 'kana': case 'paste':
      return typeof event.text === 'string';
    case 'compositionArrow':
      return event.text === 'left' || event.text === 'right';
    case 'compositionCursor':
      return nonnegativeInteger(event.cursor);
    case 'mode':
      return event.text === 'JP' || event.text === 'EN';
    case 'select':
      return integer(event.candidateId) && nonnegativeInteger(event.expectedRevision);
    case 'partial':
      return nonnegativeInteger(event.expectedRevision);
    case 'selectMove':
      return validDirection(event.direction) && event.edge === undefined;
    case 'selectEdge':
      return (event.edge === 'begin' || event.edge === 'end') && event.direction === undefined;
    case 'move':
      return event.edge !== undefined ?
        (event.edge === 'begin' || event.edge === 'end') && event.direction === undefined : validDirection(event.direction);
    case 'undoCompletion':
      return typeof event.text === 'string' && event.text.length > 0 &&
        nonnegativeInteger(event.cursor) && nonnegativeInteger(event.prefixLength) &&
        (event.prefixLength as number) <= event.text.length;
    case 'modifyKana': case 'backspace': case 'convert': case 'submit': case 'enter':
    case 'cancel': case 'selectAll': case 'forwardDelete': case 'reset':
      return true;
    default:
      return false;
  }
}

/** Validate and detach caller-owned data before any asynchronous side effect. */
export function decodeInputEvent(request: UiEvent): InputEvent | undefined {
  if (!validInputEvent(request)) { return undefined; }
  const copy: UiEvent = createInputEvent(request.kind, request.text, request.candidateId,
    request.expectedRevision, request.direction, request.edge);
  if (request.cursor !== undefined) { copy.cursor = request.cursor; }
  if (request.prefixLength !== undefined) { copy.prefixLength = request.prefixLength; }
  // The only assertion from the untrusted shape to the required-payload protocol.
  return copy as InputEvent;
}

/** Resolve after entering the serial queue, using its current composition. */
export function resolveInputMovement(event: UiEvent, mode: string, preeditLength: number): UiEvent {
  if (event.kind === 'move' && event.edge === undefined && mode === 'JP' && preeditLength > 0 &&
    (event.direction === 'left' || event.direction === 'right')) {
    return { kind: 'compositionArrow', text: event.direction };
  }
  return event;
}
