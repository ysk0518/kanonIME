import { debugLog } from './DebugLog';
import { SettingsReceiptStore, SettingsReceiptPort, SettingsScope, SettingsSyncState } from './SettingsReceiptState';
export { SettingsScope } from './SettingsReceiptState';

function prefix(scope: SettingsScope): string {
  return scope === 'settings' ? 'kanonSettings' : scope === 'request' ? 'kanonSettingsRequest' : 'kanonBackground';
}
const port: SettingsReceiptPort = {
  schedule: (callback: () => void, delay: number): number => setTimeout(callback, delay),
  unschedule: (timer: number): void => { clearTimeout(timer); },
  publish: (scope: SettingsScope, saved: number, applied: number, state: SettingsSyncState): void => {
    if (state === 'error') {
      AppStorage.setOrCreate(`${prefix(scope)}SyncState`, state);
      return;
    }
    AppStorage.setOrCreate(`${prefix(scope)}SavedRevision`, saved);
    AppStorage.setOrCreate(`${prefix(scope)}AppliedRevision`, applied);
    AppStorage.setOrCreate(`${prefix(scope)}SyncState`, state);
  },
  log: (action: string, scope: SettingsScope, revision: number, code: string): void => {
    if (action === 'failed') { debugLog.record('config', `sync failed scope=${scope} code=${code}`); }
    else if (action === 'timeout') { debugLog.record('config', `ack timeout scope=${scope} revision=${revision}`); }
    else { debugLog.record('config', `${action} scope=${scope} revision=${revision}`); }
  }
};
export const settingsReceipt: SettingsReceiptStore = new SettingsReceiptStore(port);
