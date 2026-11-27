import { KANON_HAPTIC_LEVEL, KANON_KEY_SOUND_LEVEL } from './AppStorageKeys';
import { DEFAULT_KEY_SOUND_LEVEL } from './KeyboardConfigValues';
import { keyboardSound } from './HarmonyKeyboardSound';
import inputMethodEngine from '@ohos.inputMethodEngine';
import vibrator from '@ohos.vibrator';

const PRESS_FEEDBACK_MS: number = 1500;

class KeyboardHaptics {
  private supportedSoft: boolean | undefined = undefined;
  private supportedHard: boolean | undefined = undefined;
  private lastPulse: number = 0;
  private celebrationUntil: number = 0;
  private pressedAt: number = -1;

  // Character keys give feedback when the finger lands, as Samsung and Gboard do,
  // instead of when the character is entered on release. The release then skips
  // its own feedback once. A press that never reaches release expires.
  press(): void {
    this.fire();
    this.pressedAt = Date.now();
  }

  key(): void {
    if (this.pressedAt >= 0) {
      const pressed: boolean = Date.now() - this.pressedAt < PRESS_FEEDBACK_MS;
      this.pressedAt = -1;
      if (pressed) { return; }
    }
    this.fire();
  }

  celebrationPulse(duration: number): void {
    if ((AppStorage.get<number>(KANON_HAPTIC_LEVEL) ?? 1) === 0) { return; }
    try {
      if (!this.vibrationAllowed()) { return; }
      const effect: vibrator.VibrateEffect = { type: 'time', duration: duration };
      this.lastPulse = Date.now();
      this.celebrationUntil = this.lastPulse + duration;
      vibrator.startVibration(effect, { usage: 'touch' }).catch(() => {});
    } catch (error) {}
  }

  stopCelebration(): void {
    if (Date.now() >= this.celebrationUntil) { return; }
    this.celebrationUntil = 0;
    try {
      if (!this.vibrationAllowed()) { return; }
      vibrator.stopVibration(vibrator.VibratorStopMode.VIBRATOR_STOP_MODE_TIME).catch(() => {});
    } catch (error) {}
  }

  private vibrationAllowed(): boolean {
    // BASIC_MODE does not permit vibrator access from an input method.
    return inputMethodEngine.getInputMethodAbility().getSecurityMode() === inputMethodEngine.SecurityMode.FULL;
  }

  private fire(): void {
    // BASIC can attempt playback of the same local click. It uses no protected
    // vibrator API or editor contents, and any playback failure is ignored.
    keyboardSound.key(AppStorage.get<number>(KANON_KEY_SOUND_LEVEL) ?? DEFAULT_KEY_SOUND_LEVEL);
    const level: number = AppStorage.get<number>(KANON_HAPTIC_LEVEL) ?? 1;
    if (level === 0) { return; }
    const now: number = Date.now();
    if (now < this.celebrationUntil || now - this.lastPulse < 45) { return; }
    try {
      if (!this.vibrationAllowed()) { return; }
      if (this.supportedSoft === undefined) {
        this.supportedSoft = vibrator.isSupportEffectSync(vibrator.HapticFeedback.EFFECT_SOFT);
      }
      if (level === 2 && this.supportedHard === undefined) {
        this.supportedHard = vibrator.isSupportEffectSync(vibrator.HapticFeedback.EFFECT_HARD);
      }
      const effect: vibrator.VibrateEffect = level === 2 && this.supportedHard ?
        { type: 'preset', effectId: vibrator.HapticFeedback.EFFECT_HARD } :
        this.supportedSoft ? { type: 'preset', effectId: vibrator.HapticFeedback.EFFECT_SOFT } :
          { type: 'time', duration: level === 2 ? 16 : 10 };
      this.lastPulse = now;
      vibrator.startVibration(effect, { usage: 'touch' }).catch(() => {});
    } catch (e) {
      // Feedback is optional; an unavailable motor must not interrupt typing.
    }
  }
}

export const keyboardHaptics: KeyboardHaptics = new KeyboardHaptics();
