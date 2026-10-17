@Component
export struct CandidateAppearancePreview {
  @Prop fontSize: number = 18;
  @Prop rows: number = 2;
  private samples: Resource[] = [$r('app.string.candidate_sample_0'), $r('app.string.candidate_sample_1'),
    $r('app.string.candidate_sample_2'), $r('app.string.candidate_sample_3'), $r('app.string.candidate_sample_4'), $r('app.string.candidate_sample_5')];

  build() {
    Row({ space: 6 }) {
      ForEach([0, 1, 2], (column: number) => {
        Column() {
          ForEach(this.rows === 2 ? [0, 1] : [0], (row: number) => {
            Text(this.samples[row * 3 + column])
              .fontSize(this.fontSize).fontColor($r('app.color.candidate_text'))
              .padding({ left: 8, right: 8, top: 3, bottom: 3 }).maxLines(1)
          })
        }
      })
    }.width('100%').padding(8).borderRadius(8).clip(true)
      .backgroundColor($r('app.color.candidate_background')).id('keyboard_config_candidate_preview')
  }
}
