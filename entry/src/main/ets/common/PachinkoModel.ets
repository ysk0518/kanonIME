export enum PachinkoResult {
  Miss, Reach, Jackpot
}

export enum PachinkoColor {
  White = '#f7f3ed', Blue = '#53a9ff', Green = '#48d681', Red = '#ff5965', Gold = '#ffcf42', Rainbow = 'rainbow'
}

export enum PachinkoReach {
  Normal, SP, SPSP, FullRotation, Revival
}

export enum PachinkoReplay {
  Normal = 'reach', SP = 'sp', SPSP = 'spsp', FullRotation = 'full-rotation', Revival = 'revival',
  Rush = 'jackpot', FourHolds = 'four-holds'
}

export const PACHINKO_HOLD_LIMIT: number = 4;
const PACHINKO_IDLE_MS: number = 800;
const PACHINKO_RUSH_LENGTH: number = 8;

// Integer weights keep the cumulative probability boundaries exact.
interface PachinkoTables {
  outcome: number[][];
  color: number[][];
  reach: number[][];
  step: number[][];
  pseudo: number[][];
  cutIn: number[][];
  reveal: number[];
}

export const PACHINKO_TABLES: PachinkoTables = {
  // Jackpot, reach miss, miss. Normal first, then RUSH.
  outcome: [[1, 8, 55], [2, 3, 7]],
  // Other result rows follow PachinkoResult (miss, reach miss, jackpot).
  color: [[92, 7, 1, 0, 0, 0], [54, 25, 15, 5, 1, 0], [25, 15, 15, 25, 15, 5]],
  reach: [[], [70, 25, 5, 0, 0], [8, 30, 50, 4, 8]],
  step: [[90, 7, 3, 0, 0, 0], [40, 20, 20, 15, 5, 0], [15, 5, 10, 25, 30, 15]],
  pseudo: [[97, 3, 0], [70, 25, 5], [30, 35, 35]],
  cutIn: [[], [50, 35, 15, 0, 0], [5, 15, 45, 30, 5]],
  reveal: [60, 40]
};

export const PACHINKO_COLORS: PachinkoColor[] = [
  PachinkoColor.White, PachinkoColor.Blue, PachinkoColor.Green, PachinkoColor.Red, PachinkoColor.Gold, PachinkoColor.Rainbow
];
const OUTCOMES: PachinkoResult[] = [PachinkoResult.Jackpot, PachinkoResult.Reach, PachinkoResult.Miss];

export interface PachinkoHold {
  result: PachinkoResult;
  displayColor: PachinkoColor;
  trueColor: PachinkoColor;
  digit: number;
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

export function drawPachinkoWeight(weights: number[], random: () => number): number {
  const roll: number = random();
  const total: number = weights.reduce((sum: number, weight: number): number => sum + weight, 0);
  let boundary: number = 0;
  for (let index: number = 0; index < weights.length - 1; index++) {
    boundary += weights[index];
    if (roll < boundary / total) { return index; }
  }
  return weights.length - 1;
}

export function drawPachinko(random: () => number, rushRemaining: number = 0): PachinkoResult {
  return OUTCOMES[drawPachinkoWeight(PACHINKO_TABLES.outcome[rushRemaining > 0 ? 1 : 0], random)];
}

export function drawPachinkoColor(result: PachinkoResult, random: () => number): PachinkoColor {
  return PACHINKO_COLORS[drawPachinkoWeight(PACHINKO_TABLES.color[result], random)];
}

export function enqueuePachinko(holds: PachinkoHold[], random: () => number, rushRemaining: number = 0): PachinkoHold[] {
  if (holds.length >= PACHINKO_HOLD_LIMIT) { return holds; }
  const result: PachinkoResult = drawPachinko(random, rushRemaining);
  const trueColor: PachinkoColor = drawPachinkoColor(result, random);
  const displayColor: PachinkoColor = trueColor !== PachinkoColor.White &&
    drawPachinkoWeight(PACHINKO_TABLES.reveal, random) === 1 ? PachinkoColor.White : trueColor;
  const digit: number = result === PachinkoResult.Jackpot ? pachinkoDigit(random) : 0;
  const hold: PachinkoHold = { result: result, trueColor: trueColor, displayColor: displayColor, digit: digit };
  return holds.concat(hold);
}

export function pachinkoIdleRemaining(now: number, lastActivity: number): number {
  return Math.max(0, PACHINKO_IDLE_MS - (now - lastActivity));
}

export function consumePachinkoHold(holds: PachinkoHold[], now: number, lastActivity: number): PachinkoConsumption | undefined {
  if (holds.length === 0 || pachinkoIdleRemaining(now, lastActivity) > 0) { return undefined; }
  return { hold: holds[0], remaining: holds.slice(1) };
}

function pachinkoDigit(random: () => number): number {
  return 1 + Math.floor(random() * 9);
}

export function adjacentPachinkoDigit(digit: number, random: () => number): number {
  return (digit + (random() < 0.5 ? 7 : 9)) % 9 + 1;
}

export function pachinkoStops(result: PachinkoResult, random: () => number, jackpotDigit: number = 0): PachinkoStops {
  if (result === PachinkoResult.Jackpot) {
    const digit: number = jackpotDigit || pachinkoDigit(random);
    return { left: digit, middle: digit, right: digit };
  }
  const left: number = pachinkoDigit(random);
  if (result === PachinkoResult.Reach) {
    return { left: left, middle: adjacentPachinkoDigit(left, random), right: left };
  }
  let right: number = 1 + Math.floor(random() * 8);
  if (right >= left) { right++; }
  let middle: number = 1 + Math.floor(random() * 7);
  if (middle >= Math.min(left, right)) { middle++; }
  if (middle >= Math.max(left, right)) { middle++; }
  return { left: left, middle: middle, right: right };
}

export function pachinkoRushAfter(remaining: number, result: PachinkoResult, digit: number): number {
  if (result === PachinkoResult.Jackpot && (remaining > 0 || digit % 2 === 1)) { return PACHINKO_RUSH_LENGTH; }
  return Math.max(0, remaining - 1);
}

export function parsePachinkoReplay(value: string | undefined): PachinkoReplay | undefined {
  switch (value) {
    case PachinkoReplay.Normal: return PachinkoReplay.Normal;
    case PachinkoReplay.SP: return PachinkoReplay.SP;
    case PachinkoReplay.SPSP: return PachinkoReplay.SPSP;
    case PachinkoReplay.FullRotation: return PachinkoReplay.FullRotation;
    case PachinkoReplay.Revival: return PachinkoReplay.Revival;
    case PachinkoReplay.Rush: return PachinkoReplay.Rush;
    case PachinkoReplay.FourHolds: return PachinkoReplay.FourHolds;
    default: return undefined;
  }
}

export function pachinkoReplayHolds(replay: PachinkoReplay): PachinkoHold[] {
  if (replay === PachinkoReplay.FourHolds) {
    return [
      { result: PachinkoResult.Miss, displayColor: PachinkoColor.White, trueColor: PachinkoColor.White, digit: 0 },
      { result: PachinkoResult.Miss, displayColor: PachinkoColor.Blue, trueColor: PachinkoColor.Blue, digit: 0 },
      { result: PachinkoResult.Reach, displayColor: PachinkoColor.White, trueColor: PachinkoColor.Red, digit: 0 },
      { result: PachinkoResult.Jackpot, displayColor: PachinkoColor.Rainbow, trueColor: PachinkoColor.Rainbow, digit: 6 }
    ];
  }
  const jackpot: boolean = replay === PachinkoReplay.FullRotation || replay === PachinkoReplay.Revival ||
    replay === PachinkoReplay.Rush;
  const color: PachinkoColor = jackpot ? PachinkoColor.Gold : PachinkoColor.Green;
  const hold: PachinkoHold = {
    result: jackpot ? PachinkoResult.Jackpot : PachinkoResult.Reach,
    displayColor: color, trueColor: color, digit: jackpot ? 7 : 0
  };
  return [hold];
}

export enum PachinkoStageKind {
  Reveal, Spin, Step, Pseudo, Miss, Tenpai, Normal, SP, SPSP, CutIn, Push, FullRotation, Revival, Jackpot
}

export interface PachinkoStage {
  kind: PachinkoStageKind;
  start: number;
  duration: number;
  level: number;
  color: PachinkoColor;
}

export interface PachinkoScript {
  result: PachinkoResult;
  stages: PachinkoStage[];
  duration: number;
  stops: PachinkoStops;
  leftStop: number;
  rightStop: number;
  middleStop: number;
  revivalDigit: number;
  rush: boolean;
}

function replayReach(replay: PachinkoReplay | undefined): PachinkoReach | undefined {
  switch (replay) {
    case PachinkoReplay.Normal:
    case PachinkoReplay.Rush: return PachinkoReach.Normal;
    case PachinkoReplay.SP: return PachinkoReach.SP;
    case PachinkoReplay.SPSP: return PachinkoReach.SPSP;
    case PachinkoReplay.FullRotation: return PachinkoReach.FullRotation;
    case PachinkoReplay.Revival: return PachinkoReach.Revival;
    default: return undefined;
  }
}

class PachinkoTimeline {
  stages: PachinkoStage[] = [];
  duration: number = 0;

  append(kind: PachinkoStageKind, duration: number, level: number = 0, color: PachinkoColor = PachinkoColor.White): void {
    const stage: PachinkoStage = { kind: kind, start: this.duration, duration: duration, level: level, color: color };
    this.stages.push(stage);
    this.duration += duration;
  }
}

export function buildPachinkoScript(hold: PachinkoHold, rushRemaining: number, holdCount: number,
  random: () => number, replay?: PachinkoReplay): PachinkoScript {
  const result: PachinkoResult = hold.result;
  const stops: PachinkoStops = pachinkoStops(result, random, hold.digit);
  const timeline: PachinkoTimeline = new PachinkoTimeline();
  if (hold.displayColor !== hold.trueColor) { timeline.append(PachinkoStageKind.Reveal, 300, 0, hold.trueColor); }
  timeline.append(PachinkoStageKind.Spin, 400);
  const steps: number = drawPachinkoWeight(PACHINKO_TABLES.step[result], random);
  const repeats: number = drawPachinkoWeight(PACHINKO_TABLES.pseudo[result], random);
  for (let level: number = 1; level <= steps; level++) { timeline.append(PachinkoStageKind.Step, 300, level); }
  for (let count: number = 1; count <= repeats; count++) { timeline.append(PachinkoStageKind.Pseudo, 300, count + 1); }

  let leftStop: number = timeline.duration;
  let rightStop: number = timeline.duration;
  let middleStop: number = timeline.duration;
  let revivalDigit: number = 0;
  if (result === PachinkoResult.Miss) {
    const baseDuration: number = rushRemaining > 0 ? 800 : holdCount >= 3 ? 600 : 1200;
    const tail: number = baseDuration - 400;
    timeline.append(PachinkoStageKind.Miss, tail);
    leftStop += Math.round(tail * 0.25);
    rightStop += Math.round(tail * 0.50);
    middleStop += Math.round(tail * 0.75);
  } else {
    const selected: PachinkoReach = replayReach(replay) ?? drawPachinkoWeight(PACHINKO_TABLES.reach[result], random);
    const reach: PachinkoReach = result === PachinkoResult.Reach && selected >= PachinkoReach.FullRotation ?
      PachinkoReach.Normal : selected;
    leftStop -= 60;
    timeline.append(PachinkoStageKind.Tenpai, 500);
    if (reach === PachinkoReach.FullRotation) {
      timeline.append(PachinkoStageKind.FullRotation, 3000);
    } else if (reach === PachinkoReach.SP || reach === PachinkoReach.SPSP) {
      const extended: boolean = reach === PachinkoReach.SPSP;
      timeline.append(extended ? PachinkoStageKind.SPSP : PachinkoStageKind.SP, extended ? 3600 : 2550);
      const color: PachinkoColor = PACHINKO_COLORS[1 + drawPachinkoWeight(PACHINKO_TABLES.cutIn[result], random)];
      timeline.append(PachinkoStageKind.CutIn, 450, 0, color);
      if (extended) { timeline.append(PachinkoStageKind.Push, 450); }
    } else {
      timeline.append(PachinkoStageKind.Normal, 1500);
      if (reach === PachinkoReach.Revival) {
        revivalDigit = adjacentPachinkoDigit(stops.middle, random);
        middleStop = timeline.duration - 140;
        timeline.append(PachinkoStageKind.Revival, 1500);
      }
    }
    if (revivalDigit === 0) {
      middleStop = timeline.duration - (result === PachinkoResult.Reach ? 140 : 0);
    }
    if (result === PachinkoResult.Jackpot) { timeline.append(PachinkoStageKind.Jackpot, 2000, stops.middle); }
  }
  return {
    result: result, stages: timeline.stages, duration: timeline.duration, stops: stops, leftStop: leftStop,
    rightStop: rightStop, middleStop: middleStop, revivalDigit: revivalDigit, rush: rushRemaining > 0
  };
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
