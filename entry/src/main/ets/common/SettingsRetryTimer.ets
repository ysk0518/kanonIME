export interface SettingsRetryPort {
  schedule: (callback: () => void, delay: number) => number;
  unschedule: (timer: number) => void;
  retry: () => Promise<void>;
  failed: (error: Error) => void;
}
/** Initial send plus at most three retries, two seconds apart. */
export class SettingsRetryTimer {
  private timer: number = -1;
  private count: number = 0;
  private generation: number = 0;
  private port: SettingsRetryPort;
  constructor(port: SettingsRetryPort) { this.port = port; }
  resetBudget(): void { this.count = 0; }
  stop(): void {
    this.generation++;
    if (this.timer >= 0) { this.port.unschedule(this.timer); this.timer = -1; }
    this.count = 0;
  }
  schedule(): void {
    if (this.timer >= 0 || this.count >= 3) { return; }
    this.count++;
    const generation: number = this.generation;
    this.timer = this.port.schedule(() => {
      if (generation !== this.generation) { return; }
      this.timer = -1;
      this.port.retry().catch((error: Error) => {
        if (generation === this.generation) { this.port.failed(error); }
      });
    }, 2000);
  }
}
