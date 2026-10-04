@Component
export struct KeyboardBackgroundCanvas {
  @Prop @Watch('sourceChanged') source: string = '';
  @Prop @Watch('reportGeometry') zoom: number = 100;
  @Prop x: number = 0;
  @Prop y: number = 0;
  @Prop photoBrightness: number = 75;
  @Prop poster: string = '';
  @Prop play: boolean = true;
  @Prop active: boolean = true;
  @State private inViewport: boolean = false;
  @State private canvasWidth: number = 0;
  @State private canvasHeight: number = 0;
  @State private imageRatio: number = 0;
  onGeometry: (width: number, height: number) => void = () => {};

  private sourceChanged(): void {
    this.imageRatio = 0;
    this.reportGeometry();
  }

  private displayedSource(): string {
    if (this.source.startsWith('data:image/gif;') && (!this.play || !this.active || !this.inViewport)) {
      return this.poster;
    }
    return this.source;
  }

  private imageWidth(): number {
    const ratio: number = this.imageRatio > 0 ? this.imageRatio :
      this.canvasWidth / Math.max(1, this.canvasHeight);
    return Math.max(1, Math.max(this.canvasWidth, this.canvasHeight * ratio) * this.zoom / 100);
  }

  private imageHeight(): number {
    const ratio: number = this.imageRatio > 0 ? this.imageRatio :
      this.canvasWidth / Math.max(1, this.canvasHeight);
    return this.imageWidth() / Math.max(0.001, ratio);
  }

  private reportGeometry(): void {
    this.onGeometry(Math.max(0, (this.imageWidth() - this.canvasWidth) / 2),
      Math.max(0, (this.imageHeight() - this.canvasHeight) / 2));
  }

  build() {
    Stack() {
      if (this.source.length > 0) {
        Image(this.displayedSource())
          .width(this.imageWidth())
          .height(this.imageHeight()).objectFit(ImageFit.Fill)
          .brightness(this.photoBrightness / 100)
          .position({
            x: (this.canvasWidth - this.imageWidth()) / 2 * (1 - this.x / 100),
            y: (this.canvasHeight - this.imageHeight()) / 2 * (1 - this.y / 100)
          })
          .onComplete((event) => {
            if (event && event.width > 0 && event.height > 0) {
              this.imageRatio = event.width / event.height;
              this.reportGeometry();
            }
          })
      }
    }
    .width('100%').height('100%').clip(true).hitTestBehavior(HitTestMode.None)
    .onVisibleAreaChange([0, 1], (_visible: boolean, ratio: number) => {
      this.inViewport = ratio > 0;
    })
    .onAreaChange((_previous: Area, current: Area) => {
      this.canvasWidth = Number(current.width);
      this.canvasHeight = Number(current.height);
      this.reportGeometry();
    })
  }
}
