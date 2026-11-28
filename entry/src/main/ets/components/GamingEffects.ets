import { gamingDarkKeys } from '../common/KeyboardKeyPalette';
import { KANON_GAMING_PHASE } from '../common/AppStorageKeys';
import { DEFAULT_GAMING_SPEED, GAMING_FLOW_PALETTE_OFFSET, GAMING_FLOW_STEPS, GAMING_RIPPLE_MS, GAMING_WAVE_TICK_MS,
  GamingPoint, GamingRipple, GamingRipples,
  GamingWaveFrame, gamingFlowPeriodMs, gamingFlowStep, gamingSpreadDurationMs } from '../common/GamingEffectModel';
import { gamingKeyCenter, gamingPresses, publishGamingWave, setGamingWaveTheme } from '../common/GamingKeyFeedback';
import { gamingLightingColors } from '../common/GamingLightingModel';

@Component
export struct GamingFlowClock {
  @StorageProp('kanonBackgroundHasPhoto') @Watch('refreshPalette') hasBackgroundPhoto: boolean = false;
  @StorageProp('kanonBackgroundThemeVersion') @Watch('refreshPalette') themeVersion: number = 0;
  @StorageProp('kanonGamingSpeed') @Watch('restartClock') speed: number = DEFAULT_GAMING_SPEED;
  private paletteOffset: number = 0;
  private startedAt: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    this.restartClock();
    this.refreshPalette();
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
    this.timer = -1;
    AppStorage.setOrCreate(KANON_GAMING_PHASE, -1);
  }

  private refreshPalette(): void {
    this.paletteOffset = gamingDarkKeys(this.hasBackgroundPhoto, this.paletteOffset !== 0) ? GAMING_FLOW_STEPS : 0;
    this.publishPhase();
  }

  private publishPhase(): void {
    const step: number = gamingFlowStep(Date.now() - this.startedAt, this.speed);
    AppStorage.setOrCreate(KANON_GAMING_PHASE, GAMING_FLOW_PALETTE_OFFSET + this.paletteOffset + step);
  }

  private restartClock(): void {
    clearInterval(this.timer);
    this.startedAt = Date.now();
    this.publishPhase();
    this.timer = setInterval(() => this.publishPhase(), gamingFlowPeriodMs(this.speed) / GAMING_FLOW_STEPS);
  }

  build() {
    Stack() {}.width(0).height(0).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}

@Component
export struct GamingWaveClock {
  @StorageProp('kanonBackgroundHasPhoto') @Watch('refreshTheme') hasBackgroundPhoto: boolean = false;
  @StorageProp('kanonBackgroundThemeVersion') @Watch('refreshTheme') themeVersion: number = 0;
  @StorageProp('kanonGamingSpeed') speed: number = DEFAULT_GAMING_SPEED;
  private presses: GamingRipples = new GamingRipples();
  private maxRadius: number = 0;
  private previous: number = 0;
  private timer: number = -1;
  private onPress: (x: number, y: number, area: Area) => void = (_x: number, _y: number, area: Area): void => {
    const bandWidth: number = Math.min(Number(area.width), Number(area.height));
    if (!(this.maxRadius > 0) || !Number.isFinite(bandWidth) || bandWidth <= 0) { return; }
    const center: GamingPoint = gamingKeyCenter(area);
    const now: number = Date.now();
    this.presses.add(center.x, center.y, now, gamingSpreadDurationMs(this.speed), bandWidth);
    if (this.timer === -1) {
      this.previous = now;
      this.timer = setTimeout(() => this.publishFrame(), 0);
    }
  };

  aboutToAppear(): void {
    this.refreshTheme();
    gamingPresses.listen(this.onPress);
  }

  private refreshTheme(): void { setGamingWaveTheme(gamingDarkKeys(this.hasBackgroundPhoto)); }

  aboutToDisappear(): void {
    gamingPresses.unlisten(this.onPress);
    this.stopClock();
    this.presses = new GamingRipples();
  }

  private stopClock(): void {
    clearTimeout(this.timer);
    this.timer = -1;
    publishGamingWave(undefined);
  }

  private publishFrame(): void {
    const presses: GamingRipple[] = this.presses.activeAt(this.previous);
    if (presses.length === 0) {
      this.stopClock();
      return;
    }
    const now: number = Date.now();
    const frame: GamingWaveFrame = { presses: presses, previous: this.previous, now: now, maxRadius: this.maxRadius };
    this.previous = now;
    publishGamingWave(frame);
    this.timer = setTimeout(() => this.publishFrame(), GAMING_WAVE_TICK_MS);
  }

  build() {
    Stack() {}.width('100%').height('100%').constraintSize({ maxWidth: 720 })
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      .onAreaChange((_old: Area, area: Area) => {
        const width: number = Number(area.width);
        const height: number = Number(area.height);
        this.maxRadius = Math.sqrt(width * width + height * height);
      })
  }
}

@Component
struct GamingRippleRing {
  finished: () => void = () => {};
  duration: number = GAMING_RIPPLE_MS;
  @Prop colors: number[] = gamingLightingColors.ringRgb(false);
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
      this.ring(126, 0xff000000 + this.colors[0], 2)
      this.ring(122, 0xff000000 + this.colors[1], 2)
      this.ring(118, 0xff000000 + this.colors[2], 2)
      this.ring(114, 0xff000000 + this.colors[3], 2)
      this.ring(110, 0xff000000 + this.colors[4], 2)
    }.width(128).height(128)
      .hitTestBehavior(HitTestMode.None)
      .opacity(this.expanded ? 0 : 1)
      .scale({ x: this.expanded ? 1 : 0.16, y: this.expanded ? 1 : 0.16 })
      .onAppear(() => {
        this.startTimer = setTimeout(() => {
          this.getUIContext().animateTo({ duration: this.duration, curve: Curve.EaseOut,
            onFinish: () => this.finished() }, () => { this.expanded = true; });
        }, 0);
      })
  }
}

@Component
export struct GamingRippleOverlay {
  @StorageProp('kanonBackgroundHasPhoto') @Watch('refreshColors') hasBackgroundPhoto: boolean = false;
  @StorageProp('kanonBackgroundThemeVersion') @Watch('refreshColors') themeVersion: number = 0;
  @StorageProp('kanonSettingsGeneration') @Watch('refreshColors') settingsGeneration: number = 0;
  @StorageProp('kanonGamingSpeed') speed: number = DEFAULT_GAMING_SPEED;
  @State private rings: GamingRipple[] = [];
  @State private colors: number[] = gamingLightingColors.ringRgb(false);
  private model: GamingRipples = new GamingRipples();
  private left: number = 0;
  private top: number = 0;
  private measured: boolean = false;
  private alive: boolean = false;
  private onPress: (x: number, y: number, area: Area) => void = (x: number, y: number, _area: Area): void => {
    if (this.measured) {
      this.rings = this.model.add(x - this.left, y - this.top, Date.now(), gamingSpreadDurationMs(this.speed));
    }
  };

  aboutToAppear(): void {
    this.refreshColors();
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

  private refreshColors(): void {
    this.colors = gamingLightingColors.ringRgb(gamingDarkKeys(this.hasBackgroundPhoto));
  }

  build() {
    Stack() {
      ForEach(this.rings, (ring: GamingRipple) => {
        GamingRippleRing({ duration: ring.duration, colors: this.colors, finished: () => this.removeRing(ring.id) })
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
