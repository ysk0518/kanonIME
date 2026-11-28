import { KANON_DEBUG_CONSOLE, KANON_DEBUG_ENABLED, KANON_PACHINKO_REPLAY } from './AppStorageKeys';
import { PachinkoReplay, parsePachinkoReplay } from './PachinkoModel';
import commonEventManager from '@ohos.commonEventManager';
import { BusinessError } from '@ohos.base';

const BUNDLE: string = 'local.yplic.kanon';
const CONTROL: string = `${BUNDLE}.DEBUG_CONTROL`;
const RECORD: string = `${BUNDLE}.DEBUG_RECORD`;
const REQUEST: string = `${BUNDLE}.DEBUG_REQUEST`;
const PACHINKO_REQUEST: string = `${BUNDLE}.DEBUG_PACHINKO_REQUEST`;
const PACHINKO_REPLAY: string = `${BUNDLE}.DEBUG_PACHINKO_REPLAY`;
const LIMIT: number = 160;

class DebugRecord {
  time: number = 0;
  process: string = '';
  stage: string = '';
  detail: string = '';
}

/** Opt-in, bounded metadata only. Never pass text, image data, URIs or error messages here. */
class DebugLogStore {
  private enabled: boolean = false;
  private ime: boolean = false;
  private instance: string = `${Date.now()}-${Math.random()}`;
  private subscriber: commonEventManager.CommonEventSubscriber | undefined;
  private ready: Promise<void> | undefined;
  private lines: string[] = [];
  private flushTimer: number = -1;
  private leaseTimer: number = -1;
  private pendingReplay: PachinkoReplay | undefined;
  private replayRequest: string = '';
  private replaySequence: number = 0;
  onEnabled: () => void = () => {};

  initialize(ime: boolean = false): Promise<void> {
    if (ime) { this.ime = true; }
    if (this.ready) { return this.ready; }
    this.ready = this.connect().catch((error: Error) => {
      this.ready = undefined;
      this.local('console', `subscribe failed code=${debugErrorCode(error)}`);
    });
    return this.ready;
  }

  private async connect(): Promise<void> {
    this.subscriber = await commonEventManager.createSubscriber({
      events: [CONTROL, RECORD, REQUEST, PACHINKO_REQUEST, PACHINKO_REPLAY], publisherBundleName: BUNDLE
    });
    commonEventManager.subscribe(this.subscriber, (error, event) => {
      if (error) { this.local('console', `receive failed code=${error.code}`); return; }
      if (event.parameters?.['instance'] === this.instance) { return; }
      if (event.event === REQUEST) {
        if (!this.ime) { this.send(CONTROL, this.enabled ? 'on' : 'off'); }
      } else if (event.event === PACHINKO_REQUEST || event.event === PACHINKO_REPLAY) {
        this.receivePachinkoEvent(event);
      } else if (event.event === CONTROL && (event.data === 'on' || event.data === 'off')) {
        this.applyEnabled(event.data === 'on');
        if (this.enabled) { this.record('console', 'peer connected'); }
      } else if (event.event === RECORD && this.enabled && event.data && event.data.length <= 600) {
        try {
          const record: DebugRecord = JSON.parse(event.data) as DebugRecord;
          if (Number.isFinite(record.time) && (record.process === 'app' || record.process === 'ime') &&
            typeof record.stage === 'string' && /^[a-z-]{1,32}$/.test(record.stage) &&
            typeof record.detail === 'string' && record.detail.length <= 300) { this.append(record); }
        } catch (error) { this.local('console', 'invalid log packet'); }
      }
    });
    this.send(REQUEST, '');
    if (this.enabled) { this.send(CONTROL, 'on'); }
  }

  private send(event: string, data: string, request: string = ''): void {
    try {
      commonEventManager.publish(event, { bundleName: BUNDLE, data: data,
        parameters: { instance: this.instance, request: request } }, (error) => {
        if (error) { this.local('console', `transport failed code=${error.code}`); }
      });
    } catch (error) { this.local('console', `transport failed code=${debugErrorCode(error)}`); }
  }

  private applyEnabled(value: boolean): void {
    this.enabled = value;
    AppStorage.setOrCreate(KANON_DEBUG_ENABLED, value);
    if (!value) {
      this.pendingReplay = undefined;
      this.cancelPachinkoReplay();
      this.clear();
    }
    if (value) { this.onEnabled(); }
    if (this.leaseTimer >= 0) { clearTimeout(this.leaseTimer); this.leaseTimer = -1; }
    // Do not leave diagnostics running indefinitely if the settings app exits.
    if (value) { this.leaseTimer = setTimeout(() => this.setEnabled(false), 15 * 60 * 1000); }
  }

  setEnabled(value: boolean): void {
    this.applyEnabled(value);
    if (value) { this.local('console', 'enabled; metadata only; expires in 15 minutes'); }
    this.initialize().then(() => this.send(CONTROL, value ? 'on' : 'off'));
  }

  queuePachinkoReplay(replay: PachinkoReplay): boolean {
    if (!this.enabled || this.ime) { return false; }
    this.pendingReplay = replay;
    return true;
  }

  requestPachinkoReplay(): void {
    const request: string = `${this.instance}-${++this.replaySequence}`;
    this.replayRequest = request;
    this.initialize(true).then(() => {
      if (this.replayRequest === request) { this.send(PACHINKO_REQUEST, '', request); }
    });
  }

  cancelPachinkoReplay(): void {
    this.replayRequest = '';
    if (AppStorage.get<string>(KANON_PACHINKO_REPLAY)) { AppStorage.setOrCreate(KANON_PACHINKO_REPLAY, ''); }
  }

  private receivePachinkoEvent(event: commonEventManager.CommonEventData): void {
    const request: string | undefined = typeof event.parameters?.['request'] === 'string' ?
      event.parameters['request'] as string : undefined;
    if (!request || request.length > 100) { return; }
    if (event.event === PACHINKO_REQUEST) {
      if (this.ime || !this.enabled || this.pendingReplay === undefined) { return; }
      this.send(PACHINKO_REPLAY, this.pendingReplay, request);
      this.pendingReplay = undefined;
    } else if (this.ime && request === this.replayRequest) {
      const replay: PachinkoReplay | undefined = parsePachinkoReplay(event.data);
      if (replay !== undefined) {
        this.replayRequest = '';
        AppStorage.setOrCreate(KANON_PACHINKO_REPLAY, replay);
      }
    }
  }

  record(stage: string, detail: string): void {
    if (!this.enabled) { return; }
    const record: DebugRecord = this.makeRecord(stage, detail);
    this.append(record);
    if (this.subscriber) { this.send(RECORD, JSON.stringify(record)); }
  }

  private makeRecord(stage: string, detail: string): DebugRecord {
    const record = new DebugRecord();
    record.time = Date.now();
    record.process = this.ime ? 'ime' : 'app';
    record.stage = stage;
    record.detail = detail.substring(0, 300);
    return record;
  }

  private local(stage: string, detail: string): void {
    if (this.enabled) { this.append(this.makeRecord(stage, detail)); }
  }

  private append(record: DebugRecord): void {
    const time: string = new Date(record.time).toISOString().substring(11, 23);
    this.lines.push(`${time} UTC [${record.process}/${record.stage}] ${record.detail}`);
    if (this.lines.length > LIMIT) { this.lines.splice(0, this.lines.length - LIMIT); }
    if (this.flushTimer < 0) {
      this.flushTimer = setTimeout(() => {
        this.flushTimer = -1;
        AppStorage.setOrCreate(KANON_DEBUG_CONSOLE, this.lines.join('\n'));
      }, 100);
    }
  }

  clear(): void {
    this.lines = [];
    if (this.flushTimer >= 0) { clearTimeout(this.flushTimer); this.flushTimer = -1; }
    AppStorage.setOrCreate(KANON_DEBUG_CONSOLE, '');
  }
}

export function debugErrorCode(error: Object): string {
  const code: number | string | undefined = (error as BusinessError).code;
  return typeof code === 'number' || (typeof code === 'string' && /^-?\d+$/.test(code)) ? `${code}` : 'unknown';
}

export const debugLog: DebugLogStore = new DebugLogStore();
