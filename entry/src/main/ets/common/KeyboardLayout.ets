// All dimensions in this module are vp. Convert to px only at the IME panel boundary.
// The native phone keyboard uses narrower action columns than its three text columns.
export const FLICK_ACTION_COLUMN_WIDTH: string = '17%';
export const FLICK_KEY_GAP: number = 6;
export const FLICK_SIDE_PADDING: number = 8;
export const DEFAULT_KEYBOARD_HEIGHT_PERCENT: number = 100;
export const MIN_KEYBOARD_HEIGHT_PERCENT: number = 80;
export const MAX_KEYBOARD_HEIGHT_PERCENT: number = 150;

export function keyboardHeightPercent(value: number): number {
  if (!Number.isFinite(value)) { return DEFAULT_KEYBOARD_HEIGHT_PERCENT; }
  return clampSize(Math.round(value), MIN_KEYBOARD_HEIGHT_PERCENT, MAX_KEYBOARD_HEIGHT_PERCENT);
}

// Keep sub-percent motion during dragging; only the saved setting uses whole percentages.
export function keyboardHeightPreviewPercent(value: number): number {
  if (!Number.isFinite(value)) { return DEFAULT_KEYBOARD_HEIGHT_PERCENT; }
  return clampSize(Math.round(value * 10) / 10, MIN_KEYBOARD_HEIGHT_PERCENT, MAX_KEYBOARD_HEIGHT_PERCENT);
}

export function keyVisualScale(rowHeight: number): number {
  return clampSize(rowHeight / 54.25, 0.85, 1.2);
}

export function keyPreviewSize(rowHeight: number): number {
  return Math.round(56 * keyVisualScale(rowHeight));
}

export function clampSize(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, value));
}

export function toolbarHeight(fontScale: number): number {
  return Math.max(44, Math.ceil(24 * Math.max(1, fontScale) + 16));
}

export function standardKeyHeight(width: number, height: number): number {
  return width > height ? clampSize(height * 0.42, 160, 220) : clampSize(width * 0.6, 220, 300);
}

export function panelHeight(width: number, height: number, fontScale: number,
  heightPercent: number = DEFAULT_KEYBOARD_HEIGHT_PERCENT): number {
  const landscape: boolean = width > height;
  const standardKeys: number = standardKeyHeight(width, height);
  const keys: number = Math.max(landscape ? 160 : 176, standardKeys * keyboardHeightPreviewPercent(heightPercent) / 100);
  // Keep space for the editor; the available height takes precedence on small windows.
  const limit: number = Math.min(height * (landscape ? 0.55 : 0.48), Math.max(1, height - 96));
  return Math.max(1, Math.floor(Math.min(keys + toolbarHeight(fontScale), limit)));
}

export function clipboardColumns(width: number, fontScale: number): number {
  const minimum: number = 144 * Math.max(1, fontScale);
  return Math.max(1, Math.min(4, Math.floor((width + 8) / (minimum + 8))));
}
