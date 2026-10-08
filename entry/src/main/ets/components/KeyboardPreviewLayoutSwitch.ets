/** Change the preview layout without changing the saved keyboard configuration. */
@Component
export struct KeyboardPreviewLayoutSwitch {
  @Prop qwerty: boolean = false;
  @Prop disabled: boolean = false;
  idPrefix: string = 'keyboard_preview';
  onChange: (qwerty: boolean) => void = () => {};

  build() {
    Row({ space: 8 }) {
      ForEach([false, true], (qwerty: boolean) => {
        Button(qwerty ? $r('app.string.settings_layout_qwerty') : $r('app.string.settings_layout_flick'))
          .layoutWeight(1).height(36).enabled(!this.disabled)
          .fontColor(this.qwerty === qwerty ? $r('app.color.candidate_accent') : $r('app.color.text_normal'))
          .backgroundColor(this.qwerty === qwerty ? $r('app.color.candidate_selected') : $r('app.color.key_item_normal'))
          .accessibilityText(qwerty ? (this.qwerty ? $r('app.string.background_qwerty_selected') :
            $r('app.string.background_qwerty_preview')) : (this.qwerty ? $r('app.string.background_flick_preview') :
            $r('app.string.background_flick_selected')))
          .onClick(() => this.onChange(qwerty))
          .id(`${this.idPrefix}_${qwerty ? 'qwerty' : 'flick'}`)
      })
    }.width('100%')
  }
}
