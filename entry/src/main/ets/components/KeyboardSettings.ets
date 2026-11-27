import common from '@ohos.app.ability.common';
import bundleManager from '@ohos.bundle.bundleManager';
import { ShortcutEditor } from './ShortcutEditor';
import { KeyboardBackgroundSettings } from './KeyboardBackgroundSettings';
import { SettingsHeader } from './SettingsHeader';
import { DebugConsole } from './DebugConsole';
import { keyboardSettingsSync } from '../common/KeyboardSettingsSync';
import { applySettingsPatch, KeyboardSettingsSnapshot, KeyboardSettingsPatch } from '../common/KeyboardSettingsModel';
import { readSettings } from '../common/KeyboardSettingsRepository';
import { BackgroundConfig, keyboardBackground } from '../common/KeyboardBackground';
import { MIN_KEY_GAP, MAX_KEY_GAP, MIN_KEYBOARD_HEIGHT_PERCENT, MAX_KEYBOARD_HEIGHT_PERCENT } from '../common/KeyboardLayout';
import { shortcutOrder } from '../common/ShortcutConfigValues';
import { BackgroundKeyPreview } from './BackgroundKeyPreview';
import { KeyboardPreviewLayoutSwitch } from './KeyboardPreviewLayoutSwitch';
import { MIN_CANDIDATE_FONT_SIZE, MAX_CANDIDATE_FONT_SIZE } from '../common/CandidateLayout';
import { CandidateAppearancePreview } from './CandidateAppearancePreview';
import { SETTINGS_MENU, SettingsPageId, SettingsMenuAction, SettingsMenuRow, SettingsMenuGroup,
  SettingsNumber, SettingsToggle, SettingsReset, settingsLanguages, settingsLanguageSummary, settingsThemeSummary,
  settingsUseFlick, settingsLanguagePatch, settingsLayoutPatch, settingsTogglePatch, settingsNumberPatch,
  settingsShortcutPatch, settingsReset, settingsMenuRows, settingsGamingSummary } from '../common/SettingsMenuModel';
import { GAMING_EFFECTS, GamingEffect, GamingTapResult, GamingUnlockTaps } from '../common/GamingEffectModel';

function gamingEffectTitle(effect: GamingEffect): Resource {
  switch (effect) {
    case 'flow': return $r('app.string.settings_gaming_flow');
    case 'ripple': return $r('app.string.settings_gaming_ripple');
    default: return $r('app.string.settings_gaming_off');
  }
}

function pageTitle(page: SettingsPageId): Resource {
  switch (page) {
    case SettingsPageId.Top: return $r('app.string.settings_app_name');
    case SettingsPageId.Languages: return $r('app.string.settings_menu_languages');
    case SettingsPageId.JapaneseInput: return $r('app.string.settings_menu_japanese_input');
    case SettingsPageId.Theme: return $r('app.string.settings_menu_theme');
    case SettingsPageId.Size: return $r('app.string.settings_menu_size');
    case SettingsPageId.Layout: return $r('app.string.settings_menu_layout');
    case SettingsPageId.Toolbar: return $r('app.string.settings_menu_toolbar');
    case SettingsPageId.Feedback: return $r('app.string.settings_menu_feedback');
    case SettingsPageId.About: return $r('app.string.settings_menu_about');
    case SettingsPageId.Gaming: return $r('app.string.settings_menu_gaming');
  }
}

@Component
export struct KeyboardSettings {
  @Prop @Watch('pageChanged') page: SettingsPageId = SettingsPageId.Top;
  @State private snapshot: KeyboardSettingsSnapshot = new KeyboardSettingsSnapshot();
  @State private saving: boolean = false;
  @State private retrying: boolean = false;
  @State private message: ResourceStr = '';
  @State private activeSlider: SettingsNumber | undefined = undefined;
  @State private sliderDraft: number = 0;
  @State private spacingPreviewQwerty: boolean = false;
  @State private version: string = '';
  @State private hasBackground: boolean = false;
  private gamingTaps: GamingUnlockTaps = new GamingUnlockTaps();
  @StorageLink('kanonSettingsGeneration') @Watch('settingsChanged') settingsGeneration: number = 0;
  @StorageLink('kanonSettingsSyncState') syncState: string = '';
  @StorageLink('kanonSettingsRequestSyncState') requestState: string = '';
  @StorageLink('kanonBackgroundVersion') @Watch('backgroundChanged') backgroundVersion: number = 0;
  @StorageLink('kanonBackgroundSyncState') backgroundSyncState: string = '';
  languageOnly: boolean = false;
  onOpen: (page: SettingsPageId) => void = () => {};
  onClose: () => void = () => {};
  onBackgroundBackHandler: (handler: (() => void) | undefined) => void = () => {};

  aboutToAppear(): void {
    this.snapshot = readSettings();
    keyboardSettingsSync.request().catch(() => {});
    if (!this.languageOnly) {
      this.initializeBackground().catch(() => {});
      this.loadVersion();
    }
  }

  private async loadVersion(): Promise<void> {
    try {
      const info: bundleManager.BundleInfo =
        await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.version = info.versionName;
    } catch (error) {}
  }

  private async initializeBackground(): Promise<void> {
    const context: common.Context = this.getUIContext().getHostContext() as common.Context;
    await keyboardBackground.initialize(context);
    this.backgroundChanged();
  }

  private backgroundChanged(): void {
    this.hasBackground = keyboardBackground.get().photo.length > 0;
  }

  private settingsChanged(): void {
    if (!this.saving) { this.snapshot = readSettings(); }
  }

  private pageChanged(): void {
    this.activeSlider = undefined;
    this.gamingTaps.reset();
  }

  private showGamingToast(message: Resource): void {
    try { this.getUIContext().getPromptAction().showToast({ message: message, duration: 1200 }); } catch (error) {}
  }

  private async tapVersion(): Promise<void> {
    if (this.saving || this.page !== SettingsPageId.About) { return; }
    switch (this.gamingTaps.tap(Date.now(), this.snapshot.gamingUnlocked)) {
      case GamingTapResult.ThreeLeft:
        this.showGamingToast($r('app.string.settings_gaming_taps_left', 3)); break;
      case GamingTapResult.TwoLeft:
        this.showGamingToast($r('app.string.settings_gaming_taps_left', 2)); break;
      case GamingTapResult.OneLeft:
        this.showGamingToast($r('app.string.settings_gaming_taps_left', 1)); break;
      case GamingTapResult.Unlock:
        await this.save({ gamingUnlocked: true });
        if (this.snapshot.gamingUnlocked) { this.showGamingToast($r('app.string.settings_gaming_unlocked')); }
        break;
      case GamingTapResult.AlreadyUnlocked:
        this.showGamingToast($r('app.string.settings_gaming_already_unlocked')); break;
      default: break;
    }
  }

  private syncPending(): boolean {
    const state: string = keyboardSettingsSync.isReplica() ? this.requestState : this.syncState;
    return state === 'pending' || state === 'error';
  }

  private syncFailed(): boolean {
    const state: string = keyboardSettingsSync.isReplica() ? this.requestState : this.syncState;
    return state === 'error' || (!this.languageOnly && this.backgroundSyncState === 'error');
  }

  private backgroundPending(): boolean {
    return !this.languageOnly && (this.backgroundSyncState === 'pending' || this.backgroundSyncState === 'error');
  }

  private async retrySync(): Promise<void> {
    if (this.retrying || this.saving) { return; }
    this.retrying = true;
    this.message = '';
    const requests: Promise<void>[] = [];
    if (this.syncPending()) { requests.push(keyboardSettingsSync.request()); }
    if (this.backgroundPending()) { requests.push(keyboardBackground.retrySync()); }
    try { await Promise.all(requests); }
    catch (error) { this.message = $r('app.string.settings_sync_retry_failed'); }
    finally { this.retrying = false; }
  }

  private async save(patch: KeyboardSettingsPatch | undefined, background?: BackgroundConfig): Promise<void> {
    if (patch === undefined || this.saving) { return; }
    this.saving = true;
    this.message = '';
    let settingsSaved: boolean = false;
    try {
      this.snapshot = applySettingsPatch(readSettings(), patch);
      if (background !== undefined) { await this.initializeBackground(); }
      await keyboardSettingsSync.save(patch, false);
      settingsSaved = true;
      if (background !== undefined) {
        await keyboardBackground.save(background, false);
      }
    } catch (error) {
      this.message = settingsSaved ? $r('app.string.settings_reset_background_failed') : $r('app.string.common_save_failed');
    } finally {
      this.activeSlider = undefined;
      this.snapshot = readSettings();
      this.saving = false;
    }
  }

  private reset(): void {
    const defaults: SettingsReset = settingsReset();
    this.save(defaults.patch, defaults.background);
  }

  private confirmReset(): void {
    const options: AlertDialogParamWithButtons = {
      title: $r('app.string.settings_menu_reset'),
      message: $r('app.string.settings_reset_confirm'),
      primaryButton: { value: $r('app.string.settings_reset_cancel'), action: () => {} },
      secondaryButton: { value: $r('app.string.settings_reset_action'), action: () => this.reset() }
    };
    this.getUIContext().showAlertDialog(options);
  }

  private openRow(row: SettingsMenuRow): void {
    if (row.action === SettingsMenuAction.Reset) {
      this.confirmReset();
      return;
    }
    if (row.page === SettingsPageId.Layout) { this.spacingPreviewQwerty = !settingsUseFlick(this.snapshot); }
    this.onOpen(row.page);
  }

  private rowSummary(page: SettingsPageId): string {
    const resources = this.getUIContext().getHostContext()?.resourceManager;
    if (resources === undefined) { return ''; }
    try {
      if (page === SettingsPageId.Languages) {
        return settingsLanguageSummary(this.snapshot.layoutOrder,
          resources.getStringSync($r('app.string.settings_japanese').id),
          resources.getStringSync($r('app.string.settings_summary_english').id),
          resources.getStringSync($r('app.string.settings_summary_separator').id));
      }
      if (page === SettingsPageId.Gaming) {
        return settingsGamingSummary(this.snapshot.gamingEffect,
          resources.getStringSync(gamingEffectTitle('off').id),
          resources.getStringSync(gamingEffectTitle('flow').id),
          resources.getStringSync(gamingEffectTitle('ripple').id));
      }
      return settingsThemeSummary(this.hasBackground,
        resources.getStringSync($r('app.string.settings_theme_standard').id),
        resources.getStringSync($r('app.string.settings_theme_image').id));
    } catch (error) { return ''; }
  }

  private hasLanguage(language: string): boolean {
    return settingsLanguages(this.snapshot.layoutOrder).includes(language);
  }

  private toggleValue(setting: SettingsToggle): boolean {
    switch (setting) {
      case SettingsToggle.Flick: return this.snapshot.flickEnabled;
      case SettingsToggle.MultiTap: return this.snapshot.toggleInputEnabled;
      case SettingsToggle.KeyPreview: return this.snapshot.keyPreview;
      case SettingsToggle.EmojiSuggestions: return this.snapshot.emojiSuggestions;
      case SettingsToggle.AutoCapitalize: return this.snapshot.autoCapitalize;
      case SettingsToggle.DoubleSpacePeriod: return this.snapshot.doubleSpacePeriod;
    }
  }

  private numberValue(setting: SettingsNumber): number {
    switch (setting) {
      case SettingsNumber.FlickDistance: return this.snapshot.flickDistance;
      case SettingsNumber.LongPress: return this.snapshot.longPressMs;
      case SettingsNumber.KeyGap: return this.snapshot.keyGap;
      case SettingsNumber.CandidateFont: return this.snapshot.candidateFontSize;
      case SettingsNumber.CandidateRows: return this.snapshot.candidateRows;
      case SettingsNumber.Haptics: return this.snapshot.hapticLevel;
      case SettingsNumber.KeySound: return this.snapshot.keySoundLevel;
      case SettingsNumber.Height: return this.snapshot.heightPercent;
    }
  }

  private sliderValue(setting: SettingsNumber): number {
    return this.activeSlider === setting ? this.sliderDraft : this.numberValue(setting);
  }

  private sliderTitle(setting: SettingsNumber): Resource {
    switch (setting) {
      case SettingsNumber.KeyGap: return $r('app.string.settings_key_gap', this.sliderValue(setting));
      case SettingsNumber.CandidateFont: return $r('app.string.settings_candidate_font', this.sliderValue(setting));
      case SettingsNumber.Height: return $r('app.string.settings_keyboard_height', `${this.sliderValue(setting)}%`);
      case SettingsNumber.LongPress:
        return $r('app.string.settings_long_press_seconds', (this.sliderValue(setting) / 1000).toFixed(2));
      default: return $r('app.string.settings_flick_sensitivity');
    }
  }

  private sliderChanged(setting: SettingsNumber, value: number, mode: SliderChangeMode): void {
    if (this.saving) { return; }
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.activeSlider = undefined;
      if (value !== this.numberValue(setting)) { this.save(settingsNumberPatch(setting, value)); }
    } else {
      this.sliderDraft = value;
      this.activeSlider = setting;
    }
  }

  private goBack(): void {
    this.activeSlider = undefined;
    this.onClose();
  }

  @Builder
  divider() {
    Divider().strokeWidth(1).color($r('app.color.light_gray'))
  }

  @Builder
  navigationRow(row: SettingsMenuRow) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(row.action === SettingsMenuAction.Reset ? $r('app.string.settings_menu_reset') : pageTitle(row.page))
            .fontSize(18).fontColor($r('app.color.text_normal')).width('100%')
          if (row.page === SettingsPageId.Languages || row.page === SettingsPageId.Theme ||
            row.page === SettingsPageId.Gaming) {
            Text(this.rowSummary(row.page)).fontSize(14)
              .fontColor($r('app.color.settings_accent')).width('100%')
          }
        }.layoutWeight(1)
        if (row.action === SettingsMenuAction.Open) {
          Text($r('app.string.settings_forward_glyph')).fontSize(22)
            .fontColor($r('app.color.settings_accent')).accessibilityLevel('no')
        }
      }.width('100%').constraintSize({ minHeight: 58 }).padding({ top: 13, bottom: 13 })
    }.width('100%').padding(0).backgroundColor(Color.Transparent).enabled(!this.saving)
      .onClick(() => this.openRow(row)).id(row.action === SettingsMenuAction.Reset ? 'keyboard_config_reset' :
        row.page === SettingsPageId.Theme ? 'keyboard_config_background' : `keyboard_settings_page_${row.page}`)
  }

  private smartInputTitle(setting: SettingsToggle): Resource {
    switch (setting) {
      case SettingsToggle.EmojiSuggestions: return $r('app.string.settings_emoji_suggestions');
      case SettingsToggle.AutoCapitalize: return $r('app.string.settings_auto_capitalize');
      default: return $r('app.string.settings_double_space_period');
    }
  }

  @Builder
  menu() {
    ForEach(SETTINGS_MENU, (group: SettingsMenuGroup) => {
      Column({ space: 8 }) {
        if (group.styleHeading || group.smartInput !== undefined) {
          Text(group.styleHeading ? $r('app.string.settings_menu_style') : $r('app.string.settings_menu_smart_input')).fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary')).width('100%').padding({ left: 18 })
        }
        Column() {
          if (group.smartInput !== undefined) {
            ForEach(group.smartInput, (setting: SettingsToggle, index: number) => {
              if (index > 0) { this.divider() }
              this.toggleRow(this.smartInputTitle(setting), setting, `keyboard_config_smart_input_${setting}`,
                setting === SettingsToggle.EmojiSuggestions ? $r('app.string.settings_summary_japanese') :
                  $r('app.string.settings_summary_english'))
            }, (setting: SettingsToggle) => setting.toString())
          } else {
            ForEach(settingsMenuRows(group, this.snapshot.gamingUnlocked), (row: SettingsMenuRow, index: number) => {
              if (index > 0) { this.divider() }
              this.navigationRow(row)
            }, (row: SettingsMenuRow) => row.page.toString())
          }
        }.width('100%').padding({ left: 18, right: 18 })
          .borderRadius(22).backgroundColor($r('app.color.settings_card'))
      }.width('100%')
    }, (group: SettingsMenuGroup) => group.smartInput !== undefined ? 'smartInput' : group.rows[0].page.toString())
  }

  @Builder
  languages() {
    Column({ space: 8 }) {
      if (!this.languageOnly) {
        Text($r('app.string.settings_languages')).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary')).width('100%').padding({ left: 18 })
      }
      Column() {
        ForEach(['JP', 'EN'], (language: string, index: number) => {
          if (index > 0) { this.divider() }
          Row({ space: 12 }) {
            Text(language === 'JP' ? $r('app.string.settings_japanese') : $r('app.string.settings_english'))
              .fontSize(18).fontColor($r('app.color.text_normal')).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.hasLanguage(language) })
              .selectedColor($r('app.color.settings_accent'))
              .enabled(!this.saving && !(settingsLanguages(this.snapshot.layoutOrder).length === 1 && this.hasLanguage(language)))
              .onChange((enabled: boolean) => this.save(settingsLanguagePatch(this.snapshot, language, enabled)))
              .accessibilityText(language === 'JP' ? $r('app.string.settings_use_japanese') : $r('app.string.settings_use_english'))
              .id(`keyboard_config_language_${language}`)
          }.width('100%').constraintSize({ minHeight: 56 })
        }, (language: string) => language)
      }.width('100%').padding({ left: 18, right: 18 })
        .borderRadius(22).backgroundColor($r('app.color.settings_card'))
    }.width('100%')
    if (!this.languageOnly) {
      Column({ space: 10 }) {
        this.label($r('app.string.settings_layout'))
        Row({ space: 8 }) {
          ForEach([true, false], (flick: boolean) => {
            Button(flick ? $r('app.string.settings_layout_flick') : $r('app.string.settings_layout_qwerty'))
              .layoutWeight(1).enabled(!this.saving && (!flick || this.snapshot.flickEnabled))
              .fontColor($r('app.color.text_normal'))
              .backgroundColor(settingsUseFlick(this.snapshot) === flick ?
                $r('app.color.candidate_selected') : $r('app.color.key_item_normal'))
              .accessibilityText(flick ?
                (settingsUseFlick(this.snapshot) ? $r('app.string.settings_flick_selected') : $r('app.string.settings_layout_flick')) :
                (settingsUseFlick(this.snapshot) ? $r('app.string.settings_layout_qwerty') : $r('app.string.settings_qwerty_selected')))
              .onClick(() => this.save(settingsLayoutPatch(this.snapshot, flick)))
              .id(flick ? 'keyboard_config_flick' : 'keyboard_config_qwerty')
          }, (flick: boolean) => flick.toString())
        }.width('100%')
        this.help($r('app.string.settings_layout_help'))
      }.width('100%').padding(18).borderRadius(22).backgroundColor($r('app.color.settings_card'))
    }
  }

  @Builder
  toggleRow(title: Resource, setting: SettingsToggle, id: string, summary: Resource | undefined = undefined) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title).fontSize(18).fontColor($r('app.color.text_normal')).width('100%')
        if (summary !== undefined) {
          Text(summary).fontSize(14).fontColor($r('app.color.settings_accent')).width('100%')
        }
      }.layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.toggleValue(setting) })
        .selectedColor($r('app.color.settings_accent')).enabled(!this.saving)
        .onChange((value: boolean) => {
          if (value !== this.toggleValue(setting)) { this.save(settingsTogglePatch(setting, value)); }
        }).accessibilityText(title).id(id)
    }.width('100%').constraintSize({ minHeight: 56 })
  }

  @Builder
  label(title: ResourceStr) {
    Text(title).fontSize(18).fontColor($r('app.color.text_normal')).width('100%')
  }

  @Builder
  help(text: ResourceStr) {
    Text(text).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
  }

  @Builder
  slider(setting: SettingsNumber, min: number, max: number, step: number, id: string) {
    Text(this.sliderTitle(setting)).fontSize(18).fontColor($r('app.color.text_normal')).width('100%')
    Slider({ value: this.sliderValue(setting), min: min, max: max, step: step })
      .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK_UP)
      .selectedColor($r('app.color.settings_accent')).enabled(!this.saving)
      .onChange((value: number, mode: SliderChangeMode) => this.sliderChanged(setting, value, mode))
      .accessibilityText(this.sliderTitle(setting)).id(id).width('100%')
  }

  @Builder
  japaneseInput() {
    Column() {
      this.toggleRow($r('app.string.settings_flick_enabled'), SettingsToggle.Flick, 'keyboard_config_flick_enabled')
      this.help($r('app.string.settings_flick_disabled_help'))
      this.divider()
      this.toggleRow($r('app.string.settings_toggle_input'), SettingsToggle.MultiTap, 'keyboard_config_toggle_input')
      this.divider()
      Column({ space: 4 }) {
        this.slider(SettingsNumber.FlickDistance, 12, 30, 2, 'keyboard_config_flick_distance')
        this.help($r('app.string.settings_flick_help'))
      }.padding({ top: 14, bottom: 16 })
    }.width('100%').padding({ left: 18, right: 18 }).borderRadius(22).backgroundColor($r('app.color.settings_card'))
  }

  private choiceLabel(setting: SettingsNumber, value: number): Resource {
    if (setting === SettingsNumber.CandidateRows) { return $r('app.string.settings_candidate_row_count', value); }
    if (setting === SettingsNumber.Haptics) {
      return value === 0 ? $r('app.string.settings_haptics_off') :
        value === 1 ? $r('app.string.settings_haptics_weak') : $r('app.string.settings_haptics_strong');
    }
    return value === 0 ? $r('app.string.settings_key_sound_off') :
      value === 1 ? $r('app.string.settings_key_sound_low') : $r('app.string.settings_key_sound_high');
  }

  @Builder
  choices(setting: SettingsNumber, values: number[], idPrefix: string) {
    Row({ space: 8 }) {
      ForEach(values, (value: number) => {
        Button(this.choiceLabel(setting, value)).layoutWeight(1).enabled(!this.saving)
          .fontColor($r('app.color.text_normal'))
          .backgroundColor(this.numberValue(setting) === value ?
            $r('app.color.candidate_selected') : $r('app.color.key_item_normal'))
          .onClick(() => {
            if (value !== this.numberValue(setting)) { this.save(settingsNumberPatch(setting, value)); }
          }).id(`${idPrefix}_${value}`)
      }, (value: number) => value.toString())
    }.width('100%')
  }

  @Builder
  layoutOptions() {
    Column({ space: 10 }) {
      this.slider(SettingsNumber.KeyGap, MIN_KEY_GAP, MAX_KEY_GAP, 1, 'keyboard_config_key_gap')
      this.help($r('app.string.settings_key_gap_help'))
      KeyboardPreviewLayoutSwitch({ qwerty: this.spacingPreviewQwerty, disabled: this.saving,
        idPrefix: 'keyboard_config_gap_preview',
        onChange: (qwerty: boolean) => { this.spacingPreviewQwerty = qwerty; } })
      Stack() {
        BackgroundKeyPreview({ qwerty: this.spacingPreviewQwerty, gap: this.sliderValue(SettingsNumber.KeyGap) })
      }.width('100%').height(152).borderRadius(8)
        .backgroundColor($r('app.color.keyboard_background')).id('keyboard_config_key_gap_preview')
    }.width('100%').padding(18).borderRadius(22).backgroundColor($r('app.color.settings_card'))
    Column({ space: 10 }) {
      this.label($r('app.string.settings_candidate_rows'))
      this.choices(SettingsNumber.CandidateRows, [1, 2], 'keyboard_config_candidate_rows')
      this.divider()
      this.slider(SettingsNumber.CandidateFont, MIN_CANDIDATE_FONT_SIZE, MAX_CANDIDATE_FONT_SIZE, 1,
        'keyboard_config_candidate_font')
      CandidateAppearancePreview({ fontSize: this.sliderValue(SettingsNumber.CandidateFont), rows: this.snapshot.candidateRows })
      this.help($r('app.string.settings_candidate_rows_help'))
    }.width('100%').padding(18).borderRadius(22).backgroundColor($r('app.color.settings_card'))
  }

  @Builder
  feedback() {
    Column({ space: 10 }) {
      this.label($r('app.string.settings_haptics'))
      this.choices(SettingsNumber.Haptics, [0, 1, 2], 'keyboard_config_haptic')
      this.help($r('app.string.settings_haptics_help'))
      this.divider()
      this.label($r('app.string.settings_key_sound'))
      this.choices(SettingsNumber.KeySound, [0, 1, 2], 'keyboard_config_key_sound')
      this.divider()
      this.toggleRow($r('app.string.settings_key_preview'), SettingsToggle.KeyPreview, 'keyboard_config_preview')
      this.divider()
      this.slider(SettingsNumber.LongPress, 250, 650, 50, 'keyboard_config_long_press')
    }.width('100%').padding(18).borderRadius(22).backgroundColor($r('app.color.settings_card'))
  }

  @Builder
  gamingOptions() {
    Column() {
      ForEach(GAMING_EFFECTS, (effect: GamingEffect, index: number) => {
        if (index > 0) { this.divider() }
        Button({ type: ButtonType.Normal }) {
          Row({ space: 12 }) {
            Text(gamingEffectTitle(effect)).fontSize(18).fontColor($r('app.color.text_normal')).layoutWeight(1)
            Radio({ value: effect, group: 'keyboard_gaming_effect' })
              .checked(this.snapshot.gamingEffect === effect)
              .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
          }.width('100%').constraintSize({ minHeight: 56 })
        }.width('100%').padding(0).backgroundColor(Color.Transparent)
          .enabled(!this.saving).accessibilityChecked(this.snapshot.gamingEffect === effect)
          .onClick(() => {
            if (this.snapshot.gamingEffect !== effect) { this.save({ gamingEffect: effect }); }
          }).id(`keyboard_config_gaming_${effect}`)
      }, (effect: GamingEffect) => effect)
    }.width('100%').padding({ left: 18, right: 18 }).borderRadius(22).backgroundColor($r('app.color.settings_card'))
  }

  @Builder
  content() {
    if (this.languageOnly || this.page === SettingsPageId.Languages) {
      this.languages()
    } else if (this.page === SettingsPageId.Top) {
      this.menu()
    } else if (this.page === SettingsPageId.JapaneseInput) {
      this.japaneseInput()
    } else if (this.page === SettingsPageId.Size) {
      Column({ space: 8 }) {
        this.slider(SettingsNumber.Height, MIN_KEYBOARD_HEIGHT_PERCENT, MAX_KEYBOARD_HEIGHT_PERCENT, 1,
          'keyboard_config_height')
        this.help($r('app.string.settings_size_help'))
      }.width('100%').padding(18).borderRadius(22).backgroundColor($r('app.color.settings_card'))
    } else if (this.page === SettingsPageId.Layout) {
      this.layoutOptions()
    } else if (this.page === SettingsPageId.Toolbar) {
      ShortcutEditor({ selectedShortcuts: shortcutOrder(this.snapshot.shortcutOrder), disabled: this.saving,
        onChange: (ids: string[]) => this.save(settingsShortcutPatch(ids)) })
    } else if (this.page === SettingsPageId.Feedback) {
      this.feedback()
    } else if (this.page === SettingsPageId.Gaming && this.snapshot.gamingUnlocked) {
      this.gamingOptions()
    } else if (this.page === SettingsPageId.About) {
      Column({ space: 8 }) {
        this.label($r('app.string.settings_app_name'))
        if (this.version !== '') {
          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.settings_about_version', this.version))
              .fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
          }.width('100%').constraintSize({ minHeight: 44 }).padding(0).backgroundColor(Color.Transparent)
            .onClick(() => { this.tapVersion(); }).id('keyboard_settings_version')
        }
      }.width('100%').padding(18).borderRadius(22).backgroundColor($r('app.color.settings_card'))
      DebugConsole().padding(18).borderRadius(22).backgroundColor($r('app.color.settings_card'))
    }
  }

  @Builder
  footer() {
    // Changes save at once, like Samsung Keyboard: stay quiet while the
    // keyboard has not confirmed them yet. The OS freezes a hidden keyboard,
    // which then catches up when shown. Show only failures.
    if (this.message !== '' || this.syncFailed()) {
      Column({ space: 4 }) {
        if (this.message !== '') {
          Text(this.message).fontSize(12).fontColor($r('app.color.text_error')).width('100%')
        }
        if (this.syncFailed()) {
          Row({ space: 8 }) {
            Text($r('app.string.settings_sync_waiting')).fontSize(12)
              .fontColor($r('app.color.text_secondary')).layoutWeight(1)
            Button($r('app.string.settings_sync_retry')).fontSize(12).height(32).enabled(!this.saving && !this.retrying)
              .onClick(() => this.retrySync()).id('keyboard_settings_sync_retry')
          }.width('100%')
        }
      }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 8 })
    }
  }

  // One UI style navigation: a sub-page slides in from the right and back out
  // to the right; the top page moves aside to the left. The direction follows
  // from the page itself because the menu has only two levels.
  private slideTransition(page: SettingsPageId): TransitionEffect {
    const top: boolean = page === SettingsPageId.Top;
    return TransitionEffect.asymmetric(
      TransitionEffect.translate({ x: top ? '-30%' : '100%' }).combine(TransitionEffect.opacity(top ? 0.6 : 1)),
      TransitionEffect.translate({ x: top ? '-30%' : '100%' }).combine(TransitionEffect.opacity(top ? 0.6 : 1)));
  }

  build() {
    Column() {
      if (!this.languageOnly && this.page === SettingsPageId.Theme) {
        // The theme page has its own header; slide it as one opaque page.
        Column() {
          KeyboardBackgroundSettings({ onClose: () => this.goBack(), onBackHandlerChange: this.onBackgroundBackHandler })
        }
        .width('100%').height('100%')
        .backgroundColor($r('app.color.settings_background_surface'))
        .zIndex(1)
        .transition(this.slideTransition(SettingsPageId.Theme))
      } else {
        SettingsHeader({ title: this.languageOnly ? $r('app.string.settings_languages') : pageTitle(this.page),
          compact: this.languageOnly, onBack: () => this.goBack() })
        ForEach([this.page], (page: SettingsPageId) => {
          Scroll() {
            Column({ space: 16 }) {
              this.content()
            }.width('100%').padding({ left: 16, right: 16, top: 6, bottom: 12 })
          }.layoutWeight(1).width('100%').align(Alignment.Top)
            .scrollBar(BarState.Auto).id(`keyboard_settings_scroll_${page}`)
            // Opaque, so the page underneath does not show through while sliding.
            .backgroundColor($r('app.color.settings_background_surface'))
            // A sub-page always draws over the top page, entering or leaving.
            .zIndex(page === SettingsPageId.Top ? 0 : 1)
            .transition(this.slideTransition(page))
        }, (page: SettingsPageId) => page.toString())
        this.footer()
      }
    }.width('100%').height('100%').clip(true).backgroundColor($r('app.color.settings_background_surface'))
  }
}
