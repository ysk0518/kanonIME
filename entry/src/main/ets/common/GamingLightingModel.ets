import { GAMING_FLOW_PALETTE_OFFSET, GAMING_FLOW_STEPS } from './GamingEffectModel';

export type GamingPalette = 'rainbow' | 'flame' | 'ice' | 'neon' | 'sakura' | 'solid';

export const DEFAULT_GAMING_PALETTE: GamingPalette = 'rainbow';
export const DEFAULT_GAMING_SOLID_COLOR: number = 0x32d2ff;
export const GAMING_PALETTES: GamingPalette[] = ['rainbow', 'flame', 'ice', 'neon', 'sakura', 'solid'];
export const GAMING_SOLID_COLORS: number[] = [
  0xff3b30, 0xff9500, 0xffd60a, 0x34c759, DEFAULT_GAMING_SOLID_COLOR, 0x0a84ff, 0xbf5af2, 0xffffff
];

// Keep the original rainbow colors for the keyboard and fever flashes.
const LIGHT_RAINBOW: number[] = [0xb32247, 0x995008, 0x646500, 0x087344, 0x006c91, 0x5943ac];
const DARK_RAINBOW: number[] = [0xff7196, 0xffb272, 0xece36e, 0x6cf1a0, 0x70d9ff, 0xbca0ff];
const RAINBOW_RINGS: number[] = [0xff7299, 0xfff17c, 0x65efae, 0x72c9ff, 0xb78cff];
const FLAME: number[] = [0xff3b30, 0xff9500, 0xffd60a];
const ICE: number[] = [0x3c83ff, 0x54dcff, 0xddf8ff];
const NEON: number[] = [0xff57c8, 0xb05aff, 0x527bff];
const SAKURA: number[] = [0xf29abb, 0xffc9df, 0xffedf4];
// A multiple of the flow step count, anchor counts, and ring count.
const LIGHTING_STEPS: number = 1440;
const LIGHT_SCALE: number = 0.62;
const RAINBOW_WIDTH: number = 420;

export function normalizeGamingPalette(value: string): GamingPalette {
  if (value === 'flame' || value === 'ice' || value === 'neon' || value === 'sakura' || value === 'solid') {
    return value;
  }
  return DEFAULT_GAMING_PALETTE;
}

export function normalizeGamingSolidColor(value: number): number {
  return GAMING_SOLID_COLORS.includes(value) ? value : DEFAULT_GAMING_SOLID_COLOR;
}

export function mixGamingChannel(first: number, second: number, mix: number, glow: number = 0): number {
  return Math.min(255, Math.round((first & 255) * (1 - mix) + (second & 255) * mix) + glow);
}

function scaleRgb(rgb: number, brightness: number): number {
  return (Math.round((rgb >> 16) * brightness) << 16) +
    (Math.round(((rgb >> 8) & 255) * brightness) << 8) + Math.round((rgb & 255) * brightness);
}

export function gamingLightingAnchors(palette: GamingPalette, solid: number, dark: boolean): number[] {
  let anchors: number[];
  switch (palette) {
    case 'flame': anchors = FLAME; break;
    case 'ice': anchors = ICE; break;
    case 'neon': anchors = NEON; break;
    case 'sakura': anchors = SAKURA; break;
    case 'solid':
      anchors = [solid, scaleRgb(solid, 0.7)];
      break;
    default: return (dark ? DARK_RAINBOW : LIGHT_RAINBOW).slice();
  }
  return dark ? anchors.slice() : anchors.map((rgb: number) => scaleRgb(rgb, LIGHT_SCALE));
}

export function gamingLightingRgb(anchors: number[], phase: number, glow: number = 0): number {
  const hue: number = (phase - Math.floor(phase)) * anchors.length;
  const step: number = Math.floor(hue);
  const index: number = step === anchors.length ? 0 : step;
  const mix: number = hue - step;
  const first: number = anchors[index];
  const second: number = anchors[(index + 1) % anchors.length];
  return (mixGamingChannel(first >> 16, second >> 16, mix, glow) << 16) +
    (mixGamingChannel(first >> 8, second >> 8, mix, glow) << 8) + mixGamingChannel(first, second, mix, glow);
}

function lightingTable(anchors: number[], glow: number = 0): number[] {
  const colors: number[] = [];
  for (let step: number = 0; step < LIGHTING_STEPS; step++) {
    colors.push(gamingLightingRgb(anchors, step / LIGHTING_STEPS, glow));
  }
  return colors;
}

export class GamingLightingColors {
  private palette: GamingPalette = DEFAULT_GAMING_PALETTE;
  private solid: number = DEFAULT_GAMING_SOLID_COLOR;
  private light: number[] = [];
  private dark: number[] = [];
  private pressedDark: number[] = [];
  private lightRings: number[] = RAINBOW_RINGS;
  private darkRings: number[] = RAINBOW_RINGS;

  configure(palette: GamingPalette, solid: number): void {
    if (this.palette === palette && this.solid === solid) { return; }
    this.palette = palette;
    this.solid = solid;
    if (palette === 'rainbow') {
      this.light = [];
      this.dark = [];
      this.pressedDark = [];
      this.lightRings = RAINBOW_RINGS;
      this.darkRings = RAINBOW_RINGS;
      return;
    }
    this.light = lightingTable(gamingLightingAnchors(palette, solid, false));
    const anchors: number[] = gamingLightingAnchors(palette, solid, true);
    this.dark = lightingTable(anchors);
    this.pressedDark = palette === 'solid' ? this.dark : lightingTable(anchors, 45);
    this.lightRings = this.ringSamples(this.light);
    this.darkRings = this.ringSamples(this.dark);
  }

  usesRainbow(): boolean { return this.palette === 'rainbow'; }

  flowRgb(phase: number, x: number, pressed: boolean, outline: boolean): number {
    const flow: boolean = phase >= GAMING_FLOW_PALETTE_OFFSET;
    const themePhase: number = flow ? phase - GAMING_FLOW_PALETTE_OFFSET : phase;
    const dark: boolean = (outline && pressed) || themePhase >= GAMING_FLOW_STEPS;
    const offset: number = x / RAINBOW_WIDTH - (phase % GAMING_FLOW_STEPS) / GAMING_FLOW_STEPS;
    return this.phaseRgb(offset, dark, pressed, flow);
  }

  phaseRgb(phase: number, dark: boolean, pressed: boolean = false, useSelectedPalette: boolean = true): number {
    if (!useSelectedPalette || this.usesRainbow()) {
      return gamingLightingRgb(dark ? DARK_RAINBOW : LIGHT_RAINBOW, phase, pressed && dark ? 45 : 0);
    }
    const colors: number[] = dark ? (pressed ? this.pressedDark : this.dark) : this.light;
    return colors[Math.round((phase - Math.floor(phase)) * LIGHTING_STEPS) % LIGHTING_STEPS];
  }

  ringRgb(dark: boolean): number[] { return dark ? this.darkRings : this.lightRings; }

  private ringSamples(colors: number[]): number[] {
    return RAINBOW_RINGS.map((_rgb: number, index: number) => colors[index * LIGHTING_STEPS / RAINBOW_RINGS.length]);
  }
}

export const gamingLightingColors: GamingLightingColors = new GamingLightingColors();

