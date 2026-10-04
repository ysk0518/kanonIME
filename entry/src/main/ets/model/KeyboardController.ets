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
import { englishPrediction } from '../kanon/EnglishPrediction';
import { clipboardHistory } from '../kanon/ClipboardHistory';
import { BusinessError } from '@ohos.base';
import { GetHardKeyValue } from './HardKeyUtils';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { StyleConfiguration } from '../common/StyleConfiguration';
import { panelHeight, toolbarHeight, DEFAULT_KEYBOARD_HEIGHT_PERCENT, MAX_KEYBOARD_HEIGHT_PERCENT,
  MIN_KEYBOARD_HEIGHT_PERCENT, keyboardHeightPreviewPercent } from '../common/KeyboardLayout';
import { refreshSharedLayoutOrder, refreshSharedHapticLevel, refreshKeyboardHeightPercent } from '../common/KeyboardConfig';

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
    let instance = AppStorage.get<InputHandler>('inputHandler');
    if (instance === undefined) {
      instance = new InputHandler();
      AppStorage.setOrCreate('inputHandler', instance);
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
    AppStorage.setOrCreate('kanonList', [] as string[]);
    AppStorage.setOrCreate('kanonIdList', [] as number[]);
    AppStorage.setOrCreate('kanonCandidatesExpanded', false);
    editorAdapter.queryAttribute().then((res): void => {
      if (epoch !== editorAdapter.getEpoch()) { return; }
      if (!res.ok || res.value === undefined) {
        this.addLog(`onInputStart getEditorAttribute failed code=${res.code}`);
        return;
      }
      AppStorage.setOrCreate('enterKeyType', res.value.enterKeyType);
      AppStorage.setOrCreate('inputPattern', res.value.inputPattern);
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
  private keyCodes: Array<number> = [];
  private mContext: InputMethodExtensionContext | undefined;
  private panel: inputMethodEngine.Panel | undefined;
  private panelReady: boolean = false;
  private panelGeneration: number = 0;
  private active: boolean = false;
  private heightAdjustment: boolean = false;
  private previewScreenWidth: number = 0;
  private previewScreenHeight: number = 0;
  private adjustmentBottomInset: number = -1;
  private isSpecialKeyPress: boolean = false;
  private isKeyboardShow: boolean = false;
  private inputHandle: InputHandler = InputHandler.getInstance();
  private mKeyboardDelegate: inputMethodEngine.KeyboardDelegate | undefined;
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
    this.active = true;
    this.mContext = context;
    this.inputHandle.addLog('onCreate');
    this.initWindow();
    this.registerListener();
    clipboardHistory.start();
  }

  public onDestroy(): void {
    if (!this.active) { return; }
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
        AppStorage.setOrCreate('kanonPanelWidthPx', size.width);
        AppStorage.setOrCreate('kanonPanelHeightPx', size.height);
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
    this.heightAdjustment = false;
    this.adjustmentBottomInset = -1;
    this.panelGeneration++;
    this.panelReady = false;
    const panel: inputMethodEngine.Panel | undefined = this.panel;
    this.panel = undefined;
    if (panel) {
      try { panel.off('sizeChange'); } catch (error) {
        Log.showInfo(TAG, `panel-listener-release failed code=${(error as BusinessError).code}`);
      }
      InputMethodEngine.destroyPanel(panel).catch((error: BusinessError) => {
        Log.showInfo(TAG, `panel-destroy failed code=${error.code}`);
      });
    }
  }

  public updateFontScale(scale: number): void {
    const fontScale: number = Number.isFinite(scale) && scale > 0 ? Math.min(2, scale) : 1;
    AppStorage.setOrCreate('kanonFontScale', fontScale);
    AppStorage.setOrCreate('kanonToolbarHeight', toolbarHeight(fontScale));
    this.resizePanel();
  }

  private applyPanelRect(panel: inputMethodEngine.Panel): void {
    try {
      const screen: display.Display = display.getDefaultDisplaySync();
      const density: number = screen.densityPixels > 0 ? screen.densityPixels : 1;
      const shortPx: number = Math.min(screen.width, screen.height);
      const longPx: number = Math.max(screen.width, screen.height);
      const fontScale: number = AppStorage.get<number>('kanonFontScale') ?? 1;
      const heightPercent: number = AppStorage.get<number>('kanonKeyboardHeightPercent') ?? DEFAULT_KEYBOARD_HEIGHT_PERCENT;
      this.previewScreenWidth = screen.width / density;
      this.previewScreenHeight = screen.height / density;
      this.updateHeightPreview(heightPercent);
      // Allocate the maximum canvas once while adjusting. Dragging never resizes the OS window.
      const panelPercent: number = this.heightAdjustment ? MAX_KEYBOARD_HEIGHT_PERCENT : heightPercent;
      const portraitHeight: number = Math.round(panelHeight(shortPx / density, longPx / density, fontScale, panelPercent) * density);
      const landscapeHeight: number = Math.round(panelHeight(longPx / density, shortPx / density, fontScale, panelPercent) * density);
      AppStorage.setOrCreate('kanonHeightAdjustmentBottomVp',
        this.heightAdjustment && this.adjustmentBottomInset >= 0 ? this.adjustmentBottomInset / density : 0);
      // Fixed panels are positioned by HarmonyOS, including system navigation area.
      // Register both orientations together instead of racing resize() and moveTo().
      if (this.heightAdjustment && this.adjustmentBottomInset >= 0) {
        const portraitMinimum: number = Math.round(panelHeight(shortPx / density, longPx / density,
          fontScale, MIN_KEYBOARD_HEIGHT_PERCENT) * density);
        const landscapeMinimum: number = Math.round(panelHeight(longPx / density, shortPx / density,
          fontScale, MIN_KEYBOARD_HEIGHT_PERCENT) * density);
        // Enhanced rectangles include the system inset. Keep the expansion area outside
        // the avoidance region, so the system keyboard background does not cover it.
        panel.adjustPanelRect(inputMethodEngine.PanelFlag.FLG_FIXED, {
          portraitRect: { left: 0, top: 0, width: shortPx, height: portraitHeight + this.adjustmentBottomInset },
          landscapeRect: { left: 0, top: 0, width: longPx, height: landscapeHeight + this.adjustmentBottomInset },
          portraitAvoidY: Math.max(0, portraitHeight - portraitMinimum),
          landscapeAvoidY: Math.max(0, landscapeHeight - landscapeMinimum)
        });
      } else {
        panel.adjustPanelRect(inputMethodEngine.PanelFlag.FLG_FIXED, {
          portraitRect: { left: 0, top: 0, width: shortPx, height: portraitHeight },
          landscapeRect: { left: 0, top: 0, width: longPx, height: landscapeHeight }
        });
      }
      AppStorage.setOrCreate('windowWidth', screen.width);
      AppStorage.setOrCreate('windowHeight', screen.height);
      AppStorage.setOrCreate('isLandscape', screen.width > screen.height);
      const initialHeight: number = screen.width > screen.height ? landscapeHeight : portraitHeight;
      if (!this.panelReady) {
        AppStorage.setOrCreate('inputStyle', StyleConfiguration.getInputStyle(Math.min(720, screen.width / density),
          Math.max(1, initialHeight / density - toolbarHeight(fontScale))));
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
    AppStorage.setOrCreate('kanonFlickPreview', '');
    AppStorage.setOrCreate('kanonFlickPreviewOwner', '');
    this.resizePanel();
  }

  public previewKeyboardHeight(percent: number): void {
    const value: number = keyboardHeightPreviewPercent(percent);
    AppStorage.setOrCreate('kanonKeyboardHeightPercent', value);
    AppStorage.setOrCreate('kanonFlickPreview', '');
    AppStorage.setOrCreate('kanonFlickPreviewOwner', '');
    this.updateHeightPreview(value);
  }

  private updateHeightPreview(percent: number): void {
    if (this.previewScreenWidth <= 0 || this.previewScreenHeight <= 0) { return; }
    const fontScale: number = AppStorage.get<number>('kanonFontScale') ?? 1;
    AppStorage.setOrCreate('kanonHeightPreviewVp',
      panelHeight(this.previewScreenWidth, this.previewScreenHeight, fontScale, percent));
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
      this.inputHandle.addLog('keyboard inputStart');
      this.inputHandle.onInputStart(kbController, textInputClient);
      clipboardHistory.refresh();
      this.resizePanel();
    })
    InputMethodEngine.on('keyboardShow', () => {
      refreshKeyboardHeightPercent();
      this.resizePanel();
    });
    InputMethodEngine.on('inputStop', this.inputStopped);

    this.inputHandle.addLog('pre on privateCommand');
    try {
      InputMethodEngine.on('privateCommand', (record : Record<string, inputMethodEngine.CommandDataType>) => {
        this.inputHandle.addLog('keyboard privateCommand' + JSON.stringify(record));
        Object.keys(record).forEach((key: string) => {
          this.inputHandle.addLog(`onPageShow private command key: ${key}, value: ${record[key]}`);
        })
      });
    } catch (err) {
      let error = err as BusinessError;
      this.inputHandle.addLog(`on privateCommand sendPrivateCommand catch error: ${error.code} ${error.message}`);
    }

    this.mKeyboardDelegate = inputMethodEngine.getKeyboardDelegate();

    this.mKeyboardDelegate.on('keyDown', (keyEvent: inputMethodEngine.KeyEvent) => {
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
      englishPrediction.selectionChanged(newBegin, newEnd);
      if (isDebug) {
        this.inputHandle.setSelectInfo('selectInfo: from(' + oldBegin + ',' + oldEnd + ') to (' + newBegin + ',' + newEnd + ')');
      }
    });
    this.mKeyboardDelegate.on('textChange', (text: string) => {
      if (isDebug) { this.inputHandle.setTextInfo('textInfo: ' + text); }
    });
  }

  public isShiftKeyHold(): boolean {
    if (this.keyCodes.length === 0) {
      return false;
    }
    let preDownKey = this.keyCodes[0];
    return preDownKey === KeyCode.KEYCODE_SHIFT_LEFT || preDownKey === KeyCode.KEYCODE_SHIFT_RIGHT;
  }

  public onKeyDown(keyEvent: inputMethodEngine.KeyEvent): boolean {
    this.inputHandle.addLog('onKeyDown: code = ' + keyEvent.keyCode);
    let keyCode = keyEvent.keyCode;
    let idx = this.keyCodes.indexOf(keyCode);
    if (idx === -1) {
      this.keyCodes.push(keyCode);
    } else {
      this.inputHandle.addLog(`keyCode down is intercepted: ${keyCode}}`);
    }
    this.inputHandle.addLog(`onKeyDown: this.keyCodes =  ${JSON.stringify(this.keyCodes)}}`);
    if (this.isShiftKeyHold() && this.keyCodes.length === 2 && !this.isKeyCodeAZ(keyCode)) {
      this.isSpecialKeyPress = true;
      return false;
    }
    if (this.isSpecialKeyPress || keyCode === KeyCode.KEYCODE_ALT_LEFT || keyCode === KeyCode.KEYCODE_ALT_RIGHT) {
      return false;
    }
    let keyValue: string = GetHardKeyValue(keyCode, this.isShiftKeyHold());
    if (keyValue === '') {
      this.inputHandle.addLog('onKeyDown: unknown keyCode');
      this.isSpecialKeyPress = true;
      return false;
    }
    return this.inputHardKeyCode(keyValue, keyCode);
  }

  public onKeyUp(keyEvent: inputMethodEngine.KeyEvent): boolean {
    this.inputHandle.addLog('OnKeyUp: code = ' + keyEvent.keyCode);
    let keyCode = keyEvent.keyCode;
    let idx = this.keyCodes.indexOf(keyCode);
    if (idx !== -1) {
      this.keyCodes.splice(idx, 1);
    } else {
      this.inputHandle.addLog(`keyCode KeyUp is intercepted: ${keyCode}`);
    }
    this.inputHandle.addLog(`OnKeyUp: this.keyCodes = ${JSON.stringify(this.keyCodes)}`);

    // For KEYCODE_DEL/KEYCODE_FORWARD_DEL, processed in OnKeyDown, so just intercept it
    if (keyCode === 2055 || keyCode === 2071 || (keyCode >= 2012 && keyCode <= 2016)) {
      this.inputHandle.addLog(`special code: ${keyCode}`);
      return true;
    }

    if (this.isSpecialKeyPress) {
      let keyValue = GetHardKeyValue(keyCode, this.isShiftKeyHold());
      if (!keyValue) {
        this.isSpecialKeyPress = true;
      }
      if (this.keyCodes.length === 0) {
        this.isSpecialKeyPress = false;
      }
      this.inputHandle.addLog(`OnKeyUp: this.isSpecialKeyPress: ${this.isSpecialKeyPress}`);
      return false;
    }
    return true;
  }

  public isKeyCodeAZ(keyCode: number): boolean {
    return keyCode >= KeyCode.KEYCODE_A && keyCode <= KeyCode.KEYCODE_Z;
  }

  public isKeyCodeNumber(keyCode: number): boolean {
    return (keyCode >= KeyCode.KEYCODE_0 && keyCode <= KeyCode.KEYCODE_9) || (keyCode >= KeyCode.KEYCODE_NUMPAD_0 && keyCode <= KeyCode.KEYCODE_NUMPAD_9);
  }

  public inputHardKeyCode(keyValue: string, keyCode: number): boolean {
    if (this.processFunctionKeys(keyValue)) {
      return true;
    }
    if (this.shiftKeys(keyValue)) {
      return false;
    }
    if (keyCode === KeyCode.KEYCODE_SPACE) {
      kanonIme.keySpace(false);
    } else {
      kanonIme.keyText(keyValue, false);
    }
    return true;
  }

  public shiftKeys(keyValue: string): boolean {
    switch (keyValue) {
      case 'KEYCODE_SHIFT_LEFT':
      case 'KEYCODE_SHIFT_RIGHT':
        return true;
      default:
        return false;
    }
  }

  public processFunctionKeys(keyValue: string): boolean {
    switch (keyValue) {
      case "KEYCODE_DEL":
        kanonIme.keyDelete(false);
        return true;
      case "KEYCODE_FORWARD_DEL":
        kanonIme.keyDeleteForward(false);
        return true;
      case "KEYCODE_DPAD_UP":
        kanonIme.keyMove(inputMethodEngine.Direction.CURSOR_UP, false);
        return true;
      case "KEYCODE_DPAD_DOWN":
        kanonIme.keyMove(inputMethodEngine.Direction.CURSOR_DOWN, false);
        return true;
      case "KEYCODE_DPAD_LEFT":
        kanonIme.keyMove(inputMethodEngine.Direction.CURSOR_LEFT, false);
        return true;
      case "KEYCODE_DPAD_RIGHT":
        kanonIme.keyMove(inputMethodEngine.Direction.CURSOR_RIGHT, false);
        return true;
      case "KEYCODE_ENTER":
        kanonIme.keyReturn(false);
        return true;
      default:
        return false;
    }
  }

  private unRegisterListener(): void {
    this.inputHandle.addLog('unRegisterListener');

    InputMethodEngine.off('keyboardShow');
    InputMethodEngine.off('inputStart');
    InputMethodEngine.off('inputStop', this.inputStopped);
    InputMethodEngine.off('privateCommand');
    try { display.off('change', this.displayChanged); } catch (error) {
      Log.showInfo(TAG, `display-listener-release failed code=${(error as BusinessError).code}`);
    }
    if (this.mKeyboardDelegate) {
      this.mKeyboardDelegate.off('keyDown');
      this.mKeyboardDelegate.off('keyUp');
      this.mKeyboardDelegate.off('selectionChange');
      this.mKeyboardDelegate.off('cursorContextChange');
      if (isDebug) {
        this.mKeyboardDelegate.off('textChange');
      }
    }
  }
}

export const keyboardController: KeyboardController = new KeyboardController();
