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

const TAG: string = 'KanonEditor->';

/** 操作タイムアウト。枠組み側のpromiseが返らない場合の固まり防止（REQ-05/06）。再送はしない。 */
const OP_TIMEOUT_MS: number = 3000;
/** クライアント不在時は -1、タイムアウトは -3。 */
const CODE_NO_CLIENT: number = -1;
const CODE_TIMEOUT: number = -3;
const CODE_UNRESOLVED_WRITE: number = -6;

export interface EditorResult {
  op: string;
  ok: boolean;
  /** 0=成功。失敗時は BusinessError.code。クライアント不在時は -1。 */
  code: number;
  /** 長さ・件数・真偽のみ。本文を含めない。 */
  detail: string;
}

export interface AttributeSnapshot {
  inputPattern: number;
  enterKeyType: number;
  isTextPreviewSupported: boolean;
}

/** 読み取り系の構造化結果。本文の比較は呼び出し側がメモリ内で行い、表示・ログへ出さない。 */
export interface EditorValue<T> {
  ok: boolean;
  code: number;
  value: T | undefined;
}

function errCode(err: BusinessError | undefined): number {
  if (err === undefined || err === null) {
    return -2;
  }
  return err.code;
}

export class EditorAdapter {
  private client: inputMethodEngine.InputClient | undefined = undefined;
  private queue: Promise<void> = Promise.resolve();
  private editorEpoch: number = 0;
  private unresolvedWriteEpoch: number = -1;
  private selectionStart: number = -1;
  private selectionEnd: number = -1;

  attach(client: inputMethodEngine.InputClient): number {
    this.client = client;
    this.editorEpoch++;
    this.unresolvedWriteEpoch = -1;
    this.selectionStart = -1;
    this.selectionEnd = -1;
    // 旧世代の未解決操作は破棄する（REQ-02）。固まったキューもここで切り直す。
    this.queue = Promise.resolve();
    Log.showInfo(TAG, `kanon: attach epoch=${this.editorEpoch}`);
    return this.editorEpoch;
  }

  detach(): number {
    this.client = undefined;
    this.editorEpoch++;
    this.unresolvedWriteEpoch = -1;
    this.selectionStart = -1;
    this.selectionEnd = -1;
    Log.showInfo(TAG, `kanon: detach epoch=${this.editorEpoch}`);
    return this.editorEpoch;
  }

  getEpoch(): number {
    return this.editorEpoch;
  }

  updateSelection(start: number, end: number): void {
    this.selectionStart = start;
    this.selectionEnd = end;
  }

  hasSelection(): boolean {
    return this.selectionStart >= 0 && this.selectionEnd >= 0 && this.selectionStart !== this.selectionEnd;
  }

  private withTimeout<T>(op: string, p: Promise<T>, onTimeout?: () => void): Promise<T | undefined> {
    return new Promise<T | undefined>((resolve: (v: T | undefined) => void, reject: (e: BusinessError) => void) => {
      const timerId: number = setTimeout((): void => {
        Log.showInfo(TAG, `kanon: ${op} timeout`);
        if (onTimeout !== undefined) { onTimeout(); }
        resolve(undefined);
      }, OP_TIMEOUT_MS);
      p.then((v: T): void => {
        clearTimeout(timerId);
        resolve(v);
      }).catch((e: BusinessError): void => {
        clearTimeout(timerId);
        reject(e);
      });
    });
  }

  private enqueue(op: string, fn: (client: inputMethodEngine.InputClient) => Promise<string | null>): Promise<EditorResult> {
    const epoch: number = this.editorEpoch;
    const run: Promise<EditorResult> = this.queue.then(async (): Promise<EditorResult> => {
      if (epoch !== this.editorEpoch) { return { op: op, ok: false, code: -4, detail: 'stale-epoch' }; }
      if (this.unresolvedWriteEpoch === epoch) {
        return { op: op, ok: false, code: CODE_UNRESOLVED_WRITE, detail: 'unresolved-write' };
      }
      const client: inputMethodEngine.InputClient | undefined = this.client;
      if (client === undefined) {
        Log.showInfo(TAG, `kanon: ${op} no-client`);
        return { op: op, ok: false, code: CODE_NO_CLIENT, detail: 'no-client' };
      }
      try {
        const pending: Promise<string | null> = fn(client);
        const raced: string | null | undefined = await this.withTimeout<string | null>(op, pending, (): void => {
          if (epoch !== this.editorEpoch) { return; }
          this.unresolvedWriteEpoch = epoch;
          pending.then((): void => {
            if (this.unresolvedWriteEpoch === epoch) { this.unresolvedWriteEpoch = -1; }
          }).catch((): void => {
            if (this.unresolvedWriteEpoch === epoch) { this.unresolvedWriteEpoch = -1; }
          });
        });
        if (raced === undefined) {
          return { op: op, ok: false, code: CODE_TIMEOUT, detail: 'timeout' };
        }
        if (raced === null) {
          Log.showInfo(TAG, `kanon: ${op} rejected`);
          return { op: op, ok: false, code: -5, detail: 'rejected' };
        }
        const detail: string = raced;
        Log.showInfo(TAG, `kanon: ${op} ok ${detail}`);
        return { op: op, ok: true, code: 0, detail: detail };
      } catch (err) {
        const code: number = errCode(err);
        Log.showInfo(TAG, `kanon: ${op} fail code=${code}`);
        return { op: op, ok: false, code: code, detail: `code=${code}` };
      }
    });
    // 後続操作が止まらないよう、キュー自体は常に解決させる。
    this.queue = run.then((): void => undefined).catch((): void => undefined);
    return run;
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

  setPreview(text: string, start: number, end: number): Promise<EditorResult> {
    const len: number = text.length;
    return this.enqueue('setPreview', async (client: inputMethodEngine.InputClient): Promise<string> => {
      // (-1,-1) is the documented range for replacing or clearing the entire preview.
      // A nonnegative range addresses positions inside the preview, not document coordinates.
      const range: inputMethodEngine.Range = { start: start, end: end };
      await client.setPreviewText(text, range);
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

  private enqueueValue<T>(op: string, fn: (client: inputMethodEngine.InputClient) => Promise<T>): Promise<EditorValue<T>> {
    const epoch: number = this.editorEpoch;
    const run: Promise<EditorValue<T>> = this.queue.then(async (): Promise<EditorValue<T>> => {
      if (epoch !== this.editorEpoch) { return { ok: false, code: -4, value: undefined }; }
      if (this.unresolvedWriteEpoch === epoch) {
        return { ok: false, code: CODE_UNRESOLVED_WRITE, value: undefined };
      }
      const client: inputMethodEngine.InputClient | undefined = this.client;
      if (client === undefined) {
        Log.showInfo(TAG, `kanon: ${op} no-client`);
        return { ok: false, code: -1, value: undefined };
      }
      try {
        const raced: T | undefined = await this.withTimeout<T>(op, fn(client));
        if (raced === undefined) {
          return { ok: false, code: CODE_TIMEOUT, value: undefined };
        }
        const value: T = raced;
        Log.showInfo(TAG, `kanon: ${op} ok`);
        return { ok: true, code: 0, value: value };
      } catch (err) {
        const code: number = errCode(err);
        Log.showInfo(TAG, `kanon: ${op} fail code=${code}`);
        return { ok: false, code: code, value: undefined };
      }
    });
    this.queue = run.then((): void => undefined).catch((): void => undefined);
    return run;
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

}

export const editorAdapter: EditorAdapter = new EditorAdapter();
