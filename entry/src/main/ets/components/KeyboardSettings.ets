import { DEFAULT_LAYOUT_ORDER, DEFAULT_FLICK_DISTANCE, DEFAULT_LONG_PRESS_MS,
  layoutLanguage, languageLayouts, readSharedLayoutOrder, writeSharedLayoutOrder,
  readSharedHapticLevel, writeSharedHapticLevel } from '../common/KeyboardConfig';
import { DEFAULT_SHORTCUT_ORDER, shortcutOrder } from '../common/ShortcutConfig';
import { ShortcutEditor } from './ShortcutEditor';
import { KeyboardBackgroundSettings } from './KeyboardBackgroundSettings';

@Component
export struct KeyboardSettings {
  @State private backgroundOpen: boolean = false;
  @State private selectedLayouts: string[] = [];
  @State private selectedFlick: boolean = true;
  @State private selectedShortcuts: string[] = [];
  @State private saving: boolean = false;
  @State private message: string = '';
  @State private flickDistance: number = DEFAULT_FLICK_DISTANCE;
  @State private longPressMs: number = DEFAULT_LONG_PRESS_MS;
  @State private previewEnabled: boolean = true;
  @State private hapticLevel: number = 1;
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
    this.previewEnabled = AppStorage.get<boolean>('kanonFlickPreviewEnabled') ?? true;
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
      this.message = '言語設定を適用しました';
    } catch (e) {
      this.selectedLayouts = previous;
      this.message = '言語設定を適用できませんでした';
    }
  }

  private chooseLayout(flick: boolean): void {
    this.selectedFlick = flick;
    this.selectedLayouts = this.selectedLayouts.map((item: string) => this.layoutForLanguage(layoutLanguage(item)));
    this.message = '';
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
      this.message = '保存しました';
    } catch (e) {
      this.message = '保存できませんでした。再度お試しください。';
    } finally { this.saving = false; }
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
          .accessibilityText('戻る')
          .onClick(() => this.onClose())
          .id('keyboard_config_close')
        Text(this.languageOnly ? '使用する言語' : 'キーボード設定').fontSize(20).maxFontScale(1.3)
          .fontColor($r('app.color.text_normal')).layoutWeight(1)
        if (!this.languageOnly) {
          Button(this.saving ? '保存中' : '保存')
            .fontSize(14).maxFontScale(1).height(40)
            .enabled(!this.saving && this.hasChanges())
            .opacity(this.saving || !this.hasChanges() ? 0.45 : 1)
            .onClick(() => this.save())
            .id('keyboard_config_save')
        }
      }
      .width('100%').height(56)
      Scroll() {
        Column({ space: 8 }) {
          if (this.languageOnly) {
            Text('使用する言語').fontSize(14).fontColor($r('app.color.text_secondary'))
            ForEach(['JP', 'EN'], (language: string) => {
              Row() {
                Text(language === 'JP' ? '日本語' : '英語')
                  .fontSize(15).fontColor($r('app.color.text_normal')).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.hasLanguage(language) })
                  .enabled(!this.saving && !(this.selectedLayouts.length === 1 && this.hasLanguage(language)))
                  .onChange((value: boolean) => this.toggleLanguage(language, value))
                  .accessibilityText(language === 'JP' ? '日本語を使う' : '英語を使う')
                  .id(`keyboard_config_language_${language}`)
              }
              .width('100%')
            })
            Text('言語のオン・オフはすぐに反映されます。')
              .fontSize(12).fontColor($r('app.color.text_secondary'))
          } else {
          Text('共通の配列').fontSize(14).fontColor($r('app.color.text_secondary'))
          Row({ space: 8 }) {
            ForEach([true, false], (flick: boolean) => {
              Button(`${this.selectedFlick === flick ? '✓ ' : ''}${flick ? '12キー' : 'QWERTY'}`)
                .layoutWeight(1).enabled(!this.saving)
                .fontColor(this.selectedFlick === flick ? $r('app.color.candidate_accent') : $r('app.color.text_normal'))
                .backgroundColor(this.selectedFlick === flick ? $r('app.color.candidate_selected') : $r('app.color.key_item_normal'))
                .accessibilityText(`${flick ? '12キー' : 'QWERTY'}${this.selectedFlick === flick ? '、選択中' : ''}`)
                .onClick(() => this.chooseLayout(flick))
                .id(flick ? 'keyboard_config_flick' : 'keyboard_config_qwerty')
            })
          }.width('100%')
          Text('「あA1」で日本語・英語・数字を切り替えます。左下の配列キーを押すと、使用中の日英両方を12キー／QWERTYに切り替えます。')
            .fontSize(12).fontColor($r('app.color.text_secondary'))
          Divider().color($r('app.color.light_gray'))
          Text('高さはキーボード左上のメニュー →「サイズ」で変更できます。')
            .fontSize(12).fontColor($r('app.color.text_secondary'))
          Button('背景画像を変更').width('100%').enabled(!this.saving && !this.hasChanges())
            .onClick(() => { this.backgroundOpen = true; }).id('keyboard_config_background')
          if (this.hasChanges()) {
            Text('背景画像を開く前に、変更した設定を保存してください。')
              .fontSize(12).fontColor($r('app.color.text_secondary'))
          }
          Row() {
            Text('入力キーの文字プレビュー').fontSize(15).fontColor($r('app.color.text_normal')).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.previewEnabled })
              .enabled(!this.saving)
              .onChange((value: boolean) => { this.previewEnabled = value; })
              .id('keyboard_config_preview')
          }
          Text('フリック感度')
            .fontSize(14).fontColor($r('app.color.text_normal'))
          Slider({ value: this.flickDistance, min: 12, max: 30, step: 2 })
            .enabled(!this.saving)
            .onChange((value: number) => { this.flickDistance = value; })
            .id('keyboard_config_flick_distance')
          Text('左へ動かすと短い指の動きで文字を選べます。')
            .fontSize(12).fontColor($r('app.color.text_secondary'))
          Text(`記号入力までの長押し：${(this.longPressMs / 1000).toFixed(2)}秒`)
            .fontSize(14).fontColor($r('app.color.text_normal'))
          Slider({ value: this.longPressMs, min: 250, max: 650, step: 50 })
            .enabled(!this.saving)
            .onChange((value: number) => { this.longPressMs = value; })
            .id('keyboard_config_long_press')
          Divider().color($r('app.color.light_gray'))
          Text('キー操作の振動').fontSize(15).fontColor($r('app.color.text_normal'))
          Row({ space: 8 }) {
            ForEach([0, 1, 2], (level: number) => {
              Button(level === 0 ? 'オフ' : level === 1 ? '弱' : '強')
                .layoutWeight(1).enabled(!this.saving)
                .fontColor(this.hapticLevel === level ? $r('app.color.candidate_accent') : $r('app.color.text_normal'))
                .backgroundColor(this.hapticLevel === level ? $r('app.color.candidate_selected') : $r('app.color.key_item_normal'))
                .onClick(() => { this.hapticLevel = level; })
                .id(`keyboard_config_haptic_${level}`)
            })
          }.width('100%')
          Text('振動の強さは端末によって異なります。')
            .fontSize(12).fontColor($r('app.color.text_secondary'))
          Divider().color($r('app.color.light_gray'))
          ShortcutEditor({ selectedShortcuts: $selectedShortcuts, disabled: this.saving })
          }
          if (this.message.length > 0) { Text(this.message).fontSize(14).fontColor($r('app.color.text_normal')) }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      }
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.menu_background'))
  }
}
