/** Selection notifications contain positions, not their origin or preview status. */
export interface EnglishSelectionContext {
  editing: boolean;
  undoCursor: number | undefined;
  hasPrefix: boolean;
  expectedCursor: number;
  hasCompositionCursor: boolean;
}

export interface EnglishSelectionDecision {
  collapsed: boolean;
  dropUndo: boolean;
  clearPrediction: boolean;
  abandonComposition: boolean;
}

/** Preserve the existing English policy. A mismatch is not proof of a user tap. */
export function evaluateEnglishSelection(begin: number, end: number,
  context: EnglishSelectionContext): EnglishSelectionDecision {
  const collapsed: boolean = begin === end;
  const mismatch: boolean = !collapsed || end !== context.expectedCursor;
  const clearPrediction: boolean = !context.editing &&
    (context.hasPrefix || context.hasCompositionCursor) && mismatch;
  return {
    collapsed: collapsed,
    dropUndo: !context.editing && context.undoCursor !== undefined &&
      (!collapsed || end !== context.undoCursor),
    clearPrediction: clearPrediction,
    abandonComposition: clearPrediction && context.hasCompositionCursor
  };
}
