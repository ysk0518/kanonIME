export const DEFAULT_GIF_ANIMATE: boolean = true;

export class BackgroundConfig {
  version: number = 0;
  photo: string = '';
  format: string = 'jpeg';
  poster: string = '';
  animate: boolean = DEFAULT_GIF_ANIMATE;
  sourceId: string = '';
  gifResolution: number = 0;
  gifFps: number = 0;
  gifWidth: number = 0;
  gifHeight: number = 0;
  gifFrames: number = 0;
  zoom: number = 100;
  x: number = 0;
  y: number = 0;
  brightness: number = 75;
  keyOpacity: number = 85;
}

export function backgroundDraftChanged(draft: BackgroundConfig, saved: BackgroundConfig): boolean {
  return draft.photo !== saved.photo || draft.format !== saved.format || draft.poster !== saved.poster ||
    draft.animate !== saved.animate || draft.sourceId !== saved.sourceId ||
    draft.gifResolution !== saved.gifResolution || draft.gifFps !== saved.gifFps ||
    draft.gifWidth !== saved.gifWidth || draft.gifHeight !== saved.gifHeight || draft.gifFrames !== saved.gifFrames ||
    draft.zoom !== saved.zoom || draft.x !== saved.x || draft.y !== saved.y ||
    draft.brightness !== saved.brightness || draft.keyOpacity !== saved.keyOpacity;
}

export const MAX_BACKGROUND_PHOTO: number = 6800000;
export const MAX_BACKGROUND_POSTER: number = 350000;
export const MAX_BACKGROUND_PAYLOAD: number = 7500000;
export const MAX_BACKGROUND_CHUNKS: number = 235;

export function backgroundImageUri(config: BackgroundConfig): string {
  return config.photo.length > 0 ? `data:image/${config.format};base64,${config.photo}` : '';
}

export function backgroundPosterUri(config: BackgroundConfig): string {
  return config.poster.length > 0 ? `data:image/jpeg;base64,${config.poster}` : '';
}
