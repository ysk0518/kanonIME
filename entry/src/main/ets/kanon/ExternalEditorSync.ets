/** Notifications are hints; only a successful current-client read proves empty. */
export interface EmptyEditorRead {
  ok: boolean;
  code: number;
  value: boolean | undefined;
}

export interface ExternalEditorPort {
  getEpoch: () => number;
  queryEmpty: () => Promise<EmptyEditorRead>;
}

export type ExternalEditorResult = 'ignored' | 'present' | 'empty' | 'retry' | 'failed' | 'stale';

/** Used inside the whole-input queue. Stores no editor text and performs no writes. */
export class ExternalEditorSync {
  private port: ExternalEditorPort;
  private pendingEpoch: number = -1;
  private revision: number = 0;

  constructor(port: ExternalEditorPort) { this.port = port; }
  getRevision(): number { return this.revision; }
  hasPending(): boolean { return this.pendingEpoch === this.port.getEpoch(); }
  reset(): void { this.pendingEpoch = -1; this.revision++; }

  visibilityChanged(epoch: number): void {
    this.pendingEpoch = epoch;
    this.revision++;
  }

  textChanged(epoch: number, empty: boolean): void {
    this.revision++;
    if (empty) { this.pendingEpoch = epoch; }
  }

  selectionChanged(epoch: number, begin: number, end: number): void {
    this.revision++;
    if (begin === 0 && end === 0) { this.pendingEpoch = epoch; }
  }

  async reconcile(hasComposition: boolean): Promise<ExternalEditorResult> {
    const epoch: number = this.port.getEpoch();
    if (this.pendingEpoch !== epoch) { return 'ignored'; }
    if (!hasComposition) { this.pendingEpoch = -1; return 'ignored'; }
    const revision: number = this.revision;
    let result: EmptyEditorRead;
    try { result = await this.port.queryEmpty(); }
    catch (error) { return epoch === this.port.getEpoch() ? 'failed' : 'stale'; }
    if (epoch !== this.port.getEpoch()) { return 'stale'; }
    if (revision !== this.revision) { return 'retry'; }
    if (!result.ok || result.value === undefined) {
      return 'failed';
    }
    this.pendingEpoch = -1;
    return result.value ? 'empty' : 'present';
  }
}
