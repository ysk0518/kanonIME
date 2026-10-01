// One overlay is shared by all keys. Only its current owner may clear it.
export function showKeyPreview(owner: string, value: string, x: number, y: number, kind: string): void {
  AppStorage.setOrCreate('kanonFlickPreviewOwner', owner);
  AppStorage.setOrCreate('kanonFlickPreviewX', x);
  AppStorage.setOrCreate('kanonFlickPreviewY', y);
  AppStorage.setOrCreate('kanonKeyPreviewKind', kind);
  AppStorage.setOrCreate('kanonFlickPreview', value);
}

export function hideKeyPreview(owner: string): void {
  if (AppStorage.get<string>('kanonFlickPreviewOwner') !== owner) { return; }
  AppStorage.setOrCreate('kanonFlickPreview', '');
  AppStorage.setOrCreate('kanonFlickPreviewOwner', '');
}
