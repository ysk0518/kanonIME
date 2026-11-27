import { shortcutIcon, shortcutName } from '../common/ShortcutConfig';
import { addShortcut, availableShortcuts, canMoveShortcut, moveShortcut, removeShortcut } from '../common/ShortcutConfigValues';

@Component
export struct ShortcutEditor {
  @Prop selectedShortcuts: string[] = [];
  @Prop disabled: boolean = false;
  onChange: (order: string[]) => void = () => {};

  private labelText(id: string): string {
    try {
      return this.getUIContext().getHostContext()?.resourceManager.getStringSync(shortcutName(id).id) ?? id;
    } catch (error) { return id; }
  }

  private actionEnabled(id: string, direction: number): boolean {
    return !this.disabled && (direction === 0 || canMoveShortcut(this.selectedShortcuts, id, direction));
  }

  @Builder
  previewIcon(icon: Resource) {
    Stack() {
      Image(icon).width(20).height(20).fillColor($r('app.color.key_text'))
    }.height('100%').layoutWeight(1)
  }

  @Builder
  preview() {
    Row() {
      this.previewIcon($r('app.media.ic_emoji'))
      Text('!?#').fontSize(15).maxFontScale(1.25).maxLines(1).textAlign(TextAlign.Center)
        .fontColor($r('app.color.key_text')).layoutWeight(1)
      if (this.selectedShortcuts.length === 0) {
        Blank().layoutWeight(1)
      } else {
        ForEach(this.selectedShortcuts, (id: string) => {
          this.previewIcon(shortcutIcon(id))
        }, (id: string) => id)
      }
      this.previewIcon($r('app.media.ic_more_horiz'))
      this.previewIcon($rawfile('down.svg'))
    }.width('100%').height(40).padding({ left: 8, right: 8 }).borderRadius(12)
      .backgroundColor($r('app.color.candidate_background')).accessibilityLevel('no-hide-descendants')
      .id('shortcut_toolbar_preview')
  }

  @Builder
  iconButton(icon: Resource, label: Resource, id: string, direction: number, buttonId: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Image(icon).width(20).height(20).fillColor($r('app.color.settings_accent')).accessibilityLevel('no')
    }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
      .enabled(this.actionEnabled(id, direction)).opacity(this.actionEnabled(id, direction) ? 1 : 0.35)
      .accessibilityText(label).onClick(action).id(buttonId)
  }

  @Builder
  divider() {
    Divider().strokeWidth(1).color($r('app.color.light_gray'))
  }

  @Builder
  shortcutRows() {
    Column() {
      ForEach(this.selectedShortcuts, (id: string) => {
        if (this.selectedShortcuts.indexOf(id) > 0) { this.divider() }
        Row({ space: 4 }) {
          Image(shortcutIcon(id)).width(20).height(20).margin({ right: 4 }).fillColor($r('app.color.key_text'))
            .accessibilityLevel('no')
          Text(shortcutName(id)).fontSize(18).fontColor($r('app.color.text_normal')).layoutWeight(1)
          this.iconButton($r('app.media.ic_arrow_up'), $r('app.string.shortcut_move_up', this.labelText(id)),
            id, -1, `shortcut_move_up_${id}`,
            () => this.onChange(moveShortcut(this.selectedShortcuts, id, -1)))
          this.iconButton($r('app.media.ic_arrow_down'), $r('app.string.shortcut_move_down', this.labelText(id)),
            id, 1, `shortcut_move_down_${id}`,
            () => this.onChange(moveShortcut(this.selectedShortcuts, id, 1)))
          this.iconButton($r('app.media.ic_trash'), $r('app.string.shortcut_remove', this.labelText(id)),
            id, 0, `shortcut_remove_${id}`, () => this.onChange(removeShortcut(this.selectedShortcuts, id)))
        }.width('100%').constraintSize({ minHeight: 56 })
      }, (id: string) => id)
      ForEach(availableShortcuts(this.selectedShortcuts), (id: string) => {
        if (this.selectedShortcuts.length > 0 || availableShortcuts(this.selectedShortcuts)[0] !== id) { this.divider() }
        Button({ type: ButtonType.Normal }) {
          Text($r('app.string.shortcut_add', this.labelText(id)))
            .fontSize(18).fontColor($r('app.color.settings_accent')).width('100%')
        }.width('100%').constraintSize({ minHeight: 56 }).padding(0).backgroundColor(Color.Transparent)
          .enabled(!this.disabled).onClick(() => this.onChange(addShortcut(this.selectedShortcuts, id)))
          .id(`shortcut_add_${id}`)
      }, (id: string) => id)
    }.width('100%').padding({ left: 18, right: 18 })
      .borderRadius(22).backgroundColor($r('app.color.settings_card'))
  }

  build() {
    Column({ space: 8 }) {
      this.preview()
      Text($r('app.string.shortcut_order_help'))
        .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      this.shortcutRows()
      Text($r('app.string.shortcut_hidden_help'))
        .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
    }.width('100%')
  }
}
