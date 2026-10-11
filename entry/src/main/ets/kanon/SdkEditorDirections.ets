import inputMethodEngine from '@ohos.inputMethodEngine';
import { EditorDirectionValues } from './EditorDirectionMap';

export const SDK_EDITOR_DIRECTIONS: EditorDirectionValues = {
  left: inputMethodEngine.Direction.CURSOR_LEFT,
  right: inputMethodEngine.Direction.CURSOR_RIGHT,
  up: inputMethodEngine.Direction.CURSOR_UP,
  down: inputMethodEngine.Direction.CURSOR_DOWN
};
