import { DEFAULT_LAYOUT_ORDER, DEFAULT_FLICK_ENABLED, DEFAULT_FLICK_DISTANCE, DEFAULT_LONG_PRESS_MS,
  DEFAULT_KEY_PREVIEW_ENABLED, DEFAULT_HAPTIC_LEVEL, DEFAULT_KEY_SOUND_LEVEL, KEYBOARD_LAYOUTS,
  DEFAULT_EMOJI_SUGGESTIONS, DEFAULT_AUTO_CAPITALIZE, DEFAULT_DOUBLE_SPACE_PERIOD, languageLayouts } from './KeyboardConfigValues';
import { DEFAULT_SHORTCUT_ORDER, SHORTCUT_IDS, shortcutOrder } from './ShortcutConfigValues';
import { DEFAULT_GAMING_EFFECT, DEFAULT_GAMING_SPEED, DEFAULT_GAMING_UNLOCKED, GamingEffect, gamingEffect,
  validGamingSpeed } from './GamingEffectModel';
import { DEFAULT_GAMING_PALETTE, DEFAULT_GAMING_SOLID_COLOR, GamingPalette, normalizeGamingPalette,
  normalizeGamingSolidColor } from './GamingLightingModel';
import { DEFAULT_CANDIDATE_FONT_SIZE, DEFAULT_CANDIDATE_ROWS, MIN_CANDIDATE_FONT_SIZE, MAX_CANDIDATE_FONT_SIZE } from './CandidateLayout';
import { DEFAULT_KEYBOARD_HEIGHT_PERCENT, MIN_KEYBOARD_HEIGHT_PERCENT, MAX_KEYBOARD_HEIGHT_PERCENT,
  DEFAULT_KEY_GAP, MIN_KEY_GAP, MAX_KEY_GAP } from './KeyboardLayout';
import { DEFAULT_URL_FIELD_KEY, normalizeUrlFieldKey, validUrlFieldKey } from './UrlFieldKey';

export const DEFAULT_TOGGLE_INPUT_ENABLED: boolean = false;

export class KeyboardSettingsSnapshot {
  schema: number = 1;
  revision: number = 0;
  layoutOrder: string = DEFAULT_LAYOUT_ORDER;
  flickEnabled: boolean = DEFAULT_FLICK_ENABLED;
  toggleInputEnabled: boolean = DEFAULT_TOGGLE_INPUT_ENABLED;
  flickDistance: number = DEFAULT_FLICK_DISTANCE;
  longPressMs: number = DEFAULT_LONG_PRESS_MS;
  keyPreview: boolean = DEFAULT_KEY_PREVIEW_ENABLED;
  emojiSuggestions: boolean = DEFAULT_EMOJI_SUGGESTIONS;
  gamingUnlocked: boolean = DEFAULT_GAMING_UNLOCKED;
  gamingEffect: GamingEffect = DEFAULT_GAMING_EFFECT;
  gamingSpeed: number = DEFAULT_GAMING_SPEED;
  gamingPalette: GamingPalette = DEFAULT_GAMING_PALETTE;
  gamingSolidColor: number = DEFAULT_GAMING_SOLID_COLOR;
  autoCapitalize: boolean = DEFAULT_AUTO_CAPITALIZE;
  doubleSpacePeriod: boolean = DEFAULT_DOUBLE_SPACE_PERIOD;
  keyGap: number = DEFAULT_KEY_GAP;
  candidateFontSize: number = DEFAULT_CANDIDATE_FONT_SIZE;
  candidateRows: number = DEFAULT_CANDIDATE_ROWS;
  urlFieldKey: string = DEFAULT_URL_FIELD_KEY;
  hapticLevel: number = DEFAULT_HAPTIC_LEVEL;
  keySoundLevel: number = DEFAULT_KEY_SOUND_LEVEL;
  shortcutOrder: string = DEFAULT_SHORTCUT_ORDER;
  heightPercent: number = DEFAULT_KEYBOARD_HEIGHT_PERCENT;
}

/** Only explicitly edited fields are merged into the authoritative snapshot. */
export interface KeyboardSettingsPatch {
  layoutOrder?: string;
  layoutKind?: string;
  flickEnabled?: boolean;
  toggleInputEnabled?: boolean;
  flickDistance?: number;
  longPressMs?: number;
  keyPreview?: boolean;
  emojiSuggestions?: boolean;
  gamingUnlocked?: boolean;
  gamingEffect?: GamingEffect;
  gamingSpeed?: number;
  gamingPalette?: GamingPalette;
  gamingSolidColor?: number;
  autoCapitalize?: boolean;
  doubleSpacePeriod?: boolean;
  keyGap?: number;
  candidateFontSize?: number;
  candidateRows?: number;
  urlFieldKey?: string;
  hapticLevel?: number;
  keySoundLevel?: number;
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
  // Unknown effect and lighting values are normalized when copied, applied or merged.
  return (patch.layoutOrder === undefined || validLayouts(patch.layoutOrder)) &&
    (patch.layoutKind === undefined || patch.layoutKind === 'flick' || patch.layoutKind === 'qwerty') &&
    (patch.flickEnabled === undefined || typeof patch.flickEnabled === 'boolean') &&
    (patch.toggleInputEnabled === undefined || typeof patch.toggleInputEnabled === 'boolean') &&
    (patch.flickDistance === undefined || inRange(patch.flickDistance, 12, 30)) &&
    (patch.longPressMs === undefined || inRange(patch.longPressMs, 250, 650)) &&
    (patch.keyPreview === undefined || typeof patch.keyPreview === 'boolean') &&
    (patch.emojiSuggestions === undefined || typeof patch.emojiSuggestions === 'boolean') &&
    (patch.gamingUnlocked === undefined || typeof patch.gamingUnlocked === 'boolean') &&
    (patch.gamingSpeed === undefined || validGamingSpeed(patch.gamingSpeed)) &&
    (patch.autoCapitalize === undefined || typeof patch.autoCapitalize === 'boolean') &&
    (patch.doubleSpacePeriod === undefined || typeof patch.doubleSpacePeriod === 'boolean') &&
    (patch.keyGap === undefined || inRange(patch.keyGap, MIN_KEY_GAP, MAX_KEY_GAP)) &&
    (patch.candidateFontSize === undefined || Number.isInteger(patch.candidateFontSize) && inRange(patch.candidateFontSize, MIN_CANDIDATE_FONT_SIZE, MAX_CANDIDATE_FONT_SIZE)) &&
    (patch.candidateRows === undefined || patch.candidateRows === 1 || patch.candidateRows === 2) &&
    (patch.urlFieldKey === undefined || validUrlFieldKey(patch.urlFieldKey)) &&
    (patch.hapticLevel === undefined || patch.hapticLevel === 0 || patch.hapticLevel === 1 || patch.hapticLevel === 2) &&
    (patch.keySoundLevel === undefined || patch.keySoundLevel === 0 || patch.keySoundLevel === 1 || patch.keySoundLevel === 2) &&
    (patch.shortcutOrder === undefined || validShortcuts(patch.shortcutOrder)) &&
    (patch.heightPercent === undefined || inRange(patch.heightPercent, MIN_KEYBOARD_HEIGHT_PERCENT, MAX_KEYBOARD_HEIGHT_PERCENT));
}

export function validSettingsSnapshot(snapshot: KeyboardSettingsSnapshot): boolean {
  // copySettings normalizes missing or invalid URL key values without discarding the snapshot.
  return !!snapshot && snapshot.schema === 1 && Number.isSafeInteger(snapshot.revision) && snapshot.revision >= 0 &&
    validLayouts(snapshot.layoutOrder) && typeof snapshot.flickEnabled === 'boolean' &&
    (snapshot.toggleInputEnabled === undefined || typeof snapshot.toggleInputEnabled === 'boolean') &&
    inRange(snapshot.flickDistance, 12, 30) && inRange(snapshot.longPressMs, 250, 650) &&
    typeof snapshot.keyPreview === 'boolean' &&
    (snapshot.emojiSuggestions === undefined || typeof snapshot.emojiSuggestions === 'boolean') &&
    (snapshot.gamingUnlocked === undefined || typeof snapshot.gamingUnlocked === 'boolean') &&
    (snapshot.gamingSpeed === undefined || validGamingSpeed(snapshot.gamingSpeed)) &&
    (snapshot.autoCapitalize === undefined || typeof snapshot.autoCapitalize === 'boolean') &&
    (snapshot.doubleSpacePeriod === undefined || typeof snapshot.doubleSpacePeriod === 'boolean') &&
    (snapshot.keyGap === undefined || inRange(snapshot.keyGap, MIN_KEY_GAP, MAX_KEY_GAP)) &&
    (snapshot.candidateFontSize === undefined || Number.isInteger(snapshot.candidateFontSize) && inRange(snapshot.candidateFontSize, MIN_CANDIDATE_FONT_SIZE, MAX_CANDIDATE_FONT_SIZE)) &&
    (snapshot.candidateRows === undefined || snapshot.candidateRows === 1 || snapshot.candidateRows === 2) &&
    (snapshot.hapticLevel === 0 || snapshot.hapticLevel === 1 || snapshot.hapticLevel === 2) &&
    (snapshot.keySoundLevel === undefined || snapshot.keySoundLevel === 0 || snapshot.keySoundLevel === 1 || snapshot.keySoundLevel === 2) &&
    validShortcuts(snapshot.shortcutOrder) && inRange(snapshot.heightPercent, MIN_KEYBOARD_HEIGHT_PERCENT, MAX_KEYBOARD_HEIGHT_PERCENT) &&
    (snapshot.flickEnabled || snapshot.layoutOrder.split(',').every((id: string) => id.endsWith('_qwerty')));
}

export function copySettings(snapshot: KeyboardSettingsSnapshot): KeyboardSettingsSnapshot {
  const copy: KeyboardSettingsSnapshot = JSON.parse(JSON.stringify(snapshot)) as KeyboardSettingsSnapshot;
  // Schema 1 records from older versions may omit newer settings.
  if (copy.emojiSuggestions === undefined) { copy.emojiSuggestions = DEFAULT_EMOJI_SUGGESTIONS; }
  if (copy.gamingUnlocked === undefined) { copy.gamingUnlocked = DEFAULT_GAMING_UNLOCKED; }
  copy.gamingEffect = gamingEffect(copy.gamingEffect);
  if (copy.gamingSpeed === undefined) { copy.gamingSpeed = DEFAULT_GAMING_SPEED; }
  copy.gamingPalette = normalizeGamingPalette(copy.gamingPalette);
  copy.gamingSolidColor = normalizeGamingSolidColor(copy.gamingSolidColor);
  if (copy.autoCapitalize === undefined) { copy.autoCapitalize = DEFAULT_AUTO_CAPITALIZE; }
  if (copy.doubleSpacePeriod === undefined) { copy.doubleSpacePeriod = DEFAULT_DOUBLE_SPACE_PERIOD; }
  if (copy.toggleInputEnabled === undefined) { copy.toggleInputEnabled = DEFAULT_TOGGLE_INPUT_ENABLED; }
  if (copy.keyGap === undefined) { copy.keyGap = DEFAULT_KEY_GAP; }
  if (copy.candidateFontSize === undefined) { copy.candidateFontSize = DEFAULT_CANDIDATE_FONT_SIZE; }
  if (copy.candidateRows === undefined) { copy.candidateRows = DEFAULT_CANDIDATE_ROWS; }
  copy.urlFieldKey = normalizeUrlFieldKey(copy.urlFieldKey);
  if (copy.keySoundLevel === undefined) { copy.keySoundLevel = DEFAULT_KEY_SOUND_LEVEL; }
  return copy;
}

export function applySettingsPatch(snapshot: KeyboardSettingsSnapshot, patch: KeyboardSettingsPatch): KeyboardSettingsSnapshot {
  if (!validSettingsPatch(patch)) { throw new Error('Invalid keyboard settings'); }
  const next: KeyboardSettingsSnapshot = copySettings(snapshot);
  if (patch.layoutOrder !== undefined) { next.layoutOrder = patch.layoutOrder; }
  if (patch.flickEnabled !== undefined) { next.flickEnabled = patch.flickEnabled; }
  if (patch.toggleInputEnabled !== undefined) { next.toggleInputEnabled = patch.toggleInputEnabled; }
  if (patch.flickDistance !== undefined) { next.flickDistance = patch.flickDistance; }
  if (patch.longPressMs !== undefined) { next.longPressMs = patch.longPressMs; }
  if (patch.keyPreview !== undefined) { next.keyPreview = patch.keyPreview; }
  if (patch.emojiSuggestions !== undefined) { next.emojiSuggestions = patch.emojiSuggestions; }
  if (patch.gamingUnlocked !== undefined) { next.gamingUnlocked = patch.gamingUnlocked; }
  if (patch.gamingEffect !== undefined) { next.gamingEffect = gamingEffect(patch.gamingEffect); }
  if (patch.gamingSpeed !== undefined) { next.gamingSpeed = patch.gamingSpeed; }
  if (patch.gamingPalette !== undefined) { next.gamingPalette = normalizeGamingPalette(patch.gamingPalette); }
  if (patch.gamingSolidColor !== undefined) { next.gamingSolidColor = normalizeGamingSolidColor(patch.gamingSolidColor); }
  if (patch.autoCapitalize !== undefined) { next.autoCapitalize = patch.autoCapitalize; }
  if (patch.doubleSpacePeriod !== undefined) { next.doubleSpacePeriod = patch.doubleSpacePeriod; }
  if (patch.keyGap !== undefined) { next.keyGap = Math.round(patch.keyGap); }
  if (patch.candidateFontSize !== undefined) { next.candidateFontSize = patch.candidateFontSize; }
  if (patch.candidateRows !== undefined) { next.candidateRows = patch.candidateRows; }
  if (patch.urlFieldKey !== undefined) { next.urlFieldKey = patch.urlFieldKey; }
  if (patch.hapticLevel !== undefined) { next.hapticLevel = patch.hapticLevel; }
  if (patch.keySoundLevel !== undefined) { next.keySoundLevel = patch.keySoundLevel; }
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
  if (patch.toggleInputEnabled !== undefined) { merged.toggleInputEnabled = patch.toggleInputEnabled; }
  if (patch.flickDistance !== undefined) { merged.flickDistance = patch.flickDistance; }
  if (patch.longPressMs !== undefined) { merged.longPressMs = patch.longPressMs; }
  if (patch.keyPreview !== undefined) { merged.keyPreview = patch.keyPreview; }
  if (patch.emojiSuggestions !== undefined) { merged.emojiSuggestions = patch.emojiSuggestions; }
  if (patch.gamingUnlocked !== undefined) { merged.gamingUnlocked = patch.gamingUnlocked; }
  if (patch.gamingEffect !== undefined) { merged.gamingEffect = gamingEffect(patch.gamingEffect); }
  if (patch.gamingSpeed !== undefined) { merged.gamingSpeed = patch.gamingSpeed; }
  if (patch.gamingPalette !== undefined) { merged.gamingPalette = normalizeGamingPalette(patch.gamingPalette); }
  if (patch.gamingSolidColor !== undefined) { merged.gamingSolidColor = normalizeGamingSolidColor(patch.gamingSolidColor); }
  if (patch.autoCapitalize !== undefined) { merged.autoCapitalize = patch.autoCapitalize; }
  if (patch.doubleSpacePeriod !== undefined) { merged.doubleSpacePeriod = patch.doubleSpacePeriod; }
  if (patch.keyGap !== undefined) { merged.keyGap = patch.keyGap; }
  if (patch.candidateFontSize !== undefined) { merged.candidateFontSize = patch.candidateFontSize; }
  if (patch.candidateRows !== undefined) { merged.candidateRows = patch.candidateRows; }
  if (patch.urlFieldKey !== undefined) { merged.urlFieldKey = patch.urlFieldKey; }
  if (patch.hapticLevel !== undefined) { merged.hapticLevel = patch.hapticLevel; }
  if (patch.keySoundLevel !== undefined) { merged.keySoundLevel = patch.keySoundLevel; }
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

/** Decode and normalize schema-1 storage without accessing preferences or UI. */
export function decodeSettingsRecord(payload: string): KeyboardSettingsRecord {
  const loaded: KeyboardSettingsRecord = JSON.parse(payload) as KeyboardSettingsRecord;
  if (loaded && Array.isArray(loaded.pending)) {
    for (const change of loaded.pending) {
      if (change && change.patch && change.patch.urlFieldKey !== undefined) {
        change.patch.urlFieldKey = normalizeUrlFieldKey(change.patch.urlFieldKey);
      }
    }
  }
  if (!validSettingsRecord(loaded)) { throw new Error('Invalid settings record'); }
  loaded.snapshot = copySettings(loaded.snapshot);
  return loaded;
}
