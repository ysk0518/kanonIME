/*
 * Copyright (c) 2022-2023 Huawei Device Co., Ltd.
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
import { EditorDirection } from '../kanon/InputEventTypes';

export interface HardKeyCodes {
  digit0: number;
  digit9: number;
  star: number;
  pound: number;
  dpadUp: number;
  dpadDown: number;
  dpadLeft: number;
  dpadRight: number;
  dpadCenter: number;
  a: number;
  z: number;
  comma: number;
  period: number;
  altLeft: number;
  altRight: number;
  shiftLeft: number;
  shiftRight: number;
  space: number;
  enter: number;
  del: number;
  equals: number;
  slash: number;
  at: number;
  plus: number;
  forwardDel: number;
  numpad0: number;
  numpad9: number;
  numpadEnter: number;
  numpadLeftParen: number;
  numpadRightParen: number;
}

export interface HardKeyState {
  keyCodes: number[];
  specialKeyPress: boolean;
}

type HardKeyOperationKind = 'text' | 'space' | 'enter' | 'delete' | 'deleteForward' | EditorDirection;

export interface HardKeyOperation {
  kind: HardKeyOperationKind;
  text?: string;
}

export interface HardKeyDownResult {
  state: HardKeyState;
  repeated: boolean;
  unknown: boolean;
  operation?: HardKeyOperation;
}

export interface HardKeyUpResult {
  state: HardKeyState;
  missing: boolean;
  handled: boolean;
  releasedFunctionKey: boolean;
}

export function isKeyCodeAZ(keyCode: number, codes: HardKeyCodes): boolean {
  return keyCode >= codes.a && keyCode <= codes.z;
}

export function isKeyCodeNumber(keyCode: number, codes: HardKeyCodes): boolean {
  return (keyCode >= codes.digit0 && keyCode <= codes.digit9) ||
    (keyCode >= codes.numpad0 && keyCode <= codes.numpad9);
}

function isShift(keyCode: number, codes: HardKeyCodes): boolean {
  return keyCode === codes.shiftLeft || keyCode === codes.shiftRight;
}

function keyText(keyCode: number, shiftHeld: boolean, codes: HardKeyCodes): string {
  if (!Number.isInteger(keyCode)) { return ''; }
  if (isKeyCodeAZ(keyCode, codes)) {
    const letters: string = shiftHeld ? 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' : 'abcdefghijklmnopqrstuvwxyz';
    return letters.charAt(keyCode - codes.a);
  }
  // Only top-row digits have historically produced text here.
  if (keyCode >= codes.digit0 && keyCode <= codes.digit9) {
    return '0123456789'.charAt(keyCode - codes.digit0);
  }
  switch (keyCode) {
    case codes.star: return '*';
    case codes.pound: return '#';
    case codes.comma: return ',';
    case codes.period: return '.';
    case codes.equals: return '=';
    case codes.slash: return '/';
    case codes.at: return '@';
    case codes.plus: return '+';
    case codes.numpadLeftParen: return '(';
    case codes.numpadRightParen: return ')';
    default: return '';
  }
}

function keyOperation(keyCode: number, shiftHeld: boolean, codes: HardKeyCodes): HardKeyOperation | undefined {
  switch (keyCode) {
    case codes.del: return { kind: 'delete' };
    case codes.forwardDel: return { kind: 'deleteForward' };
    case codes.dpadUp: return { kind: 'up' };
    case codes.dpadDown: return { kind: 'down' };
    case codes.dpadLeft: return { kind: 'left' };
    case codes.dpadRight: return { kind: 'right' };
    case codes.dpadCenter:
    case codes.enter:
    case codes.numpadEnter: return { kind: 'enter' };
    case codes.space: return { kind: 'space' };
    default:
      const text: string = keyText(keyCode, shiftHeld, codes);
      if (text === '') { return undefined; }
      return { kind: 'text', text: text };
  }
}

export function hardKeyDown(keyCode: number, previous: HardKeyState, codes: HardKeyCodes): HardKeyDownResult {
  const keyCodes: number[] = previous.keyCodes.slice();
  const repeated: boolean = keyCodes.indexOf(keyCode) !== -1;
  if (!repeated) { keyCodes.push(keyCode); }
  const state: HardKeyState = { keyCodes: keyCodes, specialKeyPress: previous.specialKeyPress };
  const result: HardKeyDownResult = { state: state, repeated: repeated, unknown: false };
  const shiftHeld: boolean = isShift(keyCodes[0], codes);
  if (shiftHeld && keyCodes.length === 2 && !isKeyCodeAZ(keyCode, codes)) {
    state.specialKeyPress = true;
    return result;
  }
  if (state.specialKeyPress || keyCode === codes.altLeft || keyCode === codes.altRight || isShift(keyCode, codes)) {
    return result;
  }
  const operation: HardKeyOperation | undefined = keyOperation(keyCode, shiftHeld, codes);
  if (operation === undefined) {
    state.specialKeyPress = true;
    result.unknown = true;
  } else {
    result.operation = operation;
  }
  return result;
}

export function hardKeyUp(keyCode: number, previous: HardKeyState, codes: HardKeyCodes): HardKeyUpResult {
  const keyCodes: number[] = previous.keyCodes.slice();
  const index: number = keyCodes.indexOf(keyCode);
  if (index !== -1) { keyCodes.splice(index, 1); }
  const state: HardKeyState = { keyCodes: keyCodes, specialKeyPress: previous.specialKeyPress };
  // These releases are consumed before the special-key state can be cleared.
  const releasedFunctionKey: boolean = keyCode === codes.del || keyCode === codes.forwardDel ||
    (keyCode >= codes.dpadUp && keyCode <= codes.dpadCenter);
  const handled: boolean = releasedFunctionKey || !state.specialKeyPress;
  if (!handled && keyCodes.length === 0) { state.specialKeyPress = false; }
  return { state: state, missing: index === -1, handled: handled, releasedFunctionKey: releasedFunctionKey };
}
