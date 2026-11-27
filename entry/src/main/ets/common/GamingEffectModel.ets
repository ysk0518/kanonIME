export type GamingEffect = 'off' | 'flow' | 'wave' | 'ripple' | 'pachinko';

export const DEFAULT_GAMING_UNLOCKED: boolean = false;
export const DEFAULT_GAMING_EFFECT: GamingEffect = 'off';
export const GAMING_EFFECTS: GamingEffect[] = ['off', 'flow', 'wave', 'ripple', 'pachinko'];
export const MIN_GAMING_SPEED: number = 1;
export const MAX_GAMING_SPEED: number = 5;
export const DEFAULT_GAMING_SPEED: number = 3;
export const GAMING_FLOW_STEPS: number = 36;
export const GAMING_GOLD_PHASE: number = -2;
export const GAMING_WAVE_TICK_MS: number = 50;
export const GAMING_RIPPLE_MS: number = 400;
const FLOW_PERIODS_MS: number[] = [7200, 5400, 3600, 2400, 1600];

export function gamingEffect(value: string): GamingEffect {
  if (value === 'flow' || value === 'wave' || value === 'ripple' || value === 'pachinko') { return value; }
  return DEFAULT_GAMING_EFFECT;
}

export function validGamingSpeed(value: number): boolean {
  return Number.isInteger(value) && value >= MIN_GAMING_SPEED && value <= MAX_GAMING_SPEED;
}

export function gamingSpeedEnabled(effect: GamingEffect): boolean {
  return effect === 'flow' || effect === 'wave' || effect === 'ripple';
}

export function gamingFlowPeriodMs(speed: number): number {
  const level: number = validGamingSpeed(speed) ? speed : DEFAULT_GAMING_SPEED;
  return FLOW_PERIODS_MS[level - MIN_GAMING_SPEED];
}

export function gamingFlowStep(elapsed: number, speed: number): number {
  const period: number = gamingFlowPeriodMs(speed);
  return Math.floor(Math.max(0, elapsed) % period * GAMING_FLOW_STEPS / period);
}

export function gamingSpreadDurationMs(speed: number): number {
  return Math.round(GAMING_RIPPLE_MS * gamingFlowPeriodMs(speed) / gamingFlowPeriodMs(DEFAULT_GAMING_SPEED));
}

export enum GamingTapResult {
  Quiet, ThreeLeft, TwoLeft, OneLeft, Unlock, AlreadyUnlocked
}

export class GamingUnlockTaps {
  private count: number = 0;
  private lastTap: number = 0;

  reset(): void { this.count = 0; }

  tap(now: number, unlocked: boolean): GamingTapResult {
    if (unlocked) { return GamingTapResult.AlreadyUnlocked; }
    if (now - this.lastTap >= 2000) { this.reset(); }
    this.lastTap = now;
    this.count++;
    switch (this.count) {
      case 4: return GamingTapResult.ThreeLeft;
      case 5: return GamingTapResult.TwoLeft;
      case 6: return GamingTapResult.OneLeft;
      case 7:
        this.reset();
        return GamingTapResult.Unlock;
      default: return GamingTapResult.Quiet;
    }
  }
}

const MAX_RIPPLES: number = 8;

export interface GamingRipple {
  id: number;
  x: number;
  y: number;
  startedAt: number;
  duration: number;
  bandWidth: number;
}

export class GamingRipples {
  private rings: GamingRipple[] = [];
  private nextId: number = 0;

  activeAt(now: number): GamingRipple[] {
    this.rings = this.rings.filter((ring: GamingRipple) => now - ring.startedAt < ring.duration);
    return this.rings.slice();
  }

  add(x: number, y: number, now: number, duration: number = GAMING_RIPPLE_MS, bandWidth: number = 0): GamingRipple[] {
    this.activeAt(now);
    if (this.rings.length >= MAX_RIPPLES) { this.rings.shift(); }
    const ring: GamingRipple = { id: this.nextId++, x: x, y: y, startedAt: now, duration: duration, bandWidth: bandWidth };
    this.rings.push(ring);
    return this.rings.slice();
  }

  remove(id: number): GamingRipple[] {
    this.rings = this.rings.filter((ring: GamingRipple) => ring.id !== id);
    return this.rings.slice();
  }
}

export interface GamingPoint {
  x: number;
  y: number;
}

export interface GamingWaveSample {
  intensity: number;
  hue: number;
}

export interface GamingWaveFrame {
  presses: GamingRipple[];
  previous: number;
  now: number;
  maxRadius: number;
}

export function gamingWaveSample(center: GamingPoint, frame: GamingWaveFrame): GamingWaveSample {
  const sample: GamingWaveSample = { intensity: 0, hue: 0 };
  for (const press of frame.presses) {
    const elapsed: number = frame.now - press.startedAt;
    const previous: number = Math.max(0, frame.previous - press.startedAt);
    if (elapsed < 0 || previous >= press.duration) { continue; }
    const dx: number = center.x - press.x;
    const dy: number = center.y - press.y;
    const distance: number = Math.sqrt(dx * dx + dy * dy);
    if (distance >= frame.maxRadius) { continue; }
    // Sample the swept band so a ring faster than one key per frame still lights that key.
    const inner: number = frame.maxRadius * previous / press.duration;
    const outer: number = frame.maxRadius * Math.min(1, elapsed / press.duration);
    const gap: number = Math.max(0, inner - distance, distance - outer);
    const intensity: number = 1 - 2 * gap / press.bandWidth;
    if (intensity > sample.intensity) {
      sample.intensity = intensity;
      sample.hue = distance / frame.maxRadius + Math.min(1, elapsed / press.duration) * 0.5;
    }
  }
  return sample;
}
