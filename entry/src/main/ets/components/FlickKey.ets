import { kanonIme } from '../kanon/KanonIme';
import { DEFAULT_FLICK_DISTANCE } from '../common/KeyboardConfig';
import { showKeyPreview, hideKeyPreview } from '../common/KeyPreviewState';
import { editorAdapter } from '../kanon/EditorAdapter';

@Component
export struct FlickKey {
  @StorageLink('kanonFlickDistance') flickDistance: number = DEFAULT_FLICK_DISTANCE;
  @StorageLink('kanonFlickPreviewEnabled') previewEnabled: boolean = true;
  @Prop values: string[] = [];
  @Prop modifier: boolean = false;
  @Prop english: boolean = false;
  @Prop textInput: boolean = false;
  @Prop keyId: string = '';
  @Prop uppercase: boolean = false;
  @Prop displayLabel: string = '';
  onLetter: () => void = () => {};
  @State private active: boolean = false;
  @State private flickDirection: number = 0;
  private finger: number = -1;
  private startEpoch: number = -1;
  private startX: number = 0;
  private startY: number = 0;
  private keyWidth: number = 0;
  private previewX: number = 0;
  private previewY: number = 0;

  private showPreview(): void {
    if (!this.previewEnabled || this.modifier) { this.hidePreview(); return; }
    const value: string = this.values[this.flickDirection] ?? '';
    showKeyPreview(this.values[0], value === ' ' ? 'space' : this.english && this.uppercase ? value.toUpperCase() : value,
      this.previewX, this.previewY, 'flick');
  }

  private hidePreview(): void {
    hideKeyPreview(this.values[0]);
  }

  aboutToDisappear(): void { this.hidePreview(); }

  private updateDirection(touch: TouchObject): void {
    const dx: number = touch.windowX - this.startX;
    const dy: number = touch.windowY - this.startY;
    this.flickDirection = Math.max(Math.abs(dx), Math.abs(dy)) < this.flickDistance ? 0 :
      (Math.abs(dx) > Math.abs(dy) ? (dx < 0 ? 1 : 3) : (dy < 0 ? 2 : 4));
  }

  private touch(event: TouchEvent): void {
    if (event.type === TouchType.Cancel) {
      this.active = false; this.finger = -1; this.hidePreview(); return;
    }
    if (event.type === TouchType.Down && !this.active && event.changedTouches.length > 0) {
      const finger: TouchObject = event.changedTouches[0];
      this.finger = finger.id;
      this.startEpoch = editorAdapter.getEpoch();
      this.startX = finger.windowX;
      this.startY = finger.windowY;
      // タッチ開始位置からキーの中央と上端を求め、移動中も固定する。
      this.previewX = finger.windowX - finger.x + this.keyWidth / 2;
      this.previewY = finger.windowY - finger.y - 64;
      this.flickDirection = 0;
      this.active = true;
      this.showPreview();
    } else if (this.active) {
      for (const finger of event.changedTouches) {
        if (finger.id !== this.finger) { continue; }
        const previousDirection: number = this.flickDirection;
        this.updateDirection(finger);
        if (event.type === TouchType.Up) {
          const value: string = this.values[this.flickDirection] ?? '';
          this.active = false;
          this.finger = -1;
          this.hidePreview();
          if (this.startEpoch !== editorAdapter.getEpoch()) { return; }
          if (this.modifier) { kanonIme.modifyKana(); }
          else if (value.length > 0 && (this.english || this.textInput)) {
            const letter: boolean = /^[a-z]$/.test(value);
            kanonIme.keyText(letter && this.uppercase ? value.toUpperCase() : value);
            if (letter) { this.onLetter(); }
          } else if (value.length > 0) { kanonIme.keyKana(value); }
        } else if (this.flickDirection !== previousDirection) { this.showPreview(); }
      }
    }
  }

  private label(): string {
    const value: string = this.active ? (this.values[this.flickDirection] ?? '') :
      this.displayLabel.length > 0 ? this.displayLabel : (this.values[0] ?? '');
    if (value === ' ' || value === 'space') { return 'space'; }
    return this.english && this.uppercase ? value.toUpperCase() : value;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.label())
        .fontSize(this.modifier ? 18 : this.label().length > 1 ? 17 : 20)
        .maxFontScale(1.3).maxLines(1)
        .minFontSize(10).maxFontSize(this.modifier ? 18 : this.label().length > 1 ? 17 : 20)
        .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
        .width('90%').height('70%').textAlign(TextAlign.Center)
        .fontWeight(this.active ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.active ? $r('app.color.candidate_accent') : $r('app.color.key_text'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.active ? $r('app.color.key_item_normal_pressed') : $r('app.color.key_item_normal'))
    .borderRadius(6)
    .shadow({ radius: 1, color: $r('app.color.shadow'), offsetY: 2 })
    .onTouch((event: TouchEvent) => this.touch(event))
    .onAreaChange((_oldArea: Area, area: Area) => {
      this.keyWidth = Number(area.width);
    })
    .id(this.keyId.length > 0 ? this.keyId : `flick_${this.values[0]}`)
  }
}
