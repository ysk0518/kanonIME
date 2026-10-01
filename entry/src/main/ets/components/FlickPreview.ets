// フリック・QWERTY共通のキー上表示。指の移動を遮らないようタッチは受け取らない。

@Component
export struct FlickPreview {
  @StorageLink('kanonKeyPreviewKind') kind: string = 'flick';
  @StorageLink('kanonFlickPreview') value: string = '';
  @StorageLink('kanonFlickPreviewX') previewX: number = 0;
  @StorageLink('kanonFlickPreviewY') previewY: number = 0;
  @State private panelWidth: number = 360;
  @State private panelHeight: number = 300;
  @State private originX: number = 0;
  @State private originY: number = 0;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.value.length > 0) {
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
