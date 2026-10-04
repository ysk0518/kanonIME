import InputMethodExtensionContext from '@ohos.InputMethodExtensionContext';
import { InputHandler } from '../model/KeyboardController';

export async function openKeyboardSettings(context: InputMethodExtensionContext, background: boolean = false): Promise<boolean> {
  try {
    await context.startAbility({
      bundleName: 'local.yplic.kanon',
      abilityName: 'EntryAbility',
      parameters: { kanonSettings: true, kanonBackground: background }
    });
    InputHandler.getInstance().hideKeyboardSelf();
    return true;
  } catch (e) {
    return false;
  }
}
