/** Each slider observes parent updates instead of retaining a Builder's scalar snapshot. */
@Component
export struct BackgroundAdjustment {
  @Prop label: string = '';
  @Prop value: number = 0;
  @Prop minimum: number = 0;
  @Prop maximum: number = 100;
  @Prop suffix: string = '%';
  @Prop available: boolean = true;
  sliderId: string = '';
  onChange: (value: number) => void = () => {};

  build() {
    Column({ space: 8 }) {
      Text(`${this.label}  ${Math.round(this.value)}${this.suffix}`)
        .width('100%').fontSize(14).fontColor($r('app.color.text_normal'))
      Slider({ value: this.value, min: this.minimum, max: this.maximum, step: 1 })
        .width('100%').enabled(this.available)
        .onChange((value: number) => this.onChange(value))
        .accessibilityText(this.label).id(this.sliderId)
    }.width('100%')
  }
}
