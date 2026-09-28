/*
 * Kanon IME: RealEditorPort (M4)
 * 実EditorAdapterシングルトンをCoordinatorのEditorPort面へ包む。
 * 結果の写像のみ。本文・候補は運ばない（REQ-07）。
 */

import { editorAdapter, EditorResult } from './EditorAdapter';
import { EditorPort, OpResult } from './ImeCoordinator';

function toOp(r: EditorResult): OpResult {
  return { ok: r.ok, code: r.code };
}

class RealEditorPort implements EditorPort {
  getEpoch(): number {
    return editorAdapter.getEpoch();
  }

  async setPreview(text: string, start: number, end: number): Promise<OpResult> {
    return toOp(await editorAdapter.setPreview(text, start, end));
  }

  async finishPreview(): Promise<OpResult> {
    return toOp(await editorAdapter.finishPreview());
  }

  async insert(text: string): Promise<OpResult> {
    return toOp(await editorAdapter.insert(text));
  }

  async deleteForward(length: number): Promise<OpResult> {
    return toOp(await editorAdapter.deleteForward(length));
  }

  async moveCursor(direction: number): Promise<OpResult> {
    return toOp(await editorAdapter.moveCursor(direction));
  }

  async selectRange(start: number, end: number): Promise<OpResult> {
    return toOp(await editorAdapter.selectRange(start, end));
  }

  async queryPreviewSupported(): Promise<boolean> {
    try {
      const v = await editorAdapter.queryAttribute();
      if (!v.ok || v.value === undefined) {
        return false;
      }
      return v.value.isTextPreviewSupported;
    } catch (e) {
      return false;
    }
  }

  async queryCursor(): Promise<number> {
    try {
      const v = await editorAdapter.queryIndex();
      if (!v.ok || v.value === undefined) {
        return -1;
      }
      return v.value as number;
    } catch (e) {
      return -1;
    }
  }

  async queryBefore(length: number): Promise<string> {
    try {
      const v = await editorAdapter.queryAround(length, 0);
      if (!v.ok || v.value === undefined) {
        return '';
      }
      const before: string = (v.value as string[])[0];
      return before === undefined ? '' : before;
    } catch (e) {
      return '';
    }
  }
}

export const realEditorPort: RealEditorPort = new RealEditorPort();
