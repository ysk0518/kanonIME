/*
 * Kanon IME: RealEditorPort (M4)
 * 実EditorAdapterシングルトンをCoordinatorのEditorPort面へ包む。
 * 結果の写像のみ。本文・候補は運ばない（REQ-07）。
 */

import { editorAdapter, EditorResult, EditorValue } from './EditorAdapter';
import { EditorPort, OpResult, TextReadResult } from './ImeCoordinator';

function toOp(r: EditorResult): OpResult {
  return { ok: r.ok, code: r.code };
}

class RealEditorPort implements EditorPort {
  getEpoch(): number {
    return editorAdapter.getEpoch();
  }

  hasSelection(): boolean {
    return editorAdapter.hasSelection();
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

  async deleteBackward(length: number): Promise<OpResult> {
    return toOp(await editorAdapter.deleteBackward(length));
  }

  async moveCursor(direction: number): Promise<OpResult> {
    return toOp(await editorAdapter.moveCursor(direction));
  }


  async selectByMovement(direction: number): Promise<OpResult> {
    return toOp(await editorAdapter.selectByMovement(direction));
  }

  async selectAll(): Promise<OpResult> {
    return toOp(await editorAdapter.selectAll());
  }

  async selectRange(start: number, end: number): Promise<OpResult> {
    return toOp(await editorAdapter.selectRange(start, end));
  }

  async previewCaret(position: number): Promise<OpResult> {
    const result: EditorResult = await editorAdapter.previewCaret(position);
    if (!result.ok) { return toOp(result); }
    return { ok: result.detail === 'matched=true', code: result.detail === 'matched=true' ? 0 : -7 };
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
      const v = await editorAdapter.queryForward(length);
      if (!v.ok || v.value === undefined) {
        return '';
      }
      return v.value;
    } catch (e) {
      return '';
    }
  }

  async queryBeforeResult(length: number): Promise<TextReadResult> {
    const result: EditorValue<string> = await editorAdapter.queryForward(length);
    return { ok: result.ok, code: result.code, value: result.value };
  }
}

export const realEditorPort: RealEditorPort = new RealEditorPort();
