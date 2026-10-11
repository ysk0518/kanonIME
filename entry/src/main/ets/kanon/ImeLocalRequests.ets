import { ImeSnapshot } from './ImeCoordinator';
import { InputEvent } from './InputEventTypes';
import { languageLayouts, layoutLanguage, nextLanguageLayout } from '../common/KeyboardConfigValues';

export interface PrepareLayoutRequest { kind: 'prepare'; }
export interface CycleLayoutRequest { kind: 'cycle'; }
export interface LayoutConfigRequest { kind: 'config'; layoutOrder: string; }
export type ImeLocalRequest = PrepareLayoutRequest | CycleLayoutRequest | LayoutConfigRequest;

export interface ImeLocalRequestPort {
  getEpoch: () => number;
  snapshot: () => ImeSnapshot;
  configuredOrder: () => string;
  currentLayout: () => string;
  flickEnabled: () => boolean;
  dispatch: (event: InputEvent) => Promise<void>;
  submit: () => Promise<ImeSnapshot>;
  resetComposition: () => void;
  applyLayout: (layout: string) => void;
  saveOrder: (order: string) => Promise<void>;
  publish: (snapshot: ImeSnapshot) => void;
}

/** Local operations use the caller's input queue; editing stays in Coordinator. */
export class ImeLocalRequests {
  private port: ImeLocalRequestPort;
  constructor(port: ImeLocalRequestPort) { this.port = port; }

  /** Resolve a toggle only after entering the same queue as text input. */
  toggleOrder(): string {
    if (!this.port.flickEnabled()) { return ''; }
    const current: string = this.port.currentLayout();
    const flick: boolean = !current.endsWith('_flick');
    return languageLayouts(this.port.configuredOrder()).map((id: string) =>
      `${layoutLanguage(id) === 'EN' ? 'en' : 'jp'}_${flick ? 'flick' : 'qwerty'}`).join(',');
  }

  async handle(request: ImeLocalRequest, epoch: number): Promise<ImeSnapshot> {
    if (epoch !== this.port.getEpoch()) { return this.port.snapshot(); }
    const configured: string = this.port.configuredOrder();
    const current: string = this.port.currentLayout();
    const order: string[] = languageLayouts(request.kind === 'config' ? request.layoutOrder : configured)
      .map((id: string) => this.port.flickEnabled() ? id :
        `${layoutLanguage(id) === 'EN' ? 'en' : 'jp'}_qwerty`);
    const target: string = request.kind === 'cycle' ? nextLanguageLayout(order.join(','), current) :
      (order.find((id: string) => layoutLanguage(id) === layoutLanguage(current)) ?? order[0]);
    if (target !== current || this.port.snapshot().mode !== layoutLanguage(target)) {
      await this.port.dispatch({ kind: 'mode', text: layoutLanguage(target) === 'EN' ? 'EN' : 'JP' });
      const snapshot: ImeSnapshot = this.port.snapshot();
      if (epoch !== this.port.getEpoch()) { return snapshot; }
      if (snapshot.lastError !== 'ok' || snapshot.mode !== layoutLanguage(target)) {
        this.port.publish(snapshot);
        return snapshot;
      }
      this.port.resetComposition();
      this.port.applyLayout(target);
    } else if (request.kind === 'prepare') { return this.port.snapshot(); }
    if (request.kind !== 'cycle' && epoch === this.port.getEpoch() &&
      this.port.configuredOrder() !== order.join(',')) {
      await this.port.saveOrder(order.join(','));
    }
    const snapshot: ImeSnapshot = this.port.snapshot();
    if (epoch === this.port.getEpoch()) { this.port.publish(snapshot); }
    return snapshot;
  }

  /** A failed or obsolete submit must never be followed by a paste. */
  async beforePaste(epoch: number): Promise<boolean> {
    if (epoch !== this.port.getEpoch()) { return false; }
    if (this.port.snapshot().preeditLen === 0) { return true; }
    const committed: ImeSnapshot = await this.port.submit();
    return committed.lastError === 'ok' && epoch === this.port.getEpoch();
  }
}
