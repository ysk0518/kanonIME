// Fast two-thumb typing overlaps presses: "y" is still held when "u" lands and lifts.
// Character keys enter on release, so without help the order becomes s, u, y and
// romaji "syu" turns into "すy". Like Samsung and Gboard, a key that is still held
// when another key lands is entered at that moment, and its own release then does
// nothing.
export class KeyRollover {
  private held: (() => void) | undefined = undefined;

  // Called when a key lands. Enters the key still held, if any, before the new one.
  land(): void {
    const enter: (() => void) | undefined = this.held;
    this.held = undefined;
    if (enter !== undefined) { enter(); }
  }

  // Registers the key just landed; `enter` must enter it exactly once.
  hold(enter: () => void): void {
    this.held = enter;
  }

  // Called on release or cancel. Returns false when the key was already entered
  // early (or replaced), so the caller must not enter it again.
  release(enter: () => void): boolean {
    if (this.held !== enter) { return false; }
    this.held = undefined;
    return true;
  }
}

export const keyRollover: KeyRollover = new KeyRollover();
