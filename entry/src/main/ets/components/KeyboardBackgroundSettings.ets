import common from '@ohos.app.ability.common';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import { BackgroundConfig, keyboardBackground, copyBackgroundPhoto, BackgroundPhotoError } from '../common/KeyboardBackground';
import { backgroundDraftChanged, backgroundImageUri, backgroundPosterUri, hasBackgroundPhoto,
  DEFAULT_GIF_ANIMATE } from '../common/BackgroundAppearance';
import { readSharedLayoutOrder, DEFAULT_LAYOUT_ORDER } from '../common/KeyboardConfig';
import { KeyboardBackgroundCanvas } from './KeyboardBackgroundCanvas';
import { BackgroundAdjustment } from './BackgroundAdjustment';
import { BackgroundGestureHint } from './BackgroundGestureHint';
import { BackgroundKeyPreview } from './BackgroundKeyPreview';
import { KeyboardPreviewLayoutSwitch } from './KeyboardPreviewLayoutSwitch';
import { processBackgroundGif, restoreBackgroundGif, inspectBackgroundGif, GifBackgroundStats } from '../common/GifBackgroundProcessor';
import { GifBackgroundComparison } from './GifBackgroundComparison';
import { SettingsHeader } from './SettingsHeader';
import { debugLog, debugErrorCode } from '../common/DebugLog';

@Component
export struct KeyboardBackgroundSettings {
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  @StorageLink('kanonBackgroundVersion') @Watch('backgroundChanged') backgroundVersion: number = 0;
  @StorageLink('kanonBackgroundSavedRevision') savedRevision: number = 0;
  @StorageLink('kanonBackgroundPeerVersion') @Watch('syncConfirmed') peerVersion: number = 0;
  @StorageLink('kanonSettingsForeground') @Watch('foregroundChanged') foreground: boolean = true;
  @State private synced: boolean = true;
  @State private draft: BackgroundConfig = new BackgroundConfig();
  @State private busy: boolean = false;
  @State private message: ResourceStr = '';
  @State private loaded: boolean = false;
  @State private showGestureHint: boolean = true;
  @State private previewQwerty: boolean = false;
  @State private gifResolution: number = 1280;
  @State private gifFps: number = 100;
  @State private originalGifStats: GifBackgroundStats = new GifBackgroundStats();
  @State private currentGifStats: GifBackgroundStats = new GifBackgroundStats();
  @State private gifStatsPending: boolean = false;
  @State private gifStatsError: ResourceStr = '';
  private saved: BackgroundConfig = new BackgroundConfig();
  private alive: boolean = false;
  private confirmingExit: boolean = false;
  private travelX: number = 0;
  private travelY: number = 0;
  private dragX: number = 0;
  private dragY: number = 0;
  private dragTravelX: number = 0;
  private dragTravelY: number = 0;
  private dragging: boolean = false;
  private pinchZoom: number = 100;
  onClose: () => void = () => {};
  onBackHandlerChange: (handler: (() => void) | undefined) => void = () => {};

  async aboutToAppear(): Promise<void> {
    this.alive = true;
    this.onBackHandlerChange(() => this.requestClose());
    const layout: string = AppStorage.get<string>('kanonLayout') ??
      (readSharedLayoutOrder() ?? DEFAULT_LAYOUT_ORDER).split(',')[0];
    this.previewQwerty = layout.endsWith('_qwerty');
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      await keyboardBackground.initialize(context);
      if (!this.alive) { return; }
      this.draft = keyboardBackground.get();
      this.saved = this.draft;
      this.synced = this.savedRevision !== this.saved.version || this.peerVersion >= this.saved.version;
      if (!this.synced) { this.message = $r('app.string.background_sync_pending'); }
      this.readGifSettings();
      this.loaded = true;
      keyboardBackground.preview(this.draft);
      this.refreshGifStats();
    } catch (error) {
      debugLog.record('settings', `load failed code=${debugErrorCode(error)}`);
      this.message = $r('app.string.background_load_failed');
    }
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.onBackHandlerChange(undefined);
    keyboardBackground.endPreview();
    keyboardBackground.pruneGifOriginals();
  }

  private foregroundChanged(): void {
    if (!this.alive || !this.loaded) { return; }
    if (this.foreground) { keyboardBackground.preview(this.draft); }
    else { keyboardBackground.endPreview(); }
  }

  private backgroundChanged(): void {
    if (!this.alive || !this.loaded || this.busy || !this.synced || this.changed()) { return; }
    this.draft = keyboardBackground.get();
    this.saved = this.draft;
    this.readGifSettings();
    keyboardBackground.preview(this.draft);
    this.refreshGifStats();
  }

  private syncConfirmed(): void {
    if (!this.synced && this.loaded && this.peerVersion >= this.saved.version) {
      this.synced = true;
      if (!this.changed()) { this.message = $r('app.string.background_saved'); }
    }
  }

  private async choosePhoto(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.message = '';
    debugLog.record('image', 'picker opened');
    try {
      const result: photoAccessHelper.PhotoSelectResult = await new photoAccessHelper.PhotoViewPicker().select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 1
      });
      if (result.photoUris.length === 0 || !this.alive) {
        debugLog.record('image', `picker cancelled active=${this.alive}`);
        return;
      }
      debugLog.record('image', 'picker selected');
      const draft: BackgroundConfig = await copyBackgroundPhoto(result.photoUris[0]);
      if (!this.alive) { return; }
      if (draft.format === 'gif') {
        await keyboardBackground.keepGifOriginal(draft);
        const stats: GifBackgroundStats = inspectBackgroundGif(draft.photo);
        draft.gifResolution = Math.max(stats.width, stats.height);
        draft.gifFps = Math.min(100, Math.max(1, Math.ceil(stats.maxFps)));
        draft.gifWidth = stats.width;
        draft.gifHeight = stats.height;
        draft.gifFrames = stats.frames;
        if (!this.alive) { keyboardBackground.pruneGifOriginals(); return; }
      }
      this.draft = draft;
      this.readGifSettings();
      this.showGestureHint = true;
      keyboardBackground.preview(this.draft);
      this.refreshGifStats();
    } catch (error) {
      debugLog.record('image', `selection failed code=${debugErrorCode(error)}`);
      if (this.alive) {
        this.message = error instanceof BackgroundPhotoError ? error.displayMessage :
          $r('app.string.background_image_read_failed');
      }
    } finally { if (this.alive) { this.busy = false; } }
  }

  private changed(): boolean { return this.loaded && backgroundDraftChanged(this.draft, this.saved); }

  private requestClose(): void {
    if (this.busy || this.confirmingExit) { return; }
    if (!this.changed()) { this.onClose(); return; }
    const options: AlertDialogParamWithOptions = {
      title: $r('app.string.background_unsaved_title'),
      message: $r('app.string.background_unsaved_message'),
      autoCancel: true,
      onDidDisappear: () => { this.confirmingExit = false; },
      buttonDirection: DialogButtonDirection.VERTICAL,
      buttons: [
        { value: $r('app.string.common_save'), action: () => { this.save(true); } },
        { value: $r('app.string.background_discard'), action: () => this.onClose() },
        { value: $r('app.string.settings_reset_cancel'), action: () => {} }
      ]
    };
    this.confirmingExit = true;
    this.getUIContext().showAlertDialog(options);
  }

  private copyDraft(): BackgroundConfig {
    const draft = new BackgroundConfig();
    draft.version = this.draft.version;
    draft.photo = this.draft.photo;
    draft.format = this.draft.format;
    draft.poster = this.draft.poster;
    draft.animate = this.draft.animate;
    draft.sourceId = this.draft.sourceId;
    draft.gifResolution = this.draft.gifResolution;
    draft.gifFps = this.draft.gifFps;
    draft.gifWidth = this.draft.gifWidth;
    draft.gifHeight = this.draft.gifHeight;
    draft.gifFrames = this.draft.gifFrames;
    draft.zoom = this.draft.zoom;
    draft.x = this.draft.x;
    draft.y = this.draft.y;
    draft.brightness = this.draft.brightness;
    draft.keyOpacity = this.draft.keyOpacity;
    return draft;
  }

  private readGifSettings(): void {
    this.gifResolution = this.draft.gifResolution || 1280;
    this.gifFps = this.draft.gifFps || 100;
  }

  private originalGifResolution(): number { return Math.max(this.originalGifStats.width, this.originalGifStats.height); }
  private originalGifFps(): number { return Math.min(100, Math.max(1, Math.ceil(this.originalGifStats.maxFps))); }

  private gifDefaultsChanged(): boolean {
    if (this.gifStatsPending || this.originalGifStats.frames === 0) { return false; }
    return this.gifResolution !== this.originalGifResolution() || this.gifFps !== this.originalGifFps() ||
      this.draft.gifResolution !== this.originalGifResolution() || this.draft.gifFps !== this.originalGifFps() ||
      this.currentGifStats.width !== this.originalGifStats.width || this.currentGifStats.height !== this.originalGifStats.height ||
      this.currentGifStats.frames !== this.originalGifStats.frames || this.currentGifStats.bytes !== this.originalGifStats.bytes ||
      this.draft.animate !== DEFAULT_GIF_ANIMATE;
  }

  private async refreshGifStats(): Promise<void> {
    const snapshot: BackgroundConfig = this.draft;
    this.gifStatsError = '';
    if (snapshot.format !== 'gif' || snapshot.photo.length === 0) {
      this.originalGifStats = new GifBackgroundStats();
      this.currentGifStats = new GifBackgroundStats();
      this.gifStatsPending = false;
      return;
    }
    this.gifStatsPending = true;
    try {
      const original: string = await keyboardBackground.gifOriginal(snapshot);
      if (!this.alive || this.draft.photo !== snapshot.photo || this.draft.sourceId !== snapshot.sourceId) { return; }
      this.originalGifStats = inspectBackgroundGif(original);
      this.currentGifStats = inspectBackgroundGif(snapshot.photo);
      if (snapshot.gifResolution === 0) { this.gifResolution = Math.max(this.currentGifStats.width, this.currentGifStats.height); }
      if (snapshot.gifFps === 0) { this.gifFps = Math.min(100, Math.max(1, Math.ceil(this.currentGifStats.maxFps))); }
    } catch (error) {
      if (this.alive && this.draft.photo === snapshot.photo) { this.gifStatsError = $r('app.string.background_gif_stats_failed'); }
    } finally {
      if (this.alive && this.draft.photo === snapshot.photo) { this.gifStatsPending = false; }
    }
  }

  private useProcessedGif(draft: BackgroundConfig, processed: BackgroundConfig): void {
    draft.photo = processed.photo;
    draft.poster = processed.poster;
    draft.gifResolution = processed.gifResolution;
    draft.gifFps = processed.gifFps;
    draft.gifWidth = processed.gifWidth;
    draft.gifHeight = processed.gifHeight;
    draft.gifFrames = processed.gifFrames;
  }

  private async applyGifSettings(resetDefaults: boolean = false): Promise<void> {
    if (this.busy || this.draft.format !== 'gif') { return; }
    this.busy = true;
    this.message = '';
    debugLog.record('gif', `process start reset=${resetDefaults} resolution=${this.gifResolution} fps=${this.gifFps}`);
    try {
      const draft: BackgroundConfig = this.copyDraft();
      if (resetDefaults) { draft.animate = DEFAULT_GIF_ANIMATE; }
      await keyboardBackground.keepGifOriginal(draft);
      const original: string = await keyboardBackground.gifOriginal(draft);
      const processed: BackgroundConfig = resetDefaults ? await restoreBackgroundGif(original) :
        await processBackgroundGif(original, this.gifResolution, this.gifFps);
      if (!this.alive) { keyboardBackground.pruneGifOriginals(); return; }
      this.useProcessedGif(draft, processed);
      debugLog.record('gif', `process done width=${processed.gifWidth} height=${processed.gifHeight} frames=${processed.gifFrames}`);
      this.draft = draft;
      this.readGifSettings();
      keyboardBackground.preview(draft);
      this.refreshGifStats();
      this.message = resetDefaults ? $r('app.string.background_gif_reset_done') :
        $r('app.string.background_gif_applied');
    } catch (error) {
      debugLog.record('gif', `process failed code=${debugErrorCode(error)}`);
      if (this.alive) {
        this.message = error instanceof BackgroundPhotoError ? error.displayMessage : $r('app.string.background_gif_failed');
      }
    } finally { if (this.alive) { this.busy = false; } }
  }

  private movePhoto(event: GestureEvent): void {
    if (!this.dragging || event.fingerList.length > 1 || this.busy || this.draft.photo.length === 0) { return; }
    const draft: BackgroundConfig = this.copyDraft();
    draft.x = this.dragTravelX > 0.5 ? Math.max(-100, Math.min(100,
      this.dragX + event.offsetX / this.dragTravelX * 100)) : 0;
    draft.y = this.dragTravelY > 0.5 ? Math.max(-100, Math.min(100,
      this.dragY + event.offsetY / this.dragTravelY * 100)) : 0;
    this.draft = draft;
    this.message = '';
    keyboardBackground.preview(draft);
  }

  private scalePhoto(event: GestureEvent): void {
    if (this.busy || this.draft.photo.length === 0 || !Number.isFinite(event.scale) || event.scale <= 0) { return; }
    this.setAdjustment('zoom', Math.max(100, Math.min(250, this.pinchZoom * event.scale)));
  }

  /** Replace the draft so every preview observes the same new state. */
  private setAdjustment(field: string, value: number): void {
    if (this.busy) { return; }
    const draft: BackgroundConfig = this.copyDraft();
    switch (field) {
      case 'zoom': draft.zoom = value; break;
      case 'x': draft.x = value; break;
      case 'y': draft.y = value; break;
      case 'brightness': draft.brightness = value; break;
      case 'keyOpacity': draft.keyOpacity = value; break;
      default: return;
    }
    this.draft = draft;
    this.message = '';
    keyboardBackground.preview(this.draft);
  }

  private async save(closeAfter: boolean = false): Promise<void> {
    if (this.busy || !this.changed()) { return; }
    this.busy = true;
    debugLog.record('settings', 'save pressed');
    try {
      const synced: boolean = await keyboardBackground.save(this.draft);
      if (!this.alive) { return; }
      this.draft = keyboardBackground.get();
      this.saved = this.draft;
      this.synced = synced || this.peerVersion >= this.saved.version;
      debugLog.record('settings', `save finished imeConfirmed=${synced}`);
      this.message = this.synced ? $r('app.string.background_saved') :
        $r('app.string.background_sync_pending');
      if (closeAfter) { this.onClose(); }
    } catch (error) {
      debugLog.record('settings', `save failed code=${debugErrorCode(error)}`);
      if (this.alive) { this.message = $r('app.string.background_sync_failed'); }
    }
    finally { if (this.alive) { this.busy = false; } }
  }

  private async retrySync(): Promise<void> {
    if (this.busy || this.synced) { return; }
    this.busy = true;
    this.message = $r('app.string.background_sync_pending');
    try { await keyboardBackground.retrySync(); }
    catch (error) {
      if (this.alive && !this.synced) { this.message = $r('app.string.settings_sync_retry_failed'); }
    } finally { if (this.alive) { this.busy = false; } }
  }

  @Builder
  previewCard() {
    Column({ space: 12 }) {
      KeyboardPreviewLayoutSwitch({ qwerty: this.previewQwerty, disabled: this.busy,
        idPrefix: 'background_preview', onChange: (qwerty: boolean) => { this.previewQwerty = qwerty; } })
      Stack() {
        KeyboardBackgroundCanvas({
          source: backgroundImageUri(this.draft), poster: backgroundPosterUri(this.draft),
          play: this.draft.animate, active: this.foreground && !this.busy,
          zoom: this.draft.zoom, x: this.draft.x, y: this.draft.y, photoBrightness: this.draft.brightness,
          onGeometry: (width: number, height: number) => {
            this.travelX = width;
            this.travelY = height;
          }
        }).width('100%').height(160)
        BackgroundKeyPreview({ qwerty: this.previewQwerty,
          hasBackgroundPhoto: hasBackgroundPhoto(this.draft.photo, this.draft.poster),
          keyOpacity: hasBackgroundPhoto(this.draft.photo, this.draft.poster) ? this.draft.keyOpacity : 100 })
          .width('100%').height(160)
        BackgroundGestureHint({ source: this.draft.photo,
          available: this.showGestureHint && this.loaded && !this.busy && this.foreground })
          .width('100%').height(160)
      }.width('100%').height(160).clip(true).borderRadius(12)
        .backgroundColor($r('app.color.keyboard_background')).id('background_preview')
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) { this.showGestureHint = false; }
        })
        .priorityGesture(GestureGroup(GestureMode.Parallel,
          PinchGesture({ fingers: 2, distance: 3 })
            .onActionStart((event: GestureEvent) => {
              this.dragging = false;
              this.pinchZoom = this.draft.zoom;
              this.scalePhoto(event);
            })
            .onActionUpdate((event: GestureEvent) => this.scalePhoto(event))
            .onActionEnd((event: GestureEvent) => this.scalePhoto(event)),
          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 3 })
          .onActionStart((event: GestureEvent) => {
            this.dragging = event.fingerList.length === 1;
            this.dragX = this.draft.x;
            this.dragY = this.draft.y;
            this.dragTravelX = this.travelX;
            this.dragTravelY = this.travelY;
            this.movePhoto(event);
          })
          .onActionUpdate((event: GestureEvent) => this.movePhoto(event))
          .onActionEnd((event: GestureEvent) => {
            this.movePhoto(event);
            this.dragging = false;
          })
          .onActionCancel(() => { this.dragging = false; })))
      Text($r('app.string.background_gesture_help'))
        .width('100%').fontSize(12).fontColor($r('app.color.text_secondary'))
    }.width('100%').padding(18).borderRadius(22).backgroundColor($r('app.color.settings_card'))
  }

  @Builder
  adjustmentCard() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button(this.busy ? $r('app.string.background_processing') : $r('app.string.background_pick')).layoutWeight(1)
          .enabled(this.loaded && !this.busy).onClick(() => this.choosePhoto()).id('background_pick')
        Button($r('app.string.common_reset')).layoutWeight(1)
          .fontColor($r('app.color.text_normal')).backgroundColor($r('app.color.key_item_normal'))
          .enabled(this.loaded && !this.busy && this.draft.photo.length > 0)
          .onClick(() => {
            this.draft = new BackgroundConfig();
            keyboardBackground.preview(this.draft);
            this.message = '';
          }).id('background_reset')
      }.width('100%')
      BackgroundAdjustment({ label: $r('app.string.background_zoom'), value: this.draft.zoom, minimum: 100, maximum: 250,
        available: !this.busy && this.draft.photo.length > 0, sliderId: 'background_zoom',
        onChange: (value: number) => this.setAdjustment('zoom', value) })
      BackgroundAdjustment({ label: $r('app.string.background_x'), value: this.draft.x, minimum: -100, maximum: 100, suffix: '',
        available: !this.busy && this.draft.photo.length > 0, sliderId: 'background_x',
        onChange: (value: number) => this.setAdjustment('x', value) })
      BackgroundAdjustment({ label: $r('app.string.background_y'), value: this.draft.y, minimum: -100, maximum: 100, suffix: '',
        available: !this.busy && this.draft.photo.length > 0, sliderId: 'background_y',
        onChange: (value: number) => this.setAdjustment('y', value) })
      BackgroundAdjustment({ label: $r('app.string.background_brightness'), value: this.draft.brightness, minimum: 20, maximum: 100,
        available: !this.busy && this.draft.photo.length > 0, sliderId: 'background_brightness',
        onChange: (value: number) => this.setAdjustment('brightness', value) })
      BackgroundAdjustment({ label: $r('app.string.background_key_opacity'), value: this.draft.keyOpacity, minimum: 0, maximum: 100,
        available: !this.busy && this.draft.photo.length > 0, sliderId: 'background_key_opacity',
        onChange: (value: number) => this.setAdjustment('keyOpacity', value) })
    }.width('100%').padding(18).borderRadius(22).backgroundColor($r('app.color.settings_card'))
  }

  @Builder
  gifCard() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text($r('app.string.background_animate')).fontSize(18).fontColor($r('app.color.text_normal')).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.draft.animate })
          .selectedColor($r('app.color.settings_accent')).enabled(!this.busy)
          .accessibilityText($r('app.string.background_animate_accessibility')).id('background_animate')
          .onChange((value: boolean) => {
            const draft: BackgroundConfig = this.copyDraft();
            draft.animate = value;
            this.draft = draft;
            this.message = '';
            keyboardBackground.preview(draft);
          })
      }.width('100%').constraintSize({ minHeight: 56 })
      Text($r('app.string.background_gif_limits'))
        .fontSize(12).fontColor($r('app.color.text_secondary'))
      GifBackgroundComparison({ original: this.originalGifStats, current: this.currentGifStats,
        pending: this.gifStatsPending, error: this.gifStatsError })
      BackgroundAdjustment({ label: $r('app.string.background_gif_resolution'), value: this.gifResolution,
        minimum: 1, maximum: 1280, suffix: 'px', available: !this.busy && !this.gifStatsPending, sliderId: 'background_gif_resolution',
        onChange: (value: number) => { this.gifResolution = Math.round(value); } })
      BackgroundAdjustment({ label: $r('app.string.background_gif_fps'), value: this.gifFps,
        minimum: 1, maximum: 100, suffix: 'fps', available: !this.busy && !this.gifStatsPending, sliderId: 'background_gif_fps',
        onChange: (value: number) => { this.gifFps = Math.round(value); } })
      Row({ space: 8 }) {
        Button(this.busy ? $r('app.string.background_gif_processing') : $r('app.string.background_gif_apply'))
          .layoutWeight(1).fontSize(14)
          .enabled(!this.busy && (this.gifResolution !== this.draft.gifResolution || this.gifFps !== this.draft.gifFps))
          .onClick(() => this.applyGifSettings()).id('background_gif_apply')
        Button($r('app.string.background_gif_reset')).layoutWeight(1).fontSize(14)
          .fontColor($r('app.color.text_normal')).backgroundColor($r('app.color.key_item_normal'))
          .enabled(!this.busy && this.gifDefaultsChanged())
          .onClick(() => this.applyGifSettings(true)).id('background_gif_defaults')
      }.width('100%')
      if (this.originalGifStats.frames > 0 && !this.gifStatsPending) {
        Text($r('app.string.background_gif_original_defaults', this.originalGifResolution(), this.originalGifFps()))
          .width('100%').fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      Text($r('app.string.background_gif_apply_help'))
        .fontSize(12).fontColor($r('app.color.text_secondary'))
    }.width('100%').padding(18).borderRadius(22).backgroundColor($r('app.color.settings_card'))
  }

  @Builder
  keyboardCheckCard() {
    Column({ space: 8 }) {
      TextInput({ placeholder: $r('app.string.background_check_placeholder') })
        .id('background_keyboard_check')
      Text($r('app.string.background_live_help'))
        .width('100%').fontSize(12).fontColor($r('app.color.text_secondary'))
    }.width('100%').padding(18).borderRadius(22).backgroundColor($r('app.color.settings_card'))
  }

  @Builder
  footer() {
    Column({ space: 8 }) {
      if (this.message !== '') {
        Text(this.message).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      } else if (!this.synced && !this.changed()) {
        Text($r('app.string.background_sync_pending')).fontSize(13)
          .fontColor($r('app.color.text_secondary')).width('100%')
      }
      if (!this.synced && !this.changed()) {
        Button($r('app.string.settings_sync_retry')).fontSize(12).height(32).enabled(!this.busy)
          .onClick(() => this.retrySync()).id('background_sync_retry')
      }
      Button($r('app.string.common_save')).width('100%').height(40).fontSize(13).maxFontScale(1)
        .enabled(!this.busy && this.changed()).onClick(() => this.save()).id('background_save')
    }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 12 })
  }

  build() {
    Column() {
      SettingsHeader({ title: $r('app.string.settings_menu_theme'), disabled: this.busy,
        onBack: () => this.requestClose() })
      Scroll() {
        Column({ space: 16 }) {
          this.previewCard()
          this.adjustmentCard()
          if (this.draft.format === 'gif' && this.draft.photo.length > 0) {
            this.gifCard()
          }
          this.keyboardCheckCard()
        }.width('100%').padding({ left: 16, right: 16, top: 6, bottom: 12 })
      }.layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Auto).id('background_settings_scroll')
      this.footer()
    }.width('100%').height('100%').backgroundColor($r('app.color.settings_background_surface'))
  }
}
