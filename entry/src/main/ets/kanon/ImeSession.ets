/*
 * Kanon IME: ImeSession (M4)
 * Serializes input operations and coordinates editor state.
 * - 入力先の世代変化を検出してonEditorChangedする。旧欄への書込はCoordinatorが遮断する。
 * - 未確定previewは全体置換で更新し、候補確定時は1回だけinsertする。
 * - ログは符号・件数・長さのみ。本文・候補は扱わない（REQ-07）。
 */

import { CandidateLabel, EditorPort, ImeCoordinator, ImeSnapshot, OpResult } from './ImeCoordinator';
import { EditorDirection, EditorEdge, InputEvent, KanaModifier, UiEvent, UiEventKind } from './InputEventTypes';
import { MozcEngine } from './MozcEngine';
import { CompositionPreview, CompositionPreviewPort } from './CompositionPreview';
import { CompositionCursorSync, CompositionCursorPort, CompositionCursorResult } from './CompositionCursorSync';
import { EmptyEditorRead, ExternalEditorPort, ExternalEditorResult, ExternalEditorSync } from './ExternalEditorSync';
import { createInputEvent, resolveInputMovement } from './InputEventContract';
import { InputOperationQueue } from './InputOperationQueue';
import { ImeViewPublisher } from './ImeViewPublisher';
import { ImeCandidateSource, ImeJapaneseViewSource, ImePresentation } from './ImePresentation';
import { EnglishEngine } from './EnglishEngine';
import { EnglishCompletionContext, EnglishCompletionLifecycle, EnglishCompletionPort,
  EnglishUndoResult } from './EnglishCompletionLifecycle';
import { DirectEnglishConversion, DirectEnglishInput, DirectEnglishPort } from './DirectEnglishInput';
import { ImeLocalRequest, ImeLocalRequestPort, ImeLocalRequests } from './ImeLocalRequests';
import { layoutLanguage, languageLayouts } from '../common/KeyboardConfigValues';
import { EnglishPrediction } from './EnglishPrediction';
import { ImeRuntimeBindings } from './ImeRuntimeBindings';
import { ToggleRun, toggleCycle } from './ToggleInput';

export interface ImeSessionPorts {
  editor: EditorPort;
  queryEmpty: () => Promise<EmptyEditorRead>;
  cancelPreview: () => Promise<OpResult>;
  bindings: ImeRuntimeBindings;
  prediction: EnglishPrediction;
  viewPublisher: ImeViewPublisher;
  engine: MozcEngine;
  enterKeyAction: (epoch: number) => Promise<void>;
  log: (tag: string, message: string) => void;
}

interface EnglishUndoRequest { kind: 'undoEnglish'; }
interface RevertConversionRequest { kind: 'revertConversion'; }
export type CandidateDeletionResult = 'deleted' | 'not-learned' | 'failed';
interface DeleteLearnedCandidateRequest {
  kind: 'deleteLearnedCandidate';
  candidate: CandidateLabel;
  result: CandidateDeletionResult;
}
interface ToggleTapRequest { kind: 'toggleTap'; key: string; uppercase: boolean; time: number; }
interface ToggleRightRequest { kind: 'toggleRight'; time: number; }
interface ToggleBackRequest { kind: 'toggleBack'; time: number; }
interface ToggleSelection { epoch: number; begin: number; end: number; }
type ImeRequest = UiEvent | ImeLocalRequest | EnglishUndoRequest | RevertConversionRequest |
  ToggleTapRequest | ToggleRightRequest | ToggleBackRequest | DeleteLearnedCandidateRequest;
type LocalResetReason = 'epoch' | 'discard' | 'external-empty';
interface ImeAdmissionContinue { kind: 'continue'; }
interface ImeAdmissionStopped { kind: 'stop'; snapshot: ImeSnapshot; }
type ImeAdmission = ImeAdmissionContinue | ImeAdmissionStopped;

export class ImeSession {
  private ports: ImeSessionPorts;
  private coord: ImeCoordinator;
  private engine: MozcEngine;
  private englishEngine: EnglishEngine;
  private directEnglish: DirectEnglishInput;
  private ready: boolean = false;
  private lastEpoch: number = -1;
  private compositionGeneration: number = 0;
  private editorSyncQueued: boolean = false;
  private editorSync: ExternalEditorSync;
  private mode: string = 'JP';
  private preview: CompositionPreview;
  private completion: EnglishCompletionLifecycle;
  private cursorSync: CompositionCursorSync;
  private presentation: ImePresentation;
  private inputQueue: InputOperationQueue<ImeSnapshot>;
  private localRequests: ImeLocalRequests;
  private toggleRun: ToggleRun | undefined = undefined;
  private toggleEditing: boolean = false;
  private toggleSelection: ToggleSelection | undefined = undefined;
  private now: () => number;

  constructor(ports: ImeSessionPorts, now: () => number = (): number => Date.now()) {
    this.ports = ports;
    this.now = now;
    this.coord = new ImeCoordinator(this.ports.editor);
    this.engine = ports.engine;
    this.englishEngine = new EnglishEngine(this.ports.prediction);
    const directEnglishPort: DirectEnglishPort = {
      getEpoch: (): number => this.ports.editor.getEpoch(),
      predictionAllowed: (): boolean => this.ports.bindings.predictionAllowed(),
      queryCursor: (): Promise<number> => this.ports.editor.queryCursor(),
      queryBefore: (length: number): Promise<string> => this.ports.editor.queryBefore(length),
      dispatch: (event: InputEvent): Promise<void> => this.coord.postEvent(event),
      lastError: (): string => this.coord.getSnapshot().lastError,
      enterAction: (epoch: number): Promise<void> => this.sendEnterAction(epoch)
    };
    this.directEnglish = new DirectEnglishInput(this.ports.prediction, directEnglishPort);
    const externalEditorPort: ExternalEditorPort = {
      getEpoch: (): number => this.ports.editor.getEpoch(),
      queryEmpty: ports.queryEmpty
    };
    this.editorSync = new ExternalEditorSync(externalEditorPort);
    const previewPort: CompositionPreviewPort = {
      getEpoch: (): number => this.ports.editor.getEpoch(),
      queryCursor: (): Promise<number> => this.ports.editor.queryCursor(),
      clearPreview: async (): Promise<void> => { await this.ports.cancelPreview(); },
      refreshPreview: (text: string, start: number, end: number, caret: number): Promise<boolean> => {
        // setPreviewText leaves the caret at the end before it is moved to the engine caret.
        if (start >= 0) { this.cursorSync.wrote(start + text.length); this.cursorSync.wrote(start + caret); }
        return this.coord.refreshPreview(text, start, end, caret);
      },
      disableJapanesePreview: (): void => { this.coord.setPreviewUnsupported(); },
      englishCursor: (position: number): void => { this.ports.prediction.setCompositionCursor(position); }
    };
    this.preview = new CompositionPreview(previewPort);
    const completionPort: EnglishCompletionPort = {
      getEpoch: (): number => this.ports.editor.getEpoch(),
      predictionAllowed: (): boolean => this.ports.bindings.predictionAllowed(),
      usesComposition: (): boolean => this.coord.usesEnglishComposition(),
      snapshot: (): ImeSnapshot => this.coord.getSnapshot(),
      dispatch: (event: InputEvent): Promise<void> => this.coord.postEvent(event),
      restorePreview: (start: number): void => { this.preview.restore(start); },
      refreshPreview: (snapshot: ImeSnapshot): Promise<void> => this.refreshPreview(snapshot)
    };
    this.completion = new EnglishCompletionLifecycle(this.ports.prediction, completionPort);
    const cursorPort: CompositionCursorPort = {
      getEpoch: (): number => this.ports.editor.getEpoch(),
      hasSelection: (): boolean => this.ports.editor.hasSelection(),
      queryCursor: (): Promise<number> => this.ports.editor.queryCursor(),
      alignCursor: async (position: number): Promise<boolean> => {
        await this.coord.postEvent({ kind: 'compositionCursor', cursor: position });
        return this.coord.getSnapshot().lastError === 'ok';
      }
    };
    this.cursorSync = new CompositionCursorSync(cursorPort, this.now);
    const presentationCoordinator: ImeCandidateSource = {
      getEpoch: (): number => this.ports.editor.getEpoch(),
      usesEnglishComposition: (): boolean => this.coord.usesEnglishComposition(),
      getCandidateView: (): CandidateLabel[] => this.coord.getCandidateView(),
      getCandidateRevision: (): number => this.coord.getCandidateRevision()
    };
    const presentationJapanese: ImeJapaneseViewSource = {
      getConversionReading: (): string => this.engine.getConversionReading(),
      getCursorPreview: (): string => this.engine.getCursorPreview(),
      getLastLens: (): string => this.engine.getLastLens(),
      getSelIdx: (): number => this.engine.getSelIdx()
    };
    this.presentation = new ImePresentation(presentationCoordinator, this.ports.prediction, presentationJapanese,
      ports.viewPublisher);
    this.inputQueue = new InputOperationQueue<ImeSnapshot>(
      (): number => this.ports.editor.getEpoch(), (): ImeSnapshot => this.coord.getSnapshot());
    const localRequestPort: ImeLocalRequestPort = {
      getEpoch: (): number => this.ports.editor.getEpoch(),
      snapshot: (): ImeSnapshot => this.coord.getSnapshot(),
      configuredOrder: (): string => this.ports.bindings.configuredOrder(),
      currentLayout: (): string => this.ports.bindings.currentLayout(),
      flickEnabled: (): boolean => this.ports.bindings.flickEnabled(),
      dispatch: (event: InputEvent): Promise<void> => this.coord.postEvent(event),
      submit: (): Promise<ImeSnapshot> => this.postSerial({ kind: 'submit' }),
      resetComposition: (): void => { this.preview.reset(); this.ports.prediction.clear(); },
      applyLayout: (layout: string): void => this.ports.bindings.applyLayout(layout),
      saveOrder: (order: string): Promise<void> => this.ports.bindings.saveOrder(order),
      publish: (snapshot: ImeSnapshot): void => this.publish(snapshot)
    };
    this.localRequests = new ImeLocalRequests(localRequestPort);
  }

  private async ensure(): Promise<void> {
    if (this.ready) {
      return;
    }
    this.coord.setEngine(this.engine);
    this.coord.setEnglishEngine(this.englishEngine);
    await this.engine.prepare();
    await this.coord.loadPreviewSupport();
    const layout: string = this.ports.bindings.currentLayout();
    await this.coord.postEvent({ kind: 'mode', text: layoutLanguage(layout) });
    this.mode = this.coord.getSnapshot().mode;
    this.lastEpoch = this.ports.editor.getEpoch();
    this.ready = true;
  }

  private async syncEpoch(): Promise<void> {
    const e: number = this.ports.editor.getEpoch();
    if (this.lastEpoch !== e) {
      this.compositionGeneration++;
      this.editorSync.reset();
      await this.resetCoordinatorAndMozc();
      this.resetLocalEnglish();
      await this.coord.loadPreviewSupport();
      this.lastEpoch = e;
      // A new connection can arrive without a key event. Publish the reset
      // before exposing the panel so old composing indicators do not linger.
      this.finishLocalReset(e, 'epoch');
    }
  }

  // Keep the existing wait for Mozc at each call site. Only an input-target
  // change reloads preview support before the range reset and publication.
  private resetCoordinatorAndMozc(): Promise<void> {
    this.toggleRun = undefined;
    this.coord.onEditorChanged();
    return this.engine.resetLocal();
  }

  private resetLocalEnglish(): void {
    this.englishEngine.resetLocal();
    this.ports.prediction.clear();
  }

  private finishLocalReset(epoch: number, reason: LocalResetReason): boolean {
    this.preview.reset();
    this.cursorSync.reset();
    if (reason === 'discard') { this.editorSync.reset(); }
    if (reason === 'external-empty') {
      if (epoch !== this.ports.editor.getEpoch()) { return false; }
      this.ports.log('KanonIme->', `kanon: editor-reset epoch=${epoch} reason=empty`);
    }
    this.publish(this.coord.getSnapshot(), epoch);
    return true;
  }

  /** Explicit SDK request from the application, distinct from a text hint. */
  async discardTypingText(): Promise<void> {
    const epoch: number = this.ports.editor.getEpoch();
    this.ports.log('KanonIme->', `kanon: editor-discard epoch=${epoch}`);
    await this.inputQueue.enqueue(async (): Promise<ImeSnapshot> => {
      await this.ensure();
      await this.syncEpoch();
      if (epoch !== this.ports.editor.getEpoch()) { return this.coord.getSnapshot(); }
      this.compositionGeneration++;
      if (this.preview.getLength() > 0) {
        // Clear only our active preview, then end its SDK session. Never
        // submit the old conversion or delete the application's committed text.
        const result = await this.ports.cancelPreview();
        this.ports.log('KanonIme->', `kanon: discard-preview ok=${result.ok} code=${result.code}`);
        if (epoch !== this.ports.editor.getEpoch()) { return this.coord.getSnapshot(); }
      }
      await this.resetCoordinatorAndMozc();
      this.resetLocalEnglish();
      this.finishLocalReset(epoch, 'discard');
      return this.coord.getSnapshot();
    });
  }

  private publish(s: ImeSnapshot, epoch: number = this.ports.editor.getEpoch()): void {
    if (epoch !== this.ports.editor.getEpoch()) { return; }
    this.mode = s.mode;
    this.presentation.publish(s, epoch);
  }

  selectionChanged(begin: number, end: number): void {
    const epoch: number = this.ports.editor.getEpoch();
    if (this.toggleEditing || this.toggleRun !== undefined || this.toggleSelection !== undefined) {
      this.toggleSelection = { epoch: epoch, begin: begin, end: end };
    } else {
      this.ports.prediction.selectionChanged(begin, end);
    }
    this.coord.selectionChanged(begin, end);
    this.cursorSync.notify(epoch);
    this.editorSync.selectionChanged(epoch, begin, end);
    this.scheduleEditorSync();
  }

  textChanged(empty: boolean): void {
    this.editorSync.textChanged(this.ports.editor.getEpoch(), empty);
    this.scheduleEditorSync();
  }

  editorVisibilityChanged(): void {
    const epoch: number = this.ports.editor.getEpoch();
    this.editorSync.visibilityChanged(epoch);
    this.scheduleEditorSync();
  }

  private scheduleEditorSync(): void {
    if (!this.ready || this.editorSyncQueued ||
      (!this.editorSync.hasPending() && this.toggleSelection === undefined)) { return; }
    this.editorSyncQueued = true;
    const revision: number = this.editorSync.getRevision();
    this.inputQueue.enqueue(async (): Promise<ImeSnapshot> => {
      await this.syncEpoch();
      await this.synchronizeExternalEditor();
      await this.synchronizeToggleSelection(this.ports.editor.getEpoch());
      return this.coord.getSnapshot();
    }).catch((): ImeSnapshot => this.coord.getSnapshot()).finally((): void => {
      this.editorSyncQueued = false;
      if (revision !== this.editorSync.getRevision()) {
        this.scheduleEditorSync();
      }
    });
  }

  private async synchronizeToggleSelection(epoch: number): Promise<void> {
    // The editor may report the temporary caret from a delete or preview write
    // after that write has finished. Read the live caret between queued edits.
    while (this.toggleSelection !== undefined && epoch === this.ports.editor.getEpoch()) {
      const hint: ToggleSelection = this.toggleSelection;
      if (hint.epoch !== epoch) { this.toggleSelection = undefined; return; }
      const run: ToggleRun | undefined = this.toggleRun;
      let begin: number = hint.begin;
      let end: number = hint.end;
      if (run !== undefined && run.cursor >= 0 && !this.ports.editor.hasSelection() &&
        (begin !== run.cursor || end !== run.cursor)) {
        let cursor: number = -1;
        try { cursor = await this.ports.editor.queryCursor(); } catch (error) { }
        if (epoch !== this.ports.editor.getEpoch()) { return; }
        if (hint !== this.toggleSelection) { continue; }
        if (cursor >= 0 && !this.ports.editor.hasSelection()) { begin = cursor; end = cursor; }
      }
      this.toggleSelection = undefined;
      if (run !== undefined && (begin !== end || this.ports.editor.hasSelection() ||
        (run.cursor >= 0 && begin !== run.cursor))) {
        this.toggleRun = undefined;
      }
      this.ports.prediction.selectionChanged(begin, end);
    }
  }

  private async synchronizeExternalEditor(): Promise<boolean> {
    const epoch: number = this.ports.editor.getEpoch();
    let result: ExternalEditorResult;
    do {
      // An unsupported/failed preview may exist only in the engine. An empty
      // editor is then normal and must not be mistaken for external deletion.
      const shownComposition: boolean = this.coord.getSnapshot().preeditLen > 0 && this.preview.getLength() > 0;
      const directEnglish: boolean = this.isDirectEnglish() &&
        this.ports.prediction.getPrefix().length > 0;
      result = await this.editorSync.reconcile(shownComposition || directEnglish);
    } while (result === 'retry');
    if (result === 'failed' || result === 'stale') { return false; }
    if (result !== 'empty') { return true; }
    // Forget local state only after confirming an empty field. Do not edit
    // the application's draft or infer submission from visibility/errors.
    this.compositionGeneration++;
    await this.resetCoordinatorAndMozc();
    this.resetLocalEnglish();
    return this.finishLocalReset(epoch, 'external-empty');
  }

  private async synchronizeCompositionCursor(): Promise<boolean> {
    const epoch: number = this.ports.editor.getEpoch();
    let result: CompositionCursorResult;
    do {
      const snapshot: ImeSnapshot = this.coord.getSnapshot();
      result = await this.cursorSync.reconcile({
        composing: snapshot.state === 'JP_COMPOSING' && !snapshot.needsRecovery,
        cursorAligned: this.coord.isPreviewCaretAligned(),
        start: this.preview.getStart(), previewLength: this.preview.getLength(),
        text: this.engine.getPreedit(), caret: snapshot.caretUtf16
      });
    } while (result === 'retry');
    if (result === 'failed') {
      if (this.coord.getSnapshot().lastError === 'ok') { this.coord.reportCursorSyncFailure(); }
      this.publish(this.coord.getSnapshot(), epoch);
    }
    if (result === 'aligned') {
      this.toggleRun = undefined;
      this.publish(this.coord.getSnapshot(), epoch);
    }
    return result !== 'failed' && result !== 'stale';
  }

  private async post(kind: UiEventKind, text?: string, candidateId?: number,
    expectedRevision?: number, direction?: EditorDirection, edge?: EditorEdge): Promise<ImeSnapshot> {
    return this.postRequest(createInputEvent(kind, text, candidateId, expectedRevision, direction, edge));
  }

  private async postRequest(request: ImeRequest): Promise<ImeSnapshot> {
    // プレビュー更新も含めて直列化する。次の打鍵が前の表示・確定へ割り込まない。
    const generation: number = this.compositionGeneration;
    return this.inputQueue.enqueue((): Promise<ImeSnapshot> =>
      this.postSerial(request, generation));
  }

  private async postSerial(request: ImeRequest, generation: number = this.compositionGeneration): Promise<ImeSnapshot> {
    const requestEpoch: number = this.ports.editor.getEpoch();
    try {
      const admission: ImeAdmission = await this.admit(request, generation, requestEpoch);
      if (admission.kind === 'stop') { this.toggleRun = undefined; return admission.snapshot; }
      // Validate the epoch after both synchronization and the admission await.
      if (requestEpoch !== this.ports.editor.getEpoch()) { return this.coord.getSnapshot(); }
      if (request.kind !== 'toggleTap' && request.kind !== 'toggleRight' && request.kind !== 'toggleBack' &&
        request.kind !== 'deleteLearnedCandidate') {
        this.toggleRun = undefined;
      }
      return await this.routeRequest(request, requestEpoch);
    } catch (e) {
      this.toggleRun = undefined;
      const s: ImeSnapshot = this.coord.getSnapshot();
      this.publish(s, requestEpoch);
      return s;
    }
  }

  private async admit(request: ImeRequest, generation: number, requestEpoch: number): Promise<ImeAdmission> {
    await this.ensure();
    await this.syncEpoch();
    if (requestEpoch !== this.ports.editor.getEpoch()) { return this.stopAdmission(); }
    if (!await this.synchronizeExternalEditor()) { return this.stopAdmission(); }
    await this.synchronizeToggleSelection(requestEpoch);
    if (generation !== this.compositionGeneration &&
      (request.kind === 'select' || request.kind === 'partial' || request.kind === 'undoEnglish' || request.kind === 'undo' ||
        request.kind === 'toggleBack' || request.kind === 'revertConversion' || request.kind === 'deleteLearnedCandidate')) {
      return this.stopAdmission();
    }
    if (requestEpoch !== this.ports.editor.getEpoch()) { return this.stopAdmission(); }
    const run: ToggleRun | undefined = this.toggleRun;
    if (request.kind !== 'cancel' && request.kind !== 'cycle' && request.kind !== 'config' &&
      request.kind !== 'revertConversion' && request.kind !== 'undo' &&
      (request.kind !== 'toggleBack' || (run !== undefined && run.activeAt(request.time))) &&
      !await this.synchronizeCompositionCursor()) { return this.stopAdmission(); }
    const admission: ImeAdmissionContinue = { kind: 'continue' };
    return admission;
  }

  private stopAdmission(): ImeAdmissionStopped {
    const admission: ImeAdmissionStopped = { kind: 'stop', snapshot: this.coord.getSnapshot() };
    return admission;
  }

  private isDirectEnglish(): boolean {
    return this.mode === 'EN' && !this.coord.usesEnglishComposition();
  }

  private async routeRequest(request: ImeRequest, requestEpoch: number): Promise<ImeSnapshot> {
    if (request.kind === 'deleteLearnedCandidate') {
      // Candidate IDs are reused. A menu can only delete the original candidate object.
      if (this.mode !== 'JP' || !this.coord.getCandidateView().includes(request.candidate)) {
        return this.coord.getSnapshot();
      }
      const revision: number = this.coord.getCandidateRevision();
      const result: ImeSnapshot = await this.dispatchNormal(
        createInputEvent('deleteCandidate', undefined, request.candidate.id, revision), requestEpoch);
      if (requestEpoch === this.ports.editor.getEpoch()) {
        if (result.lastError === 'candidate-not-learned') {
          request.result = 'not-learned';
        } else if (result.lastError === 'ok' && this.coord.getCandidateRevision() !== revision) {
          request.result = 'deleted';
          this.toggleRun = undefined;
        }
      }
      return result;
    }
    if (request.kind === 'revertConversion') {
      this.ports.bindings.closeCandidates();
      const snapshot: ImeSnapshot = this.coord.getSnapshot();
      if (snapshot.state === 'JP_CONVERTING' || snapshot.state === 'EN_CONVERTING') {
        return this.dispatchNormal({ kind: 'backspace' }, requestEpoch);
      }
      if (this.isDirectEnglish() && this.directEnglish.revertSelection()) {
        this.publish(snapshot, requestEpoch);
      }
      return snapshot;
    }
    this.coord.setEnglishCompositionEnabled(this.ports.bindings.predictionAllowed());
    if (this.mode === 'EN' && this.ports.prediction.takeCompositionAbandoned()) {
      this.toggleRun = undefined;
      this.englishEngine.resetLocal();
      this.coord.onEditorChanged();
      this.preview.reset();
    }
    if (request.kind === 'toggleTap' || request.kind === 'toggleRight' || request.kind === 'toggleBack') {
      this.toggleEditing = true;
      try { return await this.routeToggle(request, requestEpoch); }
      finally { this.toggleEditing = false; }
    }
    if (request.kind === 'prepare') {
      return this.localRequests.handle(request, requestEpoch);
    }
    if (request.kind === 'undo' && this.mode === 'EN') {
      const snapshot: ImeSnapshot = await this.undoEnglish(requestEpoch);
      if (requestEpoch === this.ports.editor.getEpoch()) { await this.updateCursor(); }
      return snapshot;
    }
    if (request.kind !== 'backspace' && request.kind !== 'select' && request.kind !== 'undoEnglish') {
      this.ports.prediction.dropUndo();
    }
    if (request.kind === 'cycle' || request.kind === 'config') {
      return this.localRequests.handle(request, requestEpoch);
    }
    if (request.kind === 'undoEnglish') { return this.undoEnglish(requestEpoch); }
    const kind: UiEventKind = request.kind;
    if (this.isDirectEnglish() && kind === 'convert') { return this.convertDirectEnglish(requestEpoch); }
    if (kind === 'paste' && !await this.localRequests.beforePaste(requestEpoch)) {
      return this.coord.getSnapshot();
    }
    if (this.mode === 'EN' && kind === 'backspace') {
      if (this.isDirectEnglish() && this.directEnglish.revertSelection()) {
        const snapshot: ImeSnapshot = this.coord.getSnapshot();
        this.publish(snapshot, requestEpoch);
        return snapshot;
      }
      const result: EnglishUndoResult = await this.completion.undo('backspace', requestEpoch);
      if (result === 'stale') { return this.coord.getSnapshot(); }
      if (result === 'handled') {
        const snapshot: ImeSnapshot = this.coord.getSnapshot();
        this.publish(snapshot, requestEpoch);
        return snapshot;
      }
    }
    if (this.isDirectEnglish() && (kind === 'select' || kind === 'cancel' || kind === 'enter')) {
      await this.directEnglish.handle(kind, request.candidateId, request.expectedRevision);
      const snapshot: ImeSnapshot = this.coord.getSnapshot();
      this.publish(snapshot, requestEpoch);
      return snapshot;
    }
    return this.dispatchNormal(request, requestEpoch);
  }

  private async routeToggle(request: ToggleTapRequest | ToggleRightRequest | ToggleBackRequest,
    epoch: number): Promise<ImeSnapshot> {
    const current: ToggleRun | undefined = this.toggleRun;
    this.toggleRun = undefined;
    const enabled: boolean = this.ports.bindings.toggleInputEnabled();
    const active: boolean = enabled && current !== undefined && current.activeAt(request.time);
    if (request.kind === 'toggleRight') {
      return active ? this.coord.getSnapshot() : this.routeRequest({ kind: 'move', direction: 'right' }, epoch);
    }
    if (request.kind === 'toggleBack') {
      return active && current !== undefined ? this.stepToggle(current, -1, current.time, epoch) :
        this.routeRequest({ kind: 'undo' }, epoch);
    }
    const tap: ToggleTapRequest = request;
    if (active && current !== undefined && current.key === tap.key) {
      const replaced: ImeSnapshot = await this.stepToggle(current, 1, tap.time, epoch);
      if (replaced.lastError !== 'toggle-stale' || epoch !== this.ports.editor.getEpoch()) { return replaced; }
    }
    const english: boolean = this.mode === 'EN';
    const value: string = english && tap.uppercase ? tap.key.toUpperCase() : tap.key;
    const event: UiEvent = { kind: english ? 'text' : 'kana', text: value };
    const cycle: string = enabled ? toggleCycle(tap.key, english, tap.uppercase) : '';
    const before: ImeSnapshot = this.coord.getSnapshot();
    const canStart: boolean = cycle.length > 0 && before.state !== 'JP_CONVERTING' &&
      before.state !== 'EN_CONVERTING' && this.ports.prediction.getSelectedIndex() < 0;
    const direct: boolean = this.isDirectEnglish();
    const selected: boolean = canStart && direct && this.ports.editor.hasSelection();
    const cursor: number = canStart && direct && !selected ? await this.ports.editor.queryCursor() : -1;
    if (epoch !== this.ports.editor.getEpoch()) { return this.coord.getSnapshot(); }
    const after: ImeSnapshot = await this.routeRequest(event, epoch);
    if (canStart && after.lastError === 'ok' && epoch === this.ports.editor.getEpoch() &&
      (direct || after.state === 'JP_COMPOSING' || after.state === 'EN_COMPOSING')) {
      const start: number = this.preview.getStart();
      const expected: number = selected ? await this.ports.editor.queryCursor() :
        direct ? cursor + 1 : start >= 0 ? start + after.caretUtf16 : -1;
      if (epoch === this.ports.editor.getEpoch() && (!direct || expected > 0)) {
        this.toggleRun = new ToggleRun(tap.key, cycle, 0, tap.time, expected);
      }
    }
    return after;
  }

  private async stepToggle(current: ToggleRun, offset: number, time: number, epoch: number): Promise<ImeSnapshot> {
    const next: ToggleRun = current.step(offset, time);
    const event: UiEvent = {
      kind: 'replaceToggle', previous: current.character(), text: next.character()
    };
    if (this.isDirectEnglish()) { event.cursor = current.cursor; }
    const result: ImeSnapshot = await this.routeRequest(event, epoch);
    if (result.lastError === 'ok' && epoch === this.ports.editor.getEpoch()) { this.toggleRun = next; }
    return result;
  }

  private async undoEnglish(requestEpoch: number): Promise<ImeSnapshot> {
    const result: EnglishUndoResult = await this.completion.undo('undoEnglish', requestEpoch);
    const snapshot: ImeSnapshot = this.coord.getSnapshot();
    if (result !== 'stale') { this.publish(snapshot, requestEpoch); }
    return snapshot;
  }

  private async convertDirectEnglish(requestEpoch: number): Promise<ImeSnapshot> {
    const result: DirectEnglishConversion = await this.directEnglish.convert(requestEpoch);
    if (result === 'stale') { return this.coord.getSnapshot(); }
    if (result === 'space') { return await this.postSerial({ kind: 'text', text: ' ' }); }
    const snapshot: ImeSnapshot = this.coord.getSnapshot();
    this.publish(snapshot, requestEpoch);
    return snapshot;
  }

  private async dispatchNormal(request: UiEvent, requestEpoch: number): Promise<ImeSnapshot> {
    const english: boolean = this.mode === 'EN';
    const directEnglish: boolean = this.isDirectEnglish();
    const epoch: number = this.ports.editor.getEpoch();
    const cursor: number = directEnglish && request.kind === 'text' ?
      await this.directEnglish.beforeText(request.text ?? '', epoch) : this.ports.prediction.getCursor();
    if (epoch !== this.ports.editor.getEpoch()) { this.ports.prediction.clear(); return this.coord.getSnapshot(); }
    // Resolve arrows against the live composition after the epoch check.
    const event: UiEvent = resolveInputMovement(request, this.mode, this.coord.getSnapshot().preeditLen);
    const kind: UiEventKind = event.kind;
    const undoRevision: number = kind === 'undo' ? this.coord.getSnapshot().revision : -1;
    const completion: EnglishCompletionContext | undefined = english && !directEnglish ?
      this.completion.capture(kind, request.candidateId, this.englishEngine.getTypedText(),
        this.preview.getStart(), epoch) : undefined;
    this.ports.prediction.editing = english;
    try { await this.coord.postEvent(event); }
    finally { this.ports.prediction.editing = false; }
    const s: ImeSnapshot = this.coord.getSnapshot();
    if (epoch !== this.ports.editor.getEpoch()) { this.ports.prediction.clear(); return s; }
    if (kind === 'deleteCandidate' && s.lastError !== 'ok') { return s; }
    if (kind === 'undo' && s.revision === undoRevision) { this.coord.takeUndoOrigin(); return s; }
    if (kind === 'undo') {
      const origin: number = this.coord.takeUndoOrigin();
      if (origin >= 0) { this.preview.restore(origin); }
    }
    if (!directEnglish && (kind === 'submit' || kind === 'enter') && s.lastError === 'empty-submit') {
      await this.sendEnterAction(epoch);
    }
    if (directEnglish && kind === 'replaceToggle' && s.lastError === 'ok') {
      const prefix: string = this.ports.prediction.getPrefix();
      if (prefix.length > 0 && prefix.endsWith(event.previous ?? '')) {
        this.ports.prediction.restorePrefix(prefix.slice(0, -1) + (event.text ?? ''), event.cursor ?? -1);
      }
    } else if (directEnglish) { this.directEnglish.afterEvent(kind, event.text, cursor, s.lastError === 'ok'); }
    else if (kind === 'mode') { this.ports.prediction.clear(); }
    if (completion !== undefined) { this.completion.remember(completion, s); }
    if (await this.preview.reconcile(s, kind, this.mode)) {
      this.ports.prediction.editing = english;
      try { await this.refreshPreview(s); }
      finally { this.ports.prediction.editing = false; }
    }
    const updated: ImeSnapshot = this.coord.getSnapshot();
    this.publish(updated, requestEpoch);
    return updated;
  }

  /** 未確定previewの表示更新。前回範囲を置換する（G-01置換順序）。失敗時はinsert確定のみへ落とす。 */
  private async refreshPreview(s: ImeSnapshot): Promise<void> {
    const pre: string = s.mode === 'EN' ? this.englishEngine.getPreedit() : this.engine.getPreedit();
    await this.preview.refresh(s, pre, this.coord.usesEnglishComposition());
  }

  async keyText(ch: string): Promise<void> {
    await this.post('text', ch);
  }

  async keyPaste(value: string): Promise<boolean> {
    if (value.length === 0) { return false; }
    const epoch: number = this.ports.editor.getEpoch();
    const snapshot: ImeSnapshot = await this.post('paste', value);
    return epoch === this.ports.editor.getEpoch() && snapshot.lastError === 'ok';
  }

  async keyKana(kana: string): Promise<void> {
    await this.post('kana', kana);
  }

  async keyToggleTap(key: string, uppercase: boolean): Promise<void> {
    await this.postRequest({ kind: 'toggleTap', key: key, uppercase: uppercase, time: this.now() });
  }

  async keyToggleRight(): Promise<void> {
    await this.postRequest({ kind: 'toggleRight', time: this.now() });
    await this.updateCursor();
  }

  async keyToggleBack(): Promise<void> {
    await this.postRequest({ kind: 'toggleBack', time: this.now() });
  }

  endToggleInput(): void {
    this.inputQueue.enqueue((): Promise<ImeSnapshot> => {
      this.toggleRun = undefined;
      return Promise.resolve(this.coord.getSnapshot());
    }).catch((): ImeSnapshot => this.coord.getSnapshot());
  }

  async modifyKana(modifier?: KanaModifier): Promise<void> {
    await this.post('modifyKana', modifier);
  }

  async keySpace(): Promise<void> {
    await this.post('convert');
  }

  async keyReturn(): Promise<void> {
    await this.post('enter');
  }

  async keyDelete(): Promise<void> {
    await this.post('backspace');
    await this.updateCursor();
  }

  async keyDeleteForward(): Promise<void> {
    await this.post('forwardDelete');
    await this.updateCursor();
  }

  async keyUndoEnglish(): Promise<void> {
    await this.postRequest({ kind: 'undoEnglish' });
    await this.updateCursor();
  }

  async keyUndo(): Promise<void> {
    await this.post('undo');
  }

  async forgetJapaneseCommit(): Promise<void> {
    this.coord.forgetJapaneseCommit();
    await this.inputQueue.enqueue(async (): Promise<ImeSnapshot> => {
      this.toggleRun = undefined;
      this.coord.forgetJapaneseCommit();
      return this.coord.getSnapshot();
    });
  }

  /** カーソル移動（EditViewの矢印・行頭・行末）。単一キュー経由。 */
  async keyMove(direction: EditorDirection | undefined): Promise<void> {
    await this.post('move', undefined, undefined, undefined, direction);
    await this.updateCursor();
  }

  async keySelectMove(direction: EditorDirection | undefined): Promise<void> {
    await this.post('selectMove', undefined, undefined, undefined, direction);
    await this.updateCursor();
  }

  async keySelectEdge(edge: EditorEdge): Promise<void> {
    await this.post('selectEdge', undefined, undefined, undefined, undefined, edge);
    await this.updateCursor();
  }

  async keySelectAll(): Promise<void> {
    await this.post('selectAll');
    await this.updateCursor();
  }

  async keyMoveBegin(): Promise<void> {
    await this.post('move', undefined, undefined, undefined, undefined, 'begin');
    await this.updateCursor();
  }

  async keyMoveEnd(): Promise<void> {
    await this.post('move', undefined, undefined, undefined, undefined, 'end');
    await this.updateCursor();
  }

  /** 欄カーソル位置の表示更新。移動・削除操作時のみ問い合わせる。 */
  private async updateCursor(): Promise<void> {
    await this.ports.bindings.updateCursor();
  }

  async selectCandidate(id: number): Promise<void> {
    const rev: number = this.isDirectEnglish() ?
      this.ports.prediction.getRevision() : this.coord.getCandidateRevision();
    await this.post('select', undefined, id, rev);
  }

  async deleteLearnedCandidate(candidate: CandidateLabel): Promise<CandidateDeletionResult> {
    const request: DeleteLearnedCandidateRequest = {
      kind: 'deleteLearnedCandidate', candidate: candidate, result: 'failed'
    };
    await this.postRequest(request);
    return request.result;
  }

  /** 先頭文節のみ確定（残りは未確定継続）。現行revを添える。 */
  async partialCommit(): Promise<void> {
    const rev: number = this.coord.getCandidateRevision();
    await this.post('partial', undefined, undefined, rev);
  }

  async cancelCompose(): Promise<void> {
    await this.post('cancel');
  }

  async revertConversion(): Promise<void> {
    await this.postRequest({ kind: 'revertConversion' });
  }

  async switchMode(): Promise<void> {
    await this.postRequest({ kind: 'cycle' });
  }

  flickEnabled(): boolean {
    return this.ports.bindings.flickEnabled();
  }

  async toggleLayout(fromNumberMode: boolean = false): Promise<boolean> {
    const epoch: number = this.ports.editor.getEpoch();
    let normalized: string = '';
    const snapshot: ImeSnapshot = await this.inputQueue.enqueue(async (): Promise<ImeSnapshot> => {
      normalized = this.localRequests.toggleOrder();
      if (normalized.length === 0) { return this.coord.getSnapshot(); }
      return this.postSerial({ kind: 'config', layoutOrder: normalized, fromNumberMode: fromNumberMode });
    });
    return normalized.length > 0 && epoch === this.ports.editor.getEpoch() && snapshot.lastError === 'ok' &&
      this.ports.bindings.matchesConfiguredOrder(normalized);
  }

  async prepare(): Promise<void> {
    await this.postRequest({ kind: 'prepare' });
  }

  async applyLayoutConfig(value: string): Promise<boolean> {
    const normalized: string = languageLayouts(value).join(',');
    const epoch: number = this.ports.editor.getEpoch();
    const snapshot: ImeSnapshot = await this.postRequest({ kind: 'config', layoutOrder: normalized });
    return epoch === this.ports.editor.getEpoch() && snapshot.lastError === 'ok' &&
      this.ports.bindings.matchesConfiguredOrder(normalized);
  }

  getCandidates(): CandidateLabel[] {
    return this.presentation.getCandidates(this.mode);
  }

  /** 候補スロット表示用。範囲外は空文字。 */
  getCandidateLabelAt(index: number): string {
    return this.presentation.getCandidateLabelAt(index);
  }

  /** 候補スロットのid。範囲外は-1。 */
  getCandidateIdAt(index: number): number {
    return this.presentation.getCandidateIdAt(index);
  }

  /** 候補スロット数（表示上限20・横スクロールで辿る）。 */
  getCandidateSlotCount(): number {
    return this.presentation.getCandidateSlotCount();
  }
  getCandidateIds(): string {
    return this.presentation.getCandidateIds();
  }

  /** 候補label長列（診断用・数値のみ）。 */
  getCandidateLens2(): string {
    return this.presentation.getCandidateLens2();
  }

  getMode(): string {
    return this.ports.bindings.displayedMode(this.mode);
  }

  private sendEnterAction(epoch: number): Promise<void> {
    return this.ports.enterKeyAction(epoch);
  }
}
