export interface KeySoundPort {
  play: (volume: number) => Promise<void>;
}

export class KeyboardSound {
  private port: KeySoundPort;

  constructor(port: KeySoundPort) { this.port = port; }

  key(level: number): void {
    if (level === 0) { return; }
    try {
      this.port.play(level === 2 ? 1 : 0.35).catch(() => {});
    } catch (error) {
      // Optional feedback must never interrupt typing.
    }
  }
}
