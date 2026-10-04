import common from '@ohos.app.ability.common';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import { BackgroundConfig, keyboardBackground, copyBackgroundPhoto, BackgroundPhotoError } from '../common/KeyboardBackground';
import { backgroundImageUri, backgroundPosterUri,
  DEFAULT_GIF_ANIMATE } from '../common/BackgroundAppearance';
import { readSharedLayoutOrder, DEFAULT_LAYOUT_ORDER } from '../common/KeyboardConfig';
import { KeyboardBackgroundCanvas } from './KeyboardBackgroundCanvas';
import { BackgroundAdjustment } from './BackgroundAdjustment';
import { BackgroundGestureHint } from './BackgroundGestureHint';
import { BackgroundKeyPreview } from './BackgroundKeyPreview';
import { processBackgroundGif, restoreBackgroundGif, inspectBackgroundGif, GifBackgroundStats } from '../common/GifBackgroundProcessor';
import { GifBackgroundComparison } from './GifBackgroundComparison';

@Component
export struct KeyboardBackgroundSettings {
  @StorageLink('kanonBackgroundThemeVersion') backgroundThemeVersion: number = 0;
  @StorageLink('kanonBackgroundVersion') @Watch('backgroundChanged') backgroundVersion: number = 0;
  @StorageLink('kanonBackgroundPeerVersion') @Watch('syncConfirmed') peerVersion: number = 0;
  @StorageLink('kanonSettingsForeground') @Watch('foregroundChanged') foreground: boolean = true;
  @State private synced: boolean = true;
  @State private draft: BackgroundConfig = new BackgroundConfig();
  @State private busy: boolean = false;
  @State private message: string = '';
  @State private loaded: boolean = false;
  @State private showGestureHint: boolean = true;
  @State private previewQwerty: boolean = false;
  @State private gifResolution: number = 1280;
  @State private gifFps: number = 100;
  @State private originalGifStats: GifBackgroundStats = new GifBackgroundStats();
  @State private currentGifStats: GifBackgroundStats = new GifBackgroundStats();
  @State private gifStatsPending: boolean = false;
  @State private gifStatsError: string = '';
  private saved: BackgroundConfig = new BackgroundConfig();
  private alive: boolean = false;
  private travelX: number = 0;
  private travelY: number = 0;
  private dragX: number = 0;
  private dragY: number = 0;
  private dragTravelX: number = 0;
  private dragTravelY: number = 0;
  private dragging: boolean = false;
  private pinchZoom: number = 100;
  onClose: () => void = () => {};

  async aboutToAppear(): Promise<void> {
    this.alive = true;
    const layout: string = AppStorage.get<string>('kanonLayout') ??
      (readSharedLayoutOrder() ?? DEFAULT_LAYOUT_ORDER).split(',')[0];
    this.previewQwerty = layout.endsWith('_qwerty');
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      await keyboardBackground.initialize(context);
      if (!this.alive) { return; }
      this.draft = keyboardBackground.get();
      this.saved = this.draft;
      this.readGifSettings();
      this.loaded = true;
      keyboardBackground.preview(this.draft);
      this.refreshGifStats();
    } catch (error) { this.message = '背景設定を読み込めませんでした'; }
  }

  aboutToDisappear(): void {
    this.alive = false;
    keyboardBackground.endPreview();
    keyboardBackground.pruneGifOriginals();
  }

  private foregroundChanged(): void {
    if (!this.alive || !this.loaded) { return; }
    if (this.foreground) { keyboardBackground.preview(this.draft); }
    else { keyboardBackground.endPreview(); }
  }

  private backgroundChanged(): void {
    if (!this.alive || !this.loaded || this.busy || this.changed()) { return; }
    this.draft = keyboardBackground.get();
    this.saved = this.draft;
    this.readGifSettings();
    keyboardBackground.preview(this.draft);
    this.refreshGifStats();
  }

  private syncConfirmed(): void {
    if (!this.synced && this.loaded && this.peerVersion >= this.draft.version && this.matchesSaved()) {
      this.synced = true;
      this.message = '保存しました。キーボードに反映済みです';
    }
  }

  private async choosePhoto(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.message = '';
    try {
      const result: photoAccessHelper.PhotoSelectResult = await new photoAccessHelper.PhotoViewPicker().select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 1
      });
      if (result.photoUris.length === 0 || !this.alive) { return; }
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
      if (this.alive) {
        this.message = error instanceof BackgroundPhotoError ? error.message :
          '画像を読み込めませんでした。別の画像を選んでください';
      }
    } finally { if (this.alive) { this.busy = false; } }
  }

  private matchesSaved(): boolean {
    return this.draft.version === this.saved.version && this.draft.photo === this.saved.photo &&
      this.draft.format === this.saved.format && this.draft.poster === this.saved.poster &&
      this.draft.animate === this.saved.animate &&
      this.draft.sourceId === this.saved.sourceId && this.draft.gifResolution === this.saved.gifResolution &&
      this.draft.gifFps === this.saved.gifFps &&
      this.draft.zoom === this.saved.zoom && this.draft.x === this.saved.x && this.draft.y === this.saved.y &&
      this.draft.brightness === this.saved.brightness && this.draft.keyOpacity === this.saved.keyOpacity;
  }

  private changed(): boolean { return this.loaded && (!this.synced || !this.matchesSaved()); }

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
      if (this.alive && this.draft.photo === snapshot.photo) { this.gifStatsError = 'GIFの情報を取得できませんでした'; }
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
    try {
      const draft: BackgroundConfig = this.copyDraft();
      if (resetDefaults) { draft.animate = DEFAULT_GIF_ANIMATE; }
      await keyboardBackground.keepGifOriginal(draft);
      const original: string = await keyboardBackground.gifOriginal(draft);
      const processed: BackgroundConfig = resetDefaults ? await restoreBackgroundGif(original) :
        await processBackgroundGif(original, this.gifResolution, this.gifFps);
      if (!this.alive) { keyboardBackground.pruneGifOriginals(); return; }
      this.useProcessedGif(draft, processed);
      this.draft = draft;
      this.readGifSettings();
      keyboardBackground.preview(draft);
      this.refreshGifStats();
      this.message = resetDefaults ? 'GIF設定を標準に戻しました。「保存」で確定します' :
        'GIFを調整しました。「保存」で確定します';
    } catch (error) {
      if (this.alive) {
        this.message = error instanceof BackgroundPhotoError ? error.message : 'GIFを調整できませんでした';
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
    keyboardBackground.preview(draft);
  }

  private scalePhoto(event: GestureEvent): void {
    if (this.busy || this.draft.photo.length === 0 || !Number.isFinite(event.scale) || event.scale <= 0) { return; }
    this.setAdjustment('zoom', Math.max(100, Math.min(250, this.pinchZoom * event.scale)));
  }

  /** Replace the draft so every preview observes the same new state. */
  private setAdjustment(field: string, value: number): void {
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
    keyboardBackground.preview(this.draft);
  }

  private async save(): Promise<void> {
    if (this.busy || !this.changed()) { return; }
    this.busy = true;
    try {
      const synced: boolean = await keyboardBackground.save(this.draft);
      if (!this.alive) { return; }
      this.draft = keyboardBackground.get();
      this.saved = this.draft;
      this.synced = synced;
      this.message = synced ? '保存しました。キーボードに反映済みです' :
        '画像は保存済みです。確認用の入力欄でkanonを開いて、反映を確認してください';
    } catch (error) { if (this.alive) { this.message = '反映できませんでした。もう一度保存してください'; } }
    finally { if (this.alive) { this.busy = false; } }
  }

  build() {
    Column() {
      Row() {
        Button('‹').width(44).height(44).fontSize(28)
          .backgroundColor(Color.Transparent).fontColor($r('app.color.text_normal'))
          .enabled(!this.busy).accessibilityText('戻る').onClick(() => this.onClose())
        Text('キーボードの背景').fontSize(20).fontColor($r('app.color.text_normal')).layoutWeight(1)
        Button('保存').enabled(!this.busy && this.changed()).onClick(() => this.save()).id('background_save')
      }.width('100%').height(56)
      Scroll() {
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            ForEach([false, true], (qwerty: boolean) => {
              Button(`${this.previewQwerty === qwerty ? '✓ ' : ''}${qwerty ? 'QWERTY' : '12キー'}`)
                .layoutWeight(1).height(36).enabled(!this.busy)
                .fontColor(this.previewQwerty === qwerty ? $r('app.color.candidate_accent') : $r('app.color.text_normal'))
                .backgroundColor(this.previewQwerty === qwerty ? $r('app.color.candidate_selected') : $r('app.color.key_item_normal'))
                .accessibilityText(`${qwerty ? 'QWERTY' : '12キー'}のプレビュー${this.previewQwerty === qwerty ? '、選択中' : ''}`)
                .onClick(() => { this.previewQwerty = qwerty; })
                .id(qwerty ? 'background_preview_qwerty' : 'background_preview_flick')
            })
          }.width('100%')
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
              keyOpacity: this.draft.photo.length > 0 ? this.draft.keyOpacity : 100 })
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
          Text('ドラッグで位置、2本指のピンチで拡大・縮小を調整できます。')
            .width('100%').fontSize(12).fontColor($r('app.color.text_secondary'))
          TextInput({ placeholder: 'ここをタップしてキーボードで確認' })
            .id('background_keyboard_check')
          Text('確認用キーボードにも調整中の値が反映されます。「保存」で確定します。')
            .width('100%').fontSize(12).fontColor($r('app.color.text_secondary'))
          Row({ space: 8 }) {
            Button(this.busy ? '処理中…' : '画像を選ぶ').layoutWeight(1)
              .enabled(this.loaded && !this.busy).onClick(() => this.choosePhoto()).id('background_pick')
            Button('標準に戻す').layoutWeight(1).enabled(this.loaded && !this.busy && this.draft.photo.length > 0)
              .onClick(() => {
                this.draft = new BackgroundConfig();
                keyboardBackground.preview(this.draft);
                this.message = '';
              }).id('background_reset')
          }
          if (this.draft.format === 'gif' && this.draft.photo.length > 0) {
            Row({ space: 8 }) {
              Text('アニメーションを再生').fontSize(14).fontColor($r('app.color.text_normal')).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.draft.animate }).enabled(!this.busy)
                .accessibilityText('背景GIFのアニメーションを再生').id('background_animate')
                .onChange((value: boolean) => {
                  const draft: BackgroundConfig = this.copyDraft();
                  draft.animate = value;
                  this.draft = draft;
                  keyboardBackground.preview(draft);
                })
            }.width('100%')
            Text('GIFは5MB以下・長辺1280px以下・120フレーム以下に対応しています。')
              .fontSize(12).fontColor($r('app.color.text_secondary'))
            GifBackgroundComparison({ original: this.originalGifStats, current: this.currentGifStats,
              pending: this.gifStatsPending, error: this.gifStatsError })
            BackgroundAdjustment({ label: 'GIFの解像度（長辺）', value: this.gifResolution,
              minimum: 1, maximum: 1280, suffix: 'px', available: !this.busy && !this.gifStatsPending, sliderId: 'background_gif_resolution',
              onChange: (value: number) => { this.gifResolution = Math.round(value); } })
            BackgroundAdjustment({ label: 'GIFのFPS上限', value: this.gifFps,
              minimum: 1, maximum: 100, suffix: 'fps', available: !this.busy && !this.gifStatsPending, sliderId: 'background_gif_fps',
              onChange: (value: number) => { this.gifFps = Math.round(value); } })
            Button(this.busy ? 'GIFを調整中…' : 'GIFに適用')
              .enabled(!this.busy && (this.gifResolution !== this.draft.gifResolution || this.gifFps !== this.draft.gifFps))
              .onClick(() => this.applyGifSettings()).id('background_gif_apply')
            Button('GIF設定を標準に戻す').width('100%').fontSize(14)
              .fontColor($r('app.color.text_normal')).backgroundColor($r('app.color.key_item_normal'))
              .enabled(!this.busy && this.gifDefaultsChanged())
              .onClick(() => this.applyGifSettings(true)).id('background_gif_defaults')
            if (this.originalGifStats.frames > 0 && !this.gifStatsPending) {
              Text(`標準：元GIFの長辺${this.originalGifResolution()}px・FPS上限${this.originalGifFps()}・再生ON`)
                .width('100%').fontSize(12).fontColor($r('app.color.text_secondary'))
            }
            Text('設定値を選んで「GIFに適用」を押すと反映します。元の画像より大きくは拡大せず、再生速度を保ってフレームを間引きます。')
              .fontSize(12).fontColor($r('app.color.text_secondary'))
          }
          BackgroundAdjustment({ label: '拡大率', value: this.draft.zoom, minimum: 100, maximum: 250,
            available: !this.busy && this.draft.photo.length > 0, sliderId: 'background_zoom',
            onChange: (value: number) => this.setAdjustment('zoom', value) })
          BackgroundAdjustment({ label: '横位置', value: this.draft.x, minimum: -100, maximum: 100, suffix: '',
            available: !this.busy && this.draft.photo.length > 0, sliderId: 'background_x',
            onChange: (value: number) => this.setAdjustment('x', value) })
          BackgroundAdjustment({ label: '縦位置', value: this.draft.y, minimum: -100, maximum: 100, suffix: '',
            available: !this.busy && this.draft.photo.length > 0, sliderId: 'background_y',
            onChange: (value: number) => this.setAdjustment('y', value) })
          BackgroundAdjustment({ label: '明るさ', value: this.draft.brightness, minimum: 20, maximum: 100,
            available: !this.busy && this.draft.photo.length > 0, sliderId: 'background_brightness',
            onChange: (value: number) => this.setAdjustment('brightness', value) })
          BackgroundAdjustment({ label: 'キーの不透明度', value: this.draft.keyOpacity, minimum: 0, maximum: 100,
            available: !this.busy && this.draft.photo.length > 0, sliderId: 'background_key_opacity',
            onChange: (value: number) => this.setAdjustment('keyOpacity', value) })
          if (this.message.length > 0) { Text(this.message).fontSize(13).fontColor($r('app.color.text_secondary')) }
        }.width('100%').padding(16)
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor($r('app.color.menu_background'))
  }
}
