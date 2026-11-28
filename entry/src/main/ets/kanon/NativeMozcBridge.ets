import fs from '@ohos.file.fs';
import { debugLog, debugErrorCode } from '../common/DebugLog';
import { MozcBridgePort } from './MozcBridgePort';
import { perfBegin, perfEnd, perfMark } from '../common/PerfTrace';

interface NativeApi {
  executeAsync(operation: string, text: string, candidateId: number): Promise<string>;
}

interface NativeInitResult {
  ok: boolean;
}

/** Harmony/native infrastructure; composition rules belong to MozcEngine. */
export class NativeMozcBridge implements MozcBridgePort {
  private api: NativeApi | null = null;
  private initFailed: boolean = false;
  private profileDirectory: string = '';

  /** Must run before loading Mozc, whose character-form storage is a singleton. */
  configureProfile(filesDirectory: string): void {
    if (this.api !== null || this.profileDirectory.length > 0) { return; }
    const directory: string = `${filesDirectory}/mozc`;
    try {
      if (filesDirectory.length === 0) { return; }
      if (!fs.accessSync(directory)) { fs.mkdirSync(directory, true); }
      const probe: fs.File = fs.openSync(`${directory}/.writable`,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.closeSync(probe);
      fs.unlinkSync(`${directory}/.writable`);
      this.profileDirectory = directory;
      this.initFailed = false;
      debugLog.record('engine', 'profile ready=true');
    } catch (error) {
      debugLog.record('engine', `profile ready=false code=${debugErrorCode(error)}`);
    }
  }

  /**
   * Loads Mozc once. The IME starts this as soon as it is created, and later
   * callers (the keyboard page, the first key) join the same load instead of
   * starting a second one.
   */
  prepare(): Promise<boolean> {
    if (this.api !== null) { return Promise.resolve(true); }
    if (this.pending === null) {
      this.pending = this.load().finally((): void => { this.pending = null; });
    }
    return this.pending;
  }

  private pending: Promise<boolean> | null = null;

  private async load(): Promise<boolean> {
    if (this.api !== null) { return true; }
    if (this.initFailed || this.profileDirectory.length === 0) { return false; }
    const perfId: number = perfBegin('mozc.init.start');
    try {
      const m: ESObject = await import('libkanon_bridge.so');
      // Splits the initialization: loading the library versus creating the session.
      perfMark('mozc.load.end', perfId.toString());
      const ns: ESObject = m as ESObject;
      const d: ESObject = ns.default as ESObject;
      const api: NativeApi = (d ?? ns) as NativeApi;
      if (api === null || api === undefined) { this.initFailed = true; return false; }
      const result: NativeInitResult = JSON.parse(
        await api.executeAsync('init', this.profileDirectory, 0)) as NativeInitResult;
      if (result.ok !== true) { this.initFailed = true; return false; }
      this.api = api;
      perfEnd('mozc.init.end', perfId);
      return true;
    } catch (error) {
      this.initFailed = true;
      return false;
    }
  }

  undo(): Promise<string> {
    return this.executeAsync('undo', '', 0);
  }

  async executeAsync(operation: string, text: string, candidateId: number): Promise<string> {
    if (this.api === null) { throw new Error('Mozc bridge is not prepared'); }
    return this.api.executeAsync(operation, text, candidateId);
  }
}
