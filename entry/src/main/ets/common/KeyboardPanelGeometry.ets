import { candidateAreaHeight, candidatePanelHeight } from './CandidateLayout';
import { MAX_KEYBOARD_HEIGHT_PERCENT, MIN_KEYBOARD_HEIGHT_PERCENT, toolbarHeight } from './KeyboardLayout';

export interface PanelSettings {
  fontScale: number;
  candidateFontSize: number;
  candidateRows: number;
}

export interface PanelScreen {
  widthPx: number;
  heightPx: number;
  density: number;
  widthVp: number;
  heightVp: number;
  landscape: boolean;
}

interface PanelAvoidance {
  portraitY: number;
  landscapeY: number;
}

export interface PanelGeometry {
  portraitWidthPx: number;
  portraitHeightPx: number;
  landscapeWidthPx: number;
  landscapeHeightPx: number;
  initialHeightVp: number;
  adjustmentBottomVp: number;
  avoidance?: PanelAvoidance;
}

export interface PanelStyleSize {
  width: number;
  height: number;
}

export function panelScreen(widthPx: number, heightPx: number, densityPixels: number): PanelScreen {
  const density: number = densityPixels > 0 ? densityPixels : 1;
  return {
    widthPx: widthPx, heightPx: heightPx, density: density,
    widthVp: widthPx / density, heightVp: heightPx / density, landscape: widthPx > heightPx
  };
}

export function keyboardPanelHeight(width: number, height: number, percent: number, settings: PanelSettings): number {
  return candidatePanelHeight(width, height, settings.fontScale, percent, settings.candidateFontSize, settings.candidateRows);
}

export function keyboardPanelGeometry(screen: PanelScreen, percent: number, adjusting: boolean, bottomInsetPx: number,
  settings: PanelSettings): PanelGeometry {
  const shortPx: number = Math.min(screen.widthPx, screen.heightPx);
  const longPx: number = Math.max(screen.widthPx, screen.heightPx);
  const density: number = screen.density;
  const shortVp: number = shortPx / density;
  const longVp: number = longPx / density;
  // Dragging changes the preview height inside a fixed canvas.
  const panelPercent: number = adjusting ? MAX_KEYBOARD_HEIGHT_PERCENT : percent;
  const portraitHeight: number = Math.round(keyboardPanelHeight(shortVp, longVp, panelPercent, settings) * density);
  const landscapeHeight: number = Math.round(keyboardPanelHeight(longVp, shortVp, panelPercent, settings) * density);
  const geometry: PanelGeometry = {
    portraitWidthPx: shortPx, portraitHeightPx: portraitHeight,
    landscapeWidthPx: longPx, landscapeHeightPx: landscapeHeight,
    initialHeightVp: (screen.landscape ? landscapeHeight : portraitHeight) / density,
    adjustmentBottomVp: 0
  };
  if (adjusting && bottomInsetPx >= 0) {
    const portraitMinimum: number = Math.round(keyboardPanelHeight(shortVp, longVp, MIN_KEYBOARD_HEIGHT_PERCENT, settings) * density);
    const landscapeMinimum: number = Math.round(keyboardPanelHeight(longVp, shortVp, MIN_KEYBOARD_HEIGHT_PERCENT, settings) * density);
    geometry.portraitHeightPx += bottomInsetPx;
    geometry.landscapeHeightPx += bottomInsetPx;
    geometry.adjustmentBottomVp = bottomInsetPx / density;
    geometry.avoidance = {
      portraitY: Math.max(0, portraitHeight - portraitMinimum),
      landscapeY: Math.max(0, landscapeHeight - landscapeMinimum)
    };
  }
  return geometry;
}

export function panelStyleSize(widthVp: number, initialHeightVp: number, settings: PanelSettings): PanelStyleSize {
  const bar: number = toolbarHeight(settings.fontScale);
  const twoRows: number = candidateAreaHeight(bar, settings.candidateFontSize, 2, settings.fontScale);
  const rows: number = initialHeightVp - twoRows >= 160 ? settings.candidateRows : 1;
  return {
    width: Math.min(720, widthVp),
    height: Math.max(1, initialHeightVp - candidateAreaHeight(bar, settings.candidateFontSize, rows, settings.fontScale))
  };
}
