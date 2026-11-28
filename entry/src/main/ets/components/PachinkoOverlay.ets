import { ColorMetrics } from '@ohos.arkui.node';
import { KANON_GAMING_PHASE, KANON_PACHINKO_REPLAY } from '../common/AppStorageKeys';
import { GAMING_FLOW_STEPS, GAMING_GOLD_PHASE } from '../common/GamingEffectModel';
import { keyboardHaptics } from '../common/KeyboardHaptics';
import { PachinkoColor, PachinkoConsumption, PachinkoHold, PachinkoReplay, PachinkoResult, PachinkoStops, PACHINKO_HOLD_LIMIT,
  consumePachinkoHold, enqueuePachinko, imeCommitNotifications, pachinkoIdleRemaining, pachinkoKeyNotifications,
  pachinkoStops } from '../common/PachinkoModel';

const MISS_REEL_MS: number = 1200;
const REACH_REEL_MS: number = 2500;
const LEFT_STOP_MS: number = 480;
const RIGHT_STOP_MS: number = 700;
const MISS_MIDDLE_STOP_MS: number = 980;
const REACH_MIDDLE_STOP_MS: number = 2220;
const REACH_MS: number = 620;
const JACKPOT_MS: number = 2000;
const FRAME_MS: number = 1000 / 30;
const REACH_LABELS: string[] = ['激アツ!!', 'SUPERリーチ', '確変突入!!'];
const CONFETTI_COLORS: string[] = ['#ff647e', '#ffd754', '#6aefb1', '#72c9ff', '#bf89ff'];

interface ConfettiPiece {
  x: number;
  delay: number;
  drift: number;
  size: number;
  color: string;
}

@Component
export struct PachinkoOverlay {
  @Prop @Watch('keysVisibilityChanged') keysVisible: boolean = true;
  @Prop @Watch('replayChanged') replay: string = '';
  @Prop acceptCommits: boolean = true;
  @StorageProp('kanonPachinkoSession') @Watch('resetSession') session: number = 0;
  @State private holdColors: PachinkoColor[] = [];
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private holds: PachinkoHold[] = [];
  private ready: boolean = false;
  private lastActivity: number = 0;
  private playing: boolean = false;
  private stops: PachinkoStops | undefined = undefined;
  private dimmed: boolean = false;
  private lastReelPaint: number = -1;
  private startedAt: number = 0;
  private timer: number = -1;
  private phase: number = -1;
  private paletteOffset: number = 0;
  private pulses: number = 0;
  private reachLabel: string = '';
  private confetti: ConfettiPiece[] = [];
  private onCommit: () => void = (): void => {
    this.noteActivity();
    if (!this.acceptCommits) { return; }
    const next: PachinkoHold[] = enqueuePachinko(this.holds, Math.random);
    if (next !== this.holds) { this.updateHolds(next); }
    this.scheduleHold();
  };
  private onPress: () => void = (): void => {
    if (this.holds.length > 0 || this.stops !== undefined) { this.noteActivity(); }
  };

  aboutToAppear(): void {
    imeCommitNotifications.listen(this.onCommit);
    pachinkoKeyNotifications.listen(this.onPress);
    this.replayChanged();
  }

  aboutToDisappear(): void {
    imeCommitNotifications.unlisten(this.onCommit);
    pachinkoKeyNotifications.unlisten(this.onPress);
    this.ready = false;
    this.resetSession();
  }

  private updateHolds(holds: PachinkoHold[]): void {
    this.holds = holds;
    this.holdColors = holds.map((hold: PachinkoHold): PachinkoColor => hold.color);
  }

  private noteActivity(): void {
    this.lastActivity = Date.now();
    if (this.stops !== undefined && !this.dimmed) {
      this.dimmed = true;
      this.lastReelPaint = -1;
    }
  }

  private replayChanged(): void {
    if (this.replay === '') { return; }
    this.stop();
    this.lastActivity = Date.now();
    let holds: PachinkoHold[] = [];
    if (this.replay === PachinkoReplay.FourHolds) {
      for (let index: number = 0; index < PACHINKO_HOLD_LIMIT; index++) {
        holds = enqueuePachinko(holds, Math.random);
      }
    } else {
      const result: PachinkoResult = this.replay === PachinkoReplay.Jackpot ? PachinkoResult.Jackpot : PachinkoResult.Reach;
      holds = enqueuePachinko(holds, Math.random, result);
    }
    this.updateHolds(holds);
    this.scheduleHold();
  }

  private resetSession(): void {
    this.stop();
    this.updateHolds([]);
    this.lastActivity = 0;
    this.finishReplay();
  }

  private finishReplay(): void {
    if (this.replay !== '' && AppStorage.get<string>(KANON_PACHINKO_REPLAY) === this.replay) {
      AppStorage.setOrCreate(KANON_PACHINKO_REPLAY, '');
    }
  }

  private keysVisibilityChanged(): void {
    if (!this.keysVisible && !this.playing) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    this.scheduleHold();
  }

  private scheduleHold(): void {
    if (!this.ready || !this.keysVisible || this.timer >= 0 || this.playing || this.holds.length === 0) { return; }
    const delay: number = pachinkoIdleRemaining(Date.now(), this.lastActivity);
    this.timer = setTimeout(() => this.consumeHold(), delay);
  }

  private consumeHold(): void {
    this.timer = -1;
    if (!this.keysVisible) { return; }
    const consumption: PachinkoConsumption | undefined = consumePachinkoHold(this.holds, Date.now(), this.lastActivity);
    if (consumption === undefined) {
      this.scheduleHold();
      return;
    }
    const result: PachinkoResult = consumption.hold.result;
    this.playing = true;
    this.updateHolds(consumption.remaining);
    this.stops = pachinkoStops(result, Math.random);
    this.startedAt = Date.now();
    this.dimmed = false;
    this.lastReelPaint = -1;
    this.renderReels(result);
  }

  private completeHold(): void {
    this.stop();
    if (this.holds.length === 0) { this.finishReplay(); }
    this.scheduleHold();
  }

  private renderReels(result: PachinkoResult): void {
    const stops: PachinkoStops | undefined = this.stops;
    if (stops === undefined) { return; }
    const now: number = Date.now();
    const elapsed: number = now - this.startedAt;
    const reach: boolean = result !== PachinkoResult.Miss;
    const duration: number = reach ? REACH_REEL_MS : MISS_REEL_MS;
    if (elapsed >= duration) {
      this.stops = undefined;
      if (result === PachinkoResult.Miss) { this.completeHold(); }
      else { this.beginCelebration(result); }
      return;
    }
    const idleRemaining: number = pachinkoIdleRemaining(now, this.lastActivity);
    const middleStop: number = reach ? REACH_MIDDLE_STOP_MS : MISS_MIDDLE_STOP_MS;
    const nextStop: number = elapsed < LEFT_STOP_MS ? LEFT_STOP_MS :
      elapsed < RIGHT_STOP_MS ? RIGHT_STOP_MS : elapsed < middleStop ? middleStop : duration;
    const lastStop: number = elapsed >= middleStop ? middleStop :
      elapsed >= RIGHT_STOP_MS ? RIGHT_STOP_MS : elapsed >= LEFT_STOP_MS ? LEFT_STOP_MS : 0;
    // During typing only paint the first dimmed frame and the discrete stops.
    if (this.keysVisible && (idleRemaining === 0 || this.lastReelPaint < lastStop)) {
      this.drawReels(stops, elapsed, reach, middleStop);
      this.lastReelPaint = elapsed;
    }
    const nextFrame: number = idleRemaining > 0 ? idleRemaining : FRAME_MS;
    this.timer = setTimeout(() => this.renderReels(result), this.keysVisible ?
      Math.min(nextFrame, nextStop - elapsed) : nextStop - elapsed);
  }

  private drawReels(stops: PachinkoStops, elapsed: number, reach: boolean, middleStop: number): void {
    const width: number = this.context.width;
    const height: number = this.context.height;
    const gap: number = width * 0.02;
    const windowWidth: number = width * 0.56 / 3;
    const windowHeight: number = Math.min(windowWidth * 1.45, height * 0.57);
    const x: number = width * 0.2;
    const y: number = (height - windowHeight) / 2;
    this.context.clearRect(0, 0, width, height);
    this.context.save();
    this.context.globalAlpha = this.dimmed ? 0.3 : 1;
    this.drawReelWindow(x, y, windowWidth, windowHeight, elapsed, LEFT_STOP_MS, stops.left);
    this.drawReelWindow(x + windowWidth + gap, y, windowWidth, windowHeight, elapsed, middleStop, stops.middle);
    this.drawReelWindow(x + 2 * (windowWidth + gap), y, windowWidth, windowHeight, elapsed, RIGHT_STOP_MS, stops.right);
    if (reach && elapsed >= RIGHT_STOP_MS) {
      this.drawGoldText('リーチ!', width / 2, y * 0.54, Math.min(27, y * 0.7), width * 0.6);
    }
    this.context.restore();
  }

  private drawReelWindow(x: number, y: number, width: number, height: number, elapsed: number, stopAt: number,
    digit: number): void {
    if (width <= 2 || height <= 2) { return; }
    const radius: number = Math.min(9, width / 4, height / 4);
    const right: number = x + width;
    const bottom: number = y + height;
    this.context.save();
    this.context.beginPath();
    this.context.moveTo(x + radius, y);
    this.context.arcTo(right, y, right, bottom, radius);
    this.context.arcTo(right, bottom, x, bottom, radius);
    this.context.arcTo(x, bottom, x, y, radius);
    this.context.arcTo(x, y, right, y, radius);
    this.context.closePath();
    this.context.fillStyle = '#15101d';
    this.context.fill();
    this.context.clip();
    this.context.lineWidth = 3;
    this.context.strokeStyle = '#ad8740';
    this.context.stroke();
    // Anchor the scroll at the chosen stop. The long middle reel eases out.
    const remaining: number = Math.max(0, stopAt - elapsed);
    const turns: number = stopAt > 1200 ? remaining * remaining / (stopAt * 145) : remaining / 75;
    const position: number = digit - 1 - turns;
    const first: number = Math.floor(position);
    const offset: number = (position - first) * height;
    const size: number = Math.min(width * 0.78, height * 0.75);
    this.context.font = `900 ${Math.round(size)}px sans-serif`;
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    this.context.fillStyle = '#fff4d4';
    this.context.fillText(((first % 9 + 9) % 9 + 1).toString(), x + width / 2, y + height / 2 - offset);
    if (offset > 0) {
      this.context.fillText((((first + 1) % 9 + 9) % 9 + 1).toString(), x + width / 2, y + height * 1.5 - offset);
    }
    this.context.restore();
  }

  private beginCelebration(result: PachinkoResult): void {
    this.startedAt = Date.now();
    this.pulses = 0;
    if (result === PachinkoResult.Reach) {
      this.reachLabel = REACH_LABELS[Math.floor(Math.random() * REACH_LABELS.length)];
    } else {
      try {
        const text: ColorMetrics = ColorMetrics.resourceColor($r('app.color.key_text'));
        this.paletteOffset = text.red + text.green + text.blue > 384 ? GAMING_FLOW_STEPS : 0;
      } catch (error) {}
      for (let index: number = 0; index < 42; index++) {
        const piece: ConfettiPiece = {
          x: Math.random(), delay: Math.random() * 280, drift: Math.random() * 80 - 40,
          size: 3 + Math.random() * 5, color: CONFETTI_COLORS[index % CONFETTI_COLORS.length]
        };
        this.confetti.push(piece);
      }
    }
    this.renderCelebration(result);
  }

  private publishPhase(phase: number): void {
    if (phase === this.phase) { return; }
    this.phase = phase;
    AppStorage.setOrCreate(KANON_GAMING_PHASE, phase);
  }

  private stop(): void {
    clearTimeout(this.timer);
    this.timer = -1;
    this.playing = false;
    this.stops = undefined;
    this.confetti = [];
    keyboardHaptics.stopCelebration();
    this.context.clearRect(0, 0, this.context.width, this.context.height);
    this.publishPhase(-1);
  }

  private renderCelebration(result: PachinkoResult): void {
    const elapsed: number = Date.now() - this.startedAt;
    const reach: boolean = result === PachinkoResult.Reach;
    const duration: number = reach ? REACH_MS : JACKPOT_MS;
    if (elapsed >= duration) {
      this.completeHold();
      return;
    }
    if (this.pulses === 0 || (reach && this.pulses === 1 && elapsed >= 150)) {
      keyboardHaptics.celebrationPulse(reach ? 30 : 160);
      this.pulses++;
    }
    const width: number = this.context.width;
    const height: number = this.context.height;
    this.context.clearRect(0, 0, width, height);
    this.context.save();
    this.context.globalAlpha = Math.min(1, (duration - elapsed) / 250);
    if (reach) {
      this.drawReach(elapsed, width, height);
    } else {
      this.drawJackpot(elapsed, width, height);
    }
    this.context.restore();
    this.timer = setTimeout(() => this.renderCelebration(result), Math.min(FRAME_MS, duration - elapsed));
  }

  private drawReach(elapsed: number, width: number, height: number): void {
    this.publishPhase(elapsed < 420 && elapsed % 220 < 110 ? GAMING_GOLD_PHASE : -1);
    const pop: number = Math.min(1, elapsed / 220);
    const scale: number = 0.3 + 0.7 * (1 - Math.pow(1 - pop, 3)) + Math.sin(pop * Math.PI) * 0.18;
    const shake: number = elapsed > 220 ? Math.sin((elapsed - 220) / 21) *
      Math.max(0, 1 - (elapsed - 220) / 550) * 9 : 0;
    const size: number = Math.min(66, width / 7, height / 2.5) * scale;
    this.drawGoldText(this.reachLabel, width / 2 + shake, height / 2, size, width * 0.92);
  }

  private drawJackpot(elapsed: number, width: number, height: number): void {
    const step: number = Math.floor(elapsed * GAMING_FLOW_STEPS / 720) % GAMING_FLOW_STEPS;
    this.publishPhase(this.paletteOffset + step);
    this.drawConfetti(elapsed, width, height);
    const size: number = Math.min(88, height * 0.38, width / 5);
    for (let slot: number = 0; slot < 3; slot++) {
      const x: number = width / 2 + (slot - 1) * size;
      this.drawGoldText('7', x, height * 0.39, size, size);
    }
    this.drawGoldText('大当たり!!', width / 2, height * 0.72, size * 0.59, width * 0.92);
  }

  private drawConfetti(elapsed: number, width: number, height: number): void {
    for (const piece of this.confetti) {
      const fall: number = (elapsed - piece.delay) / 930;
      if (fall < 0 || fall > 1) { continue; }
      const x: number = width * piece.x + piece.drift * fall;
      const y: number = (height + piece.size) * fall - piece.size;
      this.context.save();
      this.context.translate(x, y);
      this.context.rotate(fall * piece.drift / 5);
      this.context.fillStyle = piece.color;
      this.context.fillRect(-piece.size / 2, -piece.size / 2, piece.size, piece.size);
      this.context.restore();
    }
  }

  private drawGoldText(label: string, x: number, y: number, size: number, maxWidth: number): void {
    if (size <= 0 || maxWidth <= 0) { return; }
    this.context.save();
    this.context.font = `900 ${Math.round(size)}px sans-serif`;
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    this.context.lineJoin = 'round';
    this.context.lineWidth = Math.max(2, size / 11);
    this.context.strokeStyle = '#552800';
    this.context.shadowColor = 'rgba(0, 0, 0, 0.75)';
    this.context.shadowBlur = 6;
    this.context.shadowOffsetY = 3;
    this.context.strokeText(label, x, y, maxWidth);
    this.context.shadowBlur = 0;
    this.context.shadowOffsetY = 0;
    this.context.fillStyle = '#ffdc58';
    this.context.fillText(label, x, y, maxWidth);
    this.context.restore();
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Canvas(this.context).width('100%').height('100%')
        .hitTestBehavior(HitTestMode.None)
        .onReady(() => {
          this.ready = true;
          this.scheduleHold();
        })
      Row({ space: 5 }) {
        ForEach(this.holdColors, (color: PachinkoColor) => {
          Circle().width(10).height(10).fill(color).stroke('#2c202e').strokeWidth(1)
            .hitTestBehavior(HitTestMode.None)
        }, (color: PachinkoColor, index: number) => `${index}:${color}`)
      }.margin({ top: 3 }).hitTestBehavior(HitTestMode.None)
    }
      .width('100%').height('100%').clip(true)
      .visibility(this.keysVisible ? Visibility.Visible : Visibility.Hidden)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}
