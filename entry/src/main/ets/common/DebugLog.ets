import commonEventManager from '@ohos.commonEventManager';
import { BusinessError } from '@ohos.base';

const BUNDLE: string = 'local.yplic.kanon';
const CONTROL: string = `${BUNDLE}.DEBUG_CONTROL`;
const RECORD: string = `${BUNDLE}.DEBUG_RECORD`;
const REQUEST: string = `${BUNDLE}.DEBUG_REQUEST`;
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
      events: [CONTROL, RECORD, REQUEST], publisherBundleName: BUNDLE
    });
    commonEventManager.subscribe(this.subscriber, (error, event) => {
      if (error) { this.local('console', `receive failed code=${error.code}`); return; }
      if (event.parameters?.['instance'] === this.instance) { return; }
      if (event.event === REQUEST) {
        if (!this.ime) { this.send(CONTROL, this.enabled ? 'on' : 'off'); }
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

  private send(event: string, data: string): void {
    try {
      commonEventManager.publish(event, { bundleName: BUNDLE, data: data,
        parameters: { instance: this.instance } }, (error) => {
        if (error) { this.local('console', `transport failed code=${error.code}`); }
      });
    } catch (error) { this.local('console', `transport failed code=${debugErrorCode(error)}`); }
  }

  private applyEnabled(value: boolean): void {
    this.enabled = value;
    AppStorage.setOrCreate('kanonDebugEnabled', value);
    if (!value) { this.clear(); }
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
        AppStorage.setOrCreate('kanonDebugConsole', this.lines.join('\n'));
      }, 100);
    }
  }

  clear(): void {
    this.lines = [];
    if (this.flushTimer >= 0) { clearTimeout(this.flushTimer); this.flushTimer = -1; }
    AppStorage.setOrCreate('kanonDebugConsole', '');
  }
}

export function debugErrorCode(error: Object): string {
  const code: number | string | undefined = (error as BusinessError).code;
  return typeof code === 'number' || (typeof code === 'string' && /^-?\d+$/.test(code)) ? `${code}` : 'unknown';
}

export const debugLog: DebugLogStore = new DebugLogStore();
