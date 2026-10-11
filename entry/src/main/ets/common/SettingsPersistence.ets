import { KeyboardSettingsRecord, validSettingsRecord } from './KeyboardSettingsModel';

export interface SettingsStoragePort {
  maximumLength: number;
  write: (payload: string) => void;
  flush: () => void;
}

/** Caller adopts/publishes next only after write and flush both succeed. */
export function saveSettingsRecord(next: KeyboardSettingsRecord, port: SettingsStoragePort): void {
  if (!validSettingsRecord(next)) { throw new Error('Invalid settings record'); }
  const payload: string = JSON.stringify(next);
  if (payload.length > port.maximumLength) { throw new Error('Settings storage limit'); }
  port.write(payload);
  port.flush();
}
