@Component
export struct SettingsHeader {
  @Prop title: Resource = $r('app.string.settings_app_name');
  @Prop compact: boolean = false;
  @Prop disabled: boolean = false;
  onBack: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      Button($r('app.string.settings_back_glyph')).width(44).height(44).fontSize(30).maxFontScale(1)
        .backgroundColor(Color.Transparent).fontColor($r('app.color.settings_accent'))
        .enabled(!this.disabled).accessibilityText($r('app.string.common_back'))
        .onClick(() => this.onBack()).id('keyboard_config_close')
      Text(this.title).minFontSize(12).maxFontSize(26).maxLines(1)
        .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontWeight(FontWeight.Bold).fontColor($r('app.color.text_normal')).layoutWeight(1)
    }.width('100%').constraintSize({ minHeight: this.compact ? 48 : 66 })
      .padding({ left: 8, right: 16, top: 2, bottom: 2 })
  }
}
