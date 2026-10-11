export interface PreviewSelectionWait {
  ready: Promise<boolean>;
  cancel: () => void;
}

class PendingPreviewSelection {
  epoch: number;
  position: number;
  ready: Promise<boolean>;
  private resolve: (received: boolean) => void = (): void => {};
  private settled: boolean = false;

  constructor(epoch: number, position: number) {
    this.epoch = epoch;
    this.position = position;
    this.ready = new Promise<boolean>((resolve): void => { this.resolve = resolve; });
  }

  complete(received: boolean): void {
    if (this.settled) { return; }
    this.settled = true;
    this.resolve(received);
  }
}

/** Waits for a new collapsed-position observation, not an API acknowledgment. */
export class PreviewSelectionReceipt {
  private pending: PendingPreviewSelection | undefined = undefined;

  arm(epoch: number, position: number): PreviewSelectionWait {
    this.cancel();
    const pending: PendingPreviewSelection = new PendingPreviewSelection(epoch, position);
    this.pending = pending;
    return {
      ready: pending.ready,
      cancel: (): void => {
        if (this.pending === pending) { this.pending = undefined; }
        pending.complete(false);
      }
    };
  }

  observe(epoch: number, start: number, end: number): void {
    const pending: PendingPreviewSelection | undefined = this.pending;
    if (pending === undefined || pending.epoch !== epoch || start !== end || end !== pending.position) { return; }
    this.pending = undefined;
    pending.complete(true);
  }

  cancel(): void {
    const pending: PendingPreviewSelection | undefined = this.pending;
    this.pending = undefined;
    if (pending !== undefined) { pending.complete(false); }
  }
}

/** Arm before issuing the API; accept either callback-before-return ordering. */
export async function writePreviewWithReceipt(write: () => Promise<void>,
  wait: PreviewSelectionWait | undefined): Promise<boolean> {
  try {
    await write();
    return wait === undefined || await wait.ready;
  } catch (error) {
    if (wait !== undefined) { wait.cancel(); }
    throw error as Error;
  }
}
