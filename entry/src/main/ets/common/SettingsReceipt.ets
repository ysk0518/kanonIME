import {
  KANON_BACKGROUND_APPLIED_REVISION, KANON_BACKGROUND_SAVED_REVISION, KANON_BACKGROUND_SYNC_STATE,
  KANON_SETTINGS_APPLIED_REVISION, KANON_SETTINGS_SAVED_REVISION, KANON_SETTINGS_SYNC_STATE,
  KANON_SETTINGS_REQUEST_APPLIED_REVISION, KANON_SETTINGS_REQUEST_SAVED_REVISION, KANON_SETTINGS_REQUEST_SYNC_STATE
} from './AppStorageKeys';
import { debugLog } from './DebugLog';
import { SettingsReceiptStore, SettingsReceiptPort, SettingsScope, SettingsSyncState } from './SettingsReceiptState';
export { SettingsScope } from './SettingsReceiptState';

interface ReceiptKeys {
  savedRevision: string;
  appliedRevision: string;
  syncState: string;
}

const SETTINGS_RECEIPT_KEYS: ReceiptKeys = {
  savedRevision: KANON_SETTINGS_SAVED_REVISION,
  appliedRevision: KANON_SETTINGS_APPLIED_REVISION,
  syncState: KANON_SETTINGS_SYNC_STATE
};
const REQUEST_RECEIPT_KEYS: ReceiptKeys = {
  savedRevision: KANON_SETTINGS_REQUEST_SAVED_REVISION,
  appliedRevision: KANON_SETTINGS_REQUEST_APPLIED_REVISION,
  syncState: KANON_SETTINGS_REQUEST_SYNC_STATE
};
const BACKGROUND_RECEIPT_KEYS: ReceiptKeys = {
  savedRevision: KANON_BACKGROUND_SAVED_REVISION,
  appliedRevision: KANON_BACKGROUND_APPLIED_REVISION,
  syncState: KANON_BACKGROUND_SYNC_STATE
};

const port: SettingsReceiptPort = {
  schedule: (callback: () => void, delay: number): number => setTimeout(callback, delay),
  unschedule: (timer: number): void => { clearTimeout(timer); },
  publish: (scope: SettingsScope, saved: number, applied: number, state: SettingsSyncState): void => {
    const keys: ReceiptKeys = scope === 'settings' ? SETTINGS_RECEIPT_KEYS :
      scope === 'request' ? REQUEST_RECEIPT_KEYS : BACKGROUND_RECEIPT_KEYS;
    if (state === 'error') {
      AppStorage.setOrCreate(keys.syncState, state);
      return;
    }
    AppStorage.setOrCreate(keys.savedRevision, saved);
    AppStorage.setOrCreate(keys.appliedRevision, applied);
    AppStorage.setOrCreate(keys.syncState, state);
  },
  log: (action: string, scope: SettingsScope, revision: number, code: string): void => {
    if (action === 'failed') { debugLog.record('config', `sync failed scope=${scope} code=${code}`); }
    else if (action === 'timeout') { debugLog.record('config', `ack timeout scope=${scope} revision=${revision}`); }
    else { debugLog.record('config', `${action} scope=${scope} revision=${revision}`); }
  }
};
export const settingsReceipt: SettingsReceiptStore = new SettingsReceiptStore(port);
