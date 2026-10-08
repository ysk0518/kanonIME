import { DEFAULT_LAYOUT_ORDER, DEFAULT_FLICK_ENABLED, DEFAULT_FLICK_DISTANCE, DEFAULT_LONG_PRESS_MS,
  DEFAULT_KEY_PREVIEW_ENABLED, DEFAULT_HAPTIC_LEVEL, KEYBOARD_LAYOUTS, languageLayouts } from './KeyboardConfigValues';
import { DEFAULT_SHORTCUT_ORDER, SHORTCUT_IDS, shortcutOrder } from './ShortcutConfig';
import { DEFAULT_KEYBOARD_HEIGHT_PERCENT, MIN_KEYBOARD_HEIGHT_PERCENT, MAX_KEYBOARD_HEIGHT_PERCENT,
  DEFAULT_KEY_GAP, MIN_KEY_GAP, MAX_KEY_GAP } from './KeyboardLayout';

export class KeyboardSettingsSnapshot {
  schema: number = 1;
  revision: number = 0;
  layoutOrder: string = DEFAULT_LAYOUT_ORDER;
  flickEnabled: boolean = DEFAULT_FLICK_ENABLED;
  flickDistance: number = DEFAULT_FLICK_DISTANCE;
  longPressMs: number = DEFAULT_LONG_PRESS_MS;
  keyPreview: boolean = DEFAULT_KEY_PREVIEW_ENABLED;
  keyGap: number = DEFAULT_KEY_GAP;
  hapticLevel: number = DEFAULT_HAPTIC_LEVEL;
  shortcutOrder: string = DEFAULT_SHORTCUT_ORDER;
  heightPercent: number = DEFAULT_KEYBOARD_HEIGHT_PERCENT;
}

/** Only explicitly edited fields are merged into the authoritative snapshot. */
export interface KeyboardSettingsPatch {
  layoutOrder?: string;
  layoutKind?: string;
  flickEnabled?: boolean;
  flickDistance?: number;
  longPressMs?: number;
  keyPreview?: boolean;
  keyGap?: number;
  hapticLevel?: number;
  shortcutOrder?: string;
  heightPercent?: number;
}

export class KeyboardSettingsChange {
  actor: string = '';
  sequence: number = 0;
  patch: KeyboardSettingsPatch = {};
}

export class SettingsPeer {
  actor: string = '';
  sequence: number = 0;
}

export class KeyboardSettingsRecord {
  schema: number = 1;
  snapshot: KeyboardSettingsSnapshot = new KeyboardSettingsSnapshot();
  actor: string = `${Date.now()}-${Math.floor(Math.random() * 1000000000)}`;
  nextSequence: number = 1;
  pending: KeyboardSettingsChange[] = [];
  peers: SettingsPeer[] = [];
  legacyHeightPresent: boolean = false;
  legacyLayoutPresent: boolean = false;
  heightChosen: boolean = false;
  languagesChosen: boolean = false;
  bootstrapComplete: boolean = false;
}

function inRange(value: number, minimum: number, maximum: number): boolean {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function validLayouts(value: string): boolean {
  if (typeof value !== 'string' || value.length === 0 || value.length > 80) { return false; }
  const items: string[] = value.split(',');
  return items.length <= 2 && items.every((id: string) => KEYBOARD_LAYOUTS.includes(id)) &&
    languageLayouts(value).length === items.length;
}

function validShortcuts(value: string): boolean {
  return typeof value === 'string' && value.length <= 80 && (value === '' ||
    value.split(',').every((id: string) => SHORTCUT_IDS.includes(id)));
}

export function validSettingsPatch(patch: KeyboardSettingsPatch): boolean {
  if (!patch) { return false; }
  return (patch.layoutOrder === undefined || validLayouts(patch.layoutOrder)) &&
    (patch.layoutKind === undefined || patch.layoutKind === 'flick' || patch.layoutKind === 'qwerty') &&
    (patch.flickEnabled === undefined || typeof patch.flickEnabled === 'boolean') &&
    (patch.flickDistance === undefined || inRange(patch.flickDistance, 12, 30)) &&
    (patch.longPressMs === undefined || inRange(patch.longPressMs, 250, 650)) &&
    (patch.keyPreview === undefined || typeof patch.keyPreview === 'boolean') &&
    (patch.keyGap === undefined || inRange(patch.keyGap, MIN_KEY_GAP, MAX_KEY_GAP)) &&
    (patch.hapticLevel === undefined || patch.hapticLevel === 0 || patch.hapticLevel === 1 || patch.hapticLevel === 2) &&
    (patch.shortcutOrder === undefined || validShortcuts(patch.shortcutOrder)) &&
    (patch.heightPercent === undefined || inRange(patch.heightPercent, MIN_KEYBOARD_HEIGHT_PERCENT, MAX_KEYBOARD_HEIGHT_PERCENT));
}

export function validSettingsSnapshot(snapshot: KeyboardSettingsSnapshot): boolean {
  return !!snapshot && snapshot.schema === 1 && Number.isSafeInteger(snapshot.revision) && snapshot.revision >= 0 &&
    validLayouts(snapshot.layoutOrder) && typeof snapshot.flickEnabled === 'boolean' &&
    inRange(snapshot.flickDistance, 12, 30) && inRange(snapshot.longPressMs, 250, 650) &&
    typeof snapshot.keyPreview === 'boolean' &&
    (snapshot.keyGap === undefined || inRange(snapshot.keyGap, MIN_KEY_GAP, MAX_KEY_GAP)) &&
    (snapshot.hapticLevel === 0 || snapshot.hapticLevel === 1 || snapshot.hapticLevel === 2) &&
    validShortcuts(snapshot.shortcutOrder) && inRange(snapshot.heightPercent, MIN_KEYBOARD_HEIGHT_PERCENT, MAX_KEYBOARD_HEIGHT_PERCENT) &&
    (snapshot.flickEnabled || snapshot.layoutOrder.split(',').every((id: string) => id.endsWith('_qwerty')));
}

export function copySettings(snapshot: KeyboardSettingsSnapshot): KeyboardSettingsSnapshot {
  const copy: KeyboardSettingsSnapshot = JSON.parse(JSON.stringify(snapshot)) as KeyboardSettingsSnapshot;
  // Schema 1 records from older versions omit this newly added setting.
  if (copy.keyGap === undefined) { copy.keyGap = DEFAULT_KEY_GAP; }
  return copy;
}

export function applySettingsPatch(snapshot: KeyboardSettingsSnapshot, patch: KeyboardSettingsPatch): KeyboardSettingsSnapshot {
  if (!validSettingsPatch(patch)) { throw new Error('Invalid keyboard settings'); }
  const next: KeyboardSettingsSnapshot = copySettings(snapshot);
  if (patch.layoutOrder !== undefined) { next.layoutOrder = patch.layoutOrder; }
  if (patch.flickEnabled !== undefined) { next.flickEnabled = patch.flickEnabled; }
  if (patch.flickDistance !== undefined) { next.flickDistance = patch.flickDistance; }
  if (patch.longPressMs !== undefined) { next.longPressMs = patch.longPressMs; }
  if (patch.keyPreview !== undefined) { next.keyPreview = patch.keyPreview; }
  if (patch.keyGap !== undefined) { next.keyGap = Math.round(patch.keyGap); }
  if (patch.hapticLevel !== undefined) { next.hapticLevel = patch.hapticLevel; }
  if (patch.shortcutOrder !== undefined) { next.shortcutOrder = shortcutOrder(patch.shortcutOrder).join(','); }
  if (patch.heightPercent !== undefined) { next.heightPercent = Math.round(patch.heightPercent); }
  const kind: string = !next.flickEnabled ? 'qwerty' : patch.layoutKind ??
    (next.layoutOrder.split(',')[0].endsWith('_flick') ? 'flick' : 'qwerty');
  next.layoutOrder = languageLayouts(next.layoutOrder).map((id: string) => `${id.startsWith('en_') ? 'en' : 'jp'}_${kind}`).join(',');
  return next;
}

export function mergeSettingsPatch(base: KeyboardSettingsPatch, patch: KeyboardSettingsPatch): KeyboardSettingsPatch {
  const merged: KeyboardSettingsPatch = JSON.parse(JSON.stringify(base)) as KeyboardSettingsPatch;
  if (patch.layoutOrder !== undefined) { merged.layoutOrder = patch.layoutOrder; merged.layoutKind = undefined; }
  if (patch.layoutKind !== undefined) { merged.layoutKind = patch.layoutKind; }
  if (patch.flickEnabled !== undefined) { merged.flickEnabled = patch.flickEnabled; }
  if (patch.flickDistance !== undefined) { merged.flickDistance = patch.flickDistance; }
  if (patch.longPressMs !== undefined) { merged.longPressMs = patch.longPressMs; }
  if (patch.keyPreview !== undefined) { merged.keyPreview = patch.keyPreview; }
  if (patch.keyGap !== undefined) { merged.keyGap = patch.keyGap; }
  if (patch.hapticLevel !== undefined) { merged.hapticLevel = patch.hapticLevel; }
  if (patch.shortcutOrder !== undefined) { merged.shortcutOrder = patch.shortcutOrder; }
  if (patch.heightPercent !== undefined) { merged.heightPercent = patch.heightPercent; }
  return merged;
}

export function validSettingsRecord(record: KeyboardSettingsRecord): boolean {
  return !!record && record.schema === 1 && validSettingsSnapshot(record.snapshot) &&
    typeof record.actor === 'string' && record.actor.length <= 64 && /^\d+-\d+$/.test(record.actor) &&
    Number.isSafeInteger(record.nextSequence) && record.nextSequence > 0 &&
    Array.isArray(record.pending) && record.pending.length <= 2 &&
    record.pending.every((change: KeyboardSettingsChange, index: number) => !!change &&
      change.actor === record.actor && Number.isSafeInteger(change.sequence) && change.sequence > 0 &&
      change.sequence < record.nextSequence && (index === 0 || change.sequence > record.pending[index - 1].sequence) &&
      validSettingsPatch(change.patch)) &&
    Array.isArray(record.peers) && record.peers.length <= 32 && record.peers.every((peer: SettingsPeer) => !!peer &&
      typeof peer.actor === 'string' && peer.actor.length <= 64 && /^\d+-\d+$/.test(peer.actor) && Number.isSafeInteger(peer.sequence) && peer.sequence >= 0) &&
    typeof record.legacyHeightPresent === 'boolean' && typeof record.legacyLayoutPresent === 'boolean' &&
    typeof record.heightChosen === 'boolean' && typeof record.languagesChosen === 'boolean' && typeof record.bootstrapComplete === 'boolean';
}
