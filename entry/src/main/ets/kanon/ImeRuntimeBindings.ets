import {
  INPUT_PATTERN, KANON_CANDIDATES_EXPANDED, KANON_CURSOR, KANON_LAST_LAYOUT, KANON_LAYOUT,
  KANON_LAYOUT_ORDER, KANON_MODE
} from '../common/AppStorageKeys';
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
  toggleInputEnabled: () => boolean;
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
  currentLayout(): string { return this.port.readString(KANON_LAYOUT) ?? 'jp_flick'; }
  configuredOrder(): string { return this.port.readString(KANON_LAYOUT_ORDER) ?? DEFAULT_LAYOUT_ORDER; }
  matchesConfiguredOrder(order: string): boolean { return this.port.readString(KANON_LAYOUT_ORDER) === order; }
  displayedMode(fallback: string): string { return this.port.readString(KANON_MODE) ?? fallback; }
  flickEnabled(): boolean { return this.port.flickEnabled(); }
  toggleInputEnabled(): boolean { return this.port.toggleInputEnabled(); }
  predictionAllowed(): boolean {
    const pattern: number = this.port.readNumber(INPUT_PATTERN) ?? this.normal;
    return pattern !== this.password && pattern !== this.numberPassword && pattern !== this.newPassword;
  }
  applyLayout(layout: string): void {
    this.port.string(KANON_LAYOUT, layout);
    this.port.string(KANON_LAST_LAYOUT, layout);
    this.closeCandidates();
  }
  closeCandidates(): void {
    this.port.boolean(KANON_CANDIDATES_EXPANDED, false);
  }
  async saveOrder(order: string): Promise<void> { await this.port.saveLayoutOrder(order); }
  async updateCursor(): Promise<void> {
    const epoch: number = this.port.getEpoch();
    try {
      const position: number = await this.port.queryCursor();
      if (epoch === this.port.getEpoch()) { this.port.number(KANON_CURSOR, position); }
    } catch (error) { }
  }
}
