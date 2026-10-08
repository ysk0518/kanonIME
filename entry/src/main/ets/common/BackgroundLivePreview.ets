import commonEventManager from '@ohos.commonEventManager';
import { debugLog, debugErrorCode } from './DebugLog';
import { BackgroundConfig, MAX_BACKGROUND_PHOTO, MAX_BACKGROUND_POSTER,
  MAX_BACKGROUND_PAYLOAD, MAX_BACKGROUND_CHUNKS } from './BackgroundAppearance';

const BUNDLE: string = 'local.yplic.kanon';
export const PREVIEW_EVENT: string = `${BUNDLE}.BACKGROUND_PREVIEW`;
export const END_PREVIEW_EVENT: string = `${BUNDLE}.BACKGROUND_PREVIEW_END`;
const CHUNK: number = 32000;

class PreviewPacket {
  config: BackgroundConfig = new BackgroundConfig();
  hasPhoto: boolean = true;
}

/** Ephemeral transport. Images are sent once per selection; slider changes send only numbers. */
export class BackgroundLivePreview {
  private outgoing: BackgroundConfig | undefined;
  private session: number = 0;
  private lastSession: number = 0;
  private sequence: number = 0;
  private sentPhoto: string | undefined;
  private sentPoster: string | undefined;
  private photoRevision: number = 0;
  private queued: boolean = false;
  private timer: number = -1;
  private heartbeat: number = -1;
  private tail: Promise<void> = Promise.resolve();
  private closedSession: number = 0;
  private receivedSession: number = 0;
  private receivedSequence: number = 0;
  private photo: string | undefined;
  private poster: string | undefined;
  private parts: string[] = [];
  private partSession: number = 0;
  private partSequence: number = 0;
  private partCount: number = 0;
  private partAt: number = 0;
  private lease: number = -1;
  onPreview: (config: BackgroundConfig | undefined) => void = () => {};
  onError: () => void = () => {};

  update(config: BackgroundConfig): void {
    if (this.session === 0) {
      this.session = Math.max(Date.now(), this.lastSession + 1);
      this.lastSession = this.session;
      this.sentPhoto = undefined;
      this.sentPoster = undefined;
      this.sequence = 0;
      this.heartbeat = setInterval(() => this.schedule(), 10000);
    }
    this.outgoing = config;
    this.schedule();
  }

  resend(): void {
    if (!this.outgoing) { return; }
    this.sentPhoto = undefined;
    this.sentPoster = undefined;
    this.photoRevision++;
    this.schedule();
  }

  private schedule(): void {
    if (!this.outgoing || this.timer >= 0 || this.queued) { return; }
    this.timer = setTimeout(() => {
      this.timer = -1;
      this.queued = true;
      // Read the newest draft when earlier image transfers have finished.
      this.tail = this.tail.then(async () => {
        this.queued = false;
        const config: BackgroundConfig | undefined = this.outgoing;
        if (!config || this.session === 0) { return; }
        const session: number = this.session;
        const sequence: number = ++this.sequence;
        const photoRevision: number = this.photoRevision;
        const packet = new PreviewPacket();
        packet.config.version = config.version;
        packet.config.photo = config.photo;
        packet.config.poster = config.poster;
        packet.config.format = config.format;
        packet.config.animate = config.animate;
        packet.config.sourceId = config.sourceId;
        packet.config.gifResolution = config.gifResolution;
        packet.config.gifFps = config.gifFps;
        packet.config.gifWidth = config.gifWidth;
        packet.config.gifHeight = config.gifHeight;
        packet.config.gifFrames = config.gifFrames;
        packet.config.zoom = config.zoom;
        packet.config.x = config.x;
        packet.config.y = config.y;
        packet.config.brightness = config.brightness;
        packet.config.keyOpacity = config.keyOpacity;
        packet.hasPhoto = this.sentPhoto !== config.photo || this.sentPoster !== config.poster;
        if (!packet.hasPhoto) { packet.config.photo = ''; packet.config.poster = ''; }
        const payload: string = JSON.stringify(packet);
        const count: number = Math.ceil(payload.length / CHUNK);
        if (packet.hasPhoto) {
          debugLog.record('preview', `transfer start session=${session} chars=${payload.length} chunks=${count}`);
        }
        for (let index: number = 0; index < count; index++) {
          await this.publish(PREVIEW_EVENT, payload.slice(index * CHUNK, (index + 1) * CHUNK),
            session, sequence, index, count);
        }
        if (this.session === session && this.photoRevision === photoRevision) {
          this.sentPhoto = config.photo;
          this.sentPoster = config.poster;
        }
        if (packet.hasPhoto) { debugLog.record('preview', `transfer sent session=${session}`); }
      }).catch((error: Error) => {
        debugLog.record('preview', `transfer failed code=${debugErrorCode(error)}`);
        this.onError();
      });
    }, 50);
  }

  end(): void {
    const session: number = this.session;
    this.outgoing = undefined;
    this.session = 0;
    this.sentPhoto = undefined;
    this.sentPoster = undefined;
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    if (this.heartbeat >= 0) { clearInterval(this.heartbeat); this.heartbeat = -1; }
    if (session > 0) {
      debugLog.record('preview', `end session=${session}`);
      this.tail = this.tail.then(() => this.publish(END_PREVIEW_EVENT, '', session, 0, 0, 0))
        .catch(() => this.onError());
    }
  }

  private publish(event: string, data: string, session: number, sequence: number,
    index: number, count: number): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      commonEventManager.publish(event, { bundleName: BUNDLE, data: data,
        parameters: { sender: 'app', session: session, sequence: sequence, index: index, count: count } },
        (error) => {
          if (error) {
            debugLog.record('preview', `publish failed index=${index} count=${count} code=${error.code}`);
            reject(error);
          } else { resolve(); }
        });
    });
  }

  receive(event: commonEventManager.CommonEventData): void {
    const session: number = Number(event.parameters?.['session']);
    if (!Number.isSafeInteger(session) || session <= 0) { return; }
    if (event.event === END_PREVIEW_EVENT) {
      this.closedSession = Math.max(this.closedSession, session);
      if (session >= this.receivedSession) { this.restore(); }
      return;
    }
    const sequence: number = Number(event.parameters?.['sequence']);
    const index: number = Number(event.parameters?.['index']);
    const count: number = Number(event.parameters?.['count']);
    if (session <= this.closedSession || session < this.receivedSession ||
      !Number.isSafeInteger(sequence) || sequence <= 0 ||
      (session === this.receivedSession && sequence <= this.receivedSequence) ||
      !Number.isInteger(index) || !Number.isInteger(count) || count < 1 || count > MAX_BACKGROUND_CHUNKS ||
      index < 0 || index >= count || !event.data || event.data.length > CHUNK) { return; }
    if (session !== this.partSession || sequence !== this.partSequence || Date.now() - this.partAt > 30000) {
      if (session < this.partSession || (session === this.partSession && sequence < this.partSequence)) { return; }
      this.partSession = session;
      this.partSequence = sequence;
      this.partCount = count;
      this.partAt = Date.now();
      this.parts = [];
    }
    if (count !== this.partCount) { return; }
    this.parts[index] = event.data;
    for (let i: number = 0; i < count; i++) { if (!this.parts[i]) { return; } }
    const payload: string = this.parts.join('');
    this.parts = [];
    if (payload.length > MAX_BACKGROUND_PAYLOAD) { return; }
    try {
      const packet: PreviewPacket = JSON.parse(payload) as PreviewPacket;
      if (packet.hasPhoto === true) {
        if (typeof packet.config.photo !== 'string' || packet.config.photo.length > MAX_BACKGROUND_PHOTO ||
          !/^[A-Za-z0-9+/=]*$/.test(packet.config.photo) ||
          typeof packet.config.poster !== 'string' || packet.config.poster.length > MAX_BACKGROUND_POSTER ||
          !/^[A-Za-z0-9+/=]*$/.test(packet.config.poster)) { return; }
        this.photo = packet.config.photo;
        this.poster = packet.config.poster;
        debugLog.record('preview', `received image session=${session} photoChars=${packet.config.photo.length}`);
      } else {
        if (session !== this.receivedSession || this.photo === undefined) {
          debugLog.record('preview', `adjustment rejected missing image session=${session}`);
          return;
        }
        packet.config.photo = this.photo;
        packet.config.poster = this.poster ?? '';
      }
      this.receivedSession = session;
      this.receivedSequence = sequence;
      this.onPreview(packet.config);
      if (this.lease >= 0) { clearTimeout(this.lease); }
      // Restore saved settings even if the editor process is killed without END.
      this.lease = setTimeout(() => this.restore(), 30000);
    } catch (error) { debugLog.record('preview', `receive failed code=${debugErrorCode(error)}`); }
  }

  private restore(): void {
    debugLog.record('preview', 'restore saved background');
    if (this.lease >= 0) { clearTimeout(this.lease); this.lease = -1; }
    this.onPreview(undefined);
  }
}
