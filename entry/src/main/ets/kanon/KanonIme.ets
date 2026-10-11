/*
 * Kanon IME: KanonIme (M4)
 * 実キーボードとCoordinatorの接続点。KeyboardViewは意味のあるイベントだけを投げる（§6）。
 * - 入力先の世代変化を検出してonEditorChangedする。旧欄への書込はCoordinatorが遮断する。
 * - 未確定previewは全体置換で更新し、候補確定時は1回だけinsertする。
 * - ログは符号・件数・長さのみ。本文・候補は扱わない（REQ-07）。
 */

import { CandidateLabel, ImeCoordinator, ImeSnapshot } from './ImeCoordinator';
import { EditorDirection, EditorEdge, InputEvent, UiEvent, UiEventKind } from './InputEventTypes';
import { fromEditorDirection } from './EditorDirectionMap';
import { SDK_EDITOR_DIRECTIONS } from './SdkEditorDirections';
import { realEditorPort } from './RealEditorPort';
import { MozcEngine } from './MozcEngine';
import { NativeMozcBridge } from './NativeMozcBridge';
import { CompositionPreview, CompositionPreviewPort } from './CompositionPreview';
import { CompositionCursorSync, CompositionCursorPort, CompositionCursorResult } from './CompositionCursorSync';
import { cancelEditorPreview } from './PreviewLifecycle';
import { createInputEvent, resolveInputMovement } from './InputEventContract';
import { InputOperationQueue } from './InputOperationQueue';
import { ImeViewPublisher } from './ImeViewPublisher';
import { appStorageImeView } from './AppStorageImeView';
import { ImeCandidateSource, ImeJapaneseViewSource, ImePresentation } from './ImePresentation';
import { imeRuntimeBindings } from './AppStorageImeBindings';
import { EnglishEngine } from './EnglishEngine';
import { editorAdapter } from './EditorAdapter';
import { EnglishCompletionContext, EnglishCompletionLifecycle, EnglishCompletionPort,
  EnglishUndoResult } from './EnglishCompletionLifecycle';
import { englishPrediction } from './EnglishRuntime';
import { DirectEnglishConversion, DirectEnglishInput, DirectEnglishPort } from './DirectEnglishInput';
import { ImeLocalRequest, ImeLocalRequestPort, ImeLocalRequests } from './ImeLocalRequests';
import { layoutLanguage, languageLayouts } from '../common/KeyboardConfigValues';
import { keyboardHaptics } from '../common/KeyboardHaptics';

interface EnglishUndoRequest { kind: 'undoEnglish'; }
type ImeRequest = UiEvent | ImeLocalRequest | EnglishUndoRequest;

class KanonIme {
  private coord: ImeCoordinator = new ImeCoordinator(realEditorPort);
  private nativeBridge: NativeMozcBridge = new NativeMozcBridge();
  private engine: MozcEngine = new MozcEngine(this.nativeBridge);
  private englishEngine: EnglishEngine = new EnglishEngine(englishPrediction);
  private directEnglishPort: DirectEnglishPort = {
    getEpoch: (): number => realEditorPort.getEpoch(),
    predictionAllowed: (): boolean => imeRuntimeBindings.predictionAllowed(),
    queryCursor: (): Promise<number> => realEditorPort.queryCursor(),
    queryBefore: (length: number): Promise<string> => realEditorPort.queryBefore(length),
    dispatch: (event: InputEvent): Promise<void> => this.coord.postEvent(event),
    lastError: (): string => this.coord.getSnapshot().lastError,
    enterAction: (epoch: number): Promise<void> => this.sendEnterAction(epoch)
  };
  private directEnglish: DirectEnglishInput = new DirectEnglishInput(englishPrediction, this.directEnglishPort);
  private ready: boolean = false;
  private lastEpoch: number = -1;
  private mode: string = 'JP';
  private previewPort: CompositionPreviewPort = {
    getEpoch: (): number => realEditorPort.getEpoch(),
    queryCursor: (): Promise<number> => realEditorPort.queryCursor(),
    clearPreview: async (): Promise<void> => { await cancelEditorPreview(realEditorPort); },
    refreshPreview: (text: string, start: number, end: number, caret: number): Promise<boolean> =>
      this.coord.refreshPreview(text, start, end, caret),
    disableJapanesePreview: (): void => { this.coord.setPreviewUnsupported(); },
    englishCursor: (position: number): void => { englishPrediction.setCompositionCursor(position); }
  };
  private preview: CompositionPreview = new CompositionPreview(this.previewPort);
  private completionPort: EnglishCompletionPort = {
    getEpoch: (): number => realEditorPort.getEpoch(),
    predictionAllowed: (): boolean => imeRuntimeBindings.predictionAllowed(),
    usesComposition: (): boolean => this.coord.usesEnglishComposition(),
    snapshot: (): ImeSnapshot => this.coord.getSnapshot(),
    dispatch: (event: InputEvent): Promise<void> => this.coord.postEvent(event),
    restorePreview: (start: number): void => { this.preview.restore(start); },
    refreshPreview: (snapshot: ImeSnapshot): Promise<void> => this.refreshPreview(snapshot)
  };
  private completion: EnglishCompletionLifecycle = new EnglishCompletionLifecycle(englishPrediction, this.completionPort);
  private cursorPort: CompositionCursorPort = {
    getEpoch: (): number => realEditorPort.getEpoch(),
    hasSelection: (): boolean => realEditorPort.hasSelection(),
    queryCursor: (): Promise<number> => realEditorPort.queryCursor(),
    alignCursor: async (position: number): Promise<boolean> => {
      await this.coord.postEvent({ kind: 'compositionCursor', cursor: position });
      return this.coord.getSnapshot().lastError === 'ok';
    }
  };
  private cursorSync: CompositionCursorSync = new CompositionCursorSync(this.cursorPort);
  private presentationCoordinator: ImeCandidateSource = {
    getEpoch: (): number => realEditorPort.getEpoch(),
    usesEnglishComposition: (): boolean => this.coord.usesEnglishComposition(),
    getCandidateView: (): CandidateLabel[] => this.coord.getCandidateView(),
    getCandidateRevision: (): number => this.coord.getCandidateRevision()
  };
  private presentationJapanese: ImeJapaneseViewSource = {
    getConversionReading: (): string => this.engine.getConversionReading(),
    getCursorPreview: (): string => this.engine.getCursorPreview(),
    getLastLens: (): string => this.engine.getLastLens(),
    getSelIdx: (): number => this.engine.getSelIdx()
  };
  private presentation: ImePresentation = new ImePresentation(this.presentationCoordinator, englishPrediction, this.presentationJapanese,
    new ImeViewPublisher(appStorageImeView));
  private inputQueue: InputOperationQueue<ImeSnapshot> = new InputOperationQueue<ImeSnapshot>(
    (): number => realEditorPort.getEpoch(), (): ImeSnapshot => this.coord.getSnapshot());
  private localRequestPort: ImeLocalRequestPort = {
    getEpoch: (): number => realEditorPort.getEpoch(),
    snapshot: (): ImeSnapshot => this.coord.getSnapshot(),
    configuredOrder: (): string => imeRuntimeBindings.configuredOrder(),
    currentLayout: (): string => imeRuntimeBindings.currentLayout(),
    flickEnabled: (): boolean => imeRuntimeBindings.flickEnabled(),
    dispatch: (event: InputEvent): Promise<void> => this.coord.postEvent(event),
    submit: (): Promise<ImeSnapshot> => this.postSerial({ kind: 'submit' }),
    resetComposition: (): void => { this.preview.reset(); englishPrediction.clear(); },
    applyLayout: (layout: string): void => imeRuntimeBindings.applyLayout(layout),
    saveOrder: (order: string): Promise<void> => imeRuntimeBindings.saveOrder(order),
    publish: (snapshot: ImeSnapshot): void => this.publish(snapshot)
  };
  private localRequests: ImeLocalRequests = new ImeLocalRequests(this.localRequestPort);

  configureProfile(filesDirectory: string): void {
    this.nativeBridge.configureProfile(filesDirectory);
  }

  private async ensure(): Promise<void> {
    if (this.ready) {
      return;
    }
    this.coord.setEngine(this.engine);
    this.coord.setEnglishEngine(this.englishEngine);
    await this.engine.prepare();
    await this.coord.loadPreviewSupport();
    const layout: string = imeRuntimeBindings.currentLayout();
    await this.coord.postEvent({ kind: 'mode', text: layoutLanguage(layout) });
    this.mode = this.coord.getSnapshot().mode;
    this.lastEpoch = realEditorPort.getEpoch();
    this.ready = true;
  }

  private async syncEpoch(): Promise<void> {
    const e: number = realEditorPort.getEpoch();
    if (this.lastEpoch !== e) {
      this.coord.onEditorChanged();
      await this.engine.resetLocal();
      this.englishEngine.resetLocal();
      englishPrediction.clear();
      await this.coord.loadPreviewSupport();
      this.lastEpoch = e;
      this.preview.reset();
      this.cursorSync.reset();
    }
  }

  private publish(s: ImeSnapshot, epoch: number = realEditorPort.getEpoch()): void {
    if (epoch !== realEditorPort.getEpoch()) { return; }
    this.mode = s.mode;
    kanonRevTick++;
    this.presentation.publish(s, epoch);
  }

  selectionChanged(): void { this.cursorSync.notify(realEditorPort.getEpoch()); }

  private async synchronizeCompositionCursor(): Promise<boolean> {
    const epoch: number = realEditorPort.getEpoch();
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
    if (result === 'aligned') { this.publish(this.coord.getSnapshot(), epoch); }
    return result !== 'failed' && result !== 'stale';
  }

  private async post(kind: UiEventKind, text?: string, candidateId?: number,
    expectedRevision?: number, direction?: EditorDirection, edge?: EditorEdge): Promise<ImeSnapshot> {
    return this.postRequest(createInputEvent(kind, text, candidateId, expectedRevision, direction, edge));
  }

  private async postRequest(request: ImeRequest): Promise<ImeSnapshot> {
    // プレビュー更新も含めて直列化する。次の打鍵が前の表示・確定へ割り込まない。
    return this.inputQueue.enqueue((): Promise<ImeSnapshot> =>
      this.postSerial(request));
  }

  private async postSerial(request: ImeRequest): Promise<ImeSnapshot> {
    const requestEpoch: number = realEditorPort.getEpoch();
    try {
      await this.ensure();
      await this.syncEpoch();
      if (requestEpoch !== realEditorPort.getEpoch()) { return this.coord.getSnapshot(); }
      if (request.kind !== 'cancel' && request.kind !== 'cycle' && request.kind !== 'config' &&
        !await this.synchronizeCompositionCursor()) { return this.coord.getSnapshot(); }
      if (requestEpoch !== realEditorPort.getEpoch()) { return this.coord.getSnapshot(); }
      // Resolve the arrow's meaning inside the serial queue, after epoch checks.
      // Keep editing and segment resizing inside the live Japanese composition.
      this.coord.setEnglishCompositionEnabled(imeRuntimeBindings.predictionAllowed());
      if (this.mode === 'EN' && englishPrediction.takeCompositionAbandoned()) {
        this.englishEngine.resetLocal();
        this.coord.onEditorChanged();
        this.preview.reset();
      }
      if (request.kind === 'prepare') {
        return await this.localRequests.handle(request, requestEpoch);
      }
      if (request.kind !== 'backspace' && request.kind !== 'select' && request.kind !== 'undoEnglish') { englishPrediction.dropUndo(); }
      if (request.kind === 'cycle' || request.kind === 'config') {
        return await this.localRequests.handle(request, requestEpoch);
      }
      if (request.kind === 'undoEnglish') {
        const result: EnglishUndoResult = await this.completion.undo('undoEnglish', requestEpoch);
        const snapshot: ImeSnapshot = this.coord.getSnapshot();
        if (result !== 'stale') { this.publish(snapshot, requestEpoch); }
        return snapshot;
      }
      let kind: UiEventKind = request.kind;
      let text: string | undefined = request.text;
      const candidateId: number | undefined = request.candidateId;
      const expectedRevision: number | undefined = request.expectedRevision;
      if (this.mode === 'EN' && !this.coord.usesEnglishComposition() && kind === 'convert') {
        const result: DirectEnglishConversion = await this.directEnglish.convert(requestEpoch);
        if (result === 'stale') { return this.coord.getSnapshot(); }
        if (result === 'space') { return await this.postSerial({ kind: 'text', text: ' ' }); }
        const snapshot: ImeSnapshot = this.coord.getSnapshot();
        this.publish(snapshot, requestEpoch);
        return snapshot;
      }
      if (kind === 'paste' && !await this.localRequests.beforePaste(requestEpoch)) {
        return this.coord.getSnapshot();
      }
      if (this.mode === 'EN' && kind === 'backspace') {
        const result: EnglishUndoResult = await this.completion.undo('backspace', requestEpoch);
        if (result === 'stale') { return this.coord.getSnapshot(); }
        if (result === 'handled') {
          const snapshot: ImeSnapshot = this.coord.getSnapshot();
          this.publish(snapshot, requestEpoch);
          return snapshot;
        }
      }
      if (this.mode === 'EN' && !this.coord.usesEnglishComposition() && (kind === 'select' || kind === 'cancel' || kind === 'enter')) {
        await this.directEnglish.handle(kind, candidateId, expectedRevision);
        const snapshot: ImeSnapshot = this.coord.getSnapshot();
        this.publish(snapshot, requestEpoch);
        return snapshot;
      }
      const english: boolean = this.mode === 'EN';
      const directEnglish: boolean = english && !this.coord.usesEnglishComposition();
      const epoch: number = realEditorPort.getEpoch();
      const cursor: number = directEnglish && kind === 'text' ?
        await this.directEnglish.beforeText(text ?? '', epoch) : englishPrediction.getCursor();
      if (epoch !== realEditorPort.getEpoch()) { englishPrediction.clear(); return this.coord.getSnapshot(); }
      const ev: UiEvent = resolveInputMovement(
        request,
        this.mode, this.coord.getSnapshot().preeditLen);
      kind = ev.kind;
      text = ev.text;
      const completion: EnglishCompletionContext | undefined = english && !directEnglish ?
        this.completion.capture(kind, candidateId, this.englishEngine.getTypedText(), this.preview.getStart(), epoch) : undefined;
      englishPrediction.editing = english;
      try { await this.coord.postEvent(ev); }
      finally { englishPrediction.editing = false; }
      const s: ImeSnapshot = this.coord.getSnapshot();
      if (epoch !== realEditorPort.getEpoch()) { englishPrediction.clear(); return s; }
      if ((!english || !directEnglish) && (kind === 'submit' || kind === 'enter') && s.lastError === 'empty-submit') {
        await this.sendEnterAction(epoch);
      }
      if (directEnglish) { this.directEnglish.afterEvent(kind, text, cursor, s.lastError === 'ok'); }
      else if (kind === 'mode') { englishPrediction.clear(); }
      if (completion !== undefined) { this.completion.remember(completion, s); }
      await this.preview.reconcile(s, kind, this.mode);
      englishPrediction.editing = english;
      try { await this.refreshPreview(s); }
      finally { englishPrediction.editing = false; }
      const updated: ImeSnapshot = this.coord.getSnapshot();
      this.publish(updated, requestEpoch);
      return updated;
    } catch (e) {
      const s: ImeSnapshot = this.coord.getSnapshot();
      this.publish(s, requestEpoch);
      return s;
    }
  }

  /** 未確定previewの表示更新。前回範囲を置換する（G-01置換順序）。失敗時はinsert確定のみへ落とす。 */
  private async refreshPreview(s: ImeSnapshot): Promise<void> {
    const pre: string = s.mode === 'EN' ? this.englishEngine.getPreedit() : this.engine.getPreedit();
    await this.preview.refresh(s, pre, this.coord.usesEnglishComposition());
  }

  async keyText(ch: string, feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.post('text', ch);
  }

  async keyPaste(value: string): Promise<boolean> {
    if (value.length === 0) { return false; }
    const epoch: number = realEditorPort.getEpoch();
    const snapshot: ImeSnapshot = await this.post('paste', value);
    return epoch === realEditorPort.getEpoch() && snapshot.lastError === 'ok';
  }

  async keyKana(kana: string): Promise<void> {
    keyboardHaptics.key();
    await this.post('kana', kana);
  }

  async modifyKana(): Promise<void> {
    keyboardHaptics.key();
    await this.post('modifyKana');
  }

  /** SDK access stays at the runtime boundary, shared by composing and direct input. */
  private async sendEnterAction(epoch: number): Promise<void> {
    if (epoch !== realEditorPort.getEpoch()) { return; }
    const attr = await editorAdapter.queryAttribute();
    if (attr.ok && attr.value !== undefined && epoch === realEditorPort.getEpoch()) {
      await editorAdapter.sendEnterAction(attr.value.enterKeyType);
    }
  }

  async keySpace(feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.post('convert');
  }

  async keyReturn(feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.post('enter');
  }

  async keyDelete(feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.post('backspace');
    await this.updateCursor();
  }

  async keyDeleteForward(feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.post('forwardDelete');
    await this.updateCursor();
  }

  async keyUndoEnglish(): Promise<void> {
    await this.postRequest({ kind: 'undoEnglish' });
    await this.updateCursor();
  }

  /** カーソル移動（EditViewの矢印・行頭・行末）。単一キュー経由。 */
  async keyMove(direction: number, feedback: boolean = true): Promise<void> {
    if (feedback) { keyboardHaptics.key(); }
    await this.post('move', undefined, undefined, undefined, fromEditorDirection(direction, SDK_EDITOR_DIRECTIONS));
    await this.updateCursor();
  }

  async keySelectMove(direction: number): Promise<void> {
    keyboardHaptics.key();
    await this.post('selectMove', undefined, undefined, undefined, fromEditorDirection(direction, SDK_EDITOR_DIRECTIONS));
    await this.updateCursor();
  }

  async keySelectEdge(edge: EditorEdge): Promise<void> {
    keyboardHaptics.key();
    await this.post('selectEdge', undefined, undefined, undefined, undefined, edge);
    await this.updateCursor();
  }

  async keySelectAll(): Promise<void> {
    keyboardHaptics.key();
    await this.post('selectAll');
    await this.updateCursor();
  }

  async keyMoveBegin(): Promise<void> {
    keyboardHaptics.key();
    await this.post('move', undefined, undefined, undefined, undefined, 'begin');
    await this.updateCursor();
  }

  async keyMoveEnd(): Promise<void> {
    keyboardHaptics.key();
    await this.post('move', undefined, undefined, undefined, undefined, 'end');
    await this.updateCursor();
  }

  /** 欄カーソル位置の表示更新。移動・削除操作時のみ問い合わせる。 */
  private async updateCursor(): Promise<void> {
    await imeRuntimeBindings.updateCursor();
  }

  async selectCandidate(id: number): Promise<void> {
    keyboardHaptics.key();
    const rev: number = this.mode === 'EN' && !this.coord.usesEnglishComposition() ? englishPrediction.getRevision() : this.coord.getCandidateRevision();
    await this.post('select', undefined, id, rev);
  }

  /** 先頭文節のみ確定（残りは未確定継続）。現行revを添える。 */
  async partialCommit(): Promise<void> {
    keyboardHaptics.key();
    const rev: number = this.coord.getCandidateRevision();
    await this.post('partial', undefined, undefined, rev);
  }

  async cancelCompose(): Promise<void> {
    await this.post('cancel');
  }

  async switchMode(): Promise<void> {
    await this.postRequest({ kind: 'cycle' });
  }

  async toggleLayout(): Promise<boolean> {
    if (!imeRuntimeBindings.flickEnabled()) { return false; }
    keyboardHaptics.key();
    const epoch: number = realEditorPort.getEpoch();
    let normalized: string = '';
    const snapshot: ImeSnapshot = await this.inputQueue.enqueue(async (): Promise<ImeSnapshot> => {
      normalized = this.localRequests.toggleOrder();
      if (normalized.length === 0) { return this.coord.getSnapshot(); }
      return this.postSerial({ kind: 'config', layoutOrder: normalized });
    });
    return normalized.length > 0 && epoch === realEditorPort.getEpoch() && snapshot.lastError === 'ok' &&
      imeRuntimeBindings.matchesConfiguredOrder(normalized);
  }

  async prepare(): Promise<void> {
    await this.postRequest({ kind: 'prepare' });
  }

  async applyLayoutConfig(value: string): Promise<boolean> {
    const normalized: string = languageLayouts(value).join(',');
    const epoch: number = realEditorPort.getEpoch();
    const snapshot: ImeSnapshot = await this.postRequest({ kind: 'config', layoutOrder: normalized });
    return epoch === realEditorPort.getEpoch() && snapshot.lastError === 'ok' &&
      imeRuntimeBindings.matchesConfiguredOrder(normalized);
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
    return imeRuntimeBindings.displayedMode(this.mode);
  }
}

export const kanonIme: KanonIme = new KanonIme();

/** 候補更新ごとに単調増加する表示用 tick。ForEachのキー空間切替に使う。 */
export let kanonRevTick: number = 0;
