import { ColorMetrics } from '@ohos.arkui.node';
import { KANON_GAMING_PHASE } from '../common/AppStorageKeys';
import { GAMING_FLOW_STEPS, GAMING_GOLD_PHASE } from '../common/GamingEffectModel';
import { keyboardHaptics } from '../common/KeyboardHaptics';
import { PachinkoDraws, PachinkoResult, imeCommitNotifications } from '../common/PachinkoModel';

const REACH_MS: number = 1200;
const JACKPOT_MS: number = 2000;
const JACKPOT_REVEAL_MS: number = 720;
const FRAME_MS: number = 1000 / 30;
const REACH_LABELS: string[] = ['激アツ!!', 'SUPERリーチ', '確変突入!!'];
const CONFETTI_COLORS: string[] = ['#ff647e', '#ffd754', '#6aefb1', '#72c9ff', '#bf89ff'];
const draws: PachinkoDraws = new PachinkoDraws();

interface ConfettiPiece {
  x: number;
  delay: number;
  drift: number;
  size: number;
  color: string;
}

@Component
export struct PachinkoOverlay {
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private result: PachinkoResult = PachinkoResult.Miss;
  private startedAt: number = 0;
  private timer: number = -1;
  private phase: number = -1;
  private paletteOffset: number = 0;
  private pulses: number = 0;
  private reachLabel: string = '';
  private confetti: ConfettiPiece[] = [];
  private onCommit: () => void = (): void => {
    const result: PachinkoResult = draws.onCommit(this.result !== PachinkoResult.Miss, Math.random);
    if (result === PachinkoResult.Miss) { return; }
    this.result = result;
    // Schedule the rendering and vibration outside the input queue.
    this.timer = setTimeout(() => this.begin(), 0);
  };

  aboutToAppear(): void { imeCommitNotifications.listen(this.onCommit); }

  aboutToDisappear(): void {
    imeCommitNotifications.unlisten(this.onCommit);
    this.stop();
  }

  private begin(): void {
    this.startedAt = Date.now();
    this.pulses = 0;
    if (this.result === PachinkoResult.Reach) {
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
    this.renderFrame();
  }

  private publishPhase(phase: number): void {
    if (phase === this.phase) { return; }
    this.phase = phase;
    AppStorage.setOrCreate(KANON_GAMING_PHASE, phase);
  }

  private stop(): void {
    clearTimeout(this.timer);
    this.timer = -1;
    this.result = PachinkoResult.Miss;
    this.confetti = [];
    keyboardHaptics.stopCelebration();
    this.context.clearRect(0, 0, this.context.width, this.context.height);
    this.publishPhase(-1);
  }

  private renderFrame(): void {
    const elapsed: number = Date.now() - this.startedAt;
    const reach: boolean = this.result === PachinkoResult.Reach;
    const duration: number = reach ? REACH_MS : JACKPOT_MS;
    if (elapsed >= duration) {
      this.stop();
      return;
    }
    if (this.pulses === 0 || (reach && this.pulses === 1 && elapsed >= 150)) {
      keyboardHaptics.celebrationPulse(reach ? 30 : 160);
      this.pulses++;
    }
    const width: number = this.context.width;
    const height: number = this.context.height;
    this.context.clearRect(0, 0, width, height);
    this.context.globalAlpha = Math.min(1, (duration - elapsed) / 250);
    if (reach) {
      this.drawReach(elapsed, width, height);
    } else {
      this.drawJackpot(elapsed, width, height);
    }
    this.timer = setTimeout(() => this.renderFrame(), Math.min(FRAME_MS, duration - elapsed));
  }

  private drawReach(elapsed: number, width: number, height: number): void {
    // Three gold pulses, 360 ms apart.
    this.publishPhase(elapsed < 900 && elapsed % 360 < 145 ? GAMING_GOLD_PHASE : -1);
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
    const revealed: boolean = elapsed >= JACKPOT_REVEAL_MS;
    if (revealed) { this.drawConfetti(elapsed - JACKPOT_REVEAL_MS, width, height); }
    const slotY: number = height * (revealed ? 0.39 : 0.46);
    const size: number = Math.min(88, height * 0.38, width / 5);
    for (let slot: number = 0; slot < 3; slot++) {
      const x: number = width / 2 + (slot - 1) * size;
      const stopAt: number = 304 + slot * 176;
      if (elapsed < stopAt) {
        const spin: number = Math.floor(elapsed / 64) + slot * 3;
        const y: number = slotY + (elapsed % 64 / 64 - 0.5) * size * 0.6;
        this.drawGoldText((spin % 9 + 1).toString(), x, y, size, size);
      } else {
        const drop: number = Math.max(0, 1 - (elapsed - stopAt) / 105);
        this.drawGoldText('7', x, slotY - drop * size * 0.3, size, size);
      }
    }
    if (revealed) {
      this.drawGoldText('大当たり!!', width / 2, height * 0.72, size * 0.59, width * 0.92);
    }
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
    Canvas(this.context)
      .width('100%').height('100%').constraintSize({ maxWidth: 720 }).clip(true)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}
