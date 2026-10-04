import image from '@ohos.multimedia.image';
import util from '@ohos.util';
import { BackgroundConfig } from './BackgroundAppearance';
import { BackgroundPhotoError } from './KeyboardBackground';

/** GIF delays use hundredths of a second, as does PackingOptionsForSequence. */
function frameDelays(bytes: Uint8Array): number[] {
  if (bytes.length < 13 || bytes[0] !== 71 || bytes[1] !== 73 || bytes[2] !== 70) {
    throw new BackgroundPhotoError($r('app.string.background_error_gif_read_failed'));
  }
  let position: number = 13 + ((bytes[10] & 128) ? 3 * Math.pow(2, (bytes[10] & 7) + 1) : 0);
  let delay: number = 10;
  const delays: number[] = [];
  while (position < bytes.length) {
    const block: number = bytes[position++];
    if (block === 59) { return delays; }
    if (block === 33) {
      const label: number = bytes[position++];
      if (label === 249) {
        if (position + 6 > bytes.length || bytes[position] !== 4 || bytes[position + 5] !== 0) {
          throw new BackgroundPhotoError($r('app.string.background_error_gif_read_failed'));
        }
        delay = bytes[position + 2] + bytes[position + 3] * 256;
        if (delay === 0) { delay = 10; }
        position += 6;
        continue;
      }
    } else if (block === 44) {
      if (position + 9 > bytes.length) { break; }
      const flags: number = bytes[position + 8];
      position += 9 + ((flags & 128) ? 3 * Math.pow(2, (flags & 7) + 1) : 0);
      position++; // LZW minimum code size.
      delays.push(delay);
      delay = 10;
      if (delays.length > 120) { throw new BackgroundPhotoError($r('app.string.background_error_gif_frame_limit')); }
    } else { break; }
    // Image data and non-control extensions are length-prefixed sub-blocks.
    while (position < bytes.length) {
      const length: number = bytes[position++];
      if (length === 0) { break; }
      position += length;
    }
  }
  throw new BackgroundPhotoError($r('app.string.background_error_gif_incomplete'));
}

export class GifBackgroundStats {
  width: number = 0;
  height: number = 0;
  frames: number = 0;
  bytes: number = 0;
  seconds: number = 0;
  fps: number = 0;
  maxFps: number = 0;
}

/** Inspect encoded bytes without decoding any pixels. FPS is the whole-loop average. */
export function inspectBackgroundGif(encoded: string): GifBackgroundStats {
  const bytes: Uint8Array = new util.Base64Helper().decodeSync(encoded);
  const delays: number[] = frameDelays(bytes);
  const ticks: number = delays.reduce((total: number, delay: number) => total + delay, 0);
  const stats = new GifBackgroundStats();
  stats.width = bytes[6] + bytes[7] * 256;
  stats.height = bytes[8] + bytes[9] * 256;
  stats.frames = delays.length;
  stats.bytes = bytes.byteLength;
  stats.seconds = ticks / 100;
  stats.fps = ticks > 0 ? delays.length * 100 / ticks : 0;
  const minimumDelay: number = delays.reduce((minimum: number, delay: number) => Math.min(minimum, delay), 65535);
  stats.maxFps = delays.length > 0 ? 100 / minimumDelay : 0;
  return stats;
}

/** Restore the original encoded GIF, including its exact timing and palette. */
export async function restoreBackgroundGif(original: string): Promise<BackgroundConfig> {
  let source: image.ImageSource | undefined;
  let packer: image.ImagePacker | undefined;
  let pixels: image.PixelMap | undefined;
  try {
    const stats: GifBackgroundStats = inspectBackgroundGif(original);
    if (stats.bytes > 5000000 || Math.max(stats.width, stats.height) > 1280 || stats.frames === 0) {
      throw new BackgroundPhotoError($r('app.string.background_error_original_read_failed'));
    }
    source = image.createImageSource(new util.Base64Helper().decodeSync(original).buffer);
    const scale: number = Math.min(1, 480 / Math.max(stats.width, stats.height));
    pixels = await source.createPixelMap({ desiredSize: {
      width: Math.max(1, Math.round(stats.width * scale)), height: Math.max(1, Math.round(stats.height * scale))
    } });
    packer = image.createImagePacker();
    let poster: ArrayBuffer = await packer.packToData(pixels, { format: 'image/jpeg', quality: 75 });
    if (poster.byteLength > 250000) { poster = await packer.packToData(pixels, { format: 'image/jpeg', quality: 35 }); }
    if (poster.byteLength > 250000) { throw new BackgroundPhotoError($r('app.string.background_error_original_poster_failed')); }
    const config = new BackgroundConfig();
    config.format = 'gif';
    config.photo = original;
    config.poster = new util.Base64Helper().encodeToStringSync(new Uint8Array(poster));
    config.gifResolution = Math.max(stats.width, stats.height);
    config.gifFps = Math.min(100, Math.max(1, Math.ceil(stats.maxFps)));
    config.gifWidth = stats.width;
    config.gifHeight = stats.height;
    config.gifFrames = stats.frames;
    return config;
  } catch (error) {
    if (error instanceof BackgroundPhotoError) { throw error; }
    throw new BackgroundPhotoError($r('app.string.background_error_original_restore_failed'));
  } finally {
    if (pixels) { try { await pixels.release(); } catch (error) {} }
    if (packer) { try { await packer.release(); } catch (error) {} }
    if (source) { try { await source.release(); } catch (error) {} }
  }
}

/** Decode only the retained frames at target dimensions, then encode once. */
export async function processBackgroundGif(original: string, resolution: number, fps: number): Promise<BackgroundConfig> {
  let source: image.ImageSource | undefined;
  let packer: image.ImagePacker | undefined;
  const frames: image.PixelMap[] = [];
  try {
    const bytes: Uint8Array = new util.Base64Helper().decodeSync(original);
    if (bytes.byteLength > 5000000) { throw new BackgroundPhotoError($r('app.string.background_error_gif_too_large')); }
    const delays: number[] = frameDelays(bytes);
    if (delays.length === 0) { throw new BackgroundPhotoError($r('app.string.background_error_gif_no_frames')); }
    source = image.createImageSource(bytes.buffer);
    const info: image.ImageInfo = await source.getImageInfo();
    if (info.mimeType !== 'image/gif' || info.size.width <= 0 || info.size.height <= 0 ||
      Math.max(info.size.width, info.size.height) > 1280 || await source.getFrameCount() !== delays.length) {
      throw new BackgroundPhotoError($r('app.string.background_error_gif_dimensions_limit'));
    }
    const target: number = Math.max(1, Math.min(1280, Math.round(resolution)));
    const maxFps: number = Math.max(1, Math.min(100, Math.round(fps)));
    const scale: number = Math.min(1, target / Math.max(info.size.width, info.size.height));
    const width: number = Math.max(1, Math.round(info.size.width * scale));
    const height: number = Math.max(1, Math.round(info.size.height * scale));
    const indices: number[] = [];
    const ticks: number[] = [];
    const minimum: number = Math.ceil(100 / maxFps);
    let duration: number = 0;
    let start: number = 0;
    for (let index: number = 0; index < delays.length; index++) {
      duration += delays[index];
      if (duration >= minimum) {
        indices.push(start);
        ticks.push(duration);
        start = index + 1;
        duration = 0;
      }
    }
    if (duration > 0) {
      if (ticks.length > 0) { ticks[ticks.length - 1] += duration; }
      else { indices.push(0); ticks.push(duration); }
    }
    if (ticks.some((delay: number) => delay > 65535)) {
      throw new BackgroundPhotoError($r('app.string.background_error_gif_delay_too_long'));
    }
    // Native sequence encoding retains output frames. Bound that memory before decoding.
    if (width * height * 4 * indices.length > 128000000) {
      throw new BackgroundPhotoError($r('app.string.background_error_gif_memory_limit'));
    }
    for (let index: number = 0; index < indices.length; index++) {
      const pixels: image.PixelMap = await source.createPixelMap({ index: indices[index],
        desiredSize: { width: width, height: height } });
      frames.push(pixels);
      const decoded: image.ImageInfo = await pixels.getImageInfo();
      if (decoded.size.width !== width || decoded.size.height !== height) {
        await pixels.scale(width / decoded.size.width, height / decoded.size.height);
      }
    }
    packer = image.createImagePacker();
    const encoded: ArrayBuffer = await packer.packToDataFromPixelmapSequence(frames, {
      frameCount: frames.length, delayTimeList: ticks,
      disposalTypes: frames.map(() => 2), loopCount: 0
    });
    if (encoded.byteLength > 5000000) {
      throw new BackgroundPhotoError($r('app.string.background_error_gif_output_too_large'));
    }
    let poster: ArrayBuffer = await packer.packToData(frames[0], { format: 'image/jpeg', quality: 75 });
    if (poster.byteLength > 250000) { poster = await packer.packToData(frames[0], { format: 'image/jpeg', quality: 35 }); }
    if (poster.byteLength > 250000) { throw new BackgroundPhotoError($r('app.string.background_error_poster_too_large')); }
    const config = new BackgroundConfig();
    config.format = 'gif';
    config.photo = new util.Base64Helper().encodeToStringSync(new Uint8Array(encoded));
    config.poster = new util.Base64Helper().encodeToStringSync(new Uint8Array(poster));
    config.gifResolution = target;
    config.gifFps = maxFps;
    config.gifWidth = width;
    config.gifHeight = height;
    config.gifFrames = frames.length;
    return config;
  } catch (error) {
    if (error instanceof BackgroundPhotoError) { throw error; }
    throw new BackgroundPhotoError($r('app.string.background_error_gif_processing_failed'));
  } finally {
    for (let index: number = 0; index < frames.length; index++) {
      try { await frames[index].release(); } catch (error) {}
    }
    if (packer) { try { await packer.release(); } catch (error) {} }
    if (source) { try { await source.release(); } catch (error) {} }
  }
}
