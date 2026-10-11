import { DEFAULT_LAYOUT_ORDER, DEFAULT_FLICK_DISTANCE, DEFAULT_LONG_PRESS_MS, DEFAULT_HAPTIC_LEVEL,
  DEFAULT_KEY_PREVIEW_ENABLED, DEFAULT_FLICK_ENABLED, languageLayouts } from './KeyboardConfigValues';
import { DEFAULT_SHORTCUT_ORDER, shortcutOrder } from './ShortcutConfigValues';
import { DEFAULT_KEYBOARD_HEIGHT_PERCENT, keyboardHeightPercent } from './KeyboardLayout';
import { KeyboardSettingsSnapshot, KeyboardSettingsRecord, applySettingsPatch } from './KeyboardSettingsModel';

/** Primitive values gathered from old storage; no SDK/UI references. */
export class LegacyKeyboardSettings {
  layoutOrder: string = DEFAULT_LAYOUT_ORDER;
  flickEnabled: boolean = DEFAULT_FLICK_ENABLED;
  flickDistance: number = DEFAULT_FLICK_DISTANCE;
  longPressMs: number = DEFAULT_LONG_PRESS_MS;
  keyPreview: boolean = DEFAULT_KEY_PREVIEW_ENABLED;
  hapticLevel: number = DEFAULT_HAPTIC_LEVEL;
  shortcutOrder: string = DEFAULT_SHORTCUT_ORDER;
  heightPercent: number = DEFAULT_KEYBOARD_HEIGHT_PERCENT;
  heightPresent: boolean = false;
  layoutPresent: boolean = true;
}

function bounded(value: number, minimum: number, maximum: number, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? Math.max(minimum, Math.min(maximum, value)) : fallback;
}

export function migrateLegacySettings(legacy: LegacyKeyboardSettings): KeyboardSettingsRecord {
  const next: KeyboardSettingsRecord = new KeyboardSettingsRecord();
  const snapshot: KeyboardSettingsSnapshot = new KeyboardSettingsSnapshot();
  snapshot.flickEnabled = legacy.flickEnabled;
  snapshot.layoutOrder = languageLayouts(legacy.layoutOrder).join(',');
  snapshot.flickDistance = bounded(legacy.flickDistance, 12, 30, DEFAULT_FLICK_DISTANCE);
  snapshot.longPressMs = bounded(legacy.longPressMs, 250, 650, DEFAULT_LONG_PRESS_MS);
  snapshot.keyPreview = legacy.keyPreview;
  snapshot.hapticLevel = legacy.hapticLevel === 0 || legacy.hapticLevel === 2 ? legacy.hapticLevel : DEFAULT_HAPTIC_LEVEL;
  snapshot.shortcutOrder = shortcutOrder(legacy.shortcutOrder).join(',');
  snapshot.heightPercent = keyboardHeightPercent(legacy.heightPercent);
  next.snapshot = applySettingsPatch(snapshot, {});
  next.legacyHeightPresent = legacy.heightPresent;
  next.legacyLayoutPresent = legacy.layoutPresent;
  next.heightChosen = next.legacyHeightPresent;
  return next;
}
