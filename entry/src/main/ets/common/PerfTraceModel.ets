export function perfMessage(event: string, wallMs: number, detail: string): string {
  return `P63 ${event} ${wallMs} ${detail.length > 0 ? detail : '-'}`;
}

/** A panel can reuse its last root layout when shown at the same size. */
export class PerfKeyboardFrame {
  private laidOut: boolean = false;
  private visible: boolean = false;
  private emitted: boolean = false;

  show(): boolean {
    this.visible = true;
    return this.takeFrame();
  }

  layout(width: number, height: number): boolean {
    this.laidOut = width > 0 && height > 0;
    return this.takeFrame();
  }

  hide(): void {
    this.visible = false;
    this.emitted = false;
  }

  reset(): void {
    this.hide();
    this.laidOut = false;
  }

  private takeFrame(): boolean {
    if (!this.visible || !this.laidOut || this.emitted) { return false; }
    this.emitted = true;
    return true;
  }
}
