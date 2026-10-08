import commonEventManager from '@ohos.commonEventManager';
import { KeyboardSettingsSnapshot, KeyboardSettingsPatch, KeyboardSettingsChange,
  validSettingsSnapshot, validSettingsPatch } from './KeyboardSettingsModel';
import { readSettings, commitSettings, ensureSettingsRevision, queueSettings, nextSettingsChange,
  acceptSettingsChange, receiveSettings, settingsActor, settingsPendingCount, settingsBaseRevision, settingsLastPendingSequence,
  legacyHeightPresent, legacyLayoutPresent, importLegacySettings, settingsDiagnostics } from './KeyboardSettingsRepository';
import { settingsReceipt } from './SettingsReceipt';
import { debugLog, debugErrorCode } from './DebugLog';

const BUNDLE: string = 'local.yplic.kanon';
const REQUEST: string = `${BUNDLE}.SETTINGS_REQUEST`;
const UPDATE: string = `${BUNDLE}.SETTINGS_UPDATE`;
const CHANGE: string = `${BUNDLE}.SETTINGS_CHANGE`;
const ACK: string = `${BUNDLE}.SETTINGS_ACK`;

class SettingsHello {
  snapshot: KeyboardSettingsSnapshot = new KeyboardSettingsSnapshot();
  legacyHeight: boolean = false;
  legacyLayout: boolean = false;
}

export class SettingsSaveResult {
  revision: number = 0;
  confirmed: boolean = false;
}

/** One protocol for small settings. The UI app assigns authoritative versions. */
class KeyboardSettingsSync {
  private ime: boolean = false;
  private ready: Promise<void> | undefined;
  private subscriber: commonEventManager.CommonEventSubscriber | undefined;
  private receiveTail: Promise<void> = Promise.resolve();
  private retryTimer: number = -1;
  private retryCount: number = 0;
  private saveTail: Promise<void> = Promise.resolve();
  onApplied: (snapshot: KeyboardSettingsSnapshot, heightChanged: boolean, fromPeer: boolean) => Promise<void> = async () => {};
  isReplica(): boolean { return this.ime; }

  initialize(ime: boolean = false): Promise<void> {
    if (ime) { this.ime = true; }
    if (this.ready) { return this.ready; }
    this.ready = this.connect().catch((error: Error) => {
      this.ready = undefined;
      debugLog.record('config', `subscribe failed code=${debugErrorCode(error)}`);
      throw error;
    });
    return this.ready;
  }

  private async connect(): Promise<void> {
    if (this.ime && settingsPendingCount() > 0) { settingsReceipt.saved('request', settingsLastPendingSequence()); }
    this.subscriber = await commonEventManager.createSubscriber({
      events: [REQUEST, UPDATE, CHANGE, ACK], publisherBundleName: BUNDLE
    });
    commonEventManager.subscribe(this.subscriber, (error, event) => {
      if (error) { debugLog.record('config', `receive error code=${error.code}`); return; }
      if (event.parameters?.['sender'] !== (this.ime ? 'app' : 'ime')) { return; }
      this.receiveTail = this.receiveTail.then(() => this.receive(event)).catch((failure: Error) => {
        debugLog.record('config', `apply failed code=${debugErrorCode(failure)}`);
      });
    });
    try { await this.sendRequest(); }
    catch (error) { debugLog.record('config', `initial request failed code=${debugErrorCode(error)}`); }
  }

  async request(): Promise<void> {
    await this.initialize(this.ime);
    this.retryCount = 0;
    await this.sendRequest();
    if (this.ime) { await this.sendPending(); }
  }

  private async sendRequest(): Promise<void> {
    const hello = new SettingsHello();
    hello.snapshot = readSettings();
    hello.snapshot.revision = settingsBaseRevision();
    hello.legacyHeight = legacyHeightPresent();
    hello.legacyLayout = legacyLayoutPresent();
    await this.publish(REQUEST, this.ime ? JSON.stringify(hello) : '');
  }

  async save(patch: KeyboardSettingsPatch, waitForAck: boolean = true): Promise<SettingsSaveResult> {
    if (!validSettingsPatch(patch)) { throw new Error('Invalid settings patch'); }
    // A transport failure must not discard a locally saved change.
    try { await this.initialize(this.ime); } catch (error) { }
    const result = new SettingsSaveResult();
    const run: Promise<void> = this.saveTail.then(async () => {
      const before: KeyboardSettingsSnapshot = readSettings();
      if (this.ime) {
        const change: KeyboardSettingsChange = queueSettings(patch);
        result.revision = change.sequence;
        settingsReceipt.saved('request', change.sequence);
        try { await this.onApplied(readSettings(), before.heightPercent !== readSettings().heightPercent, false); }
        catch (error) { settingsReceipt.failed('request', debugErrorCode(error)); }
        this.retryCount = 0;
        this.sendPending().catch((error: Error) => settingsReceipt.failed('request', debugErrorCode(error)));
      } else {
        const snapshot: KeyboardSettingsSnapshot = commitSettings(patch);
        result.revision = snapshot.revision;
        settingsReceipt.saved('settings', snapshot.revision);
        this.sendSnapshot().catch((error: Error) => settingsReceipt.failed('settings', debugErrorCode(error)));
      }
    });
    this.saveTail = run.catch(() => {});
    await run;
    if (waitForAck) { result.confirmed = await settingsReceipt.wait(this.ime ? 'request' : 'settings', result.revision); }
    return result;
  }

  private async receive(event: commonEventManager.CommonEventData): Promise<void> {
    if (event.event === REQUEST) {
      if (this.ime) {
        await this.sendRequest();
        await this.sendPending();
      } else {
        if (event.data && event.data.length <= 4000) {
          const hello: SettingsHello = JSON.parse(event.data) as SettingsHello;
          if (!validSettingsSnapshot(hello.snapshot) || typeof hello.legacyHeight !== 'boolean' ||
            typeof hello.legacyLayout !== 'boolean') { return; }
          importLegacySettings(hello.snapshot, hello.legacyHeight, hello.legacyLayout);
        }
        await this.sendSnapshot();
      }
    } else if (event.event === CHANGE && !this.ime && event.data && event.data.length <= 4000) {
      const change: KeyboardSettingsChange = JSON.parse(event.data) as KeyboardSettingsChange;
      if (typeof change.actor !== 'string' || change.actor.length > 64 || !/^\d+-\d+$/.test(change.actor) ||
        !Number.isSafeInteger(change.sequence) || change.sequence <= 0 || !validSettingsPatch(change.patch)) { return; }
      const peer = acceptSettingsChange(change);
      await this.sendSnapshot(peer.actor, peer.sequence);
    } else if (event.event === UPDATE && this.ime && event.data && event.data.length <= 4000) {
      const snapshot: KeyboardSettingsSnapshot = JSON.parse(event.data) as KeyboardSettingsSnapshot;
      if (!validSettingsSnapshot(snapshot)) { return; }
      const actor: string = typeof event.parameters?.['actor'] === 'string' ? event.parameters['actor'] as string : '';
      const sequence: number = Number(event.parameters?.['sequence'] ?? 0);
      if (!Number.isSafeInteger(sequence) || sequence < 0) { return; }
      const before: KeyboardSettingsSnapshot = readSettings();
      receiveSettings(snapshot, actor, sequence);
      const applied: KeyboardSettingsSnapshot = readSettings();
      await this.onApplied(applied, before.heightPercent !== applied.heightPercent, true);
      if (actor === settingsActor()) { settingsReceipt.applied('request', sequence); }
      await this.publish(ACK, settingsBaseRevision().toString());
      debugLog.record('config', `snapshot applied revision=${settingsBaseRevision()} pending=${settingsPendingCount()}`);
      debugLog.record('config', settingsDiagnostics());
      await this.sendPending();
    } else if (event.event === ACK && !this.ime) {
      const revision: number = Number(event.data);
      if (Number.isSafeInteger(revision) && revision >= 0 && revision <= settingsBaseRevision()) {
        settingsReceipt.applied('settings', revision);
      }
    }
  }

  private async sendSnapshot(actor: string = '', sequence: number = 0): Promise<void> {
    const snapshot: KeyboardSettingsSnapshot = ensureSettingsRevision();
    settingsReceipt.saved('settings', snapshot.revision);
    await this.publish(UPDATE, JSON.stringify(snapshot), actor, sequence);
    debugLog.record('config', `snapshot sent revision=${snapshot.revision} ackSequence=${sequence}`);
  }

  private async sendPending(): Promise<void> {
    const change: KeyboardSettingsChange | undefined = nextSettingsChange();
    if (!change) {
      if (this.retryTimer >= 0) { clearTimeout(this.retryTimer); this.retryTimer = -1; }
      this.retryCount = 0;
      return;
    }
    try { await this.publish(CHANGE, JSON.stringify(change)); }
    finally {
      if (this.retryTimer < 0 && this.retryCount < 3) {
        this.retryCount++;
        this.retryTimer = setTimeout(() => {
          this.retryTimer = -1;
          this.sendPending().catch((error: Error) => settingsReceipt.failed('request', debugErrorCode(error)));
        }, 2000);
      }
    }
  }

  private publish(event: string, data: string, actor: string = '', sequence: number = 0): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      commonEventManager.publish(event, { bundleName: BUNDLE, data: data,
        parameters: { sender: this.ime ? 'ime' : 'app', actor: actor, sequence: sequence } }, (error) => {
        if (error) { reject(error); } else { resolve(); }
      });
    });
  }
}

export const keyboardSettingsSync: KeyboardSettingsSync = new KeyboardSettingsSync();
