export const GAMING_FLOW_STEPS: number = 36;
export const GAMING_FLOW_TICK_MS: number = 100;
const RAINBOW_WIDTH: number = 420;

// Each palette keeps the glyphs legible against the corresponding key surface.
const LIGHT_RAINBOW: number[] = [0xb32247, 0x995008, 0x646500, 0x087344, 0x006c91, 0x5943ac];
const DARK_RAINBOW: number[] = [0xff7196, 0xffb272, 0xece36e, 0x6cf1a0, 0x70d9ff, 0xbca0ff];

export function gamingKeyX(area: Area): number {
  const center: number = Number(area.globalPosition.x) + Number(area.width) / 2;
  return Number.isFinite(center) ? center : 0;
}

export function gamingKeyColor(phase: number, x: number, fallback: ResourceColor, pressed: boolean = false): ResourceColor {
  if (phase < 0) { return fallback; }
  const dark: boolean = phase >= GAMING_FLOW_STEPS;
  const palette: number[] = dark ? DARK_RAINBOW : LIGHT_RAINBOW;
  const offset: number = x / RAINBOW_WIDTH - (phase % GAMING_FLOW_STEPS) / GAMING_FLOW_STEPS;
  const hue: number = (offset - Math.floor(offset)) * palette.length;
  const index: number = Math.floor(hue);
  const mix: number = hue - index;
  const first: number = palette[index];
  const second: number = palette[(index + 1) % palette.length];
  const glow: number = pressed && dark ? 45 : 0;
  const red: number = mixChannel(first >> 16, second >> 16, mix, glow);
  const green: number = mixChannel(first >> 8, second >> 8, mix, glow);
  const blue: number = mixChannel(first, second, mix, glow);
  return 0xff000000 + (red << 16) + (green << 8) + blue;
}

function mixChannel(first: number, second: number, mix: number, glow: number): number {
  return Math.min(255, Math.round((first & 255) * (1 - mix) + (second & 255) * mix) + glow);
}

export function gamingKeyOutline(phase: number, x: number, radius: number, pressed: boolean = false): OutlineOptions {
  const outlinePhase: number = pressed && phase >= 0 ? phase % GAMING_FLOW_STEPS + GAMING_FLOW_STEPS : phase;
  return {
    width: phase < 0 ? 0 : pressed ? 2 : 1,
    color: gamingKeyColor(outlinePhase, x, Color.Transparent, pressed),
    radius: radius
  };
}

type GamingPressListener = (x: number, y: number) => void;

class GamingPresses {
  private listener: GamingPressListener | undefined = undefined;

  listen(listener: GamingPressListener): void { this.listener = listener; }

  unlisten(listener: GamingPressListener): void {
    if (this.listener === listener) { this.listener = undefined; }
  }

  down(event: TouchEvent): void {
    if (this.listener === undefined || event.type !== TouchType.Down) { return; }
    const point: TouchObject | undefined = event.changedTouches[0];
    if (point !== undefined) { this.listener(point.windowX, point.windowY); }
  }
}

export const gamingPresses: GamingPresses = new GamingPresses();

export function gamingControlPressed(event: TouchEvent, phase: number, pressed: boolean): boolean {
  gamingPresses.down(event);
  if (phase < 0 || event.type === TouchType.Up || event.type === TouchType.Cancel) { return false; }
  return event.type === TouchType.Down || pressed;
}
