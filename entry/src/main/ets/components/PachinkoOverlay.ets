import { ColorMetrics } from '@ohos.arkui.node';
import { KANON_GAMING_PHASE, KANON_PACHINKO_REPLAY } from '../common/AppStorageKeys';
import { GAMING_FLOW_STEPS, GAMING_GOLD_PHASE } from '../common/GamingEffectModel';
import { keyboardHaptics } from '../common/KeyboardHaptics';
import { PachinkoColor, PachinkoConsumption, PachinkoHold, PachinkoReplay, PachinkoScript, PachinkoStage,
  PachinkoStageKind, buildPachinkoScript, consumePachinkoHold, enqueuePachinko, imeCommitNotifications,
  pachinkoIdleRemaining, pachinkoKeyNotifications, pachinkoReplayHolds, pachinkoRushAfter,
  parsePachinkoReplay } from '../common/PachinkoModel';

const FRAME_MS: number = 1000 / 30;
const RUSH_END_MS: number = 1200;
const SP_SECOND_PULSE_MS: number = 150;
const CONFETTI_COLORS: string[] = ['#ff647e', '#ffd754', '#6aefb1', '#72c9ff', '#bf89ff'];
const RAINBOW_COLORS: string[] = ['#ff5b6b', '#ffd253', '#60ed8d', '#57cbff', '#9a78ff', '#ff78c8'];

@Component
export struct PachinkoOverlay {
  @Prop @Watch('keysVisibilityChanged') keysVisible: boolean = true;
  @Prop @Watch('replayChanged') replay: string = '';
  @Prop acceptCommits: boolean = true;
  @StorageProp('kanonPachinkoSession') @Watch('resetSession') session: number = 0;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private holdContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private holds: PachinkoHold[] = [];
  private ready: boolean = false;
  private holdReady: boolean = false;
  private rainbowHold: boolean = false;
  private lastActivity: number = 0;
  private script: PachinkoScript | undefined = undefined;
  private rushRemaining: number = 0;
  private rushEnding: boolean = false;
  private rushEndTimer: number = -1;
  private debugReplay: PachinkoReplay | undefined = undefined;
  private forcedReplay: PachinkoReplay | undefined = undefined;
  @State private dimmed: boolean = false;
  private startedAt: number = 0;
  private timer: number = -1;
  private stageIndex: number = -1;
  private secondPulse: boolean = false;
  private phase: number = -1;
  private paletteOffset: number = 0;

  private onCommit: () => void = (): void => {
    this.noteActivity();
    if (!this.acceptCommits && this.rushRemaining === 0) { return; }
    const next: PachinkoHold[] = enqueuePachinko(this.holds, Math.random, this.rushRemaining);
    if (next !== this.holds) { this.updateHolds(next); }
    this.scheduleHold();
  };
  private onPress: () => void = (): void => {
    if (this.holds.length > 0 || this.script !== undefined) { this.noteActivity(); }
  };

  aboutToAppear(): void {
    imeCommitNotifications.listen(this.onCommit);
    pachinkoKeyNotifications.listen(this.onPress);
    try {
      const color: ColorMetrics = ColorMetrics.resourceColor($r('app.color.key_text'));
      this.paletteOffset = color.red + color.green + color.blue > 384 ? GAMING_FLOW_STEPS : 0;
    } catch (error) {}
    this.replayChanged();
  }

  aboutToDisappear(): void {
    imeCommitNotifications.unlisten(this.onCommit);
    pachinkoKeyNotifications.unlisten(this.onPress);
    this.ready = false;
    this.holdReady = false;
    this.resetSession();
  }

  private updateHolds(holds: PachinkoHold[]): void {
    this.holds = holds;
    this.rainbowHold = holds.some((hold: PachinkoHold): boolean => hold.displayColor === PachinkoColor.Rainbow);
    this.drawHolds(0);
  }

  private noteActivity(): void {
    this.lastActivity = Date.now();
    if (this.keysVisible && this.script !== undefined && !this.dimmed) {
      // The first key press dims the Canvas. Further presses only extend the idle deadline.
      this.tick();
    }
  }

  private replayChanged(): void {
    const replay: PachinkoReplay | undefined = parsePachinkoReplay(this.replay);
    if (replay === undefined) {
      if (this.debugReplay !== undefined) { this.clearSession(); }
      return;
    }
    this.clearSession();
    this.debugReplay = replay;
    this.forcedReplay = replay;
    this.lastActivity = Date.now();
    this.updateHolds(pachinkoReplayHolds(replay));
    this.scheduleHold();
  }

  private clearSession(): void {
    this.stopSpin();
    clearTimeout(this.rushEndTimer);
    this.rushEndTimer = -1;
    this.rushRemaining = 0;
    this.rushEnding = false;
    this.debugReplay = undefined;
    this.forcedReplay = undefined;
    this.updateHolds([]);
    this.lastActivity = 0;
  }

  private resetSession(): void {
    this.clearSession();
    this.finishReplay();
  }

  private finishReplay(): void {
    this.debugReplay = undefined;
    if (this.replay !== '' && AppStorage.get<string>(KANON_PACHINKO_REPLAY) === this.replay) {
      AppStorage.setOrCreate(KANON_PACHINKO_REPLAY, '');
    }
  }

  private keysVisibilityChanged(): void {
    clearTimeout(this.timer);
    this.timer = -1;
    if (!this.keysVisible) { this.publishPhase(-1); }
    if (this.script !== undefined) { this.tick(true); }
    else { this.scheduleHold(); }
  }

  private scheduleHold(): void {
    if (!this.ready || !this.keysVisible || this.timer >= 0 || this.script !== undefined || this.holds.length === 0) {
      return;
    }
    this.timer = setTimeout(() => this.consumeHold(), pachinkoIdleRemaining(Date.now(), this.lastActivity));
  }

  private consumeHold(): void {
    this.timer = -1;
    if (!this.keysVisible) { return; }
    const now: number = Date.now();
    const consumption: PachinkoConsumption | undefined = consumePachinkoHold(this.holds, now, this.lastActivity);
    if (consumption === undefined) {
      this.scheduleHold();
      return;
    }
    this.script = buildPachinkoScript(consumption.hold, this.rushRemaining, this.holds.length, Math.random,
      this.forcedReplay);
    this.forcedReplay = undefined;
    this.startedAt = now;
    this.updateHolds(consumption.remaining);
    this.tick();
  }

  private stopSpin(): void {
    clearTimeout(this.timer);
    this.timer = -1;
    this.script = undefined;
    this.stageIndex = -1;
    this.dimmed = false;
    this.secondPulse = false;
    keyboardHaptics.stopCelebration();
    if (this.ready) { this.context.clearRect(0, 0, this.context.width, this.context.height); }
    this.publishPhase(-1);
  }

  private completeHold(script: PachinkoScript): void {
    this.stopSpin();
    const previous: number = this.rushRemaining;
    this.rushRemaining = pachinkoRushAfter(previous, script.result, script.stops.middle);
    if (previous > 0 && this.rushRemaining === 0) {
      this.rushEnding = true;
      this.rushEndTimer = setTimeout(() => {
        this.rushEndTimer = -1;
        this.rushEnding = false;
        this.drawHolds(0);
        this.finishReplayIfDone();
      }, RUSH_END_MS);
    }
    this.drawHolds(0);
    this.finishReplayIfDone();
    this.scheduleHold();
  }

  private finishReplayIfDone(): void {
    if (this.debugReplay !== undefined && this.script === undefined && this.holds.length === 0 &&
      (this.acceptCommits || (this.rushRemaining === 0 && !this.rushEnding))) {
      this.finishReplay();
    }
  }

  private tick(repaint: boolean = false): void {
    clearTimeout(this.timer);
    this.timer = -1;
    const script: PachinkoScript | undefined = this.script;
    if (script === undefined) { return; }
    const now: number = Date.now();
    const elapsed: number = now - this.startedAt;
    if (elapsed >= script.duration) {
      this.completeHold(script);
      return;
    }
    let index: number = Math.max(0, this.stageIndex);
    while (elapsed >= script.stages[index].start + script.stages[index].duration) { index++; }
    const stage: PachinkoStage = script.stages[index];
    const local: number = elapsed - stage.start;
    const development: boolean = stage.kind === PachinkoStageKind.SP || stage.kind === PachinkoStageKind.SPSP;
    if (index !== this.stageIndex) {
      this.stageIndex = index;
      this.secondPulse = false;
      if (this.keysVisible) { this.stagePulse(stage.kind, development); }
    }
    let next: number = stage.duration - local;
    if (development && !this.secondPulse) {
      if (local >= SP_SECOND_PULSE_MS) {
        this.secondPulse = true;
        if (this.keysVisible) { keyboardHaptics.celebrationPulse(30); }
      } else {
        next = Math.min(next, SP_SECOND_PULSE_MS - local);
      }
    }
    const idle: number = pachinkoIdleRemaining(now, this.lastActivity);
    const dimmed: boolean = idle > 0;
    if (this.keysVisible) {
      if (!dimmed || repaint) {
        this.drawStage(script, stage, elapsed, local);
        if (this.rainbowHold) { this.drawHolds(elapsed); }
      }
      this.dimmed = dimmed;
      this.updatePhase(stage, local, dimmed);
      next = Math.min(next, dimmed ? idle : FRAME_MS);
    }
    this.timer = setTimeout(() => this.tick(), next);
  }

  private stagePulse(kind: PachinkoStageKind, development: boolean): void {
    if (kind === PachinkoStageKind.Jackpot) {
      keyboardHaptics.celebrationPulse(160);
    } else if (development || kind === PachinkoStageKind.Tenpai || kind === PachinkoStageKind.CutIn) {
      keyboardHaptics.celebrationPulse(30);
    }
  }

  private updatePhase(stage: PachinkoStage, local: number, dimmed: boolean): void {
    let phase: number = -1;
    if (!dimmed && stage.kind === PachinkoStageKind.Tenpai && local % 220 < 110) {
      phase = GAMING_GOLD_PHASE;
    } else if (!dimmed && stage.kind === PachinkoStageKind.Jackpot) {
      // Key decorations change only at flash boundaries. Continuous color runs on Canvas.
      const flash: number = Math.floor(local / 300);
      phase = this.paletteOffset + Math.floor(flash * GAMING_FLOW_STEPS / 7);
    }
    this.publishPhase(phase);
  }

  private publishPhase(phase: number): void {
    if (phase === this.phase) { return; }
    this.phase = phase;
    AppStorage.setOrCreate(KANON_GAMING_PHASE, phase);
  }

  private drawStage(script: PachinkoScript, stage: PachinkoStage, elapsed: number, local: number): void {
    const width: number = this.context.width;
    const height: number = this.context.height;
    const progress: number = local / stage.duration;
    this.context.clearRect(0, 0, width, height);
    this.context.save();
    if (stage.kind === PachinkoStageKind.Reveal) {
      const scale: number = 1 + Math.sin(progress * Math.PI) * 1.5;
      const color: PachinkoColor = progress < 0.5 ? PachinkoColor.White : stage.color;
      this.drawBall(this.context, width / 2, 35, 5 * scale, color, elapsed);
      this.context.restore();
      return;
    }

    const special: boolean = stage.kind === PachinkoStageKind.SP || stage.kind === PachinkoStageKind.SPSP ||
      stage.kind === PachinkoStageKind.CutIn || stage.kind === PachinkoStageKind.Push;
    const jackpot: boolean = stage.kind === PachinkoStageKind.Jackpot;
    if (special) {
      this.context.fillStyle = 'rgba(10, 3, 21, 0.76)';
      this.context.fillRect(0, 0, width, height);
    } else if (jackpot) {
      this.context.fillStyle = this.rainbow(this.context, 0, width, local);
      this.context.fillRect(0, 0, width, height);
      this.context.fillStyle = 'rgba(32, 7, 30, 0.78)';
      this.context.fillRect(0, 0, width, height);
    }

    const reelWidth: number = width * (jackpot ? 0.22 : 0.18);
    const reelHeight: number = Math.min(reelWidth * 1.45, height * 0.5);
    const y: number = (height - reelHeight) / 2;
    const center: number = width / 2;
    const middleWidth: number = reelWidth * (special ? 1.42 : 1);
    const middleHeight: number = reelHeight * (special ? 1.15 : 1);
    const separation: number = (middleWidth + reelWidth) / 2 + width * 0.018;
    let left: number = this.reelPosition(script.stops.left, elapsed, script.leftStop);
    let right: number = this.reelPosition(script.stops.right, elapsed, script.rightStop);
    let middle: number = this.middlePosition(script, elapsed);
    if (stage.kind === PachinkoStageKind.Pseudo) {
      left = this.pseudoPosition(left, this.reelPosition(script.stops.left, stage.start, script.leftStop), progress);
      right = this.pseudoPosition(right, this.reelPosition(script.stops.right, stage.start, script.rightStop), progress);
      middle = this.pseudoPosition(middle, this.middlePosition(script, stage.start), progress);
    } else if (stage.kind === PachinkoStageKind.FullRotation) {
      middle = script.stops.middle - 1 - 16 * (1 - progress) * (1 - progress);
      left = middle;
      right = middle;
    } else if (stage.kind === PachinkoStageKind.Revival) {
      const direction: number = (script.revivalDigit - script.stops.middle + 9) % 9 === 1 ? 1 : -1;
      const slide: number = Math.min(1, Math.max(0, (progress - 0.55) / 0.25));
      middle = script.stops.middle - 1 + direction * (1 - slide);
      if (progress > 0.3 && progress < 0.55) { middle += Math.sin(local / 25) * 0.09; }
    } else if (jackpot) {
      middle = script.stops.middle - 1;
    }
    this.drawReelWindow(center - separation - reelWidth / 2, y, reelWidth, reelHeight, left, script.rush, jackpot);
    this.drawReelWindow(center - middleWidth / 2, (height - middleHeight) / 2, middleWidth, middleHeight, middle,
      script.rush, special || jackpot);
    this.drawReelWindow(center + separation - reelWidth / 2, y, reelWidth, reelHeight, right, script.rush, jackpot);
    this.drawNotice(stage, local, progress, width, height, reelHeight);
    this.context.restore();
  }

  private reelPosition(digit: number, elapsed: number, stopAt: number): number {
    return digit - 1 - Math.max(0, stopAt - elapsed) / 80;
  }

  private pseudoPosition(position: number, initial: number, progress: number): number {
    const frozen: number = Math.round(initial);
    return frozen + (position - frozen) * Math.max(0, (progress - 0.5) * 2);
  }

  private middlePosition(script: PachinkoScript, elapsed: number): number {
    const digit: number = script.revivalDigit || script.stops.middle;
    if (script.middleStop - script.rightStop < 500) { return this.reelPosition(digit, elapsed, script.middleStop); }
    const span: number = script.middleStop - script.rightStop;
    const remaining: number = Math.max(0, script.middleStop - Math.max(elapsed, script.rightStop));
    const beforeReach: number = Math.max(0, script.rightStop - elapsed);
    return digit - 1 - remaining * remaining / (span * 185) - beforeReach / 80;
  }

  private drawNotice(stage: PachinkoStage, local: number, progress: number, width: number, height: number,
    reelHeight: number): void {
    const center: number = width / 2;
    const top: number = height * 0.18;
    switch (stage.kind) {
      case PachinkoStageKind.Step: {
        const size: number = Math.min(height * 0.16, 16 + stage.level * 4);
        this.drawBand('STEP ' + stage.level.toString(), width, top, size, PachinkoColor.Gold, local, 0.36 + stage.level * 0.1);
        break;
      }
      case PachinkoStageKind.Pseudo:
        this.drawGoldText('×' + stage.level.toString(), center, top, reelHeight * 0.52, width * 0.92);
        break;
      case PachinkoStageKind.Tenpai:
        this.drawGoldText('リーチ!', center, top, reelHeight * (0.66 - Math.min(1, progress * 2) * 0.16), width * 0.94);
        break;
      case PachinkoStageKind.SP:
        this.drawBand('SPリーチ', width, top, height * 0.12, PachinkoColor.Blue, local, 0.72);
        break;
      case PachinkoStageKind.SPSP:
        this.drawBand('激アツ', width, top, height * 0.15, PachinkoColor.Red, local, 0.9);
        break;
      case PachinkoStageKind.CutIn:
        this.drawBand('勝負!!', width, height * 0.5, height * 0.18, stage.color, local, 1.08);
        break;
      case PachinkoStageKind.Push:
        this.drawGoldText('PUSH!', center, height * 0.8, height * (0.2 + 0.045 * Math.sin(local / 48)), width * 0.95);
        break;
      case PachinkoStageKind.FullRotation:
        this.drawGoldText('全回転', center, top, reelHeight * 0.52, width * 0.94);
        break;
      case PachinkoStageKind.Revival:
        if (progress >= 0.55) {
          this.drawGoldText('復活!!', center, top, reelHeight * 0.55, width * 0.94);
        }
        break;
      case PachinkoStageKind.Jackpot: {
        const seven: boolean = stage.level === 7;
        const odd: boolean = stage.level % 2 === 1;
        this.drawConfetti(local, width, height, seven ? 64 : odd ? 42 : 30);
        const label: string = seven ? '７７７　確変大当たり!!' : odd ? '確変大当たり' : '大当たり';
        const size: number = reelHeight * (seven ? 0.63 + 0.05 * Math.sin(local / 65) : 0.49);
        this.drawGoldText(label, center, height * 0.82, size, width * 0.96, odd ? '#ffdc58' : '#fff7dd');
        break;
      }
      default: break;
    }
  }

  private drawBand(label: string, width: number, y: number, size: number, color: PachinkoColor, local: number,
    ratio: number): void {
    const bandWidth: number = width * ratio;
    const travel: number = Math.max(0, 1 - local / 130);
    const x: number = (width - bandWidth) / 2 - width * travel * travel;
    this.context.fillStyle = '#211126';
    this.context.fillRect(x, y - size * 0.72, bandWidth, size * 1.44);
    this.context.strokeStyle = color === PachinkoColor.Rainbow ? this.rainbow(this.context, x, bandWidth, local) : color;
    this.context.lineWidth = 4;
    this.context.strokeRect(x, y - size * 0.72, bandWidth, size * 1.44);
    this.drawGoldText(label, x + bandWidth / 2, y, size, bandWidth - 12);
  }

  private drawReelWindow(x: number, y: number, width: number, height: number, position: number,
    rush: boolean, highlighted: boolean): void {
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
    this.context.strokeStyle = rush ? '#ec3d49' : '#ad8740';
    this.context.stroke();
    if (rush) {
      this.context.lineWidth = 1;
      this.context.strokeStyle = '#ffd651';
      this.context.strokeRect(x + 3, y + 3, width - 6, height - 6);
    }
    const first: number = Math.floor(position);
    const offset: number = (position - first) * height;
    const size: number = Math.min(width * 0.78, height * 0.75);
    this.context.font = `900 ${Math.round(size)}vp sans-serif`;
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    this.context.fillStyle = highlighted ? '#ffe16a' : '#fff4d4';
    this.context.fillText(((first % 9 + 9) % 9 + 1).toString(), x + width / 2, y + height / 2 - offset);
    if (offset > 0) {
      this.context.fillText((((first + 1) % 9 + 9) % 9 + 1).toString(), x + width / 2, y + height * 1.5 - offset);
    }
    this.context.restore();
  }

  private drawConfetti(elapsed: number, width: number, height: number, count: number): void {
    for (let index: number = 0; index < count; index++) {
      const fall: number = (elapsed - (index * 97) % 540) / 1250;
      if (fall < 0 || fall > 1) { continue; }
      const drift: number = (index * 63) % 89 - 44;
      const x: number = width * ((index * 379) % 997) / 997 + drift * fall;
      const size: number = 3 + index % 6;
      this.context.save();
      this.context.translate(x, (height + size) * fall - size);
      this.context.rotate(fall * drift / 5);
      this.context.fillStyle = CONFETTI_COLORS[index % CONFETTI_COLORS.length];
      this.context.fillRect(-size / 2, -size / 2, size, size);
      this.context.restore();
    }
  }

  private rainbow(context: CanvasRenderingContext2D, x: number, width: number, elapsed: number): CanvasGradient {
    const gradient: CanvasGradient = context.createLinearGradient(x, 0, x + width, 0);
    const phase: number = (elapsed % 720) / 120;
    const first: number = Math.floor(phase);
    for (let step: number = 0; step < RAINBOW_COLORS.length; step++) {
      const position: number = (step + phase - first) / RAINBOW_COLORS.length;
      const color: number = (step + RAINBOW_COLORS.length - first) % RAINBOW_COLORS.length;
      gradient.addColorStop(position, RAINBOW_COLORS[color]);
    }
    return gradient;
  }

  private drawBall(context: CanvasRenderingContext2D, x: number, y: number, radius: number, color: PachinkoColor,
    elapsed: number): void {
    context.beginPath();
    context.arc(x, y, radius, 0, 2 * Math.PI);
    context.fillStyle = color === PachinkoColor.Rainbow ? this.rainbow(context, x - radius, radius * 2, elapsed) : color;
    context.fill();
    context.lineWidth = 1;
    context.strokeStyle = '#2c202e';
    context.stroke();
  }

  private drawHolds(elapsed: number): void {
    if (!this.holdReady) { return; }
    const context: CanvasRenderingContext2D = this.holdContext;
    const width: number = context.width;
    context.clearRect(0, 0, width, context.height);
    const label: string = this.rushEnding ? 'RUSH 終了' :
      this.rushRemaining > 0 ? 'RUSH 残り ' + this.rushRemaining.toString() : '';
    context.font = 'bold 12vp sans-serif';
    const textWidth: number = label === '' ? 0 : context.measureText(label).width;
    const gap: number = this.holds.length > 0 && label !== '' ? 6 : 0;
    const span: number = Math.max(0, this.holds.length * 15 - 5);
    const x: number = (width - span - gap - textWidth) / 2;
    for (let index: number = 0; index < this.holds.length; index++) {
      this.drawBall(context, x + index * 15 + 5, 11, 5, this.holds[index].displayColor, elapsed);
    }
    if (label !== '') {
      context.textBaseline = 'middle';
      context.textAlign = 'left';
      context.strokeStyle = '#4f1721';
      context.lineWidth = 3;
      context.strokeText(label, x + span + gap, 11);
      context.fillStyle = '#ffdb65';
      context.fillText(label, x + span + gap, 11);
    }
  }

  private drawGoldText(label: string, x: number, y: number, size: number, maxWidth: number, color: string = '#ffdc58'): void {
    if (size <= 0 || maxWidth <= 0) { return; }
    this.context.save();
    this.context.font = `900 ${Math.round(size)}vp sans-serif`;
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
    this.context.fillStyle = color;
    this.context.fillText(label, x, y, maxWidth);
    this.context.restore();
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Canvas(this.context).width('100%').height('100%')
        .opacity(this.dimmed ? 0.3 : 1)
        .hitTestBehavior(HitTestMode.None)
        .onReady(() => {
          this.ready = true;
          this.scheduleHold();
        })
      Canvas(this.holdContext).width('100%').height(22)
        .hitTestBehavior(HitTestMode.None)
        .onReady(() => {
          this.holdReady = true;
          this.drawHolds(0);
        })
        .onAreaChange(() => this.drawHolds(0))
    }
      .width('100%').height('100%').clip(true)
      .visibility(this.keysVisible ? Visibility.Visible : Visibility.Hidden)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}
