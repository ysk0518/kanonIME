import { debugLog } from './DebugLog';

export type SettingsScope = 'settings' | 'request' | 'background';

class ReceiptWaiter {
  revision: number = 0;
  timer: number = -1;
  resolve: (confirmed: boolean) => void = () => {};
}

class Receipt {
  saved: number = 0;
  applied: number = 0;
  waiters: ReceiptWaiter[] = [];
}

/** Shared saved / applied / timeout semantics for metadata and background transfers. */
class SettingsReceiptStore {
  private settings: Receipt = new Receipt();
  private request: Receipt = new Receipt();
  private background: Receipt = new Receipt();

  private get(scope: SettingsScope): Receipt {
    return scope === 'settings' ? this.settings : scope === 'request' ? this.request : this.background;
  }

  private prefix(scope: SettingsScope): string {
    return scope === 'settings' ? 'kanonSettings' : scope === 'request' ? 'kanonSettingsRequest' : 'kanonBackground';
  }

  private publish(scope: SettingsScope, receipt: Receipt): void {
    const prefix: string = this.prefix(scope);
    AppStorage.setOrCreate(`${prefix}SavedRevision`, receipt.saved);
    AppStorage.setOrCreate(`${prefix}AppliedRevision`, receipt.applied);
    AppStorage.setOrCreate(`${prefix}SyncState`, receipt.applied >= receipt.saved ? 'applied' : 'pending');
  }

  saved(scope: SettingsScope, revision: number): void {
    const receipt: Receipt = this.get(scope);
    receipt.saved = Math.max(receipt.saved, revision);
    this.publish(scope, receipt);
    debugLog.record('config', `saved scope=${scope} revision=${revision}`);
  }

  applied(scope: SettingsScope, revision: number): void {
    const receipt: Receipt = this.get(scope);
    receipt.applied = Math.max(receipt.applied, revision);
    this.publish(scope, receipt);
    const completed: ReceiptWaiter[] = receipt.waiters.filter((waiter: ReceiptWaiter) => waiter.revision <= receipt.applied);
    receipt.waiters = receipt.waiters.filter((waiter: ReceiptWaiter) => waiter.revision > receipt.applied);
    for (const waiter of completed) { clearTimeout(waiter.timer); waiter.resolve(true); }
    debugLog.record('config', `applied scope=${scope} revision=${revision}`);
  }

  failed(scope: SettingsScope, code: string): void {
    AppStorage.setOrCreate(`${this.prefix(scope)}SyncState`, 'error');
    debugLog.record('config', `sync failed scope=${scope} code=${code}`);
  }

  async wait(scope: SettingsScope, revision: number, timeout: number = 2000): Promise<boolean> {
    const receipt: Receipt = this.get(scope);
    if (receipt.applied >= revision) { return true; }
    return new Promise<boolean>((resolve) => {
      const waiter = new ReceiptWaiter();
      waiter.revision = revision;
      waiter.resolve = resolve;
      waiter.timer = setTimeout(() => {
        receipt.waiters = receipt.waiters.filter((entry: ReceiptWaiter) => entry !== waiter);
        debugLog.record('config', `ack timeout scope=${scope} revision=${revision}`);
        resolve(false);
      }, timeout);
      receipt.waiters.push(waiter);
    });
  }
}

export const settingsReceipt = new SettingsReceiptStore();
