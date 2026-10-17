import { panelHeight, toolbarHeight } from './KeyboardLayout';

export const DEFAULT_CANDIDATE_FONT_SIZE: number = 18;
export const DEFAULT_CANDIDATE_ROWS: number = 2;
export const MIN_CANDIDATE_FONT_SIZE: number = 14;
export const MAX_CANDIDATE_FONT_SIZE: number = 24;

export function candidateRowHeight(fontSize: number, fontScale: number): number {
  return Math.max(28, Math.ceil(fontSize * 1.2 * Math.max(1, fontScale) + 6));
}

export function candidateAreaHeight(toolbar: number, fontSize: number, rows: number, fontScale: number): number {
  // Preserve the toolbar's own height, without imposing it on every candidate row.
  return Math.max(toolbar, candidateRowHeight(fontSize, fontScale) * rows);
}

export function candidatePanelHeight(width: number, height: number, fontScale: number,
  percent: number, fontSize: number, rows: number): number {
  const toolbar: number = toolbarHeight(fontScale);
  const preferred: number = candidateAreaHeight(toolbar, fontSize, rows, fontScale);
  const total: number = panelHeight(width, height, fontScale, percent, preferred);
  if (rows === 2 && total - preferred < 160) {
    return panelHeight(width, height, fontScale, percent, candidateAreaHeight(toolbar, fontSize, 1, fontScale));
  }
  return total;
}
