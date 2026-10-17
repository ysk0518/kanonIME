/*
 * Kanon IME: EditorAdapter (M1/G-01)
 * SPEC KANON_SPEC.md §5/§6: 入力先への書き込みは本ファイルへ閉じ込める。
 * - REQ-05: 全操作を単一キューで直列化し、await なしの並列発行をしない。
 * - REQ-06: 失敗時の自動再送をしない。成否とエラーコードを呼び出し側へ返す。
 * - REQ-07: 入力内容・周辺本文・候補をログへ出さない。ログは操作名・長さ・符号のみ。
 */

import inputMethodEngine from '@ohos.inputMethodEngine';
import { BusinessError } from '@ohos.base';
import Log from '../model/Log';
import { EditorOperationQueue, EditorOperationRuntime, EditorOperationEvent, EditorResult, EditorValue, EDITOR_STALE_EPOCH } from './EditorOperationQueue';
import { PreviewSelectionReceipt, PreviewSelectionWait, writePreviewWithReceipt } from './PreviewSelectionReceipt';
import { PreviewCaretPlacement, PreviewCaretPort } from './PreviewCaretPlacement';
export { EditorResult, EditorValue } from './EditorOperationQueue';

const TAG: string = 'KanonEditor->';

export interface AttributeSnapshot {
  inputPattern: number;
  enterKeyType: number;
  isTextPreviewSupported: boolean;
}

function errCode(err: Error | undefined): number {
  if (err === undefined || err === null) {
    return -2;
  }
  const code: number = (err as BusinessError).code;
  return typeof code === 'number' && Number.isFinite(code) ? code : -2;
}

export class EditorAdapter {
  private previewSelection: PreviewSelectionReceipt = new PreviewSelectionReceipt();
  private previewCaretPlacement: PreviewCaretPlacement = new PreviewCaretPlacement();
  private operationRuntime: EditorOperationRuntime = {
    schedule: (callback: () => void, delayMs: number): number => setTimeout(callback, delayMs),
    unschedule: (timer: number): void => { clearTimeout(timer); },
    errorCode: errCode,
    log: (op: string, event: EditorOperationEvent, detail: string): void => {
      if (op === 'setPreview' && event === 'timeout') { this.previewSelection.cancel(); }
      if (op === 'previewCaret' && event === 'timeout') {
        this.previewCaretPlacement.cancel();
        this.previewSelection.cancel();
      }
      Log.showInfo(TAG, `kanon: ${op} ${event}${detail.length > 0 ? ' ' + detail : ''}`);
    }
  };
  private operations: EditorOperationQueue<inputMethodEngine.InputClient> =
    new EditorOperationQueue<inputMethodEngine.InputClient>(this.operationRuntime);
  private selectionStart: number = -1;
  private selectionEnd: number = -1;

  attach(client: inputMethodEngine.InputClient): number {
    this.previewSelection.cancel();
    this.previewCaretPlacement.cancel();
    const epoch: number = this.operations.attach(client);
    this.selectionStart = -1;
    this.selectionEnd = -1;
    Log.showInfo(TAG, `kanon: attach epoch=${epoch}`);
    return epoch;
  }

  detach(): number {
    this.previewSelection.cancel();
    this.previewCaretPlacement.cancel();
    const epoch: number = this.operations.detach();
    this.selectionStart = -1;
    this.selectionEnd = -1;
    Log.showInfo(TAG, `kanon: detach epoch=${epoch}`);
    return epoch;
  }

  getEpoch(): number {
    return this.operations.getEpoch();
  }

  updateSelection(start: number, end: number): void {
    this.selectionStart = start;
    this.selectionEnd = end;
    this.previewSelection.observe(this.getEpoch(), start, end);
  }

  hasSelection(): boolean {
    return this.selectionStart >= 0 && this.selectionEnd >= 0 && this.selectionStart !== this.selectionEnd;
  }

  private enqueue(op: string, fn: (client: inputMethodEngine.InputClient) => Promise<string | null>): Promise<EditorResult> {
    return this.operations.enqueue(op, fn);
  }

  fetchAttribute(): Promise<EditorResult> {
    return this.enqueue('attr', async (client: inputMethodEngine.InputClient): Promise<string> => {
      const attr: inputMethodEngine.EditorAttribute = await client.getEditorAttribute();
      const snap: AttributeSnapshot = {
        inputPattern: attr.inputPattern,
        enterKeyType: attr.enterKeyType,
        isTextPreviewSupported: attr.isTextPreviewSupported
      };
      return `pattern=${snap.inputPattern} enter=${snap.enterKeyType} preview=${snap.isTextPreviewSupported}`;
    });
  }

  setPreview(text: string, start: number, end: number, observedEnd?: number): Promise<EditorResult> {
    const len: number = text.length;
    return this.enqueue('setPreview', async (client: inputMethodEngine.InputClient): Promise<string | null> => {
      // (-1,-1) is the documented range for replacing or clearing the entire preview.
      // A nonnegative range addresses positions inside the preview, not document coordinates.
      const range: inputMethodEngine.Range = { start: start, end: end };
      const wait: PreviewSelectionWait | undefined = observedEnd === undefined ? undefined :
        this.previewSelection.arm(this.getEpoch(), observedEnd);
      const observed: boolean = await writePreviewWithReceipt(
        (): Promise<void> => client.setPreviewText(text, range), wait);
      if (!observed) { return null; }
      return `len=${len} range=[${start},${end}]`;
    });
  }

  finishPreview(): Promise<EditorResult> {
    return this.enqueue('finishPreview', async (client: inputMethodEngine.InputClient): Promise<string> => {
      await client.finishTextPreview();
      return 'done';
    });
  }

  insert(text: string): Promise<EditorResult> {
    const len: number = text.length;
    return this.enqueue('insert', async (client: inputMethodEngine.InputClient): Promise<string | null> => {
      const inserted: boolean = await client.insertText(text);
      return inserted ? `len=${len}` : null;
    });
  }

  /**
   * G-01実証済み: 名称と逆方向に作用する。deleteBackward(n)=カーソル右をn文字、
   * deleteForward(n)=カーソル左をn文字。BackspaceにはdeleteForwardを使うこと（M3）。
   * nの単位は文字（サロゲートペアは分割されず1文字として消えることを確認）。
   */
  deleteBackward(length: number): Promise<EditorResult> {
    return this.enqueue('deleteBackward', async (client: inputMethodEngine.InputClient): Promise<string | null> => {
      const deleted: boolean = await client.deleteBackward(length);
      return deleted ? `len=${length}` : null;
    });
  }

  /** G-01実証済み: カーソル左をn文字削除（Backspace用）。単位は文字。カーソル位置はUTF-16単位。 */
  deleteForward(length: number): Promise<EditorResult> {
    return this.enqueue('deleteForward', async (client: inputMethodEngine.InputClient): Promise<string | null> => {
      const deleted: boolean = await client.deleteForward(length);
      return deleted ? `len=${length}` : null;
    });
  }

  moveCursor(direction: number): Promise<EditorResult> {
    return this.enqueue('moveCursor', async (client: inputMethodEngine.InputClient): Promise<string> => {
      await client.moveCursor(direction);
      return `dir=${direction}`;
    });
  }

  selectByMovement(direction: number): Promise<EditorResult> {
    return this.enqueue('selectByMovement', async (client: inputMethodEngine.InputClient): Promise<string> => {
      await client.selectByMovement({ direction: direction });
      return `dir=${direction}`;
    });
  }

  selectAll(): Promise<EditorResult> {
    return this.enqueue('selectAll', async (client: inputMethodEngine.InputClient): Promise<string> => {
      await client.sendExtendAction(inputMethodEngine.ExtendAction.SELECT_ALL);
      return 'done';
    });
  }

  sendEnterAction(enterKeyType: number): Promise<EditorResult> {
    return this.enqueue('sendKeyFunction', async (client: inputMethodEngine.InputClient): Promise<string> => {
      await client.sendKeyFunction(enterKeyType);
      return `enter=${enterKeyType}`;
    });
  }

  cursorIndex(): Promise<EditorResult> {
    return this.enqueue('cursorIndex', async (client: inputMethodEngine.InputClient): Promise<string> => {
      const index: number = await client.getTextIndexAtCursor();
      return `index=${index}`;
    });
  }

  selectRange(start: number, end: number): Promise<EditorResult> {
    return this.enqueue('selectRange', async (client: inputMethodEngine.InputClient): Promise<string> => {
      await client.selectByRange({ start: start, end: end });
      return `range=[${start},${end}]`;
    });
  }

  previewCaret(position: number, previewStart: number, previewText: string): Promise<EditorResult> {
    return this.enqueue('previewCaret', async (client: inputMethodEngine.InputClient): Promise<string> => {
      const port: PreviewCaretPort = {
        getEpoch: (): number => this.getEpoch(),
        queryCursor: (): Promise<number> => client.getTextIndexAtCursor(),
        moveCursor: async (direction: number, expectedPosition: number): Promise<void> => {
          const wait: PreviewSelectionWait = this.previewSelection.arm(this.getEpoch(), expectedPosition);
          // A reply can precede the selection notification in container clients.
          await writePreviewWithReceipt((): Promise<void> => client.moveCursor(direction < 0 ?
            inputMethodEngine.Direction.CURSOR_LEFT : inputMethodEngine.Direction.CURSOR_RIGHT), wait);
        }
      };
      const matched: boolean = await this.previewCaretPlacement.place(port,
        { text: previewText, start: previewStart, position: position });
      return `matched=${matched}`;
    });
  }

  private enqueueValue<T>(op: string, fn: (client: inputMethodEngine.InputClient) => Promise<T>): Promise<EditorValue<T>> {
    return this.operations.enqueueValue(op, fn);
  }

  queryAttribute(): Promise<EditorValue<AttributeSnapshot>> {
    return this.enqueueValue('qAttr', async (client: inputMethodEngine.InputClient): Promise<AttributeSnapshot> => {
      const attr: inputMethodEngine.EditorAttribute = await client.getEditorAttribute();
      return {
        inputPattern: attr.inputPattern,
        enterKeyType: attr.enterKeyType,
        isTextPreviewSupported: attr.isTextPreviewSupported
      };
    });
  }

  queryIndex(): Promise<EditorValue<number>> {
    return this.enqueueValue('qIndex', async (client: inputMethodEngine.InputClient): Promise<number> => {
      return await client.getTextIndexAtCursor();
    });
  }

  queryForward(length: number): Promise<EditorValue<string>> {
    return this.enqueueValue('qForward', async (client: inputMethodEngine.InputClient): Promise<string> => {
      return await client.getForward(length);
    });
  }

  /** An empty notification or position zero alone does not prove an empty field. */
  async queryEmpty(): Promise<EditorValue<boolean>> {
    const epoch: number = this.getEpoch();
    // Surrounding-text APIs can exclude selected text. Selecting the entire
    // field must not be mistaken for an empty field.
    if (this.hasSelection()) { return { ok: true, code: 0, value: false }; }
    // Each SDK call has its own queue result. A timed-out read must never
    // resume later and start another SDK call after this probe has returned.
    const first: EditorValue<number> = await this.queryIndex();
    if (epoch !== this.getEpoch()) { return { ok: false, code: EDITOR_STALE_EPOCH, value: undefined }; }
    if (!first.ok || first.value === undefined) { return { ok: false, code: first.code, value: undefined }; }
    if (first.value !== 0) { return { ok: true, code: 0, value: false }; }
    const before: EditorValue<string> = await this.queryForward(1);
    if (epoch !== this.getEpoch()) { return { ok: false, code: EDITOR_STALE_EPOCH, value: undefined }; }
    if (!before.ok || before.value === undefined) { return { ok: false, code: before.code, value: undefined }; }
    if (before.value.length !== 0) { return { ok: true, code: 0, value: false }; }
    const after: EditorValue<string> = await this.enqueueValue('qBackward',
      (client: inputMethodEngine.InputClient): Promise<string> => client.getBackward(1));
    if (epoch !== this.getEpoch()) { return { ok: false, code: EDITOR_STALE_EPOCH, value: undefined }; }
    if (!after.ok || after.value === undefined) { return { ok: false, code: after.code, value: undefined }; }
    if (after.value.length !== 0) { return { ok: true, code: 0, value: false }; }
    const last: EditorValue<number> = await this.queryIndex();
    if (epoch !== this.getEpoch()) { return { ok: false, code: EDITOR_STALE_EPOCH, value: undefined }; }
    return { ok: last.ok, code: last.code,
      value: last.value === undefined ? undefined : last.value === 0 && !this.hasSelection() };
  }

}

export const editorAdapter: EditorAdapter = new EditorAdapter();
