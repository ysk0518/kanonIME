import display from '@ohos.display';
import { readKeyboardHeightPercent, writeKeyboardHeightPercent } from '../common/KeyboardConfig';
import { DEFAULT_KEYBOARD_HEIGHT_PERCENT, keyboardHeightPercent, keyboardHeightPreviewPercent,
  standardKeyHeight } from '../common/KeyboardLayout';
import { keyboardController } from '../model/KeyboardController';

// This fixed-size layer does not subscribe to the changing height or key layout.
@Component
struct KeyboardSizeActions {
  onCancel: () => void = () => {};
  onReset: () => void = () => {};
  onConfirm: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      Button('キャンセル').layoutWeight(1).height(40).fontSize(13).maxFontScale(1)
        .onClick(() => this.onCancel()).id('keyboard_size_close')
      Button('標準').layoutWeight(1).height(40).fontSize(13).maxFontScale(1)
        .onClick(() => this.onReset()).id('keyboard_size_reset')
      Button('決定').layoutWeight(1).height(40).fontSize(13).maxFontScale(1)
        .onClick(() => this.onConfirm()).id('keyboard_size_save')
    }.width('100%').height(56).padding(8)
      .backgroundColor($r('app.color.menu_background'))
      .renderGroup(true)
  }
}

// Preview inside the IME. Only confirmation writes to its own preferences.
@Component
export struct KeyboardSizeSettings {
  @State private heightPercent: number = DEFAULT_KEYBOARD_HEIGHT_PERCENT;
  @State private message: string = '';
  @StorageLink('kanonToolbarHeight') toolbarHeight: number = 44;
  @StorageLink('kanonHeightPreviewVp') heightPreview: number = 264;
  @StorageLink('kanonHeightAdjustmentBottomVp') adjustmentBottom: number = 0;
  @State private canvasHeight: number = 0;
  private savedPercent: number = DEFAULT_KEYBOARD_HEIGHT_PERCENT;
  private finger: number = -1;
  private startY: number = 0;
  private startPercent: number = DEFAULT_KEYBOARD_HEIGHT_PERCENT;
  private standardHeight: number = 220;
  private previewTimer: number = -1;
  private pendingPercent: number = DEFAULT_KEYBOARD_HEIGHT_PERCENT;
  onClose: () => void = () => {};

  aboutToAppear(): void {
    this.savedPercent = readKeyboardHeightPercent();
    this.heightPercent = this.savedPercent;
    keyboardController.beginKeyboardHeightAdjustment();
  }

  aboutToDisappear(): void {
    this.cancelPendingPreview();
    // Also restore when the IME is hidden or navigation leaves resize mode.
    keyboardController.endKeyboardHeightAdjustment();
  }

  private cancelPendingPreview(): void {
    if (this.previewTimer >= 0) { clearTimeout(this.previewTimer); this.previewTimer = -1; }
  }

  private applyPreview(): void {
    const percent: number = this.pendingPercent;
    if (percent === this.heightPercent) { return; }
    this.heightPercent = percent;
    this.message = '';
    keyboardController.previewKeyboardHeight(percent);
  }

  private preview(value: number, immediate: boolean = false): void {
    this.pendingPercent = keyboardHeightPreviewPercent(value);
    if (immediate) {
      this.cancelPendingPreview();
      this.applyPreview();
    } else if (this.previewTimer < 0) {
      // Coalesce move events, using the most recent position at roughly 60 updates/s.
      this.previewTimer = setTimeout(() => {
        this.previewTimer = -1;
        this.applyPreview();
      }, 16);
    }
  }

  private cancel(): void {
    this.cancelPendingPreview();
    this.onClose();
  }

  private touch(event: TouchEvent): void {
    if (event.type === TouchType.Cancel) {
      this.cancelPendingPreview(); this.finger = -1; return;
    }
    if (event.type === TouchType.Down && this.finger < 0 && event.changedTouches.length > 0) {
      const touch: TouchObject = event.changedTouches[0];
      try {
        const screen: display.Display = display.getDefaultDisplaySync();
        const density: number = screen.densityPixels > 0 ? screen.densityPixels : 1;
        this.standardHeight = standardKeyHeight(screen.width / density, screen.height / density);
      } catch (error) {
        this.message = '画面サイズを取得できませんでした。もう一度お試しください。';
        return;
      }
      this.finger = touch.id;
      // Display coordinates remain stable while the panel's top edge moves.
      this.startY = touch.displayY;
      this.startPercent = this.heightPercent;
    } else if (this.finger >= 0) {
      for (const touch of event.changedTouches) {
        if (touch.id !== this.finger) { continue; }
        this.preview(this.startPercent + (this.startY - touch.displayY) * 100 / this.standardHeight,
          event.type === TouchType.Up);
        if (event.type === TouchType.Up) { this.finger = -1; }
      }
    }
  }

  private confirm(): void {
    this.cancelPendingPreview();
    try {
      const percent: number = keyboardHeightPercent(this.heightPercent);
      if (percent !== this.savedPercent) { writeKeyboardHeightPercent(percent); }
      this.onClose();
    } catch (error) {
      this.message = '保存できませんでした。もう一度お試しください。';
    }
  }

  build() {
    Stack() {
      // Dim the key preview only; the unused expansion area stays transparent.
      Column() {}.width('100%').height(this.heightPreview)
        .backgroundColor('#55000000')
        .position({ x: 0, y: Math.max(0, this.canvasHeight - this.adjustmentBottom - this.heightPreview) })
      Row({ space: 12 }) {
        Text('↕').fontSize(24).fontColor($r('app.color.text_normal'))
        Text(`上下にドラッグ · ${Math.round(this.heightPercent)}％`).fontSize(14).maxFontScale(1)
          .fontColor($r('app.color.text_normal')).id('keyboard_size_value')
      }.width('100%').height(this.toolbarHeight).justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.menu_background'))
        .accessibilityText('上下にドラッグしてキーボードの高さを調整')
        .onTouch((event: TouchEvent) => this.touch(event)).id('keyboard_size_height')
        .position({ x: 0, y: Math.max(0, this.canvasHeight - this.adjustmentBottom - this.heightPreview) })
      if (this.message.length > 0) {
        Text(this.message).fontSize(12).fontColor($r('app.color.text_normal'))
          .backgroundColor($r('app.color.menu_background'))
          .markAnchor({ x: '50%', y: '100%' })
          .position({ x: '50%', y: Math.max(0, this.canvasHeight - this.adjustmentBottom - 56) })
      }
      KeyboardSizeActions({
        onCancel: () => this.cancel(),
        onReset: () => this.preview(DEFAULT_KEYBOARD_HEIGHT_PERCENT, true),
        onConfirm: () => this.confirm()
      }).width('100%').height(56)
        .position({ x: 0, y: Math.max(0, this.canvasHeight - this.adjustmentBottom - 56) })
    }.width('100%').height('100%')
      .backgroundColor(Color.Transparent)
      // Consume touches across the preview so displayed keys cannot type.
      .onTouch(() => {}).hitTestBehavior(HitTestMode.Default)
      .onAreaChange((_old: Area, area: Area) => { this.canvasHeight = Number(area.height); })
  }
}
