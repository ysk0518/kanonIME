import { DEFAULT_LAYOUT_ORDER, DEFAULT_FLICK_DISTANCE, DEFAULT_LONG_PRESS_MS,
  DEFAULT_HAPTIC_LEVEL, DEFAULT_KEY_PREVIEW_ENABLED,
  layoutLanguage, languageLayouts, readSharedLayoutOrder, writeSharedLayoutOrder,
  readSharedHapticLevel, writeSharedHapticLevel } from '../common/KeyboardConfig';
import { DEFAULT_SHORTCUT_ORDER, shortcutOrder } from '../common/ShortcutConfig';
import { ShortcutEditor } from './ShortcutEditor';
import { KeyboardBackgroundSettings } from './KeyboardBackgroundSettings';

@Component
export struct KeyboardSettings {
  @State private settingsTab: number = 0;
  @State private backgroundOpen: boolean = false;
  @State private selectedLayouts: string[] = [];
  @State private selectedFlick: boolean = true;
  @State private selectedShortcuts: string[] = [];
  @State private saving: boolean = false;
  @State private message: ResourceStr = '';
  @State private flickDistance: number = DEFAULT_FLICK_DISTANCE;
  @State private longPressMs: number = DEFAULT_LONG_PRESS_MS;
  @State private previewEnabled: boolean = DEFAULT_KEY_PREVIEW_ENABLED;
  @State private hapticLevel: number = DEFAULT_HAPTIC_LEVEL;
  private savedSettingsKey: string = '';
  languageOnly: boolean = false;
  onClose: () => void = () => {};

  aboutToAppear(): void {
    this.selectedShortcuts = shortcutOrder(AppStorage.get<string>('kanonShortcutOrder') ?? DEFAULT_SHORTCUT_ORDER);
    const shared: string | undefined = readSharedLayoutOrder();
    const layouts: string[] = languageLayouts(shared ??
      AppStorage.get<string>('kanonLayoutOrder') ?? DEFAULT_LAYOUT_ORDER);
    const current: string = shared === undefined ? AppStorage.get<string>('kanonLayout') ?? layouts[0] : layouts[0];
    this.selectedFlick = current.endsWith('_flick');
    this.selectedLayouts = layouts.map((id: string) => this.layoutForLanguage(layoutLanguage(id)));
    this.flickDistance = AppStorage.get<number>('kanonFlickDistance') ?? DEFAULT_FLICK_DISTANCE;
    this.longPressMs = AppStorage.get<number>('kanonLongPressMs') ?? DEFAULT_LONG_PRESS_MS;
    this.previewEnabled = AppStorage.get<boolean>('kanonFlickPreviewEnabled') ?? DEFAULT_KEY_PREVIEW_ENABLED;
    this.hapticLevel = readSharedHapticLevel();
    this.savedSettingsKey = this.currentSettingsKey();
  }

  private currentSettingsKey(): string {
    return [this.selectedLayouts.join(','), this.selectedFlick ? '1' : '0',
      this.selectedShortcuts.join(','), this.flickDistance.toString(), this.longPressMs.toString(),
      this.previewEnabled ? '1' : '0', this.hapticLevel.toString()].join('|');
  }

  private hasChanges(): boolean {
    return this.savedSettingsKey.length > 0 && this.currentSettingsKey() !== this.savedSettingsKey;
  }

  private hasLanguage(language: string): boolean {
    return this.selectedLayouts.some((id: string) => layoutLanguage(id) === language);
  }

  private layoutForLanguage(language: string): string {
    return `${language === 'EN' ? 'en' : 'jp'}_${this.selectedFlick ? 'flick' : 'qwerty'}`;
  }

  private toggleLanguage(language: string, enable: boolean): void {
    const previous: string[] = this.selectedLayouts;
    if (enable && !this.hasLanguage(language)) {
      this.selectedLayouts = this.selectedLayouts.concat([this.layoutForLanguage(language)]);
    } else if (!enable && this.selectedLayouts.length > 1) {
      this.selectedLayouts = this.selectedLayouts.filter((id: string) => layoutLanguage(id) !== language);
    }
    try {
      const order: string = languageLayouts(this.selectedLayouts.join(',')).join(',');
      writeSharedLayoutOrder(order);
      AppStorage.setOrCreate('kanonLayoutOrder', order);
      this.message = $r('app.string.settings_language_applied');
    } catch (e) {
      this.selectedLayouts = previous;
      this.message = $r('app.string.settings_language_failed');
    }
  }

  private chooseLayout(flick: boolean): void {
    this.selectedFlick = flick;
    this.selectedLayouts = this.selectedLayouts.map((item: string) => this.layoutForLanguage(layoutLanguage(item)));
    this.message = '';
  }

  private tabDefaultsChanged(tab: number): boolean {
    if (tab === 0) {
      return this.selectedFlick !== DEFAULT_LAYOUT_ORDER.split(',')[0].endsWith('_flick') ||
        this.flickDistance !== DEFAULT_FLICK_DISTANCE || this.longPressMs !== DEFAULT_LONG_PRESS_MS;
    }
    if (tab === 1) { return this.previewEnabled !== DEFAULT_KEY_PREVIEW_ENABLED; }
    return this.hapticLevel !== DEFAULT_HAPTIC_LEVEL || this.selectedShortcuts.join(',') !== DEFAULT_SHORTCUT_ORDER;
  }

  private restoreTabDefaults(tab: number): void {
    if (this.saving || !this.tabDefaultsChanged(tab)) { return; }
    if (tab === 0) {
      this.chooseLayout(DEFAULT_LAYOUT_ORDER.split(',')[0].endsWith('_flick'));
      this.flickDistance = DEFAULT_FLICK_DISTANCE;
      this.longPressMs = DEFAULT_LONG_PRESS_MS;
    } else if (tab === 1) {
      this.previewEnabled = DEFAULT_KEY_PREVIEW_ENABLED;
    } else {
      this.hapticLevel = DEFAULT_HAPTIC_LEVEL;
      this.selectedShortcuts = DEFAULT_SHORTCUT_ORDER.split(',');
    }
    this.message = $r('app.string.settings_defaults_pending');
  }

  @Builder
  tabResetButton(tab: number) {
    Column({ space: 8 }) {
      Divider().color($r('app.color.light_gray'))
      Button($r('app.string.common_reset')).width('100%')
        .enabled(!this.saving && this.tabDefaultsChanged(tab))
        .onClick(() => this.restoreTabDefaults(tab)).id(`keyboard_config_reset_${tab}`)
      Text(tab === 0 ? $r('app.string.settings_reset_input_scope') :
        tab === 1 ? $r('app.string.settings_reset_appearance_scope') : $r('app.string.settings_reset_feedback_scope'))
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
    }.width('100%')
  }

  private async save(): Promise<void> {
    if (this.saving || !this.hasChanges()) { return; }
    this.saving = true;
    try {
      const order: string = languageLayouts(this.selectedLayouts.map((id: string) =>
        this.layoutForLanguage(layoutLanguage(id))).join(',')).join(',');
      writeSharedLayoutOrder(order);
      AppStorage.setOrCreate('kanonLayoutOrder', order);
      AppStorage.setOrCreate('kanonFlickDistance', this.flickDistance);
      AppStorage.setOrCreate('kanonLongPressMs', this.longPressMs);
      AppStorage.setOrCreate('kanonFlickPreviewEnabled', this.previewEnabled);
      writeSharedHapticLevel(this.hapticLevel);
      AppStorage.setOrCreate('kanonHapticLevel', this.hapticLevel);
      AppStorage.setOrCreate('kanonShortcutOrder', shortcutOrder(this.selectedShortcuts.join(',')).join(','));
      this.savedSettingsKey = this.currentSettingsKey();
      this.message = $r('app.string.common_saved');
    } catch (e) {
      this.message = $r('app.string.common_save_failed');
    } finally { this.saving = false; }
  }

  @Builder
  languageOptions() {
    Column({ space: 8 }) {
            Text($r('app.string.settings_languages')).fontSize(14).fontColor($r('app.color.text_secondary'))
            ForEach(['JP', 'EN'], (language: string) => {
              Row() {
                Text(language === 'JP' ? $r('app.string.settings_japanese') : $r('app.string.settings_english'))
                  .fontSize(15).fontColor($r('app.color.text_normal')).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.hasLanguage(language) })
                  .enabled(!this.saving && !(this.selectedLayouts.length === 1 && this.hasLanguage(language)))
                  .onChange((value: boolean) => this.toggleLanguage(language, value))
                  .accessibilityText(language === 'JP' ? $r('app.string.settings_use_japanese') : $r('app.string.settings_use_english'))
                  .id(`keyboard_config_language_${language}`)
              }
              .width('100%')
            })
            Text($r('app.string.settings_language_immediate'))
              .fontSize(12).fontColor($r('app.color.text_secondary'))

    }.width('100%')
  }

  @Builder
  inputOptions() {
    Column({ space: 12 }) {
      Text($r('app.string.settings_language_location'))
        .fontSize(12).fontColor($r('app.color.text_secondary'))
          Text($r('app.string.settings_layout')).fontSize(14).fontColor($r('app.color.text_secondary'))
          Row({ space: 8 }) {
            ForEach([true, false], (flick: boolean) => {
              Button(flick ? $r('app.string.settings_layout_flick') : $r('app.string.settings_layout_qwerty'))
                .layoutWeight(1).enabled(!this.saving)
                .fontColor(this.selectedFlick === flick ? $r('app.color.candidate_accent') : $r('app.color.text_normal'))
                .backgroundColor(this.selectedFlick === flick ? $r('app.color.candidate_selected') : $r('app.color.key_item_normal'))
                .accessibilityText(flick ? (this.selectedFlick ? $r('app.string.settings_flick_selected') : $r('app.string.settings_layout_flick')) : (this.selectedFlick ? $r('app.string.settings_layout_qwerty') : $r('app.string.settings_qwerty_selected')))
                .onClick(() => this.chooseLayout(flick))
                .id(flick ? 'keyboard_config_flick' : 'keyboard_config_qwerty')
            })
          }.width('100%')
          Text($r('app.string.settings_layout_help'))
            .fontSize(12).fontColor($r('app.color.text_secondary'))

          Text($r('app.string.settings_flick_sensitivity'))
            .fontSize(14).fontColor($r('app.color.text_normal'))
          Slider({ value: this.flickDistance, min: 12, max: 30, step: 2 })
            .enabled(!this.saving)
            .onChange((value: number) => { this.flickDistance = value; })
            .id('keyboard_config_flick_distance')
          Text($r('app.string.settings_flick_help'))
            .fontSize(12).fontColor($r('app.color.text_secondary'))
          Text($r('app.string.settings_long_press_seconds', (this.longPressMs / 1000).toFixed(2)))
            .fontSize(14).fontColor($r('app.color.text_normal'))
          Slider({ value: this.longPressMs, min: 250, max: 650, step: 50 })
            .enabled(!this.saving)
            .onChange((value: number) => { this.longPressMs = value; })
            .id('keyboard_config_long_press')
      this.tabResetButton(0)
    }.width('100%')
  }

  @Builder
  appearanceOptions() {
    Column({ space: 12 }) {
          Text($r('app.string.settings_size_help'))
            .fontSize(12).fontColor($r('app.color.text_secondary'))
          Button($r('app.string.settings_background')).width('100%').enabled(!this.saving && !this.hasChanges())
            .onClick(() => { this.backgroundOpen = true; }).id('keyboard_config_background')
          if (this.hasChanges()) {
            Text($r('app.string.settings_save_before_background'))
              .fontSize(12).fontColor($r('app.color.text_secondary'))
          }
          Row() {
            Text($r('app.string.settings_key_preview')).fontSize(15).fontColor($r('app.color.text_normal')).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.previewEnabled })
              .enabled(!this.saving)
              .onChange((value: boolean) => { this.previewEnabled = value; })
              .id('keyboard_config_preview')
          }
      this.tabResetButton(1)
    }.width('100%')
  }

  @Builder
  feedbackOptions() {
    Column({ space: 12 }) {
          Text($r('app.string.settings_haptics')).fontSize(15).fontColor($r('app.color.text_normal'))
          Row({ space: 8 }) {
            ForEach([0, 1, 2], (level: number) => {
              Button(level === 0 ? $r('app.string.settings_haptics_off') : level === 1 ? $r('app.string.settings_haptics_weak') : $r('app.string.settings_haptics_strong'))
                .layoutWeight(1).enabled(!this.saving)
                .fontColor(this.hapticLevel === level ? $r('app.color.candidate_accent') : $r('app.color.text_normal'))
                .backgroundColor(this.hapticLevel === level ? $r('app.color.candidate_selected') : $r('app.color.key_item_normal'))
                .onClick(() => { this.hapticLevel = level; })
                .id(`keyboard_config_haptic_${level}`)
            })
          }.width('100%')
          Text($r('app.string.settings_haptics_help'))
            .fontSize(12).fontColor($r('app.color.text_secondary'))
          Divider().color($r('app.color.light_gray'))
          ShortcutEditor({ selectedShortcuts: $selectedShortcuts, disabled: this.saving })
      this.tabResetButton(2)
    }.width('100%')
  }

  build() {
    Column({ space: 8 }) {
      if (this.backgroundOpen) {
        KeyboardBackgroundSettings({ onClose: () => { this.backgroundOpen = false; } })
      } else {
      Row() {
        Button('‹')
          .width(44).height(44).fontSize(28).maxFontScale(1)
          .backgroundColor(Color.Transparent).fontColor($r('app.color.text_normal'))
          .accessibilityText($r('app.string.common_back'))
          .onClick(() => this.onClose())
          .id('keyboard_config_close')
        Text(this.languageOnly ? $r('app.string.settings_languages') : $r('app.string.settings_title')).fontSize(20).maxFontScale(1.3)
          .fontColor($r('app.color.text_normal')).layoutWeight(1)
        if (!this.languageOnly) {
          Button(this.saving ? $r('app.string.common_saving') : $r('app.string.common_save'))
            .fontSize(14).maxFontScale(1).height(40)
            .enabled(!this.saving && this.hasChanges())
            .opacity(this.saving || !this.hasChanges() ? 0.45 : 1)
            .onClick(() => this.save())
            .id('keyboard_config_save')
        }
      }
      .width('100%').height(56)

        if (this.languageOnly) {
          Scroll() { this.languageOptions() }.layoutWeight(1).width('100%')
        } else {
          Tabs({ barPosition: BarPosition.End, index: this.settingsTab }) {
            TabContent() {
              Scroll() { this.inputOptions() }.width('100%').height('100%')
            }.tabBar($r('app.string.settings_tab_input'))
            TabContent() {
              Scroll() { this.appearanceOptions() }.width('100%').height('100%')
            }.tabBar($r('app.string.settings_tab_appearance'))
            TabContent() {
              Scroll() { this.feedbackOptions() }.width('100%').height('100%')
            }.tabBar($r('app.string.settings_tab_feedback'))
          }.layoutWeight(1).width('100%').barHeight(52).scrollable(false)
            .onChange((index: number) => { this.settingsTab = index; })
            .id('keyboard_settings_tabs')
        }
        if (this.message !== '') {
          Text(this.message).fontSize(14).fontColor($r('app.color.text_normal')).width('100%')
        }
      }
    }.padding(12).width('100%').height('100%').backgroundColor($r('app.color.menu_background'))
  }
}
