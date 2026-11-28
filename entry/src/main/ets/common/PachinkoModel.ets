export enum PachinkoResult {
  Miss, Reach, Jackpot
}

export enum PachinkoColor {
  Blue = '#53a9ff', Green = '#48d681', Red = '#ff5965', Gold = '#ffcf42'
}

export enum PachinkoReplay {
  Reach = 'reach', Jackpot = 'jackpot', FourHolds = 'four-holds'
}

export const PACHINKO_HOLD_LIMIT: number = 4;
const PACHINKO_IDLE_MS: number = 800;

export interface PachinkoHold {
  result: PachinkoResult;
  color: PachinkoColor;
}

export interface PachinkoConsumption {
  hold: PachinkoHold;
  remaining: PachinkoHold[];
}

export interface PachinkoStops {
  left: number;
  middle: number;
  right: number;
}

export function drawPachinko(random: () => number): PachinkoResult {
  const roll: number = random();
  if (roll < 1 / 64) { return PachinkoResult.Jackpot; }
  // The next eight of the 64 equal intervals belong to Reach.
  if (roll < 9 / 64) { return PachinkoResult.Reach; }
  return PachinkoResult.Miss;
}

export function drawPachinkoColor(result: PachinkoResult, random: () => number): PachinkoColor {
  const roll: number = random();
  if (result === PachinkoResult.Jackpot) {
    if (roll < 0.3) { return PachinkoColor.Gold; }
    return roll < 0.8 ? PachinkoColor.Red : PachinkoColor.Green;
  }
  if (result === PachinkoResult.Reach) {
    if (roll < 0.2) { return PachinkoColor.Red; }
    return roll < 0.6 ? PachinkoColor.Green : PachinkoColor.Blue;
  }
  return roll < 0.1 ? PachinkoColor.Green : PachinkoColor.Blue;
}

export function enqueuePachinko(holds: PachinkoHold[], random: () => number,
  forcedResult?: PachinkoResult): PachinkoHold[] {
  if (holds.length >= PACHINKO_HOLD_LIMIT) { return holds; }
  const result: PachinkoResult = forcedResult ?? drawPachinko(random);
  const hold: PachinkoHold = { result: result, color: drawPachinkoColor(result, random) };
  return holds.concat(hold);
}

export function pachinkoIdleRemaining(now: number, lastActivity: number): number {
  return Math.max(0, PACHINKO_IDLE_MS - (now - lastActivity));
}

export function consumePachinkoHold(holds: PachinkoHold[], now: number, lastActivity: number): PachinkoConsumption | undefined {
  if (holds.length === 0 || pachinkoIdleRemaining(now, lastActivity) > 0) { return undefined; }
  return { hold: holds[0], remaining: holds.slice(1) };
}

export function pachinkoStops(result: PachinkoResult, random: () => number): PachinkoStops {
  if (result === PachinkoResult.Jackpot) { return { left: 7, middle: 7, right: 7 }; }
  const left: number = 1 + Math.floor(random() * 9);
  if (result === PachinkoResult.Reach) {
    return { left: left, middle: left === 9 ? 8 : left + 1, right: left };
  }
  let right: number = 1 + Math.floor(random() * 8);
  if (right >= left) { right++; }
  let middle: number = 1 + Math.floor(random() * 7);
  if (middle >= Math.min(left, right)) { middle++; }
  if (middle >= Math.max(left, right)) { middle++; }
  return { left: left, middle: middle, right: right };
}

type ImeListener = () => void;

class ImeNotifications {
  private listener: ImeListener | undefined = undefined;

  listen(listener: ImeListener): void { this.listener = listener; }

  unlisten(listener: ImeListener): void {
    if (this.listener === listener) { this.listener = undefined; }
  }

  emit(): void {
    try {
      this.listener?.();
    } catch (error) {
      // Optional visual feedback cannot interrupt input handling.
    }
  }
}

export { ImeNotifications as ImeCommitNotifications };
export const imeCommitNotifications: ImeNotifications = new ImeNotifications();
export const pachinkoKeyNotifications: ImeNotifications = new ImeNotifications();
