import { DEFAULT_LAYOUT_ORDER } from '../common/KeyboardConfigValues';

export interface ImeInputPatterns {
  normal: number;
  password: number;
  numberPassword: number;
  newPassword: number;
}

export interface ImeRuntimeBindingsPort {
  readString: (key: string) => string | undefined;
  readNumber: (key: string) => number | undefined;
  string: (key: string, value: string) => void;
  number: (key: string, value: number) => void;
  boolean: (key: string, value: boolean) => void;
  flickEnabled: () => boolean;
  saveLayoutOrder: (order: string) => Promise<void>;
  getEpoch: () => number;
  queryCursor: () => Promise<number>;
}

/** Runtime configuration/display access; no editing or platform globals. */
export class ImeRuntimeBindings {
  private port: ImeRuntimeBindingsPort;
  private normal: number;
  private password: number;
  private numberPassword: number;
  private newPassword: number;
  constructor(port: ImeRuntimeBindingsPort, patterns: ImeInputPatterns) {
    this.port = port;
    this.normal = patterns.normal;
    this.password = patterns.password;
    this.numberPassword = patterns.numberPassword;
    this.newPassword = patterns.newPassword;
  }
  currentLayout(): string { return this.port.readString('kanonLayout') ?? 'jp_flick'; }
  configuredOrder(): string { return this.port.readString('kanonLayoutOrder') ?? DEFAULT_LAYOUT_ORDER; }
  matchesConfiguredOrder(order: string): boolean { return this.port.readString('kanonLayoutOrder') === order; }
  displayedMode(fallback: string): string { return this.port.readString('kanonMode') ?? fallback; }
  flickEnabled(): boolean { return this.port.flickEnabled(); }
  predictionAllowed(): boolean {
    const pattern: number = this.port.readNumber('inputPattern') ?? this.normal;
    return pattern !== this.password && pattern !== this.numberPassword && pattern !== this.newPassword;
  }
  applyLayout(layout: string): void {
    this.port.string('kanonLayout', layout);
    this.port.string('kanonLastLayout', layout);
    this.port.boolean('kanonCandidatesExpanded', false);
  }
  async saveOrder(order: string): Promise<void> { await this.port.saveLayoutOrder(order); }
  async updateCursor(): Promise<void> {
    const epoch: number = this.port.getEpoch();
    try {
      const position: number = await this.port.queryCursor();
      if (epoch === this.port.getEpoch()) { this.port.number('kanonCursor', position); }
    } catch (error) { }
  }
}
