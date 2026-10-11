/** SDK-independent ordering, input target generations and API deadlines. */
export const EDITOR_OPERATION_TIMEOUT_MS: number = 3000;
export const EDITOR_NO_CLIENT: number = -1;
export const EDITOR_TIMEOUT: number = -3;
export const EDITOR_STALE_EPOCH: number = -4;
export const EDITOR_REJECTED: number = -5;
export const EDITOR_UNRESOLVED_WRITE: number = -6;

export interface EditorResult {
  op: string;
  ok: boolean;
  code: number;
  /** Metadata only: never editor text or error messages. */
  detail: string;
}

export interface EditorValue<T> {
  ok: boolean;
  code: number;
  value: T | undefined;
}

export type EditorOperationEvent = 'timeout' | 'no-client' | 'rejected' | 'ok' | 'fail';

export interface EditorOperationRuntime {
  schedule: (callback: () => void, delayMs: number) => number;
  unschedule: (timer: number) => void;
  errorCode: (error: Error | undefined) => number;
  log: (op: string, event: EditorOperationEvent, detail: string) => void;
}

export class EditorOperationQueue<C> {
  private client: C | undefined = undefined;
  private queue: Promise<void> = Promise.resolve();
  private editorEpoch: number = 0;
  private unresolvedWriteEpoch: number = -1;
  private runtime: EditorOperationRuntime;

  constructor(runtime: EditorOperationRuntime) { this.runtime = runtime; }

  attach(client: C): number {
    this.client = client;
    this.editorEpoch++;
    this.unresolvedWriteEpoch = -1;
    // New input targets can proceed while an old platform promise is unresolved.
    this.queue = Promise.resolve();
    return this.editorEpoch;
  }

  detach(): number {
    this.client = undefined;
    this.editorEpoch++;
    this.unresolvedWriteEpoch = -1;
    return this.editorEpoch;
  }

  getEpoch(): number { return this.editorEpoch; }

  private current(epoch: number): boolean { return epoch === this.editorEpoch; }

  private withTimeout<T>(op: string, pending: Promise<T>, onTimeout?: () => void): Promise<T | undefined> {
    return new Promise<T | undefined>((resolve: (value: T | undefined) => void, reject: (error: Error) => void) => {
      let settled: boolean = false;
      const timer: number = this.runtime.schedule((): void => {
        if (settled) { return; }
        settled = true;
        this.runtime.log(op, 'timeout', '');
        if (onTimeout !== undefined) { onTimeout(); }
        resolve(undefined);
      }, EDITOR_OPERATION_TIMEOUT_MS);
      pending.then((value: T): void => {
        if (settled) { return; }
        settled = true;
        this.runtime.unschedule(timer);
        resolve(value);
      }).catch((error: Error): void => {
        if (settled) { return; }
        settled = true;
        this.runtime.unschedule(timer);
        reject(error);
      });
    });
  }

  /** Metadata operations retain the existing conservative write timeout guard. */
  enqueue(op: string, fn: (client: C) => Promise<string | null>): Promise<EditorResult> {
    const epoch: number = this.editorEpoch;
    const run: Promise<EditorResult> = this.queue.then(async (): Promise<EditorResult> => {
      if (epoch !== this.editorEpoch) { return { op: op, ok: false, code: EDITOR_STALE_EPOCH, detail: 'stale-epoch' }; }
      if (this.unresolvedWriteEpoch === epoch) {
        return { op: op, ok: false, code: EDITOR_UNRESOLVED_WRITE, detail: 'unresolved-write' };
      }
      const client: C | undefined = this.client;
      if (client === undefined) {
        this.runtime.log(op, 'no-client', '');
        return { op: op, ok: false, code: EDITOR_NO_CLIENT, detail: 'no-client' };
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
        if (!this.current(epoch)) { return { op: op, ok: false, code: EDITOR_STALE_EPOCH, detail: 'stale-epoch' }; }
        if (raced === undefined) { return { op: op, ok: false, code: EDITOR_TIMEOUT, detail: 'timeout' }; }
        if (raced === null) {
          this.runtime.log(op, 'rejected', '');
          return { op: op, ok: false, code: EDITOR_REJECTED, detail: 'rejected' };
        }
        this.runtime.log(op, 'ok', raced);
        return { op: op, ok: true, code: 0, detail: raced };
      } catch (error) {
        if (!this.current(epoch)) { return { op: op, ok: false, code: EDITOR_STALE_EPOCH, detail: 'stale-epoch' }; }
        const code: number = this.runtime.errorCode(error as Error);
        this.runtime.log(op, 'fail', `code=${code}`);
        return { op: op, ok: false, code: code, detail: `code=${code}` };
      }
    });
    this.queue = run.then((): void => undefined).catch((): void => undefined);
    return run;
  }

  enqueueValue<T>(op: string, fn: (client: C) => Promise<T>): Promise<EditorValue<T>> {
    const epoch: number = this.editorEpoch;
    const run: Promise<EditorValue<T>> = this.queue.then(async (): Promise<EditorValue<T>> => {
      if (epoch !== this.editorEpoch) { return { ok: false, code: EDITOR_STALE_EPOCH, value: undefined }; }
      if (this.unresolvedWriteEpoch === epoch) { return { ok: false, code: EDITOR_UNRESOLVED_WRITE, value: undefined }; }
      const client: C | undefined = this.client;
      if (client === undefined) {
        this.runtime.log(op, 'no-client', '');
        return { ok: false, code: EDITOR_NO_CLIENT, value: undefined };
      }
      try {
        const raced: T | undefined = await this.withTimeout<T>(op, fn(client));
        if (!this.current(epoch)) { return { ok: false, code: EDITOR_STALE_EPOCH, value: undefined }; }
        if (raced === undefined) { return { ok: false, code: EDITOR_TIMEOUT, value: undefined }; }
        this.runtime.log(op, 'ok', '');
        return { ok: true, code: 0, value: raced };
      } catch (error) {
        if (!this.current(epoch)) { return { ok: false, code: EDITOR_STALE_EPOCH, value: undefined }; }
        const code: number = this.runtime.errorCode(error as Error);
        this.runtime.log(op, 'fail', `code=${code}`);
        return { ok: false, code: code, value: undefined };
      }
    });
    this.queue = run.then((): void => undefined).catch((): void => undefined);
    return run;
  }
}
