export type SettingsScope = 'settings' | 'request' | 'background';
export type SettingsSyncState = 'applied' | 'pending' | 'error';
export interface SettingsReceiptPort {
  schedule: (callback: () => void, delay: number) => number;
  unschedule: (timer: number) => void;
  publish: (scope: SettingsScope, saved: number, applied: number, state: SettingsSyncState) => void;
  log: (action: string, scope: SettingsScope, revision: number, code: string) => void;
}
class ReceiptWaiter {
  revision: number = 0;
  timer: number = -1;
  settled: boolean = false;
  resolve: (confirmed: boolean) => void = () => {};
}
class Receipt {
  saved: number = 0;
  applied: number = 0;
  waiters: ReceiptWaiter[] = [];
}
export class SettingsReceiptStore {
  private settings: Receipt = new Receipt();
  private request: Receipt = new Receipt();
  private background: Receipt = new Receipt();
  private port: SettingsReceiptPort;
  constructor(port: SettingsReceiptPort) { this.port = port; }
  private get(scope: SettingsScope): Receipt {
    return scope === 'settings' ? this.settings : scope === 'request' ? this.request : this.background;
  }
  private publish(scope: SettingsScope, receipt: Receipt): void {
    this.port.publish(scope, receipt.saved, receipt.applied, receipt.applied >= receipt.saved ? 'applied' : 'pending');
  }
  saved(scope: SettingsScope, revision: number): void {
    const receipt: Receipt = this.get(scope);
    receipt.saved = Math.max(receipt.saved, revision);
    this.publish(scope, receipt);
    this.port.log('saved', scope, revision, '');
  }
  applied(scope: SettingsScope, revision: number): void {
    const receipt: Receipt = this.get(scope);
    receipt.applied = Math.max(receipt.applied, revision);
    this.publish(scope, receipt);
    const completed: ReceiptWaiter[] = receipt.waiters.filter((waiter: ReceiptWaiter) => waiter.revision <= receipt.applied);
    receipt.waiters = receipt.waiters.filter((waiter: ReceiptWaiter) => waiter.revision > receipt.applied);
    for (const waiter of completed) {
      waiter.settled = true;
      this.port.unschedule(waiter.timer);
      waiter.resolve(true);
    }
    this.port.log('applied', scope, revision, '');
  }
  failed(scope: SettingsScope, code: string): void {
    const receipt: Receipt = this.get(scope);
    this.port.publish(scope, receipt.saved, receipt.applied, 'error');
    this.port.log('failed', scope, 0, code);
  }
  async wait(scope: SettingsScope, revision: number, timeout: number = 2000): Promise<boolean> {
    const receipt: Receipt = this.get(scope);
    if (receipt.applied >= revision) { return true; }
    return new Promise<boolean>((resolve) => {
      const waiter: ReceiptWaiter = new ReceiptWaiter();
      waiter.revision = revision;
      waiter.resolve = resolve;
      waiter.timer = this.port.schedule(() => {
        if (waiter.settled) { return; }
        waiter.settled = true;
        receipt.waiters = receipt.waiters.filter((entry: ReceiptWaiter) => entry !== waiter);
        this.port.log('timeout', scope, revision, '');
        resolve(false);
      }, timeout);
      receipt.waiters.push(waiter);
    });
  }
}
