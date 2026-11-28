import {
  ENTER_KEY_TYPE, INPUT_HANDLER, INPUT_PATTERN, INPUT_STYLE, IS_LANDSCAPE, KANON_CANDIDATES_EXPANDED,
  KANON_CANDIDATE_FONT_SIZE, KANON_CANDIDATE_ROWS, KANON_FLICK_PREVIEW, KANON_FLICK_PREVIEW_OWNER,
  KANON_FONT_SCALE, KANON_HEIGHT_ADJUSTMENT_BOTTOM_VP, KANON_HEIGHT_PREVIEW_VP, KANON_ID_LIST,
  KANON_KEYBOARD_HEIGHT_PERCENT, KANON_KEYBOARD_VISIBLE, KANON_KEY_SOUND_LEVEL, KANON_LAYOUT, KANON_LIST, KANON_MODE,
  KANON_PACHINKO_SESSION, KANON_PANEL_HEIGHT_PX, KANON_PANEL_WIDTH_PX, KANON_TOOLBAR_HEIGHT, WINDOW_HEIGHT, WINDOW_WIDTH
} from '../common/AppStorageKeys';
// Modified for kanonIME by ysk0518 and contributors, 2026.
/*
 * Copyright (c) 2023-2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


import inputMethodEngine from '@ohos.inputMethodEngine';
import InputMethodExtensionContext from '@ohos.InputMethodExtensionContext';
import display from '@ohos.display';
import windowManager from '@ohos.window';
import Log from './Log';
import { editorAdapter } from '../kanon/EditorAdapter';
import { kanonIme } from '../kanon/KanonIme';
import { englishPrediction } from '../kanon/EnglishRuntime';
import { clipboardHistory } from '../kanon/ClipboardHistory';
import { BusinessError } from '@ohos.base';
import { HardKeyDownResult, HardKeyOperation, HardKeyState, HardKeyUpResult, hardKeyDown, hardKeyUp } from './HardKeyInput';
import { SDK_HARD_KEY_CODES } from './SdkHardKeyCodes';
import { SDK_EDITOR_DIRECTIONS } from '../kanon/SdkEditorDirections';
import { StyleConfiguration } from '../common/StyleConfiguration';
import { toolbarHeight, DEFAULT_KEYBOARD_HEIGHT_PERCENT, keyboardHeightPreviewPercent } from '../common/KeyboardLayout';
import { keyboardPanelGeometry, keyboardPanelHeight, panelScreen, panelStyleSize,
  PanelGeometry, PanelScreen, PanelSettings, PanelStyleSize } from '../common/KeyboardPanelGeometry';
import { openKeyboardPreferences, refreshSharedLayoutOrder, refreshSharedHapticLevel, refreshKeyboardHeightPercent, layoutLanguage } from '../common/KeyboardConfig';
import { keyboardSettingsSync } from '../common/KeyboardSettingsSync';
import { keyboardBackground } from '../common/KeyboardBackground';
import { debugLog } from '../common/DebugLog';
import { perfMark, perfPanelHidden, perfPanelReset, perfPanelShown } from '../common/PerfTrace';
import { pachinkoKeyNotifications } from '../common/PachinkoModel';
import { harmonyKeyboardSound } from '../common/HarmonyKeyboardSound';
import { DEFAULT_CANDIDATE_FONT_SIZE, DEFAULT_CANDIDATE_ROWS } from '../common/CandidateLayout';

interface CursorInfo {
  x: number;
  y: number;
  height: number
}
const InputMethodEngine: inputMethodEngine.InputMethodAbility = inputMethodEngine.getInputMethodAbility();
const TAG: string = 'KeyboardController->';
const isDebug: boolean = false;

export class InputHandler {
  private mKbController: inputMethodEngine.KeyboardController | undefined;
  private cursorInfo: CursorInfo = { x: 0, y: 0, height: 0 };
  private selectInfo: string = '';
  private textInfo: string = '';
  private inputInfo: string = '';

  private constructor() {
    this.mKbController = undefined;
  }

  public static getInstance(): InputHandler {
    let instance = AppStorage.get<InputHandler>(INPUT_HANDLER);
    if (instance === undefined) {
      instance = new InputHandler();
      AppStorage.setOrCreate(INPUT_HANDLER, instance);
    }
    return instance;
  }

  public onInputStart(kbController: inputMethodEngine.KeyboardController, textInputClient: inputMethodEngine.InputClient): void {
    this.mKbController = kbController;
    // Kanon M1: EditorAdapterへ現クライアントを接続（editorEpoch更新＝REQ-02の世代管理）。
    const epoch: number = editorAdapter.attach(textInputClient);
    refreshSharedLayoutOrder();
    refreshSharedHapticLevel();
    refreshKeyboardHeightPercent();
    englishPrediction.clear();
    AppStorage.setOrCreate(KANON_LIST, [] as string[]);
    AppStorage.setOrCreate(KANON_ID_LIST, [] as number[]);
    AppStorage.setOrCreate(KANON_CANDIDATES_EXPANDED, false);
    editorAdapter.queryAttribute().then((res): void => {
      if (epoch !== editorAdapter.getEpoch()) { return; }
      if (!res.ok || res.value === undefined) {
        this.addLog(`onInputStart getEditorAttribute failed code=${res.code}`);
        return;
      }
      AppStorage.setOrCreate(ENTER_KEY_TYPE, res.value.enterKeyType);
      AppStorage.setOrCreate(INPUT_PATTERN, res.value.inputPattern);
    });
  }

  public hideKeyboardSelf(): void {
    this.addLog('hideKeyboardSelf');
    if (this.mKbController !== undefined) {
      try { this.mKbController.hide(); } catch (error) {
        this.addLog(`hideKeyboardSelf failed code=${(error as BusinessError).code}`);
      }
    } else {
      this.addLog('hideKeyboardSelf this.mKbController is undefined');
    }
  }

  public addLog(message: string): void {
    Log.showInfo(TAG, `kikaInput-js: ${message}`);
  }

  public setCursorInfo(info: CursorInfo): void {
    this.addLog(`setCursorInfo info = ${JSON.stringify(info)}`);
    this.cursorInfo = info;
  }

  public setSelectInfo(info: string): void {
    this.selectInfo = info;
    this.addLog(`setSelectInfo info = ${info}`);
  }

  public setTextInfo(info: string): void {
    this.textInfo = info;
    this.addLog(`setTextInfo info = ${info}`);
  }

  public setInputInfo(info: string): void {
    this.inputInfo = info;
    this.addLog(`setInputInfo info = ${info}`);
  }

}

class KeyboardController {
  private hardKeyState: HardKeyState = { keyCodes: [], specialKeyPress: false };
  private mContext: InputMethodExtensionContext | undefined;
  private panel: inputMethodEngine.Panel | undefined;
  private panelReady: boolean = false;
  private soundPanelVisible: boolean = false;
  private panelGeneration: number = 0;
  private active: boolean = false;
  private heightAdjustment: boolean = false;
  private previewScreenWidth: number = 0;
  private previewScreenHeight: number = 0;
  private adjustmentBottomInset: number = -1;
  private isKeyboardShow: boolean = false;
  private inputHandle: InputHandler = InputHandler.getInstance();
  private mKeyboardDelegate: inputMethodEngine.KeyboardDelegate | undefined;
  private privateCommandRegistered: boolean = false;
  private discardTypingRegistered: boolean = false;
  private typingDiscarded: () => void = (): void => {
    if (!this.active) { return; }
    kanonIme.discardTypingText().catch(() => {});
  };
  private privateCommandReceived: (record: Record<string, inputMethodEngine.CommandDataType>) => void =
    (record: Record<string, inputMethodEngine.CommandDataType>): void => {
      this.inputHandle.addLog('keyboard privateCommand' + JSON.stringify(record));
      Object.keys(record).forEach((key: string) => {
        this.inputHandle.addLog(`onPageShow private command key: ${key}, value: ${record[key]}`);
      });
    };
  private displayChanged: (displayId: number) => void = (displayId: number): void => {
    this.inputHandle.addLog('screenChangeEvent');
    this.resizePanel();
  };
  private inputStopped: () => void = () => {
    if (!this.active) { return; }
    this.inputHandle.addLog('keyboard inputStop');
    editorAdapter.detach();
    englishPrediction.clear();
    const context: InputMethodExtensionContext | undefined = this.mContext;
    this.onDestroy();
    if (context) { context.destroy(); }
  };

  constructor() {
    this.mContext = undefined;
    this.panel = undefined;
    this.mKeyboardDelegate = undefined;
  }

  public onCreate(context: InputMethodExtensionContext): void {
    // Set the writable Mozc profile before settings callbacks or panel creation
    // can prepare the engine and initialize its native storage singletons.
    kanonIme.configureProfile(context.filesDir);
    kanonIme.warmUpEngine();
    // The IME must open its own preferences using its extension context.
    // AbilityStage initialization alone does not guarantee a usable store here.
    openKeyboardPreferences(context);
    refreshSharedLayoutOrder();
    refreshSharedHapticLevel();
    refreshKeyboardHeightPercent();
    keyboardBackground.initialize(context, true).catch(() => {});
    keyboardSettingsSync.onApplied = async (snapshot, heightChanged: boolean, fromPeer: boolean) => {
      this.updateKeySound();
      const candidateKey: string = `${snapshot.candidateFontSize}:${snapshot.candidateRows}`;
      const candidatesChanged: boolean = this.candidateSettingsKey !== candidateKey;
      this.candidateSettingsKey = candidateKey;
      if (heightChanged || candidatesChanged) { this.refreshKeyboardHeight(); }
      if (fromPeer) {
        await kanonIme.prepare();
        const activeLayout: string = AppStorage.get<string>(KANON_LAYOUT) ?? '';
        if (!snapshot.layoutOrder.split(',').includes(activeLayout) ||
          AppStorage.get<string>(KANON_MODE) !== layoutLanguage(activeLayout)) { throw new Error('Layout application pending'); }
      }
    };
    keyboardSettingsSync.initialize(true).catch(() => {});
    this.active = true;
    this.mContext = context;
    this.inputHandle.addLog('onCreate');
    this.initWindow();
    this.registerListener();
    clipboardHistory.start();
  }

  public onDestroy(): void {
    if (!this.active) { return; }
    AppStorage.setOrCreate(KANON_KEYBOARD_VISIBLE, false);
    debugLog.cancelPachinkoReplay();
    this.active = false;
    clipboardHistory.stop();
    this.inputHandle.addLog('onDestroy');
    this.unRegisterListener();
    this.destroyPanel();
  }

  private initWindow(): void {
    if (!this.mContext) { return; }
    const generation: number = ++this.panelGeneration;
    const panelInfo: inputMethodEngine.PanelInfo = {
      type: inputMethodEngine.PanelType.SOFT_KEYBOARD,
      flag: inputMethodEngine.PanelFlag.FLG_FIXED
    };
    this.updateFontScale(this.mContext.config.fontSizeScale ?? 1);
    InputMethodEngine.createPanel(this.mContext, panelInfo).then(async (panel: inputMethodEngine.Panel) => {
      if (!this.active || generation !== this.panelGeneration) {
        await InputMethodEngine.destroyPanel(panel);
        return;
      }
      this.panel = panel;
      this.panelReady = false;
      panel.on('sizeChange', (size: windowManager.Size) => {
        if (generation !== this.panelGeneration || size.width <= 0 || size.height <= 0) { return; }
        AppStorage.setOrCreate(KANON_PANEL_WIDTH_PX, size.width);
        AppStorage.setOrCreate(KANON_PANEL_HEIGHT_PX, size.height);
      });
      // The OS can hide the panel on focus loss without keyboardHide.
      // Use actual panel visibility for the sound pool lifetime.
      panel.on('show', () => {
        if (this.active && generation === this.panelGeneration) {
          if (!this.soundPanelVisible) { perfPanelShown(); }
          if (!this.soundPanelVisible) { debugLog.requestPachinkoReplay(); }
          this.soundPanelVisible = true;
          AppStorage.setOrCreate(KANON_KEYBOARD_VISIBLE, true);
          this.updateKeySound();
          kanonIme.editorVisibilityChanged();
        }
      });
      panel.on('hide', () => {
        if (this.active && generation === this.panelGeneration) {
          if (this.soundPanelVisible) { perfPanelHidden(); }
          this.soundPanelVisible = false;
          AppStorage.setOrCreate(KANON_KEYBOARD_VISIBLE, false);
          debugLog.cancelPachinkoReplay();
          this.updateKeySound();
          kanonIme.editorVisibilityChanged();
        }
      });
      this.applyPanelRect(panel);
      await panel.setUiContent('pages/Index');
      if (!this.active || generation !== this.panelGeneration) { return; }
      this.panelReady = true;
      this.resizePanel();
    }).catch((error: BusinessError) => {
      Log.showInfo(TAG, `panel-create failed code=${error.code}`);
    });
  }

  private destroyPanel(): void {
    if (this.soundPanelVisible) { perfPanelHidden(); }
    perfPanelReset();
    this.soundPanelVisible = false;
    harmonyKeyboardSound.release();
    this.heightAdjustment = false;
    this.adjustmentBottomInset = -1;
    this.panelGeneration++;
    this.panelReady = false;
    const panel: inputMethodEngine.Panel | undefined = this.panel;
    this.panel = undefined;
    if (panel) {
      try {
        panel.off('sizeChange');
        panel.off('show');
        panel.off('hide');
      } catch (error) {
        Log.showInfo(TAG, `panel-listener-release failed code=${(error as BusinessError).code}`);
      }
      InputMethodEngine.destroyPanel(panel).catch((error: BusinessError) => {
        Log.showInfo(TAG, `panel-destroy failed code=${error.code}`);
      });
    }
  }

  private updateKeySound(): void {
    if (this.soundPanelVisible && this.mContext && AppStorage.get<number>(KANON_KEY_SOUND_LEVEL)) {
      harmonyKeyboardSound.prepare(this.mContext);
    } else {
      harmonyKeyboardSound.release();
    }
  }

  public updateFontScale(scale: number): void {
    const fontScale: number = Number.isFinite(scale) && scale > 0 ? Math.min(2, scale) : 1;
    AppStorage.setOrCreate(KANON_FONT_SCALE, fontScale);
    AppStorage.setOrCreate(KANON_TOOLBAR_HEIGHT, toolbarHeight(fontScale));
    this.resizePanel();
  }

  private candidateSettingsKey: string = '';

  private panelSettings(fontScale: number): PanelSettings {
    return {
      fontScale: fontScale,
      candidateFontSize: AppStorage.get<number>(KANON_CANDIDATE_FONT_SIZE) ?? DEFAULT_CANDIDATE_FONT_SIZE,
      candidateRows: AppStorage.get<number>(KANON_CANDIDATE_ROWS) ?? DEFAULT_CANDIDATE_ROWS
    };
  }

  private applyPanelRect(panel: inputMethodEngine.Panel): void {
    try {
      const screen: display.Display = display.getDefaultDisplaySync();
      const dimensions: PanelScreen = panelScreen(screen.width, screen.height, screen.densityPixels);
      const fontScale: number = AppStorage.get<number>(KANON_FONT_SCALE) ?? 1;
      const heightPercent: number = AppStorage.get<number>(KANON_KEYBOARD_HEIGHT_PERCENT) ?? DEFAULT_KEYBOARD_HEIGHT_PERCENT;
      this.previewScreenWidth = dimensions.widthVp;
      this.previewScreenHeight = dimensions.heightVp;
      this.updateHeightPreview(heightPercent);
      const geometry: PanelGeometry = keyboardPanelGeometry(dimensions, heightPercent, this.heightAdjustment,
        this.adjustmentBottomInset, this.panelSettings(fontScale));
      AppStorage.setOrCreate(KANON_HEIGHT_ADJUSTMENT_BOTTOM_VP, geometry.adjustmentBottomVp);
      // Fixed panels are positioned by HarmonyOS, including system navigation area.
      // Register both orientations together instead of racing resize() and moveTo().
      const portraitRect: windowManager.Rect = {
        left: 0, top: 0, width: geometry.portraitWidthPx, height: geometry.portraitHeightPx
      };
      const landscapeRect: windowManager.Rect = {
        left: 0, top: 0, width: geometry.landscapeWidthPx, height: geometry.landscapeHeightPx
      };
      if (geometry.avoidance !== undefined) {
        // Enhanced rectangles include the system inset. Keep the expansion area outside
        // the avoidance region, so the system keyboard background does not cover it.
        const rect: inputMethodEngine.EnhancedPanelRect = {
          portraitRect: portraitRect, landscapeRect: landscapeRect,
          portraitAvoidY: geometry.avoidance.portraitY, landscapeAvoidY: geometry.avoidance.landscapeY
        };
        panel.adjustPanelRect(inputMethodEngine.PanelFlag.FLG_FIXED, rect);
      } else {
        const rect: inputMethodEngine.PanelRect = { portraitRect: portraitRect, landscapeRect: landscapeRect };
        panel.adjustPanelRect(inputMethodEngine.PanelFlag.FLG_FIXED, rect);
      }
      AppStorage.setOrCreate(WINDOW_WIDTH, screen.width);
      AppStorage.setOrCreate(WINDOW_HEIGHT, screen.height);
      AppStorage.setOrCreate(IS_LANDSCAPE, dimensions.landscape);
      if (!this.panelReady) {
        const size: PanelStyleSize = panelStyleSize(dimensions.widthVp, geometry.initialHeightVp, this.panelSettings(fontScale));
        AppStorage.setOrCreate(INPUT_STYLE, StyleConfiguration.getInputStyle(size.width, size.height));
      }
    } catch (error) {
      Log.showInfo(TAG, `panel-layout failed code=${(error as BusinessError).code}`);
    }
  }

  private resizePanel(): void {
    const panel: inputMethodEngine.Panel | undefined = this.panel;
    if (!this.active || !this.panelReady || !panel) { return; }
    this.applyPanelRect(panel);
  }

  public refreshKeyboardHeight(): void {
    refreshKeyboardHeightPercent();
    AppStorage.setOrCreate(KANON_FLICK_PREVIEW, '');
    AppStorage.setOrCreate(KANON_FLICK_PREVIEW_OWNER, '');
    this.resizePanel();
  }

  public previewKeyboardHeight(percent: number): void {
    const value: number = keyboardHeightPreviewPercent(percent);
    AppStorage.setOrCreate(KANON_KEYBOARD_HEIGHT_PERCENT, value);
    AppStorage.setOrCreate(KANON_FLICK_PREVIEW, '');
    AppStorage.setOrCreate(KANON_FLICK_PREVIEW_OWNER, '');
    this.updateHeightPreview(value);
  }

  private updateHeightPreview(percent: number): void {
    if (this.previewScreenWidth <= 0 || this.previewScreenHeight <= 0) { return; }
    const fontScale: number = AppStorage.get<number>(KANON_FONT_SCALE) ?? 1;
    AppStorage.setOrCreate(KANON_HEIGHT_PREVIEW_VP,
      keyboardPanelHeight(this.previewScreenWidth, this.previewScreenHeight, percent, this.panelSettings(fontScale)));
  }

  public beginKeyboardHeightAdjustment(): void {
    this.heightAdjustment = true;
    this.refreshKeyboardHeight();
    const panel: inputMethodEngine.Panel | undefined = this.panel;
    if (!panel) { return; }
    const generation: number = this.panelGeneration;
    try {
      const screen: display.Display = display.getDefaultDisplaySync();
      panel.getSystemPanelCurrentInsets(screen.id).then((insets: inputMethodEngine.SystemPanelInsets) => {
        if (!this.heightAdjustment || generation !== this.panelGeneration) { return; }
        this.adjustmentBottomInset = Math.max(0, insets.bottom);
        this.resizePanel();
      }).catch((error: BusinessError) => {
        Log.showInfo(TAG, `size-adjustment-insets failed code=${error.code}`);
      });
    } catch (error) {
      Log.showInfo(TAG, `size-adjustment-insets failed code=${(error as BusinessError).code}`);
    }
  }

  public endKeyboardHeightAdjustment(): void {
    this.heightAdjustment = false;
    this.refreshKeyboardHeight();
  }

  private registerListener(): void {
    this.inputHandle.addLog('registerListener');

    display.on('change', this.displayChanged);
    InputMethodEngine.on('inputStart', (kbController: inputMethodEngine.KeyboardController, textInputClient: inputMethodEngine.InputClient) => {
      perfMark('ime.inputStart');
      this.inputHandle.addLog('keyboard inputStart');
      debugLog.cancelPachinkoReplay();
      AppStorage.setOrCreate(KANON_PACHINKO_SESSION, (AppStorage.get<number>(KANON_PACHINKO_SESSION) ?? 0) + 1);
      this.inputHandle.onInputStart(kbController, textInputClient);
      clipboardHistory.refresh();
      this.resizePanel();
    })
    InputMethodEngine.on('keyboardShow', () => {
      keyboardSettingsSync.request().catch(() => {});
      // Returning from settings may reuse the current editor without inputStart.
      // Refresh both layout and flick availability before showing the existing panel.
      refreshSharedLayoutOrder();
      refreshSharedHapticLevel();
      AppStorage.setOrCreate(KANON_KEYBOARD_VISIBLE, true);
      keyboardBackground.requestSync().catch(() => {});
      refreshKeyboardHeightPercent();
      this.resizePanel();
    });
    InputMethodEngine.on('keyboardHide', () => {
      AppStorage.setOrCreate(KANON_KEYBOARD_VISIBLE, false);
      debugLog.cancelPachinkoReplay();
    });
    InputMethodEngine.on('inputStop', this.inputStopped);
    try {
      InputMethodEngine.on('discardTypingText', this.typingDiscarded);
      this.discardTypingRegistered = true;
    } catch (error) {
      Log.showInfo(TAG, `discard-listener unavailable code=${(error as BusinessError).code}`);
    }

    this.inputHandle.addLog('pre on privateCommand');
    try {
      InputMethodEngine.on('privateCommand', this.privateCommandReceived);
      this.privateCommandRegistered = true;
    } catch (err) {
      let error = err as BusinessError;
      this.inputHandle.addLog(`on privateCommand sendPrivateCommand catch error: ${error.code} ${error.message}`);
    }

    this.mKeyboardDelegate = inputMethodEngine.getKeyboardDelegate();

    this.mKeyboardDelegate.on('keyDown', (keyEvent: inputMethodEngine.KeyEvent) => {
      pachinkoKeyNotifications.emit();
      if (this.isKeyboardShow) {
        this.inputHandle.hideKeyboardSelf();
      }
      this.inputHandle.addLog(`keyDown: code = ${keyEvent.keyCode}`);
      let result = this.onKeyDown(keyEvent);
      this.inputHandle.addLog(`keyDown: result = ${result}`);
      return result;
    });

    this.mKeyboardDelegate.on('keyUp', (keyEvent: inputMethodEngine.KeyEvent) => {
      this.inputHandle.addLog(`keyUp: code = ${keyEvent.keyCode}`);
      let result = this.onKeyUp(keyEvent);
      this.inputHandle.addLog(`keyUp: result = ${result}`);
      return result;
    });
    this.mKeyboardDelegate.on('cursorContextChange', (x: number, y: number, height: number) => {
      let cursorInfo: CursorInfo = { x: x, y: y, height: height };
      this.inputHandle.setCursorInfo(cursorInfo);
    });
    this.mKeyboardDelegate.on('selectionChange', (oldBegin: number, oldEnd: number, newBegin: number, newEnd: number) => {
      editorAdapter.updateSelection(newBegin, newEnd);
      kanonIme.selectionChanged(newBegin, newEnd);
      if (isDebug) {
        this.inputHandle.setSelectInfo('selectInfo: from(' + oldBegin + ',' + oldEnd + ') to (' + newBegin + ',' + newEnd + ')');
      }
    });
    this.mKeyboardDelegate.on('textChange', (text: string) => {
      kanonIme.textChanged(text.length === 0);
      if (isDebug) { this.inputHandle.setTextInfo('textInfo: ' + text); }
    });
  }

  public onKeyDown(keyEvent: inputMethodEngine.KeyEvent): boolean {
    const keyCode: number = keyEvent.keyCode;
    this.inputHandle.addLog('onKeyDown: code = ' + keyCode);
    const result: HardKeyDownResult = hardKeyDown(keyCode, this.hardKeyState, SDK_HARD_KEY_CODES);
    this.hardKeyState = result.state;
    if (result.repeated) {
      this.inputHandle.addLog(`keyCode down is intercepted: ${keyCode}}`);
    }
    this.inputHandle.addLog(`onKeyDown: this.keyCodes =  ${JSON.stringify(result.state.keyCodes)}}`);
    if (result.unknown) {
      this.inputHandle.addLog('onKeyDown: unknown keyCode');
    }
    if (result.operation === undefined) { return false; }
    this.dispatchHardKey(result.operation);
    return true;
  }

  public onKeyUp(keyEvent: inputMethodEngine.KeyEvent): boolean {
    const keyCode: number = keyEvent.keyCode;
    this.inputHandle.addLog('OnKeyUp: code = ' + keyCode);
    const result: HardKeyUpResult = hardKeyUp(keyCode, this.hardKeyState, SDK_HARD_KEY_CODES);
    this.hardKeyState = result.state;
    if (result.missing) {
      this.inputHandle.addLog(`keyCode KeyUp is intercepted: ${keyCode}`);
    }
    this.inputHandle.addLog(`OnKeyUp: this.keyCodes = ${JSON.stringify(result.state.keyCodes)}`);
    if (result.releasedFunctionKey) {
      this.inputHandle.addLog(`special code: ${keyCode}`);
    } else if (!result.handled) {
      this.inputHandle.addLog(`OnKeyUp: this.isSpecialKeyPress: ${result.state.specialKeyPress}`);
    }
    return result.handled;
  }

  private dispatchHardKey(operation: HardKeyOperation): void {
    switch (operation.kind) {
      case 'text':
        kanonIme.keyText(operation.text ?? '', false);
        break;
      case 'space':
        kanonIme.keySpace(false);
        break;
      case 'delete':
        kanonIme.keyDelete(false);
        break;
      case 'deleteForward':
        kanonIme.keyDeleteForward(false);
        break;
      case 'enter':
        kanonIme.keyReturn(false);
        break;
      case 'up':
        kanonIme.keyMove(SDK_EDITOR_DIRECTIONS.up, false);
        break;
      case 'down':
        kanonIme.keyMove(SDK_EDITOR_DIRECTIONS.down, false);
        break;
      case 'left':
        kanonIme.keyMove(SDK_EDITOR_DIRECTIONS.left, false);
        break;
      case 'right':
        kanonIme.keyMove(SDK_EDITOR_DIRECTIONS.right, false);
        break;
    }
  }

  private unRegisterListener(): void {
    this.inputHandle.addLog('unRegisterListener');

    InputMethodEngine.off('keyboardShow');
    InputMethodEngine.off('keyboardHide');
    InputMethodEngine.off('inputStart');
    InputMethodEngine.off('inputStop', this.inputStopped);
    if (this.discardTypingRegistered) {
      try { InputMethodEngine.off('discardTypingText', this.typingDiscarded); }
      catch (error) { Log.showInfo(TAG, `discard-listener-release failed code=${(error as BusinessError).code}`); }
      this.discardTypingRegistered = false;
    }
    if (this.privateCommandRegistered) {
      try {
        InputMethodEngine.off('privateCommand', this.privateCommandReceived);
      } catch (error) {
        this.inputHandle.addLog(`private-command-listener-release failed code=${(error as BusinessError).code}`);
      } finally {
        this.privateCommandRegistered = false;
      }
    }
    try { display.off('change', this.displayChanged); } catch (error) {
      Log.showInfo(TAG, `display-listener-release failed code=${(error as BusinessError).code}`);
    }
    if (this.mKeyboardDelegate) {
      this.mKeyboardDelegate.off('keyDown');
      this.mKeyboardDelegate.off('keyUp');
      this.mKeyboardDelegate.off('selectionChange');
      this.mKeyboardDelegate.off('cursorContextChange');
      this.mKeyboardDelegate.off('textChange');
    }
  }
}

export const keyboardController: KeyboardController = new KeyboardController();
