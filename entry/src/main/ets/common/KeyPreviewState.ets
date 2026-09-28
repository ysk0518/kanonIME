// One overlay is shared by all keys. Only its current owner may clear it.
export function showKeyPreview(owner: string, value: string, x: number, y: number, kind: string,
  directions: string[] = [], direction: number = 0, keyHeight: number = 0,
  flickDistance: number = 18): void {
  AppStorage.setOrCreate('kanonFlickPreviewOwner', owner);
  AppStorage.setOrCreate('kanonFlickPreviewX', x);
  AppStorage.setOrCreate('kanonFlickPreviewY', y);
  AppStorage.setOrCreate('kanonKeyPreviewKind', kind);
  AppStorage.setOrCreate('kanonKeyPreviewDirections', directions.slice());
  AppStorage.setOrCreate('kanonKeyPreviewDirection', direction);
  AppStorage.setOrCreate('kanonKeyPreviewKeyHeight', keyHeight);
  AppStorage.setOrCreate('kanonKeyPreviewFlickDistance', flickDistance);
  AppStorage.setOrCreate('kanonFlickPreview', value);
}

export function hideKeyPreview(owner: string): void {
  if (AppStorage.get<string>('kanonFlickPreviewOwner') !== owner) { return; }
  AppStorage.setOrCreate('kanonFlickPreview', '');
  AppStorage.setOrCreate('kanonKeyPreviewDirections', [] as string[]);
  AppStorage.setOrCreate('kanonFlickPreviewOwner', '');
}
