// フリック・QWERTY共通のキー上表示。指の移動を遮らないようタッチは受け取らない。
import { NumberFlickGuide } from './NumberFlickGuide';

@Component
export struct FlickPreview {
  @StorageLink('kanonKeyPreviewKind') kind: string = 'flick';
  @StorageLink('kanonFlickPreview') value: string = '';
  @StorageLink('kanonFlickPreviewX') previewX: number = 0;
  @StorageLink('kanonFlickPreviewY') previewY: number = 0;
  @StorageLink('kanonKeyPreviewDirections') directions: string[] = [];
  @StorageLink('kanonKeyPreviewDirection') selectedDirection: number = 0;
  @StorageLink('kanonKeyPreviewKeyHeight') keyHeight: number = 0;
  @StorageLink('kanonKeyPreviewFlickDistance') flickDistance: number = 18;
  @State private panelWidth: number = 360;
  @State private panelHeight: number = 300;
  @State private originX: number = 0;
  @State private originY: number = 0;

  private baseGuideSize(): number {
    if (this.kind === 'number_guide_above') {
      // The bottom row has too little space below its center for a readable cross.
      const roomAbove: number = this.previewY - this.originY - this.flickDistance - 24 - 4;
      return Math.max(1, Math.min(132, this.panelWidth - 8, roomAbove));
    }
    const centerX: number = this.previewX - this.originX;
    const centerY: number = this.guideCenterY();
    // Preserve the key center even at panel edges; fit the cross by reducing its size.
    const room: number = Math.min(centerX - 4, this.panelWidth - centerX - 4,
      centerY - 4, this.panelHeight - centerY - 4);
    return Math.max(1, Math.min(132, room * 2));
  }

  private guideCenterY(): number {
    return this.previewY - this.originY + this.keyHeight / 2;
  }

  private guideCell(): number {
    return this.baseGuideSize() / 3;
  }

  private guideWidth(): number {
    return this.guideCell() * 3;
  }

  private guideX(): number {
    const size: number = this.guideWidth();
    const center: number = this.previewX - this.originX;
    const target: number = center - size / 2;
    return this.kind === 'number_guide_above' ? Math.max(4, Math.min(target, this.panelWidth - size - 4)) : target;
  }

  private guideY(): number {
    const height: number = this.guideCell() * 3;
    if (this.kind === 'number_guide_above') {
      return Math.max(4, this.previewY - this.originY - this.flickDistance - 24 - height);
    }
    return this.guideCenterY() - height / 2;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if ((this.kind === 'number_guide' || this.kind === 'number_guide_above') && this.directions.length > 0) {
        NumberFlickGuide({ values: this.directions, selectedDirection: this.selectedDirection,
          cellSize: this.guideCell() })
          .position({ x: this.guideX(), y: this.guideY() })
          .id('number_flick_guide')
      } else if (this.value.length > 0) {
        Text(this.value)
          .fontSize(this.value.length > 1 ? 18 : 28)
          .maxFontScale(1.3).maxLines(1)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.candidate_accent'))
          .textAlign(TextAlign.Center)
          .width(56)
          .height(56)
          .backgroundColor($r('app.color.key_item_normal_pressed'))
          .borderRadius(8)
          .shadow({ radius: 2, color: $r('app.color.shadow'), offsetY: 1 })
          .position({ x: Math.max(4, Math.min(this.previewX - this.originX - 28, this.panelWidth - 60)),
            y: Math.max(4, Math.min(this.previewY - this.originY, this.panelHeight - 60)) })
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
