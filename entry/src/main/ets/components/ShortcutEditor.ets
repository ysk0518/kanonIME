import { DEFAULT_SHORTCUT_ORDER, SHORTCUT_IDS, shortcutIcon, shortcutName } from '../common/ShortcutConfig';

@Component
export struct ShortcutEditor {
  @Link selectedShortcuts: string[];
  @Prop disabled: boolean = false;

  private labelText(id: string): string {
    try {
      return this.getUIContext().getHostContext()?.resourceManager.getStringSync(shortcutName(id).id) ?? id;
    } catch (error) { return id; }
  }

  private move(id: string, direction: number): void {
    const index: number = this.selectedShortcuts.indexOf(id);
    const next: number = index + direction;
    if (index < 0 || next < 0 || next >= this.selectedShortcuts.length) { return; }
    const order: string[] = this.selectedShortcuts.slice();
    order[index] = order[next];
    order[next] = id;
    this.selectedShortcuts = order;
  }

  build() {
    Column({ space: 8 }) {
      Text($r('app.string.shortcut_title')).fontSize(14).fontColor($r('app.color.text_secondary'))
      Text($r('app.string.shortcut_order_help'))
        .fontSize(12).fontColor($r('app.color.text_secondary'))
      ForEach(this.selectedShortcuts, (id: string) => {
        Row({ space: 4 }) {
          Image(shortcutIcon(id)).width(20).height(20).fillColor($r('app.color.key_text'))
            .accessibilityLevel('no')
          Text(shortcutName(id)).fontSize(14).fontColor($r('app.color.text_normal')).layoutWeight(1)
          Button('←').width(40).height(36).fontSize(16).maxFontScale(1)
            .enabled(!this.disabled && this.selectedShortcuts.indexOf(id) > 0)
            .accessibilityText($r('app.string.shortcut_move_left', this.labelText(id)))
            .onClick(() => this.move(id, -1)).id(`shortcut_move_left_${id}`)
          Button('→').width(40).height(36).fontSize(16).maxFontScale(1)
            .enabled(!this.disabled && this.selectedShortcuts.indexOf(id) < this.selectedShortcuts.length - 1)
            .accessibilityText($r('app.string.shortcut_move_right', this.labelText(id)))
            .onClick(() => this.move(id, 1)).id(`shortcut_move_right_${id}`)
          Button($r('app.string.shortcut_delete')).fontSize(12).maxFontScale(1).width(56).height(36).enabled(!this.disabled)
            .accessibilityText($r('app.string.shortcut_remove', this.labelText(id)))
            .onClick(() => { this.selectedShortcuts = this.selectedShortcuts.filter((item: string) => item !== id); })
            .id(`shortcut_remove_${id}`)
        }.width('100%')
      }, (id: string) => id)
      ForEach(SHORTCUT_IDS.filter((id: string) => !this.selectedShortcuts.includes(id)), (id: string) => {
        Button($r('app.string.shortcut_add', this.labelText(id))).width('100%').enabled(!this.disabled)
          .fontColor($r('app.color.text_normal')).backgroundColor($r('app.color.key_item_normal'))
          .onClick(() => { this.selectedShortcuts = this.selectedShortcuts.concat([id]); })
          .id(`shortcut_add_${id}`)
      }, (id: string) => id)
      Row() {
        Text($r('app.string.shortcut_hidden_help'))
          .fontSize(12).fontColor($r('app.color.text_secondary')).layoutWeight(1)
        Button($r('app.string.shortcut_reset')).fontSize(12).enabled(!this.disabled)
          .onClick(() => { this.selectedShortcuts = DEFAULT_SHORTCUT_ORDER.split(','); })
          .id('shortcut_reset')
      }.width('100%')
    }.width('100%')
  }
}
