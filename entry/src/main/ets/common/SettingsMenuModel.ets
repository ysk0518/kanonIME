import { BackgroundConfig } from './BackgroundAppearance';
import { languageLayouts, layoutLanguage } from './KeyboardConfigValues';
import { KeyboardSettingsPatch, KeyboardSettingsSnapshot } from './KeyboardSettingsModel';
import { keyboardHeightPercent, keyboardKeyGap } from './KeyboardLayout';
import { shortcutOrder } from './ShortcutConfigValues';

export enum SettingsPageId {
  Top, Languages, JapaneseInput, Theme, Size, Layout, Toolbar, Feedback, About
}

export enum SettingsMenuAction {
  Open, Reset
}

export interface SettingsMenuRow {
  action: SettingsMenuAction;
  page: SettingsPageId;
}

export enum SettingsToggle {
  Flick, MultiTap, KeyPreview, EmojiSuggestions, AutoCapitalize, DoubleSpacePeriod
}

export interface SettingsMenuGroup {
  styleHeading: boolean;
  rows: SettingsMenuRow[];
  smartInput?: SettingsToggle[];
}

function open(page: SettingsPageId): SettingsMenuRow {
  return { action: SettingsMenuAction.Open, page: page };
}

export const SETTINGS_MENU: SettingsMenuGroup[] = [
  { styleHeading: false, rows: [open(SettingsPageId.Languages)] },
  { styleHeading: false, rows: [open(SettingsPageId.JapaneseInput)] },
  { styleHeading: false, rows: [], smartInput: [
    SettingsToggle.EmojiSuggestions, SettingsToggle.AutoCapitalize, SettingsToggle.DoubleSpacePeriod
  ] },
  { styleHeading: true, rows: [
    open(SettingsPageId.Theme), open(SettingsPageId.Size), open(SettingsPageId.Layout), open(SettingsPageId.Toolbar)
  ] },
  { styleHeading: false, rows: [open(SettingsPageId.Feedback)] },
  { styleHeading: false, rows: [
    { action: SettingsMenuAction.Reset, page: SettingsPageId.Top }, open(SettingsPageId.About)
  ] }
];

export function settingsLanguages(layoutOrder: string): string[] {
  return languageLayouts(layoutOrder).map((id: string) => layoutLanguage(id));
}

export function settingsLanguageSummary(layoutOrder: string, japanese: string, english: string, separator: string): string {
  return settingsLanguages(layoutOrder).map((language: string) => language === 'JP' ? japanese : english).join(separator);
}

export function settingsThemeSummary(hasImage: boolean, standard: string, custom: string): string {
  return hasImage ? custom : standard;
}

export function settingsUseFlick(snapshot: KeyboardSettingsSnapshot): boolean {
  return snapshot.flickEnabled && languageLayouts(snapshot.layoutOrder)[0].endsWith('_flick');
}

export function settingsLanguagePatch(snapshot: KeyboardSettingsSnapshot, language: string,
  enabled: boolean): KeyboardSettingsPatch | undefined {
  const languages: string[] = settingsLanguages(snapshot.layoutOrder);
  const selected: boolean = languages.includes(language);
  if ((language !== 'JP' && language !== 'EN') || enabled === selected || (!enabled && languages.length === 1)) {
    return undefined;
  }
  const next: string[] = enabled ? languages.concat([language]) : languages.filter((item: string) => item !== language);
  const kind: string = settingsUseFlick(snapshot) ? 'flick' : 'qwerty';
  return { layoutOrder: next.map((item: string) => `${item === 'JP' ? 'jp' : 'en'}_${kind}`).join(',') };
}

export function settingsLayoutPatch(snapshot: KeyboardSettingsSnapshot, flick: boolean): KeyboardSettingsPatch | undefined {
  if ((flick && !snapshot.flickEnabled) || flick === settingsUseFlick(snapshot)) { return undefined; }
  return { layoutKind: flick ? 'flick' : 'qwerty' };
}

export function settingsTogglePatch(setting: SettingsToggle, value: boolean): KeyboardSettingsPatch {
  switch (setting) {
    case SettingsToggle.Flick: return { flickEnabled: value };
    case SettingsToggle.MultiTap: return { toggleInputEnabled: value };
    case SettingsToggle.KeyPreview: return { keyPreview: value };
    case SettingsToggle.EmojiSuggestions: return { emojiSuggestions: value };
    case SettingsToggle.AutoCapitalize: return { autoCapitalize: value };
    case SettingsToggle.DoubleSpacePeriod: return { doubleSpacePeriod: value };
  }
}

export enum SettingsNumber {
  FlickDistance, LongPress, KeyGap, CandidateFont, CandidateRows, Haptics, KeySound, Height
}

export function settingsNumberPatch(setting: SettingsNumber, value: number): KeyboardSettingsPatch {
  switch (setting) {
    case SettingsNumber.FlickDistance: return { flickDistance: value };
    case SettingsNumber.LongPress: return { longPressMs: value };
    case SettingsNumber.KeyGap: return { keyGap: keyboardKeyGap(value) };
    case SettingsNumber.CandidateFont: return { candidateFontSize: Math.round(value) };
    case SettingsNumber.CandidateRows: return { candidateRows: value };
    case SettingsNumber.Haptics: return { hapticLevel: value };
    case SettingsNumber.KeySound: return { keySoundLevel: value };
    case SettingsNumber.Height: return { heightPercent: keyboardHeightPercent(value) };
  }
}

export function settingsShortcutPatch(ids: string[]): KeyboardSettingsPatch {
  return { shortcutOrder: shortcutOrder(ids.join(',')).join(',') };
}

export interface SettingsReset {
  patch: KeyboardSettingsPatch;
  background: BackgroundConfig;
}

export function settingsReset(): SettingsReset {
  const defaults: KeyboardSettingsSnapshot = new KeyboardSettingsSnapshot();
  const patch: KeyboardSettingsPatch = {
    layoutOrder: defaults.layoutOrder, flickEnabled: defaults.flickEnabled, toggleInputEnabled: defaults.toggleInputEnabled,
    flickDistance: defaults.flickDistance, longPressMs: defaults.longPressMs, keyPreview: defaults.keyPreview,
    emojiSuggestions: defaults.emojiSuggestions, autoCapitalize: defaults.autoCapitalize,
    doubleSpacePeriod: defaults.doubleSpacePeriod, keyGap: defaults.keyGap, candidateFontSize: defaults.candidateFontSize, candidateRows: defaults.candidateRows,
    urlFieldKey: defaults.urlFieldKey,
    hapticLevel: defaults.hapticLevel, keySoundLevel: defaults.keySoundLevel, shortcutOrder: defaults.shortcutOrder,
    heightPercent: defaults.heightPercent
  };
  return { patch: patch, background: new BackgroundConfig() };
}
