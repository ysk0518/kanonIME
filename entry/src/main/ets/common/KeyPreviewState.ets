import {
  KANON_FLICK_PREVIEW, KANON_FLICK_PREVIEW_OWNER, KANON_FLICK_PREVIEW_X, KANON_FLICK_PREVIEW_Y,
  KANON_KEY_PREVIEW_KIND
} from './AppStorageKeys';
// One overlay is shared by all keys. Only its current owner may clear it.
export function showKeyPreview(owner: string, value: string, x: number, y: number, kind: string): void {
  AppStorage.setOrCreate(KANON_FLICK_PREVIEW_OWNER, owner);
  AppStorage.setOrCreate(KANON_FLICK_PREVIEW_X, x);
  AppStorage.setOrCreate(KANON_FLICK_PREVIEW_Y, y);
  AppStorage.setOrCreate(KANON_KEY_PREVIEW_KIND, kind);
  AppStorage.setOrCreate(KANON_FLICK_PREVIEW, value);
}

export function hideKeyPreview(owner: string): void {
  if (AppStorage.get<string>(KANON_FLICK_PREVIEW_OWNER) !== owner) { return; }
  AppStorage.setOrCreate(KANON_FLICK_PREVIEW, '');
  AppStorage.setOrCreate(KANON_FLICK_PREVIEW_OWNER, '');
}
