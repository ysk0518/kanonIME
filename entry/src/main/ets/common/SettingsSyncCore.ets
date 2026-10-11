import { KeyboardSettingsSnapshot, KeyboardSettingsPatch, KeyboardSettingsChange, SettingsPeer,
  validSettingsSnapshot, validSettingsPatch } from './KeyboardSettingsModel';
import { SettingsReceiptStore } from './SettingsReceiptState';
import { SettingsRetryTimer, SettingsRetryPort } from './SettingsRetryTimer';
import { validRequestReceipt } from './SettingsAckPolicy';

export interface SettingsWireEvent {
  event: string;
  data?: string;
  sender?: string;
  actor?: string;
  sequence?: number;
}
export interface SettingsSyncPorts {
  subscribe: (receive: (event: SettingsWireEvent) => Promise<void>) => Promise<void>;
  publish: (event: SettingsWireEvent) => Promise<void>;
  schedule: (callback: () => void, delay: number) => number;
  unschedule: (timer: number) => void;
  receipt: SettingsReceiptStore;
  log: (message: string) => void;
  errorCode: (error: Error) => string;
  readSettings: () => KeyboardSettingsSnapshot;
  commitSettings: (patch: KeyboardSettingsPatch) => KeyboardSettingsSnapshot;
  ensureSettingsRevision: () => KeyboardSettingsSnapshot;
  queueSettings: (patch: KeyboardSettingsPatch) => KeyboardSettingsChange;
  nextSettingsChange: () => KeyboardSettingsChange | undefined;
  acceptSettingsChange: (change: KeyboardSettingsChange) => SettingsPeer;
  receiveSettings: (snapshot: KeyboardSettingsSnapshot, actor: string, sequence: number) => void;
  settingsActor: () => string;
  settingsPendingCount: () => number;
  settingsBaseRevision: () => number;
  settingsLastPendingSequence: () => number;
  settingsIssuedSequence: () => number;
  legacyHeightPresent: () => boolean;
  legacyLayoutPresent: () => boolean;
  importLegacySettings: (snapshot: KeyboardSettingsSnapshot, heightPresent: boolean, layoutPresent: boolean) => void;
  settingsDiagnostics: () => string;
}

export const BUNDLE: string = 'local.yplic.kanon';
export const REQUEST: string = `${BUNDLE}.SETTINGS_REQUEST`;
export const UPDATE: string = `${BUNDLE}.SETTINGS_UPDATE`;
export const CHANGE: string = `${BUNDLE}.SETTINGS_CHANGE`;
export const ACK: string = `${BUNDLE}.SETTINGS_ACK`;

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
export class KeyboardSettingsSyncCore {
  private ime: boolean = false;
  private ready: Promise<void> | undefined;
  private ports: SettingsSyncPorts;
  constructor(ports: SettingsSyncPorts) { this.ports = ports; }
  private receiveTail: Promise<void> = Promise.resolve();
  private retryPort: SettingsRetryPort = {
    schedule: (callback: () => void, delay: number): number => this.ports.schedule(callback, delay),
    unschedule: (timer: number): void => { this.ports.unschedule(timer); },
    retry: (): Promise<void> => this.sendPending(),
    failed: (error: Error): void => { this.ports.receipt.failed('request', this.ports.errorCode(error)); }
  };
  private retry: SettingsRetryTimer = new SettingsRetryTimer(this.retryPort);
  private saveTail: Promise<void> = Promise.resolve();
  private applicationPending: boolean = false;
  private pendingReceiptSequence: number = 0;
  private pendingHeight: boolean = false;
  private applicationGeneration: number = 0;
  private applicationTail: Promise<void> = Promise.resolve();
  onApplied: (snapshot: KeyboardSettingsSnapshot, heightChanged: boolean, fromPeer: boolean) => Promise<void> = async () => {};
  isReplica(): boolean { return this.ime; }

  initialize(ime: boolean = false): Promise<void> {
    if (ime) { this.ime = true; }
    if (this.ready) { return this.ready; }
    this.ready = this.connect().catch((error: Error) => {
      this.ready = undefined;
      this.ports.log(`subscribe failed code=${this.ports.errorCode(error)}`);
      throw error;
    });
    return this.ready;
  }

  private async connect(): Promise<void> {
    if (this.ime && this.ports.settingsPendingCount() > 0) { this.ports.receipt.saved('request', this.ports.settingsLastPendingSequence()); }
    await this.ports.subscribe((event: SettingsWireEvent): Promise<void> =>
      this.receiveEvent(event).catch((failure: Error) => {
        this.ports.log(`apply failed code=${this.ports.errorCode(failure)}`);
      }));
    try { await this.sendRequest(); }
    catch (error) { this.ports.log(`initial request failed code=${this.ports.errorCode(error)}`); }
  }

  async request(): Promise<void> {
    await this.initialize(this.ime);
    this.retry.resetBudget();
    await this.sendRequest();
    if (this.ime) { await this.sendPending(); }
  }

  private async sendRequest(): Promise<void> {
    const hello = new SettingsHello();
    hello.snapshot = this.ports.readSettings();
    hello.snapshot.revision = this.ports.settingsBaseRevision();
    hello.legacyHeight = this.ports.legacyHeightPresent();
    hello.legacyLayout = this.ports.legacyLayoutPresent();
    await this.publish(REQUEST, this.ime ? JSON.stringify(hello) : '');
  }

  async save(patch: KeyboardSettingsPatch, waitForAck: boolean = true): Promise<SettingsSaveResult> {
    if (!validSettingsPatch(patch)) { throw new Error('Invalid settings patch'); }
    // A transport failure must not discard a locally saved change.
    try { await this.initialize(this.ime); } catch (error) { }
    const result = new SettingsSaveResult();
    const run: Promise<void> = this.saveTail.then(async () => {
      const before: KeyboardSettingsSnapshot = this.ports.readSettings();
      if (this.ime) {
        const change: KeyboardSettingsChange = this.ports.queueSettings(patch);
        if (this.applicationPending) {
          this.applicationGeneration++;
          this.pendingHeight = this.pendingHeight || before.heightPercent !== this.ports.readSettings().heightPercent;
        }
        result.revision = change.sequence;
        this.ports.receipt.saved('request', change.sequence);
        try { await this.onApplied(this.ports.readSettings(), before.heightPercent !== this.ports.readSettings().heightPercent, false); }
        catch (error) {
          this.pendingHeight = this.pendingHeight || before.heightPercent !== this.ports.readSettings().heightPercent;
          this.ports.receipt.failed('request', this.ports.errorCode(error));
        }
        this.retry.resetBudget();
        this.sendPending().catch((error: Error) => this.ports.receipt.failed('request', this.ports.errorCode(error)));
      } else {
        const snapshot: KeyboardSettingsSnapshot = this.ports.commitSettings(patch);
        result.revision = snapshot.revision;
        this.ports.receipt.saved('settings', snapshot.revision);
        this.sendSnapshot().catch((error: Error) => this.ports.receipt.failed('settings', this.ports.errorCode(error)));
      }
    });
    this.saveTail = run.catch(() => {});
    await run;
    if (waitForAck) { result.confirmed = await this.ports.receipt.wait(this.ime ? 'request' : 'settings', result.revision); }
    return result;
  }

  receiveEvent(event: SettingsWireEvent): Promise<void> {
    if (event.sender !== (this.ime ? 'app' : 'ime')) { return Promise.resolve(); }
    const run: Promise<void> = this.receiveTail.then(() => this.receive(event));
    this.receiveTail = run.catch(() => {});
    return run;
  }

  private async receive(event: SettingsWireEvent): Promise<void> {
    if (event.event === REQUEST) {
      if (this.ime) {
        await this.sendRequest();
        await this.sendPending();
      } else {
        if (event.data && event.data.length <= 4000) {
          const hello: SettingsHello = JSON.parse(event.data) as SettingsHello;
          if (!validSettingsSnapshot(hello.snapshot) || typeof hello.legacyHeight !== 'boolean' ||
            typeof hello.legacyLayout !== 'boolean') { return; }
          this.ports.importLegacySettings(hello.snapshot, hello.legacyHeight, hello.legacyLayout);
        }
        await this.sendSnapshot();
      }
    } else if (event.event === CHANGE && !this.ime && event.data && event.data.length <= 4000) {
      const change: KeyboardSettingsChange = JSON.parse(event.data) as KeyboardSettingsChange;
      if (typeof change.actor !== 'string' || change.actor.length > 64 || !/^\d+-\d+$/.test(change.actor) ||
        !Number.isSafeInteger(change.sequence) || change.sequence <= 0 || !validSettingsPatch(change.patch)) { return; }
      const peer = this.ports.acceptSettingsChange(change);
      await this.sendSnapshot(peer.actor, peer.sequence);
    } else if (event.event === UPDATE && this.ime && event.data && event.data.length <= 4000) {
      const snapshot: KeyboardSettingsSnapshot = JSON.parse(event.data) as KeyboardSettingsSnapshot;
      if (!validSettingsSnapshot(snapshot)) { return; }
      const actor: string = event.actor ?? '';
      const sequence: number = Number(event.sequence ?? 0);
      if (!Number.isSafeInteger(sequence) || sequence < 0) { return; }
      const before: KeyboardSettingsSnapshot = this.ports.readSettings();
      this.ports.receiveSettings(snapshot, actor, sequence);
      const applied: KeyboardSettingsSnapshot = this.ports.readSettings();
      this.applicationPending = true;
      this.applicationGeneration++;
      this.pendingHeight = this.pendingHeight || before.heightPercent !== applied.heightPercent;
      if (validRequestReceipt(actor, this.ports.settingsActor(), sequence, this.ports.settingsIssuedSequence())) {
        this.pendingReceiptSequence = Math.max(this.pendingReceiptSequence, sequence);
      }
      try { await this.applyPending(); }
      catch (error) {
        this.retry.schedule();
        if (this.pendingReceiptSequence > 0) { this.ports.receipt.failed('request', this.ports.errorCode(error)); }
        throw error as Error;
      }
      await this.sendPending();
    } else if (event.event === ACK && !this.ime) {
      const revision: number = Number(event.data);
      if (Number.isSafeInteger(revision) && revision >= 0 && revision <= this.ports.settingsBaseRevision()) {
        this.ports.receipt.applied('settings', revision);
      }
    }
  }

  private async sendSnapshot(actor: string = '', sequence: number = 0): Promise<void> {
    const snapshot: KeyboardSettingsSnapshot = this.ports.ensureSettingsRevision();
    this.ports.receipt.saved('settings', snapshot.revision);
    await this.publish(UPDATE, JSON.stringify(snapshot), actor, sequence);
    this.ports.log(`snapshot sent revision=${snapshot.revision} ackSequence=${sequence}`);
  }

  private applyPending(): Promise<void> {
    const run: Promise<void> = this.applicationTail.then(async (): Promise<void> => {
      if (!this.applicationPending) { return; }
      const generation: number = this.applicationGeneration;
      const applied: KeyboardSettingsSnapshot = this.ports.readSettings();
      await this.onApplied(applied, this.pendingHeight, true);
      if (generation !== this.applicationGeneration) { return; }
      if (this.pendingReceiptSequence > 0) { this.ports.receipt.applied('request', this.pendingReceiptSequence); }
      await this.publish(ACK, this.ports.settingsBaseRevision().toString());
      if (generation !== this.applicationGeneration) { return; }
      this.applicationPending = false;
      this.pendingReceiptSequence = 0;
      this.pendingHeight = false;
      this.ports.log(`snapshot applied revision=${this.ports.settingsBaseRevision()} pending=${this.ports.settingsPendingCount()}`);
      this.ports.log(this.ports.settingsDiagnostics());
    });
    this.applicationTail = run.catch(() => {});
    return run;
  }

  private async sendPending(): Promise<void> {
    try {
      await this.applyPending();
      const change: KeyboardSettingsChange | undefined = this.ports.nextSettingsChange();
      if (change) { await this.publish(CHANGE, JSON.stringify(change)); }
    }
    finally {
      if (this.applicationPending || this.ports.nextSettingsChange() !== undefined) { this.retry.schedule(); }
      else { this.retry.stop(); }
    }
  }

  private publish(event: string, data: string, actor: string = '', sequence: number = 0): Promise<void> {
    return this.ports.publish({ event: event, data: data, sender: this.ime ? 'ime' : 'app',
      actor: actor, sequence: sequence });
  }
}
