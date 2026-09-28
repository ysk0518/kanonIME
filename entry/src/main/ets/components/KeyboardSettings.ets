import { DEFAULT_LAYOUT_ORDER, DEFAULT_FLICK_DISTANCE, DEFAULT_LONG_PRESS_MS,
  KEYBOARD_LAYOUTS, layoutName, layoutLanguage, languageLayouts } from '../common/KeyboardConfig';
import { kanonIme } from '../kanon/KanonIme';
import { DEFAULT_SHORTCUT_ORDER, shortcutOrder } from '../common/ShortcutConfig';
import { ShortcutEditor } from './ShortcutEditor';

@Component
export struct KeyboardSettings {
  @State private selectedLayouts: string[] = [];
  @State private selectedShortcuts: string[] = [];
  @State private saving: boolean = false;
  @State private message: string = '';
  @State private flickDistance: number = DEFAULT_FLICK_DISTANCE;
  @State private longPressMs: number = DEFAULT_LONG_PRESS_MS;
  @State private previewEnabled: boolean = true;
  onSaved: () => void = () => {};

  aboutToAppear(): void {
    this.selectedShortcuts = shortcutOrder(AppStorage.get<string>('kanonShortcutOrder') ?? DEFAULT_SHORTCUT_ORDER);
    this.selectedLayouts = languageLayouts(AppStorage.get<string>('kanonLayoutOrder') ?? DEFAULT_LAYOUT_ORDER);
    this.flickDistance = AppStorage.get<number>('kanonFlickDistance') ?? DEFAULT_FLICK_DISTANCE;
    this.longPressMs = AppStorage.get<number>('kanonLongPressMs') ?? DEFAULT_LONG_PRESS_MS;
    this.previewEnabled = AppStorage.get<boolean>('kanonFlickPreviewEnabled') ?? true;
  }

  private hasLanguage(language: string): boolean {
    return this.selectedLayouts.some((id: string) => layoutLanguage(id) === language);
  }

  private toggleLanguage(language: string, enable: boolean): void {
    if (enable && !this.hasLanguage(language)) {
      this.selectedLayouts = this.selectedLayouts.concat([language === 'JP' ? 'jp_flick' : 'en_flick']);
    } else if (!enable && this.selectedLayouts.length > 1) {
      this.selectedLayouts = this.selectedLayouts.filter((id: string) => layoutLanguage(id) !== language);
    }
    this.message = '';
  }

  private chooseLayout(id: string): void {
    this.selectedLayouts = this.selectedLayouts.map((item: string) =>
      layoutLanguage(item) === layoutLanguage(id) ? id : item);
    this.message = '';
  }

  private async save(): Promise<void> {
    if (this.saving) { return; }
    this.saving = true;
    try {
      if (await kanonIme.applyLayoutConfig(this.selectedLayouts.join(','))) {
        AppStorage.setOrCreate('kanonFlickDistance', this.flickDistance);
        AppStorage.setOrCreate('kanonLongPressMs', this.longPressMs);
        AppStorage.setOrCreate('kanonFlickPreviewEnabled', this.previewEnabled);
        AppStorage.setOrCreate('kanonShortcutOrder', shortcutOrder(this.selectedShortcuts.join(',')).join(','));
        this.message = '保存しました';
        this.onSaved();
      } else { this.message = '保存できませんでした。入力を確定してから再度お試しください。'; }
    } finally { this.saving = false; }
  }

  build() {
    Column({ space: 4 }) {
      Row() {
        Text('キーボード設定').fontSize(18).fontColor($r('app.color.text_normal')).layoutWeight(1)
        Button(this.saving ? '保存中' : '保存')
          .enabled(!this.saving)
          .onClick(() => this.save())
          .id('keyboard_config_save')
      }
      .width('100%')
      Scroll() {
        Column({ space: 8 }) {
          ShortcutEditor({ selectedShortcuts: $selectedShortcuts, disabled: this.saving })
          Divider().color($r('app.color.light_gray'))
          Text('言語ごとのキーボード').fontSize(14).fontColor($r('app.color.text_secondary'))
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
            if (this.hasLanguage(language)) {
              Column({ space: 4 }) {
                ForEach(KEYBOARD_LAYOUTS.filter((id: string) => layoutLanguage(id) === language), (id: string) => {
                  Button(`${this.selectedLayouts.includes(id) ? '✓ ' : ''}${layoutName(id)}`)
                    .width('100%').enabled(!this.saving)
                    .fontColor(this.selectedLayouts.includes(id) ? $r('app.color.candidate_accent') : $r('app.color.text_normal'))
                    .backgroundColor(this.selectedLayouts.includes(id) ? $r('app.color.candidate_selected') : $r('app.color.key_item_normal'))
                    .accessibilityText(`${layoutName(id)}${this.selectedLayouts.includes(id) ? '、選択中' : ''}`)
                    .onClick(() => this.chooseLayout(id))
                    .id(`keyboard_config_${id}`)
                })
              }.width('100%')
            }
          })
          Text('🌐で言語を切り替えます。各言語の配列と、最後に使った言語を保存します。')
            .fontSize(12).fontColor($r('app.color.text_secondary'))
          Divider().color($r('app.color.light_gray'))
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
          if (this.message.length > 0) { Text(this.message).fontSize(14).fontColor($r('app.color.text_normal')) }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.menu_background'))
  }
}
