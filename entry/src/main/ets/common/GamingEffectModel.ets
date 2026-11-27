export type GamingEffect = 'off' | 'flow' | 'ripple';

export const DEFAULT_GAMING_UNLOCKED: boolean = false;
export const DEFAULT_GAMING_EFFECT: GamingEffect = 'off';
export const GAMING_EFFECTS: GamingEffect[] = ['off', 'flow', 'ripple'];

export function gamingEffect(value: string): GamingEffect {
  if (value === 'flow' || value === 'ripple') { return value; }
  return DEFAULT_GAMING_EFFECT;
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

export const GAMING_RIPPLE_MS: number = 400;
const MAX_RIPPLES: number = 8;

export interface GamingRipple {
  id: number;
  x: number;
  y: number;
  startedAt: number;
}

export class GamingRipples {
  private rings: GamingRipple[] = [];
  private nextId: number = 0;

  add(x: number, y: number, now: number): GamingRipple[] {
    this.rings = this.rings.filter((ring: GamingRipple) => now - ring.startedAt < GAMING_RIPPLE_MS);
    if (this.rings.length >= MAX_RIPPLES) { this.rings.shift(); }
    this.rings.push({ id: this.nextId++, x: x, y: y, startedAt: now });
    return this.rings.slice();
  }

  remove(id: number): GamingRipple[] {
    this.rings = this.rings.filter((ring: GamingRipple) => ring.id !== id);
    return this.rings.slice();
  }
}
