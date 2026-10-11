/** Platform callbacks are supplied by the key component. */
export interface SpaceGesturePort {
  getEpoch: () => number;
  schedule: (callback: () => void, delayMs: number) => number;
  unschedule: (timer: number) => void;
  tap: () => void;
  move: (direction: string) => Promise<void>;
  feedback: () => void;
  changed: (pressing: boolean, dragging: boolean) => void;
}

const DRAG_STEP: number = 18;
const TAP_SLOP: number = 12;

/** A single held finger owns the gesture until release or cancellation. */
export class SpaceGesture {
  private pressing: boolean = false;
  private dragging: boolean = false;
  private finger: number = -1;
  private epoch: number = -1;
  private timer: number = -1;
  private startX: number = 0;
  private startY: number = 0;
  private latestX: number = 0;
  private originX: number = 0;
  private sentSteps: number = 0;
  private generation: number = 0;
  private port: SpaceGesturePort;

  constructor(port: SpaceGesturePort) { this.port = port; }

  cancel(): void {
    this.generation++;
    if (this.timer >= 0) { this.port.unschedule(this.timer); this.timer = -1; }
    this.pressing = false;
    this.dragging = false;
    this.finger = -1;
    this.epoch = -1;
    this.sentSteps = 0;
    this.port.changed(false, false);
  }

  down(finger: number, x: number, y: number, longPressMs: number): void {
    if (this.finger >= 0) { return; }
    const generation: number = ++this.generation;
    this.finger = finger;
    this.epoch = this.port.getEpoch();
    this.startX = x;
    this.startY = y;
    this.latestX = x;
    this.pressing = true;
    this.dragging = false;
    this.sentSteps = 0;
    this.port.changed(true, false);
    this.timer = this.port.schedule(() => {
      if (generation !== this.generation) { return; }
      this.timer = -1;
      if (!this.pressing || this.epoch !== this.port.getEpoch()) { this.cancel(); return; }
      this.dragging = true;
      this.originX = this.latestX;
      this.port.changed(true, true);
      this.port.feedback();
    }, longPressMs);
  }

  contact(finger: number, x: number, y: number, released: boolean): void {
    if (finger !== this.finger || this.finger < 0) { return; }
    if (this.epoch !== this.port.getEpoch()) { this.cancel(); return; }
    this.latestX = x;
    if (!this.dragging && Math.max(Math.abs(x - this.startX), Math.abs(y - this.startY)) > TAP_SLOP) {
      this.cancel();
      return;
    }
    if (this.dragging) { this.dragTo(x); }
    if (released) {
      const tap: boolean = !this.dragging && this.pressing;
      this.cancel();
      if (tap) { this.port.tap(); }
    }
  }

  private dragTo(x: number): void {
    const target: number = Math.trunc((x - this.originX) / DRAG_STEP);
    const delta: number = target - this.sentSteps;
    if (delta === 0) { return; }
    const step: number = delta < 0 ? -1 : 1;
    const generation: number = this.generation;
    this.port.feedback();
    // Keep the existing per-event limit and submit moves through the IME queue.
    for (let count: number = 0; count < Math.min(16, Math.abs(delta)); count++) {
      this.sentSteps += step;
      this.port.move(step < 0 ? 'left' : 'right').catch(() => {
        // A late failure from an old gesture must not cancel the next gesture.
        if (generation === this.generation) { this.cancel(); }
      });
    }
  }
}
