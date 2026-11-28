import hilog from '@ohos.hilog';
import { PerfKeyboardFrame, perfMessage } from './PerfTraceModel';
import { KANON_BACKGROUND_HAS_PHOTO, KANON_LAYOUT, KANON_MODE } from './AppStorageKeys';

const DOMAIN: number = 0x4B50;
const TAG: string = 'KanonPerf';
const keyboardFrame: PerfKeyboardFrame = new PerfKeyboardFrame();
let sequence: number = 0;

function enabled(): boolean {
  return hilog.isLoggable(DOMAIN, TAG, hilog.LogLevel.DEBUG);
}

function writeMark(event: string, detail: string): void {
  hilog.debug(DOMAIN, TAG, '%{public}s', perfMessage(event, Date.now(), detail));
}

export function perfMark(event: string, detail: string = ''): void {
  if (enabled()) { writeMark(event, detail); }
}

export function perfBegin(event: string): number {
  if (!enabled()) { return 0; }
  const id: number = ++sequence;
  writeMark(event, id.toString());
  return id;
}

export function perfEnd(event: string, id: number): void {
  if (id !== 0) { writeMark(event, id.toString()); }
}

type FrameRequest = (done: () => void) => void;
let frameRequest: FrameRequest | undefined = undefined;

/** The keyboard page registers how to wait for its next rendered frame. */
export function perfSetFrameRequest(request: FrameRequest | undefined): void {
  frameRequest = request;
}

function markFrame(): void {
  if (!enabled()) { return; }
  const mode: string = AppStorage.get<string>(KANON_MODE) ?? '-';
  const layout: string = AppStorage.get<string>(KANON_LAYOUT) ?? '-';
  const photo: boolean | undefined = AppStorage.get<boolean>(KANON_BACKGROUND_HAS_PHOTO);
  const background: string = photo === undefined ? 'unknown' : (photo ? 'present' : 'absent');
  const detail: string = `${mode}/${layout}/${background}`;
  const request: FrameRequest | undefined = frameRequest;
  if (request === undefined) {
    writeMark('kb.frame', detail);
    return;
  }
  try {
    request((): void => { writeMark('kb.frame', detail); });
  } catch (error) {
    writeMark('kb.frame', detail);
  }
}

export function perfPanelShown(): void {
  perfMark('kb.show');
  if (keyboardFrame.show()) { markFrame(); }
}

export function perfKeyboardLaidOut(width: number, height: number): void {
  if (keyboardFrame.layout(width, height)) { markFrame(); }
}

export function perfPanelHidden(): void {
  perfMark('kb.hide');
  keyboardFrame.hide();
}

export function perfPanelReset(): void {
  keyboardFrame.reset();
}
