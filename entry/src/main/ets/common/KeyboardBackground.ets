import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import util from '@ohos.util';
import commonEventManager from '@ohos.commonEventManager';
import { ColorMetrics } from '@ohos.arkui.node';
import { BackgroundConfig, backgroundImageUri, backgroundPosterUri,
  MAX_BACKGROUND_PHOTO, MAX_BACKGROUND_POSTER, MAX_BACKGROUND_PAYLOAD, MAX_BACKGROUND_CHUNKS } from './BackgroundAppearance';
import { BackgroundLivePreview, PREVIEW_EVENT, END_PREVIEW_EVENT } from './BackgroundLivePreview';
import { debugLog, debugErrorCode } from './DebugLog';
import { keyboardConfigDiagnostics } from './KeyboardConfig';
import { settingsReceipt } from './SettingsReceipt';
export { BackgroundConfig } from './BackgroundAppearance';

const BUNDLE: string = 'local.yplic.kanon';
const UPDATE: string = `${BUNDLE}.BACKGROUND_UPDATE`;
const REQUEST: string = `${BUNDLE}.BACKGROUND_REQUEST`;
const ACK: string = `${BUNDLE}.BACKGROUND_ACK`;
const CHUNK: number = 32000;

// The theme revision argument makes resource-derived alpha colors reactive to color-mode changes.
export function backgroundKeyColor(color: ResourceColor, opacity: number, themeRevision: number = 0): ResourceColor {
  if (opacity >= 100) { return color; }
  try {
    const resolved: ColorMetrics = ColorMetrics.resourceColor(color);
    return ColorMetrics.rgba(resolved.red, resolved.green, resolved.blue,
      resolved.alpha / 255 * Math.max(0, opacity) / 100).color;
  } catch (error) { return color; }
}

function bounded(value: number, min: number, max: number, fallback: number): number {
  return Number.isFinite(value) ? Math.max(min, Math.min(max, value)) : fallback;
}

function normalized(config: BackgroundConfig, checkPhoto: boolean = true): BackgroundConfig {
  const out = new BackgroundConfig();
  out.version = bounded(config.version, 0, Number.MAX_SAFE_INTEGER, 0);
  out.format = config.format === 'gif' ? 'gif' : 'jpeg';
  out.animate = config.animate !== false;
  out.sourceId = typeof config.sourceId === 'string' && /^gif-\d+-\d+$/.test(config.sourceId) ? config.sourceId : '';
  out.gifResolution = Math.round(bounded(config.gifResolution, 0, 1280, 0));
  out.gifFps = Math.round(bounded(config.gifFps, 0, 100, 0));
  out.gifWidth = Math.round(bounded(config.gifWidth, 0, 1280, 0));
  out.gifHeight = Math.round(bounded(config.gifHeight, 0, 1280, 0));
  out.gifFrames = Math.round(bounded(config.gifFrames, 0, 120, 0));
  out.poster = typeof config.poster === 'string' && config.poster.length <= MAX_BACKGROUND_POSTER &&
    (!checkPhoto || /^[A-Za-z0-9+/=]*$/.test(config.poster)) ? config.poster : '';
  out.photo = typeof config.photo === 'string' && config.photo.length <=
    (out.format === 'gif' ? MAX_BACKGROUND_PHOTO : 700000) &&
    (!checkPhoto || /^[A-Za-z0-9+/=]*$/.test(config.photo)) ? config.photo : '';
  if (out.format === 'gif' && out.poster.length === 0) { out.photo = ''; }
  out.zoom = bounded(config.zoom, 100, 250, 100);
  out.x = bounded(config.x, -100, 100, 0);
  out.y = bounded(config.y, -100, 100, 0);
  out.brightness = bounded(config.brightness, 20, 100, 75);
  out.keyOpacity = bounded(config.keyOpacity, 0, 100, 85);
  return out;
}

class KeyboardBackgroundStore {
  private context: common.Context | undefined;
  private subscriber: commonEventManager.CommonEventSubscriber | undefined;
  private current: BackgroundConfig = new BackgroundConfig();
  private incomingVersion: number = 0;
  private chunks: string[] = [];
  private chunkCount: number = 0;
  private incomingAt: number = 0;
  private ready: Promise<void> | undefined;
  private ime: boolean = false;
  private peerVersion: number = 0;
  private live: BackgroundLivePreview = new BackgroundLivePreview();
  private visiblePreview: BackgroundConfig | undefined;
  private originalRevision: number = 0;

  initialize(context: common.Context, ime: boolean = false): Promise<void> {
    if (ime) { this.ime = true; }
    debugLog.initialize(ime);
    debugLog.onEnabled = () => {
      debugLog.record('config', keyboardConfigDiagnostics());
      debugLog.record('background', `state version=${this.current.version} peer=${this.peerVersion} format=${this.current.format} photoChars=${this.current.photo.length} preview=${this.visiblePreview !== undefined}`);
      this.requestSync().catch((error: Error) => debugLog.record('background', `sync request failed code=${debugErrorCode(error)}`));
    };
    if (this.ready !== undefined) { return this.ready; }
    this.context = context;
    try {
      this.current = normalized(JSON.parse(fs.readTextSync(`${context.filesDir}/keyboard-background.json`)) as BackgroundConfig);
      debugLog.record('background', `disk loaded version=${this.current.version} photoChars=${this.current.photo.length}`);
    } catch (error) {
      debugLog.record('background', `disk load unavailable code=${debugErrorCode(error)}`);
      this.current = new BackgroundConfig();
    }
    this.apply();
    this.ready = this.connect().catch((error: Error) => {
      debugLog.record('background', `connect failed code=${debugErrorCode(error)}`);
      this.ready = undefined;
      throw error;
    });
    return this.ready;
  }

  private async connect(): Promise<void> {
    this.live.onPreview = (config: BackgroundConfig | undefined) => {
      this.visiblePreview = config ? normalized(config, false) : undefined;
      this.apply();
    };
    this.live.onError = () => { AppStorage.setOrCreate('kanonBackgroundPreviewError', true); };
    this.subscriber = await commonEventManager.createSubscriber({
      events: [UPDATE, REQUEST, ACK, PREVIEW_EVENT, END_PREVIEW_EVENT], publisherBundleName: BUNDLE
    });
    commonEventManager.subscribe(this.subscriber, (error, event) => {
      if (error) { debugLog.record('background', `subscription error code=${error.code}`); return; }
      if (event.parameters?.['sender'] === (this.ime ? 'ime' : 'app')) { return; }
      if (event.event === PREVIEW_EVENT || event.event === END_PREVIEW_EVENT) {
        if (this.ime && event.parameters?.['sender'] === 'app') { this.live.receive(event); }
        return;
      }
      if (event.event === ACK) {
        const version: number = Number(event.data);
        debugLog.record('background', `ack version=${version} expected=${this.current.version}`);
        if (Number.isSafeInteger(version) && version > this.peerVersion) {
          this.peerVersion = version;
          AppStorage.setOrCreate('kanonBackgroundPeerVersion', version);
          settingsReceipt.applied('background', version);
        }
        return;
      }
      if (event.event === REQUEST) {
        if (!this.ime) { this.live.resend(); }
        const version: number = Number(event.data);
        debugLog.record('background', `sync request peer=${version} local=${this.current.version}`);
        if (this.current.version > version) { this.broadcast().catch(() => {}); }
        else { this.publish(ACK, this.current.version.toString()).catch(() => {}); }
      } else { this.receive(event); }
    });
    debugLog.record('background', 'subscribed');
    await this.requestSync();
  }

  get(): BackgroundConfig {
    return normalized(this.current);
  }

  private apply(): void {
    const config: BackgroundConfig = this.visiblePreview ?? this.current;
    if (this.visiblePreview === undefined) {
      debugLog.record('background', `apply saved version=${config.version} format=${config.format} photoChars=${config.photo.length}`);
    }
    AppStorage.setOrCreate('kanonBackgroundImage', backgroundImageUri(config));
    AppStorage.setOrCreate('kanonBackgroundPoster', backgroundPosterUri(config));
    AppStorage.setOrCreate('kanonBackgroundAnimate', config.animate);
    AppStorage.setOrCreate('kanonBackgroundZoom', config.zoom);
    AppStorage.setOrCreate('kanonBackgroundX', config.x);
    AppStorage.setOrCreate('kanonBackgroundY', config.y);
    AppStorage.setOrCreate('kanonBackgroundBrightness', config.brightness);
    AppStorage.setOrCreate('kanonBackgroundKeyOpacity', config.photo.length > 0 ? config.keyOpacity : 100);
    AppStorage.setOrCreate('kanonBackgroundVersion', this.current.version);
  }

  preview(config: BackgroundConfig): void {
    this.live.update(config);
  }

  endPreview(): void { this.live.end(); }

  async keepGifOriginal(config: BackgroundConfig): Promise<void> {
    if (!this.context || this.ime) { throw new BackgroundPhotoError($r('app.string.background_error_original_save_failed')); }
    let file: fs.File | undefined;
    try {
      if (config.sourceId.length > 0 && fs.accessSync(`${this.context.filesDir}/${config.sourceId}.gif`)) { return; }
      const id: string = `gif-${Date.now()}-${++this.originalRevision}`;
      file = await fs.open(`${this.context.filesDir}/${id}.gif`, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      const bytes: Uint8Array = new util.Base64Helper().decodeSync(config.photo);
      const written: number = await fs.write(file.fd, bytes.buffer);
      if (written !== bytes.byteLength) { throw new Error('Incomplete GIF'); }
      config.sourceId = id;
    } catch (error) { throw new BackgroundPhotoError($r('app.string.background_error_original_save_failed')); }
    finally { if (file) { try { await fs.close(file); } catch (error) {} } }
  }

  async gifOriginal(config: BackgroundConfig): Promise<string> {
    if (!this.context || !/^gif-\d+-\d+$/.test(config.sourceId)) { return config.photo; }
    const path: string = `${this.context.filesDir}/${config.sourceId}.gif`;
    let file: fs.File | undefined;
    try {
      if (!fs.accessSync(path)) { return config.photo; }
      file = await fs.open(path, fs.OpenMode.READ_ONLY);
      const stat: fs.Stat = await fs.stat(file.fd);
      if (stat.size <= 0 || stat.size > 5000000) { throw new BackgroundPhotoError($r('app.string.background_error_original_read_failed')); }
      return new util.Base64Helper().encodeToStringSync(new Uint8Array(await readBackgroundFile(file.fd, stat.size)));
    } catch (error) { throw new BackgroundPhotoError($r('app.string.background_error_original_read_failed')); }
    finally { if (file) { try { await fs.close(file); } catch (error) {} } }
  }

  pruneGifOriginals(): void {
    if (!this.context || this.ime) { return; }
    try {
      fs.listFileSync(this.context.filesDir).forEach((name: string) => {
        if (/^gif-\d+-\d+\.gif$/.test(name) && name !== `${this.current.sourceId}.gif`) {
          try { fs.unlinkSync(`${this.context!.filesDir}/${name}`); } catch (error) {}
        }
      });
    } catch (error) {}
  }

  private persist(config: BackgroundConfig): void {
    if (!this.context) { throw new Error('Background storage unavailable'); }
    const path: string = `${this.context.filesDir}/keyboard-background.json`;
    debugLog.record('background', `disk save start version=${config.version} photoChars=${config.photo.length}`);
    let file: fs.File | undefined;
    try {
      file = fs.openSync(`${path}.tmp`, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(config));
      fs.closeSync(file);
      file = undefined;
      fs.renameSync(`${path}.tmp`, path);
      this.current = config;
      this.apply();
      debugLog.record('background', `disk save done version=${config.version}`);
    } catch (error) {
      debugLog.record('background', `disk save failed code=${debugErrorCode(error)}`);
      if (file) { try { fs.closeSync(file); } catch (closeError) {} }
      throw new Error('Background could not be saved');
    }
  }

  async save(config: BackgroundConfig): Promise<boolean> {
    if (this.ready) { await this.ready; }
    const next: BackgroundConfig = normalized(config);
    debugLog.record('background', `save normalized format=${next.format} photoChars=${next.photo.length} dropped=${config.photo.length > 0 && next.photo.length === 0}`);
    next.version = Math.max(Date.now(), this.current.version + 1);
    this.persist(next);
    settingsReceipt.saved('background', next.version);
    this.pruneGifOriginals();
    try { await this.broadcast(); }
    catch (error) {
      settingsReceipt.failed('background', debugErrorCode(error));
      // Saving succeeded; keep the change and retry transfer when the IME requests it.
      return false;
    }
    if (this.peerVersion >= next.version) { return true; }
    return settingsReceipt.wait('background', next.version);
  }

  async requestSync(): Promise<void> {
    debugLog.record('background', `request sync version=${this.current.version}`);
    await this.publish(REQUEST, this.current.version.toString());
  }

  private publish(event: string, data: string, version: number = 0,
    index: number = 0, count: number = 0): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      commonEventManager.publish(event, { bundleName: BUNDLE, data: data,
        parameters: { version: version, index: index, count: count, sender: this.ime ? 'ime' : 'app' } }, (error) => {
        if (error) {
          debugLog.record('background', `publish failed kind=${event === UPDATE ? 'update' : event === ACK ? 'ack' : 'request'} index=${index} count=${count} code=${error.code}`);
          reject(error);
        } else { resolve(); }
      });
    });
  }

  private async broadcast(): Promise<void> {
    const config: BackgroundConfig = this.get();
    const payload: string = JSON.stringify(config);
    const count: number = Math.ceil(payload.length / CHUNK);
    debugLog.record('background', `transfer start version=${config.version} chars=${payload.length} chunks=${count}`);
    for (let i: number = 0; i < count; i++) {
      await this.publish(UPDATE, payload.slice(i * CHUNK, (i + 1) * CHUNK), config.version, i, count);
    }
    debugLog.record('background', `transfer sent version=${config.version} chunks=${count}`);
  }

  private receive(event: commonEventManager.CommonEventData): void {
    const version: number = Number(event.parameters?.['version']);
    const index: number = Number(event.parameters?.['index']);
    const count: number = Number(event.parameters?.['count']);
    if (!Number.isSafeInteger(version) || version <= this.current.version ||
      !Number.isInteger(index) || !Number.isInteger(count) || count < 1 || count > MAX_BACKGROUND_CHUNKS ||
      index < 0 || index >= count || !event.data || event.data.length > CHUNK) { return; }
    if (version < this.incomingVersion && Date.now() - this.incomingAt < 30000) { return; }
    if (version !== this.incomingVersion || Date.now() - this.incomingAt > 30000) {
      debugLog.record('background', `receive start version=${version} chunks=${count}`);
      this.incomingVersion = version;
      this.chunks = [];
      this.chunkCount = count;
      this.incomingAt = Date.now();
    }
    if (count !== this.chunkCount) { debugLog.record('background', 'receive rejected chunk count'); return; }
    this.chunks[index] = event.data;
    for (let i: number = 0; i < count; i++) { if (!this.chunks[i]) { return; } }
    const payload: string = this.chunks.join('');
    this.chunks = [];
    if (payload.length > MAX_BACKGROUND_PAYLOAD) { debugLog.record('background', 'receive rejected payload limit'); return; }
    debugLog.record('background', `receive complete version=${version} chars=${payload.length}`);
    try {
      const next: BackgroundConfig = normalized(JSON.parse(payload) as BackgroundConfig);
      if (next.version === version) {
        this.persist(next);
        debugLog.record('background', `receive applied version=${version} photoChars=${next.photo.length}`);
        this.publish(ACK, version.toString()).catch(() => {});
      }
    } catch (error) { debugLog.record('background', `receive failed code=${debugErrorCode(error)}`); }
  }
}

export const keyboardBackground = new KeyboardBackgroundStore();

export class BackgroundPhotoError extends Error {
  displayMessage: Resource;
  constructor(displayMessage: Resource) {
    super('background-photo-error');
    this.displayMessage = displayMessage;
  }
}

async function readBackgroundFile(fd: number, size: number): Promise<ArrayBuffer> {
  try {
    const original = new ArrayBuffer(size);
    const output = new Uint8Array(original);
    let offset: number = 0;
    while (offset < size) {
      const chunk = new ArrayBuffer(Math.min(65536, size - offset));
      const read: number = await fs.read(fd, chunk);
      if (read <= 0) { throw new Error('Incomplete image'); }
      output.set(new Uint8Array(chunk, 0, read), offset);
      offset += read;
    }
    return original;
  } catch (error) { throw new BackgroundPhotoError($r('app.string.background_error_image_data_failed')); }
}

/** Preserve bounded GIFs with a static poster; convert other formats to bounded JPEG. */
export async function copyBackgroundPhoto(uri: string): Promise<BackgroundConfig> {
  let file: fs.File | undefined;
  let source: image.ImageSource | undefined;
  let packer: image.ImagePacker | undefined;
  let pixels: image.PixelMap | undefined;
  let gifFile: fs.File | undefined;
  let stage: string = 'open';
  try {
    file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    stage = 'decode';
    source = image.createImageSource(file.fd);
    packer = image.createImagePacker();
    const info: image.ImageInfo = await source.getImageInfo();
    debugLog.record('image', `decoded width=${info.size.width} height=${info.size.height} gif=${info.mimeType === 'image/gif'}`);
    if (info.size.width <= 0 || info.size.height <= 0) { throw new Error('Invalid image'); }
    const config = new BackgroundConfig();
    const gif: boolean = info.mimeType === 'image/gif';
    if (gif) {
      stage = 'gif-limits';
      const stat: fs.Stat = await fs.stat(file.fd);
      const frames: number = await source.getFrameCount();
      debugLog.record('gif', `selected bytes=${stat.size} frames=${frames}`);
      if (stat.size <= 0 || stat.size > 5000000 || Math.max(info.size.width, info.size.height) > 1280 ||
        frames > 120) {
        throw new BackgroundPhotoError($r('app.string.background_error_gif_selection_limits'));
      }
      gifFile = await fs.open(uri, fs.OpenMode.READ_ONLY);
      const original: ArrayBuffer = await readBackgroundFile(gifFile.fd, stat.size);
      config.format = 'gif';
      config.photo = new util.Base64Helper().encodeToStringSync(new Uint8Array(original));
    }
    const ratio: number = Math.min(1, (gif ? 480 : 1280) / Math.max(info.size.width, info.size.height));
    stage = 'pack';
    pixels = await source.createPixelMap({ desiredSize: {
      width: Math.max(1, Math.round(info.size.width * ratio)),
      height: Math.max(1, Math.round(info.size.height * ratio))
    } });
    let bytes: ArrayBuffer = await packer.packToData(pixels, { format: 'image/jpeg', quality: 80 });
    const limit: number = gif ? 250000 : 500000;
    if (bytes.byteLength > limit) {
      bytes = await packer.packToData(pixels, { format: 'image/jpeg', quality: 55 });
    }
    if (bytes.byteLength > limit && gif) {
      bytes = await packer.packToData(pixels, { format: 'image/jpeg', quality: 35 });
    }
    if (bytes.byteLength > limit) {
      debugLog.record('image', `packed limit exceeded bytes=${bytes.byteLength} limit=${limit}`);
      throw new BackgroundPhotoError($r('app.string.background_error_image_too_large'));
    }
    const jpeg: string = new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes));
    if (gif) { config.poster = jpeg; } else { config.photo = jpeg; }
    debugLog.record('image', `ready format=${config.format} photoChars=${config.photo.length} posterChars=${config.poster.length}`);
    return config;
  } catch (error) {
    debugLog.record('image', `read failed stage=${stage} code=${debugErrorCode(error)}`);
    if (error instanceof BackgroundPhotoError) { throw error; }
    throw new BackgroundPhotoError($r('app.string.background_image_read_failed'));
  }
  finally {
    if (pixels) { try { await pixels.release(); } catch (error) {} }
    if (packer) { try { await packer.release(); } catch (error) {} }
    if (source) { try { await source.release(); } catch (error) {} }
    if (file) { try { await fs.close(file); } catch (error) {} }
    if (gifFile) { try { await fs.close(gifFile); } catch (error) {} }
  }
}
