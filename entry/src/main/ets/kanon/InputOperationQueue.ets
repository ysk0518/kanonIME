/** Serializes a complete input operation, including its preview/display update. */
export class InputOperationQueue<T> {
  private tail: Promise<void> = Promise.resolve();
  private getEpoch: () => number;
  private staleResult: () => T;

  constructor(getEpoch: () => number, staleResult: () => T) {
    this.getEpoch = getEpoch;
    this.staleResult = staleResult;
  }

  enqueue(operation: () => Promise<T>): Promise<T> {
    const epoch: number = this.getEpoch();
    const run: Promise<T> = this.tail.then((): Promise<T> => {
      if (epoch !== this.getEpoch()) { return Promise.resolve(this.staleResult()); }
      return operation();
    });
    // Report failure to its caller but keep the queue available for later input.
    this.tail = run.then((): void => undefined).catch((): void => undefined);
    return run;
  }
}
