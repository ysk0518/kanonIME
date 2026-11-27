import { ColorMetrics } from '@ohos.arkui.node';
import { KANON_GAMING_WAVE_TIME } from './AppStorageKeys';
import { GAMING_FLOW_STEPS, GAMING_GOLD_PHASE, GamingPoint, GamingWaveFrame, GamingWaveSample,
  gamingWaveSample } from './GamingEffectModel';

const RAINBOW_WIDTH: number = 420;

// Each palette keeps the glyphs legible against the corresponding key surface.
const LIGHT_RAINBOW: number[] = [0xb32247, 0x995008, 0x646500, 0x087344, 0x006c91, 0x5943ac];
const DARK_RAINBOW: number[] = [0xff7196, 0xffb272, 0xece36e, 0x6cf1a0, 0x70d9ff, 0xbca0ff];

const NO_WAVE: GamingWaveSample = { intensity: 0, hue: 0 };
const NO_TINT: LinearGradientOptions = { colors: [[Color.Transparent, 0], [Color.Transparent, 1]] };
let waveFrame: GamingWaveFrame | undefined = undefined;
const waveSamples: Map<GamingPoint, GamingWaveSample> = new Map<GamingPoint, GamingWaveSample>();

function waveSample(now: number, center: GamingPoint | undefined): GamingWaveSample {
  const frame: GamingWaveFrame | undefined = waveFrame;
  if (now === 0 || frame === undefined || frame.now !== now || center === undefined) { return NO_WAVE; }
  const cached: GamingWaveSample | undefined = waveSamples.get(center);
  if (cached !== undefined) { return cached; }
  const sample: GamingWaveSample = gamingWaveSample(center, frame);
  waveSamples.set(center, sample);
  return sample;
}

export function gamingKeyCenter(area: Area): GamingPoint {
  const x: number = Number(area.globalPosition.x) + Number(area.width) / 2;
  const y: number = Number(area.globalPosition.y) + Number(area.height) / 2;
  return { x: Number.isFinite(x) ? x : 0, y: Number.isFinite(y) ? y : 0 };
}

export function publishGamingWave(frame: GamingWaveFrame | undefined): void {
  waveFrame = frame;
  waveSamples.clear();
  AppStorage.setOrCreate(KANON_GAMING_WAVE_TIME, frame === undefined ? 0 : frame.now);
}

export function gamingKeyColor(phase: number, now: number, center: GamingPoint | undefined,
  fallback: ResourceColor, pressed: boolean = false): ResourceColor {
  if (phase === GAMING_GOLD_PHASE) {
    try {
      const base: ColorMetrics = ColorMetrics.resourceColor(fallback);
      return base.red + base.green + base.blue > 384 ? '#ffe078' : '#885400';
    } catch (error) { return fallback; }
  }
  const wave: GamingWaveSample = waveSample(now, center);
  if (wave.intensity > 0) {
    try {
      const base: ColorMetrics = ColorMetrics.resourceColor(fallback);
      const palette: number[] = base.red + base.green + base.blue > 384 ? DARK_RAINBOW : LIGHT_RAINBOW;
      const color: number = rainbow(wave.hue, palette, 0);
      const mix: number = wave.intensity;
      return 0xff000000 + (mixChannel(base.red, color >> 16, mix, 0) << 16) +
        (mixChannel(base.green, color >> 8, mix, 0) << 8) + mixChannel(base.blue, color, mix, 0);
    } catch (error) { return fallback; }
  }
  return flowColor(phase, center?.x ?? 0, fallback, pressed);
}

function flowColor(phase: number, x: number, fallback: ResourceColor, pressed: boolean): ResourceColor {
  if (phase < 0) { return fallback; }
  const dark: boolean = phase >= GAMING_FLOW_STEPS;
  const palette: number[] = dark ? DARK_RAINBOW : LIGHT_RAINBOW;
  const offset: number = x / RAINBOW_WIDTH - (phase % GAMING_FLOW_STEPS) / GAMING_FLOW_STEPS;
  return 0xff000000 + rainbow(offset, palette, pressed && dark ? 45 : 0);
}

function rainbow(offset: number, palette: number[], glow: number): number {
  const hue: number = (offset - Math.floor(offset)) * palette.length;
  const index: number = Math.floor(hue);
  const mix: number = hue - index;
  const first: number = palette[index];
  const second: number = palette[(index + 1) % palette.length];
  const red: number = mixChannel(first >> 16, second >> 16, mix, glow);
  const green: number = mixChannel(first >> 8, second >> 8, mix, glow);
  const blue: number = mixChannel(first, second, mix, glow);
  return (red << 16) + (green << 8) + blue;
}

function mixChannel(first: number, second: number, mix: number, glow: number): number {
  return Math.min(255, Math.round((first & 255) * (1 - mix) + (second & 255) * mix) + glow);
}

export function gamingKeyOutline(phase: number, now: number, center: GamingPoint | undefined,
  radius: number, pressed: boolean = false): OutlineOptions {
  if (phase === GAMING_GOLD_PHASE) { return { width: 2, color: '#e7ab29', radius: radius }; }
  const wave: GamingWaveSample = waveSample(now, center);
  if (wave.intensity > 0) {
    return { width: 2, color: waveColor(wave, 255), radius: radius };
  }
  const outlinePhase: number = pressed && phase >= 0 ? phase % GAMING_FLOW_STEPS + GAMING_FLOW_STEPS : phase;
  return {
    width: phase < 0 ? 0 : pressed ? 2 : 1,
    color: flowColor(outlinePhase, center?.x ?? 0, Color.Transparent, pressed),
    radius: radius
  };
}

export function gamingKeyTint(now: number, center: GamingPoint | undefined): LinearGradientOptions {
  const wave: GamingWaveSample = waveSample(now, center);
  if (wave.intensity <= 0) { return NO_TINT; }
  // A flat translucent layer follows the key surface, including its pressed background.
  const tint: number = waveColor(wave, 54);
  return { colors: [[tint, 0], [tint, 1]] };
}

function waveColor(wave: GamingWaveSample, alpha: number): number {
  return Math.round(alpha * wave.intensity) * 0x1000000 + rainbow(wave.hue, DARK_RAINBOW, 0);
}

type GamingPressListener = (x: number, y: number, area: Area) => void;

class GamingPresses {
  private listener: GamingPressListener | undefined = undefined;

  listen(listener: GamingPressListener): void { this.listener = listener; }

  unlisten(listener: GamingPressListener): void {
    if (this.listener === listener) { this.listener = undefined; }
  }

  down(event: TouchEvent): void {
    if (this.listener === undefined || event.type !== TouchType.Down) { return; }
    const point: TouchObject | undefined = event.changedTouches[0];
    // Use the pressed key's layout position plus the touch inside it: the same
    // coordinate space as the overlay's globalPosition. Window coordinates do
    // not match it because the keyboard root is anchored to the window bottom.
    if (point !== undefined) {
      const area: Area = event.target.area;
      const origin: Position = area.globalPosition;
      this.listener(Number(origin.x ?? 0) + point.x, Number(origin.y ?? 0) + point.y, area);
    }
  }
}

export const gamingPresses: GamingPresses = new GamingPresses();

export function gamingControlPressed(event: TouchEvent, phase: number, pressed: boolean): boolean {
  gamingPresses.down(event);
  if (phase < 0 || event.type === TouchType.Up || event.type === TouchType.Cancel) { return false; }
  return event.type === TouchType.Down || pressed;
}
