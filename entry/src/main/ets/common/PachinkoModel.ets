export enum PachinkoResult {
  Miss, Reach, Jackpot
}

export function drawPachinko(random: () => number): PachinkoResult {
  const roll: number = random();
  if (roll < 1 / 64) { return PachinkoResult.Jackpot; }
  // The next eight of the 64 equal intervals belong to Reach.
  if (roll < 9 / 64) { return PachinkoResult.Reach; }
  return PachinkoResult.Miss;
}

export class PachinkoDraws {
  private remaining: number = 0;

  onCommit(playing: boolean, random: () => number): PachinkoResult {
    if (this.remaining > 0) {
      this.remaining--;
      return PachinkoResult.Miss;
    }
    if (playing) { return PachinkoResult.Miss; }
    const result: PachinkoResult = drawPachinko(random);
    if (result !== PachinkoResult.Miss) { this.remaining = 3; }
    return result;
  }
}

type CommitListener = () => void;

export class ImeCommitNotifications {
  private listener: CommitListener | undefined = undefined;

  listen(listener: CommitListener): void { this.listener = listener; }

  unlisten(listener: CommitListener): void {
    if (this.listener === listener) { this.listener = undefined; }
  }

  emit(): void {
    try {
      this.listener?.();
    } catch (error) {
      // Optional visual feedback cannot turn a successful editor write into a failure.
    }
  }
}

export const imeCommitNotifications: ImeCommitNotifications = new ImeCommitNotifications();
