// フリック・QWERTY共通のキー上表示。指の移動を遮らないようタッチは受け取らない。
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { keyVisualScale, keyPreviewSize } from '../common/KeyboardLayout';

@Component
export struct FlickPreview {
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('kanonKeyPreviewKind') kind: string = 'flick';
  @StorageLink('kanonFlickPreview') value: string = '';
  @StorageLink('kanonFlickPreviewX') previewX: number = 0;
  @StorageLink('kanonFlickPreviewY') previewY: number = 0;
  @State private panelWidth: number = 360;
  @State private panelHeight: number = 300;
  @State private originX: number = 0;
  @State private originY: number = 0;

  private previewSize(): number { return keyPreviewSize(this.inputStyle.basicButtonHeight); }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.value.length > 0) {
        Text(this.value)
          .fontSize((this.value.length > 1 ? 18 : 28) * keyVisualScale(this.inputStyle.basicButtonHeight))
          .maxFontScale(1.3).maxLines(1)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.candidate_accent'))
          .textAlign(TextAlign.Center)
          .width(this.previewSize())
          .height(this.previewSize())
          .backgroundColor($r('app.color.key_item_normal_pressed'))
          .borderRadius(8)
          .shadow({ radius: 2, color: $r('app.color.shadow'), offsetY: 1 })
          .position({ x: Math.max(4, Math.min(this.previewX - this.originX - this.previewSize() / 2,
            this.panelWidth - this.previewSize() - 4)),
            y: Math.max(4, Math.min(this.previewY - this.originY, this.panelHeight - this.previewSize() - 4)) })
          .accessibilityLevel('no')
          .id(this.kind === 'qwerty' ? 'qwerty_preview' : 'flick_preview')
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
    .onAreaChange((_oldArea: Area, area: Area) => {
      this.panelWidth = Number(area.width);
      this.panelHeight = Number(area.height);
      this.originX = Number(area.globalPosition.x ?? 0);
      this.originY = Number(area.globalPosition.y ?? 0);
    })
  }
}
