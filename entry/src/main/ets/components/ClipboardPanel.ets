import { clipboardSnapshot } from '../kanon/ClipboardSnapshot';
import { clipboardStore, CLIPBOARD_PIN_LIMIT, CLIPBOARD_TEXT_LIMIT } from '../common/ClipboardStore';
import { clipboardHistory } from '../kanon/ClipboardHistory';
import InputMethodExtensionContext from '@ohos.InputMethodExtensionContext';
import { kanonIme } from '../kanon/KanonIme';
import { SubMenuType } from '../model/KeyboardKeyData';
import { ClipboardCard } from './ClipboardCard';
import { clipboardColumns } from '../common/KeyboardLayout';

@Component
export struct ClipboardPanel {
  @StorageLink('submenuType') submenuType: number = SubMenuType.CLIPBOARD;
  @StorageLink('kanonClipboardRevision') @Watch('refresh') revision: number = 0;
  @StorageLink('kanonClipboardAutoStatus') autoStatus: string = 'permission';
  @StorageLink('kanonClipboardCurrentText') private current: string = '';
  @State private pinned: string[] = [];
  @State private recent: string[] = [];
  @State private busy: boolean = false;
  @State private message: string = '';
  @State private editing: boolean = false;
  @State private selected: string[] = [];
  @StorageLink('kanonFontScale') fontScale: number = 1;
  @State private contentWidth: number = 336;
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    this.refresh();
    clipboardHistory.refresh();
  }

  aboutToDisappear(): void { this.alive = false; clipboardSnapshot.clear(); }

  private refresh(): void {
    this.pinned = clipboardStore.getPinned();
    this.recent = clipboardStore.getRecent().filter((value: string) => !this.pinned.includes(value));
    const available: string[] = this.pinned.concat(this.recent, this.current.length > CLIPBOARD_TEXT_LIMIT ? [this.current] : []);
    this.selected = this.selected.filter((value: string) => available.includes(value));
  }

  private async enableHistory(): Promise<void> {
    try {
      const context: InputMethodExtensionContext = this.getUIContext().getHostContext() as InputMethodExtensionContext;
      await context.startAbility({ bundleName: 'local.yplic.kanon', abilityName: 'EntryAbility',
        parameters: { kanonClipboardPermission: true } });
    } catch (e) { this.message = '権限設定を開けませんでした。'; }
  }

  private async capture(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      await clipboardSnapshot.capture();
      if (!this.alive) { return; }
      this.current = clipboardSnapshot.getText();
      this.message = clipboardSnapshot.getStatus() === 'error' ? 'クリップボードを読み取れませんでした' :
        this.current.length === 0 ? '貼り付けられるテキストがありません' : '';
      this.refresh();
    } finally { if (this.alive) { this.busy = false; } }
  }

  private async paste(value: string): Promise<void> {
    if (this.busy || value.length === 0) { return; }
    this.busy = true;
    try {
      const pasted: boolean = await kanonIme.keyPaste(value);
      if (!this.alive) { return; }
      if (pasted) { this.submenuType = SubMenuType.NORMAL; }
      else { this.message = '貼り付けに失敗しました。再度お試しください。'; }
    } finally { if (this.alive) { this.busy = false; } }
  }

  private tap(value: string): void {
    if (this.busy) { return; }
    if (!this.editing) { this.paste(value); return; }
    this.selected = this.selected.includes(value) ? this.selected.filter((item: string) => item !== value) :
      this.selected.concat([value]);
  }

  private hold(value: string): void {
    if (this.busy) { return; }
    this.editing = true;
    if (!this.selected.includes(value)) { this.selected = this.selected.concat([value]); }
    this.message = '';
  }

  private allPinned(): boolean {
    return this.selected.length > 0 && this.selected.every((value: string) => this.pinned.includes(value));
  }

  private finishEditing(): void { this.selected = []; this.editing = false; }

  private pinSelected(): void {
    if (this.busy || this.selected.length === 0) { return; }
    const unpin: boolean = this.allPinned();
    const values: string[] = this.selected.slice();
    this.message = '';
    for (const value of values) {
      if (unpin) { clipboardStore.remember(value); clipboardStore.removePinned(value); }
      else {
        const result: string = clipboardStore.pin(value);
        if (result === 'full' || result === 'too-long') {
          this.message = result === 'full' ? `固定は${CLIPBOARD_PIN_LIMIT}件までです` :
            `固定できるのは${CLIPBOARD_TEXT_LIMIT}文字までです`;
          break;
        }
      }
    }
    this.finishEditing();
    this.refresh();
  }

  private deleteSelected(): void {
    if (this.busy) { return; }
    const values: string[] = this.selected.slice();
    for (const value of values) {
      if (value === this.current) { clipboardHistory.forgetCurrent(); }
      clipboardStore.removePinned(value);
      clipboardStore.removeRecent(value);
    }
    this.finishEditing();
    this.message = '';
    this.refresh();
  }

  @Builder
  cards(values: string[], kind: string) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(values, (value: string, index: number) => {
        Column() {
          ClipboardCard({ value: value, pinned: this.pinned.includes(value), editing: this.editing,
            selected: this.selected.includes(value), cardId: `clipboard_paste_${kind}_${index}`,
            onTap: () => this.tap(value), onHold: () => this.hold(value) })
        }
        .width(Math.max(1, (this.contentWidth - (clipboardColumns(this.contentWidth, this.fontScale) - 1) * 8) /
          clipboardColumns(this.contentWidth, this.fontScale)))
        .margin({ bottom: 8, right: (index + 1) % clipboardColumns(this.contentWidth, this.fontScale) === 0 ? 0 : 8 })
        .enabled(!this.busy)
      }, (value: string) => value)
    }.width('100%')
  }

  @Builder
  action(icon: Resource, label: string, enabled: boolean, run: () => void, key: string) {
    Stack() { Image(icon).width(22).height(22).fillColor($r('app.color.key_text')) }
      .width(40).height(36).borderRadius(18).enabled(enabled && !this.busy)
      .opacity(enabled ? 1 : 0.4).onClick(() => run()).accessibilityText(label).id(key)
  }

  build() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(this.editing ? `${this.selected.length}件選択` : 'クリップボード')
          .fontSize(16).fontColor($r('app.color.text_normal')).layoutWeight(1)
        if (this.editing) {
          Text('完了').fontSize(14).fontColor($r('app.color.candidate_accent')).padding(8)
            .enabled(!this.busy).onClick(() => this.finishEditing()).id('clipboard_edit_done')
        } else {
          this.action($r('app.media.ic_edit'), '履歴を選択して編集', this.recent.length + this.pinned.length > 0 ||
            this.current.length > CLIPBOARD_TEXT_LIMIT, () => { this.editing = true; this.message = ''; }, 'clipboard_edit')
        }
        if (!this.editing && this.autoStatus !== 'ready') {
          PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE, buttonType: ButtonType.Capsule })
            .enabled(!this.busy)
            .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
              if (result === PasteButtonOnClickResult.SUCCESS) { this.capture(); }
            })
            .id('clipboard_read')
        }
      }.width('100%').constraintSize({ minHeight: 36 })
      if (this.autoStatus !== 'ready') {
        Button('コピー履歴を自動で追加する').fontSize(13).padding(8).constraintSize({ minHeight: 32 }).enabled(!this.busy)
          .onClick(() => this.enableHistory()).id('clipboard_history_setup')
      }
      if (this.editing) {
        Row({ space: 8 }) {
          Text('すべて選択').fontSize(13).fontColor($r('app.color.candidate_accent')).layoutWeight(1)
            .enabled(!this.busy).onClick(() => {
              this.selected = this.recent.concat(this.pinned,
                this.current.length > CLIPBOARD_TEXT_LIMIT ? [this.current] : []);
            }).id('clipboard_select_all')
          this.action(this.allPinned() ? $r('app.media.ic_unpin') : $r('app.media.ic_pin'),
            this.allPinned() ? '選択した固定を解除' : '選択したテキストを固定',
            this.selected.length > 0, () => this.pinSelected(), 'clipboard_pin_selected')
          this.action($r('app.media.ic_trash'), '選択したテキストを削除', this.selected.length > 0,
            () => this.deleteSelected(), 'clipboard_delete_selected')
        }.width('100%').constraintSize({ minHeight: 36 })
      }
      if (this.message.length > 0) {
        Text(this.message).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      }
      Scroll() {
        Column({ space: 4 }) {
          if (this.current.length > CLIPBOARD_TEXT_LIMIT) {
            Text('最新のコピー').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%').padding({ top: 4, bottom: 4 })
            this.cards([this.current], 'current')
          }
          if (this.recent.length > 0) {
            Text('最近').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%').padding({ top: 4, bottom: 4 })
            this.cards(this.recent, 'recent')
          }
          if (this.pinned.length > 0) {
            Text('固定').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%').padding({ top: 4, bottom: 4 })
            this.cards(this.pinned, 'pinned')
          }
          if (this.recent.length + this.pinned.length === 0 && this.current.length <= CLIPBOARD_TEXT_LIMIT) {
            Column({ space: 12 }) {
              Image($r('app.media.ic_clipboard')).width(40).height(40).fillColor($r('app.color.text_secondary')).opacity(0.5)
              Text('コピーしたテキストがここに並びます').fontSize(14).fontColor($r('app.color.text_secondary'))
              Text('よく使う文章は長押しで固定できます').fontSize(12).fontColor($r('app.color.text_secondary'))
            }.width('100%').padding({ top: 28, bottom: 28 })
          }
        }.width('100%')
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
      .onAreaChange((_old: Area, area: Area) => {
        const width: number = Number(area.width);
        if (width > 0 && Math.abs(width - this.contentWidth) > 0.5) { this.contentWidth = width; }
      })
      if (!this.editing && this.recent.length + this.pinned.length > 0) {
        Text('タップで貼り付け・長押しで選択').fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
      }
    }
    .padding({ left: 12, right: 12, top: 4, bottom: 8 }).width('100%').height('100%')
    .backgroundColor($r('app.color.menu_background'))
  }
}
