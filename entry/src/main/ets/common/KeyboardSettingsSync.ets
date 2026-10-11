import commonEventManager from '@ohos.commonEventManager';
import { readSettings, commitSettings, ensureSettingsRevision, queueSettings, nextSettingsChange,
  acceptSettingsChange, receiveSettings, settingsActor, settingsPendingCount, settingsBaseRevision,
  settingsLastPendingSequence, legacyHeightPresent, legacyLayoutPresent, importLegacySettings,
  settingsDiagnostics, settingsIssuedSequence } from './KeyboardSettingsRepository';
import { settingsReceipt } from './SettingsReceipt';
import { debugLog, debugErrorCode } from './DebugLog';
import { KeyboardSettingsSyncCore, SettingsSyncPorts, SettingsWireEvent,
  BUNDLE, REQUEST, UPDATE, CHANGE, ACK } from './SettingsSyncCore';
export { SettingsSaveResult } from './SettingsSyncCore';

let subscriber: commonEventManager.CommonEventSubscriber | undefined;
const ports: SettingsSyncPorts = {
  subscribe: async (receive: (event: SettingsWireEvent) => Promise<void>): Promise<void> => {
    subscriber = await commonEventManager.createSubscriber({
      events: [REQUEST, UPDATE, CHANGE, ACK], publisherBundleName: BUNDLE
    });
    commonEventManager.subscribe(subscriber, (error, event) => {
      if (error) { debugLog.record('config', `receive error code=${error.code}`); return; }
      const data: SettingsWireEvent = {
        event: event.event,
        data: event.data,
        sender: typeof event.parameters?.['sender'] === 'string' ? event.parameters['sender'] as string : undefined,
        actor: typeof event.parameters?.['actor'] === 'string' ? event.parameters['actor'] as string : undefined,
        sequence: Number(event.parameters?.['sequence'] ?? 0)
      };
      receive(data).catch((failure: Error) => {
        debugLog.record('config', `apply failed code=${debugErrorCode(failure)}`);
      });
    });
  },
  publish: (event: SettingsWireEvent): Promise<void> => new Promise<void>((resolve, reject) => {
    commonEventManager.publish(event.event, { bundleName: BUNDLE, data: event.data,
      parameters: { sender: event.sender ?? '', actor: event.actor ?? '', sequence: event.sequence ?? 0 } }, (error) => {
      if (error) { reject(error); } else { resolve(); }
    });
  }),
  schedule: (callback: () => void, delay: number): number => setTimeout(callback, delay),
  unschedule: (timer: number): void => { clearTimeout(timer); },
  receipt: settingsReceipt,
  log: (message: string): void => { debugLog.record('config', message); },
  errorCode: (error: Error): string => debugErrorCode(error),
  readSettings: readSettings, commitSettings: commitSettings, ensureSettingsRevision: ensureSettingsRevision,
  queueSettings: queueSettings, nextSettingsChange: nextSettingsChange, acceptSettingsChange: acceptSettingsChange,
  receiveSettings: receiveSettings, settingsActor: settingsActor, settingsPendingCount: settingsPendingCount,
  settingsBaseRevision: settingsBaseRevision, settingsLastPendingSequence: settingsLastPendingSequence,
  settingsIssuedSequence: settingsIssuedSequence, legacyHeightPresent: legacyHeightPresent,
  legacyLayoutPresent: legacyLayoutPresent, importLegacySettings: importLegacySettings,
  settingsDiagnostics: settingsDiagnostics
};
export const keyboardSettingsSync: KeyboardSettingsSyncCore = new KeyboardSettingsSyncCore(ports);
