const test = require('node:test');
const assert = require('node:assert/strict');
const { keyboardPanelGeometry, keyboardPanelHeight, panelScreen, panelStyleSize } =
  require('../../entry/src/main/ets/common/KeyboardPanelGeometry.ets');

// Expected values from the original controller at 420 × 900 vp and density 2.5.
// Percent, scale, rows, panel heights (px), preview heights (vp), style heights (vp).
const cases = [
  [80, 1, 1, 603, 500, 241, 200, 201.2, 160],
  [100, 1, 1, 730, 540, 292, 216, 252, 176],
  [150, 1, 1, 1045, 578, 418, 231, 378, 191.2],
  [80, 1, 2, 643, 540, 257, 216, 201.2, 160],
  [100, 1, 2, 770, 578, 308, 231, 252, 175.2],
  [150, 1, 2, 1080, 578, 432, 231, 376, 175.2],
  [80, 1.3, 1, 613, 510, 245, 204, 201.2, 160],
  [100, 1.3, 1, 740, 550, 296, 220, 252, 176],
  [150, 1.3, 1, 1055, 578, 422, 231, 378, 187.2],
  [80, 1.3, 2, 678, 575, 271, 230, 201.2, 160],
  [100, 1.3, 2, 805, 578, 322, 231, 252, 161.2],
  [150, 1.3, 2, 1080, 578, 432, 231, 362, 161.2]
];

for (const [percent, fontScale, candidateRows, portraitPx, landscapePx,
  portraitPreview, landscapePreview, portraitStyle, landscapeStyle] of cases) {
  const settings = { fontScale, candidateFontSize: 18, candidateRows };
  for (const landscape of [false, true]) {
    test(`P31: ${landscape ? 'landscape' : 'portrait'} geometry at ${percent}%, scale ${fontScale}, ${candidateRows} rows`, () => {
      const screen = landscape ? panelScreen(2250, 1050, 2.5) : panelScreen(1050, 2250, 2.5);
      assert.equal(screen.landscape, landscape);
      const geometry = keyboardPanelGeometry(screen, percent, false, 37, settings);
      assert.deepEqual(geometry, {
        portraitWidthPx: 1050, portraitHeightPx: portraitPx,
        landscapeWidthPx: 2250, landscapeHeightPx: landscapePx,
        initialHeightVp: (landscape ? landscapePx : portraitPx) / 2.5,
        adjustmentBottomVp: 0
      });
      assert.equal(keyboardPanelHeight(screen.widthVp, screen.heightVp, percent, settings),
        landscape ? landscapePreview : portraitPreview);
      assert.deepEqual(panelStyleSize(screen.widthVp, geometry.initialHeightVp, settings), {
        width: landscape ? 720 : 420, height: landscape ? landscapeStyle : portraitStyle
      });
    });
  }
}

test('P31: height adjustment reserves the maximum canvas and adds the inset outside avoidance', () => {
  const screen = panelScreen(1050, 2250, 2.5);
  const settings = { fontScale: 1.3, candidateFontSize: 18, candidateRows: 2 };
  const pendingInset = keyboardPanelGeometry(screen, 100, true, -1, settings);
  assert.deepEqual(pendingInset, {
    portraitWidthPx: 1050, portraitHeightPx: 1080,
    landscapeWidthPx: 2250, landscapeHeightPx: 578,
    initialHeightVp: 432, adjustmentBottomVp: 0
  });
  const inset = keyboardPanelGeometry(screen, 80, true, 37, settings);
  assert.deepEqual(inset, {
    portraitWidthPx: 1050, portraitHeightPx: 1117,
    landscapeWidthPx: 2250, landscapeHeightPx: 615,
    initialHeightVp: 432, adjustmentBottomVp: 14.8,
    avoidance: { portraitY: 402, landscapeY: 3 }
  });
  assert.deepEqual(keyboardPanelGeometry(screen, 150, true, 37, settings), inset);
  assert.deepEqual(keyboardPanelGeometry(screen, 100, true, 0, settings), {
    ...pendingInset, avoidance: inset.avoidance
  });
  assert.equal(keyboardPanelHeight(screen.widthVp, screen.heightVp, 100.4, settings), 323);
});

test('P31: short landscape falls back to one candidate row and invalid density falls back to one', () => {
  const screen = panelScreen(2200, 1000, 2.5);
  const settings = { fontScale: 1.3, candidateFontSize: 24, candidateRows: 2 };
  assert.equal(keyboardPanelHeight(screen.widthVp, screen.heightVp, 100, settings), 212);
  const geometry = keyboardPanelGeometry(screen, 100, false, -1, settings);
  assert.deepEqual(panelStyleSize(screen.widthVp, geometry.initialHeightVp, settings), { width: 720, height: 168 });
  for (const density of [0, -1, NaN]) {
    assert.deepEqual(panelScreen(300, 300, density), {
      widthPx: 300, heightPx: 300, density: 1, widthVp: 300, heightVp: 300, landscape: false
    });
  }
  assert.deepEqual(panelStyleSize(300, 20, settings), { width: 300, height: 1 });
});
