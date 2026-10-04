/** A short visual hint; never intercepts the image editor's gestures. */
@Component
export struct BackgroundGestureHint {
  @Prop @Watch('restart') available: boolean = false;
  @Prop @Watch('restart') source: string = '';
  @State private visible: boolean = false;
  @State private pinch: boolean = false;
  @State private motion: boolean = false;
  private timers: number[] = [];
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    this.restart();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.clearTimers();
  }

  private clearTimers(): void {
    this.timers.forEach((timer: number) => clearTimeout(timer));
    this.timers = [];
  }

  private restart(): void {
    this.clearTimers();
    this.visible = false;
    if (!this.alive || !this.available || this.source.length === 0) { return; }
    this.pinch = false;
    this.motion = false;
    this.visible = true;
    this.timers.push(setTimeout(() => this.animateMotion(), 250));
    this.timers.push(setTimeout(() => { this.pinch = true; this.motion = false; }, 1750));
    this.timers.push(setTimeout(() => this.animateMotion(), 2000));
    this.timers.push(setTimeout(() => { this.visible = false; this.clearTimers(); }, 3500));
  }

  private animateMotion(): void {
    if (!this.alive || !this.visible || !this.available) { return; }
    // Both fingers share one animation transaction. Phase changes reset without animation.
    this.getUIContext().animateTo({ duration: 650, curve: Curve.EaseInOut,
      iterations: 2, playMode: PlayMode.Alternate }, () => { this.motion = true; });
  }

  @Builder
  finger(direction: number) {
    Circle().width(24).height(24).fill('#66FFFFFF').stroke(Color.White).strokeWidth(2)
      .translate({ x: this.pinch ? direction * (this.motion ? 22 : 4) : (this.motion ? 22 : -22) })
  }

  build() {
    Stack() {
      if (this.visible) {
        Column({ space: 10 }) {
          Row({ space: 20 }) {
            this.finger(-1)
            if (this.pinch) { this.finger(1) }
          }.height(30)
          Text(this.pinch ? '2本指で拡大・縮小' : 'ドラッグで移動')
            .fontSize(13).fontColor(Color.White)
        }.padding({ top: 12, bottom: 12, left: 36, right: 36 })
          .backgroundColor('#B3000000').borderRadius(16)
      }
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}
