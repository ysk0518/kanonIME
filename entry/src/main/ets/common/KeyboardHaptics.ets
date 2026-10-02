import inputMethodEngine from '@ohos.inputMethodEngine';
import vibrator from '@ohos.vibrator';

class KeyboardHaptics {
  private supportedSoft: boolean | undefined = undefined;
  private supportedHard: boolean | undefined = undefined;
  private lastPulse: number = 0;

  key(): void {
    const level: number = AppStorage.get<number>('kanonHapticLevel') ?? 1;
    if (level === 0) { return; }
    const now: number = Date.now();
    if (now - this.lastPulse < 45) { return; }
    try {
      // BASIC_MODE does not permit vibrator access from an input method.
      if (inputMethodEngine.getInputMethodAbility().getSecurityMode() !== inputMethodEngine.SecurityMode.FULL) {
        return;
      }
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
