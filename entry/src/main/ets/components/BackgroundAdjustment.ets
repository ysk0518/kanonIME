/** Each slider observes parent updates instead of retaining a Builder's scalar snapshot. */
@Component
export struct BackgroundAdjustment {
  @Prop label: Resource = $r('app.string.background_zoom');
  @Prop value: number = 0;
  @Prop minimum: number = 0;
  @Prop maximum: number = 100;
  @Prop suffix: string = '%';
  @Prop available: boolean = true;
  sliderId: string = '';
  onChange: (value: number) => void = () => {};

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.label).layoutWeight(1).fontSize(14).fontColor($r('app.color.text_normal'))
        Text(`${Math.round(this.value)}${this.suffix}`).fontSize(14).fontColor($r('app.color.text_normal'))
      }.width('100%').constraintSize({ minHeight: 24 })
      Slider({ value: this.value, min: this.minimum, max: this.maximum, step: 1 })
        .width('100%').enabled(this.available)
        .onChange((value: number) => this.onChange(value))
        .accessibilityText(this.label).id(this.sliderId)
    }.width('100%')
  }
}
