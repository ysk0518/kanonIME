/* Kanon IME: HarmonyOS runtime bindings and keyboard entry points. */

import { CandidateLabel, OpResult } from './ImeCoordinator';
import { EditorEdge } from './InputEventTypes';
import { fromEditorDirection } from './EditorDirectionMap';
import { SDK_EDITOR_DIRECTIONS } from './SdkEditorDirections';
import { realEditorPort } from './RealEditorPort';
import { MozcEngine } from './MozcEngine';
import { NativeMozcBridge } from './NativeMozcBridge';
import { cancelEditorPreview } from './PreviewLifecycle';
import { ImeViewPublisher } from './ImeViewPublisher';
import { appStorageImeView } from './AppStorageImeView';
import { imeRuntimeBindings } from './AppStorageImeBindings';
import { editorAdapter } from './EditorAdapter';
import { englishPrediction } from './EnglishRuntime';
import { keyboardHaptics } from '../common/KeyboardHaptics';
import Log from '../model/Log';
import { EmptyEditorRead } from './ExternalEditorSync';
import { ImeSession, ImeSessionPorts } from './ImeSession';

/** SDK access stays at the runtime boundary, shared by composing and direct input. */
async function sendEnterAction(epoch: number): Promise<void> {
  if (epoch !== realEditorPort.getEpoch()) { return; }
  const attr = await editorAdapter.queryAttribute();
  if (attr.ok && attr.value !== undefined && epoch === realEditorPort.getEpoch()) {
    await editorAdapter.sendEnterAction(attr.value.enterKeyType);
  }
}

class KanonIme {
  private nativeBridge: NativeMozcBridge = new NativeMozcBridge();
  private ports: ImeSessionPorts = {
    editor: realEditorPort,
    queryEmpty: async (): Promise<EmptyEditorRead> => {
      const result = await editorAdapter.queryEmpty();
      return { ok: result.ok, code: result.code, value: result.value };
    },
    cancelPreview: (): Promise<OpResult> => cancelEditorPreview(realEditorPort),
    bindings: imeRuntimeBindings,
    prediction: englishPrediction,
    viewPublisher: new ImeViewPublisher(appStorageImeView),
    engine: new MozcEngine(this.nativeBridge),
    enterKeyAction: (epoch: number): Promise<void> => sendEnterAction(epoch),
    log: (tag: string, message: string): void => { Log.showInfo(tag, message); }
  };
  private session: ImeSession = new ImeSession(this.ports);

  configureProfile(filesDirectory: string): void {
    this.nativeBridge.configureProfile(filesDirectory);
  }

  async discardTypingText(): Promise<void> {
    await this.session.discardTypingText();
  }

  selectionChanged(begin: number, end: number): void {
    this.session.selectionChanged(begin, end);
  }

  textChanged(empty: boolean): void {
    this.session.textChanged(empty);
  }

  editorVisibilityChanged(): void {
    this.session.editorVisibilityChanged();
  }

  async keyText(ch: string, feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.session.keyText(ch);
  }

  async keyPaste(value: string): Promise<boolean> {
    return this.session.keyPaste(value);
  }

  async keyKana(kana: string): Promise<void> {
    keyboardHaptics.key();
    await this.session.keyKana(kana);
  }

  async modifyKana(): Promise<void> {
    keyboardHaptics.key();
    await this.session.modifyKana();
  }

  async keySpace(feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.session.keySpace();
  }

  async keyReturn(feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.session.keyReturn();
  }

  async keyDelete(feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.session.keyDelete();
  }

  async keyDeleteForward(feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.session.keyDeleteForward();
  }

  async keyUndoEnglish(): Promise<void> {
    await this.session.keyUndoEnglish();
  }

  async keyUndo(): Promise<void> {
    keyboardHaptics.key();
    await this.session.keyUndo();
  }

  forgetJapaneseCommit(): Promise<void> { return this.session.forgetJapaneseCommit(); }

  async keyMove(direction: number, feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.session.keyMove(fromEditorDirection(direction, SDK_EDITOR_DIRECTIONS));
  }

  async keySelectMove(direction: number): Promise<void> {
    keyboardHaptics.key();
    await this.session.keySelectMove(fromEditorDirection(direction, SDK_EDITOR_DIRECTIONS));
  }

  async keySelectEdge(edge: EditorEdge): Promise<void> {
    keyboardHaptics.key();
    await this.session.keySelectEdge(edge);
  }

  async keySelectAll(): Promise<void> {
    keyboardHaptics.key();
    await this.session.keySelectAll();
  }

  async keyMoveBegin(): Promise<void> {
    keyboardHaptics.key();
    await this.session.keyMoveBegin();
  }

  async keyMoveEnd(): Promise<void> {
    keyboardHaptics.key();
    await this.session.keyMoveEnd();
  }

  async selectCandidate(id: number): Promise<void> {
    keyboardHaptics.key();
    await this.session.selectCandidate(id);
  }

  async partialCommit(): Promise<void> {
    keyboardHaptics.key();
    await this.session.partialCommit();
  }

  async cancelCompose(): Promise<void> {
    await this.session.cancelCompose();
  }

  async revertConversion(): Promise<void> {
    await this.session.revertConversion();
  }

  async switchMode(): Promise<void> {
    await this.session.switchMode();
  }

  async toggleLayout(): Promise<boolean> {
    if (!this.session.flickEnabled()) { return false; }
    keyboardHaptics.key();
    return this.session.toggleLayout();
  }

  async prepare(): Promise<void> {
    await this.session.prepare();
  }

  async applyLayoutConfig(value: string): Promise<boolean> {
    return this.session.applyLayoutConfig(value);
  }

  getCandidates(): CandidateLabel[] {
    return this.session.getCandidates();
  }

  getCandidateLabelAt(index: number): string {
    return this.session.getCandidateLabelAt(index);
  }

  getCandidateIdAt(index: number): number {
    return this.session.getCandidateIdAt(index);
  }

  getCandidateSlotCount(): number {
    return this.session.getCandidateSlotCount();
  }

  getCandidateIds(): string {
    return this.session.getCandidateIds();
  }

  getCandidateLens2(): string {
    return this.session.getCandidateLens2();
  }

  getMode(): string {
    return this.session.getMode();
  }
}

export const kanonIme: KanonIme = new KanonIme();
