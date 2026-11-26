import common from '@ohos.app.ability.common';
import resourceManager from '@ohos.resourceManager';
import audio from '@ohos.multimedia.audio';
import media from '@ohos.multimedia.media';
import { KeyboardSound, KeySoundPort } from './KeyboardSound';

const CLICK: string = 'key_click.wav';

class KeySoundSession {
  active: boolean = true;
  private pool: media.SoundPool | undefined;
  private resources: resourceManager.ResourceManager | undefined;
  private volumeGroup: audio.AudioVolumeGroupManager | undefined;
  private soundId: number = 0;

  async load(context: common.Context): Promise<void> {
    try {
      this.volumeGroup = audio.getAudioManager().getVolumeManager()
        .getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID);
      // The public SDK exposes no touch-sound usage. A short UI click belongs to
      // the notification volume rather than media. Also require normal ringer mode.
      const pool: media.SoundPool = await media.createSoundPool(4, {
        usage: audio.StreamUsage.STREAM_USAGE_NOTIFICATION, rendererFlags: 0
      });
      this.pool = pool;
      if (!this.active) { return; }
      pool.on('loadComplete', (soundId: number): void => { this.soundId = soundId; });
      const resources: resourceManager.ResourceManager = context.resourceManager;
      const descriptor: resourceManager.RawFileDescriptor = resources.getRawFdSync(CLICK);
      this.resources = resources;
      await pool.load(descriptor.fd, descriptor.offset, descriptor.length);
    } catch (error) {
      await this.release();
    }
  }

  play(volume: number): Promise<void> {
    const pool: media.SoundPool | undefined = this.pool;
    if (!pool || this.soundId <= 0 || !this.active ||
      this.volumeGroup?.getRingerModeSync() !== audio.AudioRingMode.RINGER_MODE_NORMAL) { return Promise.resolve(); }
    // Start at once without waiting for the previous click. The pool keeps up to
    // four overlapping streams and drops the oldest, so fast typing never queues.
    return pool.play(this.soundId, { leftVolume: volume, rightVolume: volume })
      .then((): void => {}).catch((): void => {});
  }

  async release(): Promise<void> {
    const pool: media.SoundPool | undefined = this.pool;
    this.pool = undefined;
    this.soundId = 0;
    try { await pool?.release(); } catch (error) {}
    try { this.resources?.closeRawFdSync(CLICK); } catch (error) {}
    this.resources = undefined;
  }
}

class HarmonyKeyboardSound implements KeySoundPort {
  private session: KeySoundSession | undefined;
  private lifecycle: Promise<void> = Promise.resolve();

  prepare(context: common.Context): void {
    if (this.session) { return; }
    const session: KeySoundSession = new KeySoundSession();
    this.session = session;
    // Release an old pool before creating another, including on SDK versions
    // that allow only one SoundPool per process.
    this.lifecycle = this.lifecycle.then(async (): Promise<void> => {
      if (session.active) { await session.load(context); }
    });
  }

  play(volume: number): Promise<void> {
    return this.session?.play(volume) ?? Promise.resolve();
  }

  release(): void {
    const session: KeySoundSession | undefined = this.session;
    if (!session) { return; }
    this.session = undefined;
    session.active = false;
    this.lifecycle = this.lifecycle.then((): Promise<void> => session.release());
  }
}

export const harmonyKeyboardSound: HarmonyKeyboardSound = new HarmonyKeyboardSound();
export const keyboardSound: KeyboardSound = new KeyboardSound(harmonyKeyboardSound);
