// Visual guide only: input continues to be handled by the original key.
@Component
export struct NumberFlickGuide {
  @Prop values: string[] = [];
  @Prop selectedDirection: number = 0;
  @Prop cellSize: number = 44;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach([0, 1, 2, 3, 4], (side: number) => {
        if ((this.values[side] ?? '').length > 0) {
          Text(this.values[side])
            .fontSize(side === this.selectedDirection ? 24 : 18)
            .minFontSize(10).maxFontSize(side === this.selectedDirection ? 24 : 18)
            .maxFontScale(1.3).maxLines(1)
            .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
            .fontWeight(side === this.selectedDirection ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(side === this.selectedDirection ? $r('app.color.candidate_accent') : $r('app.color.text_normal'))
            .textAlign(TextAlign.Center).width(this.cellSize).height(this.cellSize)
            .backgroundColor(side === this.selectedDirection ? $r('app.color.candidate_selected') : $r('app.color.key_item_normal'))
            .borderRadius(8)
            .border({ width: 1, color: side === this.selectedDirection ? $r('app.color.candidate_accent') : $r('app.color.text_secondary') })
            .position({ x: (side === 1 ? 0 : side === 3 ? 2 : 1) * this.cellSize,
              y: (side === 2 ? 0 : side === 4 ? 2 : 1) * this.cellSize })
            .id(`number_flick_guide_${side}`)
        }
      })
    }
    .width(this.cellSize * 3).height(this.cellSize * 3)
    .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}
