import { GifBackgroundStats } from '../common/GifBackgroundProcessor';

@Component
export struct GifBackgroundComparison {
  @Prop original: GifBackgroundStats = new GifBackgroundStats();
  @Prop current: GifBackgroundStats = new GifBackgroundStats();
  @Prop pending: boolean = false;
  @Prop error: ResourceStr = '';

  private formatBytes(bytes: number): string {
    return bytes >= 1000000 ? `${(bytes / 1000000).toFixed(2)} MB` : `${(bytes / 1000).toFixed(1)} KB`;
  }

  private reduction(before: number, after: number): string {
    if (before <= 0) { return ''; }
    const change: number = (1 - after / before) * 100;
    const resource: Resource = change >= 0 ? $r('app.string.gif_reduction') : $r('app.string.gif_increase');
    try {
      return this.getUIContext().getHostContext()?.resourceManager.getStringSync(resource.id, Math.abs(change).toFixed(0)) ?? '';
    } catch (error) { return ''; }
  }

  @Builder
  statsRow(label: ResourceStr, before: ResourceStr, after: ResourceStr) {
    Row({ space: 8 }) {
      Text(label).width('23%').fontSize(12).fontColor($r('app.color.text_secondary'))
      Text(before).layoutWeight(1).fontSize(12).fontColor($r('app.color.text_normal'))
      Text(after).layoutWeight(1).fontSize(12).fontColor($r('app.color.text_normal'))
    }.width('100%').alignItems(VerticalAlign.Top)
  }

  build() {
    Column({ space: 8 }) {
      Text($r('app.string.gif_comparison')).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_normal'))
        .width('100%')
      if (this.pending) {
        Text($r('app.string.gif_stats_loading')).fontSize(12).fontColor($r('app.color.text_secondary'))
      } else if (this.error !== '') {
        Text(this.error).fontSize(12).fontColor($r('app.color.text_secondary'))
      } else if (this.original.frames > 0 && this.current.frames > 0) {
        this.statsRow('', $r('app.string.gif_original'), $r('app.string.gif_current'))
        this.statsRow($r('app.string.gif_resolution'), `${this.original.width}×${this.original.height}px`, `${this.current.width}×${this.current.height}px`)
        this.statsRow($r('app.string.gif_average_fps'), `${this.original.fps.toFixed(1)} fps`, `${this.current.fps.toFixed(1)} fps`)
        this.statsRow($r('app.string.gif_frames'), `${this.original.frames}`, `${this.current.frames}`)
        this.statsRow($r('app.string.gif_duration'), $r('app.string.gif_seconds', this.original.seconds.toFixed(2)), $r('app.string.gif_seconds', this.current.seconds.toFixed(2)))
        this.statsRow($r('app.string.gif_bytes'), this.formatBytes(this.original.bytes), this.formatBytes(this.current.bytes))
        Text($r('app.string.gif_comparison_summary',
          this.reduction(this.original.width * this.original.height, this.current.width * this.current.height),
          this.reduction(this.original.frames, this.current.frames), this.reduction(this.original.bytes, this.current.bytes)))
          .width('100%').fontSize(12).fontColor($r('app.color.text_secondary'))
        Text($r('app.string.gif_average_help'))
          .width('100%').fontSize(11).fontColor($r('app.color.text_secondary'))
      }
    }.padding(12).width('100%').borderRadius(12).backgroundColor($r('app.color.key_item_normal'))
      .id('background_gif_comparison')
  }
}
