import { EditorDirection } from './InputEventTypes';

/** Values are supplied by the SDK boundary, never assumed by the core. */
export interface EditorDirectionValues { left: number; right: number; up: number; down: number; }

export function fromEditorDirection(value: number, sdk: EditorDirectionValues): EditorDirection | undefined {
  if (value === sdk.left) { return 'left'; }
  if (value === sdk.right) { return 'right'; }
  if (value === sdk.up) { return 'up'; }
  if (value === sdk.down) { return 'down'; }
  return undefined;
}

export function toEditorDirection(direction: EditorDirection, sdk: EditorDirectionValues): number | undefined {
  switch (direction) {
    case 'left': return sdk.left;
    case 'right': return sdk.right;
    case 'up': return sdk.up;
    case 'down': return sdk.down;
    default: return undefined;
  }
}
