import { ColorMetrics } from '@ohos.arkui.node';
import { KANON_GAMING_PHASE } from '../common/AppStorageKeys';
import { GAMING_RIPPLE_MS, GamingRipple, GamingRipples } from '../common/GamingEffectModel';
import { GAMING_FLOW_STEPS, GAMING_FLOW_TICK_MS, gamingPresses } from '../common/GamingKeyFeedback';

@Component
export struct GamingFlowClock {
  @StorageProp('kanonBackgroundThemeVersion') @Watch('refreshPalette') themeVersion: number = 0;
  private paletteOffset: number = 0;
  private startedAt: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    this.startedAt = Date.now();
    this.refreshPalette();
    this.timer = setInterval(() => this.publishPhase(), GAMING_FLOW_TICK_MS);
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
    this.timer = -1;
    AppStorage.setOrCreate(KANON_GAMING_PHASE, -1);
  }

  private refreshPalette(): void {
    try {
      const text: ColorMetrics = ColorMetrics.resourceColor($r('app.color.key_text'));
      this.paletteOffset = text.red + text.green + text.blue > 384 ? GAMING_FLOW_STEPS : 0;
    } catch (error) {}
    this.publishPhase();
  }

  private publishPhase(): void {
    const elapsed: number = Math.max(0, Date.now() - this.startedAt);
    const step: number = Math.floor(elapsed / GAMING_FLOW_TICK_MS) % GAMING_FLOW_STEPS;
    AppStorage.setOrCreate(KANON_GAMING_PHASE, this.paletteOffset + step);
  }

  build() {
    Stack() {}.width(0).height(0).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}

@Component
struct GamingRippleRing {
  finished: () => void = () => {};
  @State private expanded: boolean = false;
  private startTimer: number = -1;

  aboutToDisappear(): void { clearTimeout(this.startTimer); }

  @Builder
  ring(diameter: number, color: ResourceColor, stroke: number) {
    Circle().width(diameter).height(diameter).fill(Color.Transparent).stroke(color).strokeWidth(stroke)
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack() {
      this.ring(122, '#80202633', 7)
      this.ring(126, '#ff7299', 2)
      this.ring(122, '#fff17c', 2)
      this.ring(118, '#65efae', 2)
      this.ring(114, '#72c9ff', 2)
      this.ring(110, '#b78cff', 2)
    }.width(128).height(128)
      .hitTestBehavior(HitTestMode.None)
      .opacity(this.expanded ? 0 : 1)
      .scale({ x: this.expanded ? 1 : 0.16, y: this.expanded ? 1 : 0.16 })
      .onAppear(() => {
        this.startTimer = setTimeout(() => {
          this.getUIContext().animateTo({ duration: GAMING_RIPPLE_MS, curve: Curve.EaseOut,
            onFinish: () => this.finished() }, () => { this.expanded = true; });
        }, 0);
      })
  }
}

@Component
export struct GamingRippleOverlay {
  @State private rings: GamingRipple[] = [];
  private model: GamingRipples = new GamingRipples();
  private left: number = 0;
  private top: number = 0;
  private measured: boolean = false;
  private alive: boolean = false;
  private onPress: (x: number, y: number) => void = (x: number, y: number): void => {
    if (this.measured) { this.rings = this.model.add(x - this.left, y - this.top, Date.now()); }
  };

  aboutToAppear(): void {
    this.alive = true;
    gamingPresses.listen(this.onPress);
  }

  aboutToDisappear(): void {
    this.alive = false;
    gamingPresses.unlisten(this.onPress);
  }

  private removeRing(id: number): void {
    if (this.alive) { this.rings = this.model.remove(id); }
  }

  build() {
    Stack() {
      ForEach(this.rings, (ring: GamingRipple) => {
        GamingRippleRing({ finished: () => this.removeRing(ring.id) })
          .position({ x: ring.x - 64, y: ring.y - 64 })
          .hitTestBehavior(HitTestMode.None)
      }, (ring: GamingRipple) => ring.id.toString())
    }.width('100%').height('100%').constraintSize({ maxWidth: 720 }).clip(true)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
      .onAreaChange((_old: Area, area: Area) => {
        this.left = Number(area.globalPosition.x);
        this.top = Number(area.globalPosition.y);
        this.measured = true;
      })
  }
}
