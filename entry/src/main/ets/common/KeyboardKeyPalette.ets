import resourceManager from '@ohos.resourceManager';
import { ColorMetrics } from '@ohos.arkui.node';
import { usesDarkKeyPalette } from './BackgroundAppearance';
import { debugLog, debugErrorCode } from './DebugLog';

const darkColors: Map<number, number> = new Map<number, number>();

export function initializeKeyboardKeyPalette(resources: resourceManager.ResourceManager): void {
  if (darkColors.size > 0) { return; }
  try {
    const config: resourceManager.Configuration = resources.getConfigurationSync();
    config.colorMode = resourceManager.ColorMode.DARK;
    const darkResources: resourceManager.ResourceManager = resources.getOverrideResourceManager(config);
    // Resolve pressed colors here too, before any key can need them.
    const colors: Resource[] = [
      $r('app.color.candidate_accent'), $r('app.color.candidate_selected'),
      $r('app.color.key_item_gray'), $r('app.color.key_item_gray_pressed'),
      $r('app.color.key_item_normal'), $r('app.color.key_item_normal_pressed'),
      $r('app.color.key_item_normal_text'), $r('app.color.key_text'), $r('app.color.shadow')
    ];
    for (const color of colors) {
      darkColors.set(color.id, darkResources.getColorSync(color.id) >>> 0);
    }
  } catch (error) {
    darkColors.clear();
    debugLog.record('background', `dark key palette unavailable code=${debugErrorCode(error)}`);
  }
}

export function photoKeyColor(color: Resource, hasPhoto: boolean): ResourceColor {
  return usesDarkKeyPalette(hasPhoto, false) ? darkColors.get(color.id) ?? color : color;
}

export function gamingDarkKeys(hasPhoto: boolean, fallback: boolean = false): boolean {
  let systemDark: boolean = fallback;
  if (!hasPhoto) {
    try {
      const text: ColorMetrics = ColorMetrics.resourceColor($r('app.color.key_text'));
      systemDark = text.red + text.green + text.blue > 384;
    } catch (error) {}
  }
  return usesDarkKeyPalette(hasPhoto, systemDark);
}
