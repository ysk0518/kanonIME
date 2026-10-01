// All dimensions in this module are vp. Convert to px only at the IME panel boundary.
// The native phone keyboard uses narrower action columns than its three text columns.
export const FLICK_ACTION_COLUMN_WIDTH: string = '17%';
export const FLICK_KEY_GAP: number = 6;
export const FLICK_SIDE_PADDING: number = 8;

export function clampSize(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, value));
}

export function toolbarHeight(fontScale: number): number {
  return Math.max(44, Math.ceil(24 * Math.max(1, fontScale) + 16));
}

export function panelHeight(width: number, height: number, fontScale: number): number {
  const landscape: boolean = width > height;
  const keys: number = landscape ? clampSize(height * 0.42, 160, 220) : clampSize(width * 0.6, 220, 300);
  // Keep space for the editor; the available height takes precedence on small windows.
  const limit: number = Math.min(height * (landscape ? 0.55 : 0.48), Math.max(1, height - 96));
  return Math.max(1, Math.floor(Math.min(keys + toolbarHeight(fontScale), limit)));
}

export function clipboardColumns(width: number, fontScale: number): number {
  const minimum: number = 144 * Math.max(1, fontScale);
  return Math.max(1, Math.min(4, Math.floor((width + 8) / (minimum + 8))));
}
