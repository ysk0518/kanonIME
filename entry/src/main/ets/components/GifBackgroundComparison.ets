import { GifBackgroundStats } from '../common/GifBackgroundProcessor';

@Component
export struct GifBackgroundComparison {
  @Prop original: GifBackgroundStats = new GifBackgroundStats();
  @Prop current: GifBackgroundStats = new GifBackgroundStats();
  @Prop pending: boolean = false;
  @Prop error: string = '';

  private formatBytes(bytes: number): string {
    return bytes >= 1000000 ? `${(bytes / 1000000).toFixed(2)} MB` : `${(bytes / 1000).toFixed(1)} KB`;
  }

  private reduction(before: number, after: number): string {
    if (before <= 0) { return ''; }
    const change: number = (1 - after / before) * 100;
    return change >= 0 ? `${change.toFixed(0)}％減` : `${(-change).toFixed(0)}％増`;
  }

  @Builder
  statsRow(label: string, before: string, after: string) {
    Row({ space: 8 }) {
      Text(label).width('23%').fontSize(12).fontColor($r('app.color.text_secondary'))
      Text(before).layoutWeight(1).fontSize(12).fontColor($r('app.color.text_normal'))
      Text(after).layoutWeight(1).fontSize(12).fontColor($r('app.color.text_normal'))
    }.width('100%').alignItems(VerticalAlign.Top)
  }

  build() {
    Column({ space: 8 }) {
      Text('GIFの比較').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_normal'))
        .width('100%')
      if (this.pending) {
        Text('GIFの情報を読み込み中…').fontSize(12).fontColor($r('app.color.text_secondary'))
      } else if (this.error.length > 0) {
        Text(this.error).fontSize(12).fontColor($r('app.color.text_secondary'))
      } else if (this.original.frames > 0 && this.current.frames > 0) {
        this.statsRow('', '元GIF', '反映中')
        this.statsRow('解像度', `${this.original.width}×${this.original.height}px`, `${this.current.width}×${this.current.height}px`)
        this.statsRow('平均FPS', `${this.original.fps.toFixed(1)} fps`, `${this.current.fps.toFixed(1)} fps`)
        this.statsRow('フレーム数', `${this.original.frames}`, `${this.current.frames}`)
        this.statsRow('1周の時間', `${this.original.seconds.toFixed(2)}秒`, `${this.current.seconds.toFixed(2)}秒`)
        this.statsRow('容量', this.formatBytes(this.original.bytes), this.formatBytes(this.current.bytes))
        Text(`画素数 ${this.reduction(this.original.width * this.original.height, this.current.width * this.current.height)}・` +
          `フレーム数 ${this.reduction(this.original.frames, this.current.frames)}・` +
          `容量 ${this.reduction(this.original.bytes, this.current.bytes)}`)
          .width('100%').fontSize(12).fontColor($r('app.color.text_secondary'))
        Text('平均FPSは1周全体のフレーム数と再生時間から計算しています。')
          .width('100%').fontSize(11).fontColor($r('app.color.text_secondary'))
      }
    }.padding(12).width('100%').borderRadius(12).backgroundColor($r('app.color.key_item_normal'))
      .id('background_gif_comparison')
  }
}
