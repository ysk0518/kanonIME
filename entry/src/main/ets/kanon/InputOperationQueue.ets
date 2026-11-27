/** Serializes a complete input operation, including its preview/display update. */
export class InputOperationQueue<T> {
  private tail: Promise<void> = Promise.resolve();
  private getEpoch: () => number;
  private staleResult: () => T;
  private count: number = 0;
  private finished: number = 0;

  constructor(getEpoch: () => number, staleResult: () => T) {
    this.getEpoch = getEpoch;
    this.staleResult = staleResult;
  }

  /** Increases on every enqueue, so a caller can tell whether its operation is still the last one. */
  enqueuedCount(): number { return this.count; }

  /** Operations enqueued and not yet finished, including the one running. */
  unfinished(): number { return this.count - this.finished; }

  enqueue(operation: () => Promise<T>): Promise<T> {
    this.count++;
    const epoch: number = this.getEpoch();
    const run: Promise<T> = this.tail.then((): Promise<T> => {
      if (epoch !== this.getEpoch()) { return Promise.resolve(this.staleResult()); }
      return operation();
    });
    // Report failure to its caller but keep the queue available for later input.
    this.tail = run.then((): void => undefined).catch((): void => undefined)
      .finally((): void => { this.finished++; });
    return run;
  }
}
