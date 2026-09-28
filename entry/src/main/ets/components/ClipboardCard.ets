@Component
export struct ClipboardCard {
  @Prop value: string = '';
  @Prop pinned: boolean = false;
  @Prop editing: boolean = false;
  @Prop selected: boolean = false;
  cardId: string = '';
  onTap: () => void = () => {};
  onHold: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Text(this.value.substring(0, 500))
        .fontSize(15).fontColor($r('app.color.text_normal'))
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%').padding({ right: this.editing || this.pinned ? 24 : 0 })
      Row() {
        if (this.editing) {
          Text(this.selected ? '✓' : '')
            .width(18).height(18).fontSize(13).textAlign(TextAlign.Center)
            .fontColor($r('app.color.key_text'))
            .backgroundColor(this.selected ? $r('app.color.candidate_selected') : Color.Transparent)
            .border({ width: 1, color: this.selected ? $r('app.color.candidate_accent') : $r('app.color.text_secondary') })
            .borderRadius(9)
        } else if (this.pinned) {
          Image($r('app.media.ic_pin')).width(14).height(14).fillColor($r('app.color.text_secondary'))
        }
      }.height(this.editing || this.pinned ? 18 : 0)
    }
    .padding(12).width('100%').constraintSize({ minHeight: 56 })
    .backgroundColor(this.selected ? $r('app.color.candidate_selected') : $r('app.color.key_item_normal'))
    .borderRadius(12)
    .border({ width: 1, color: this.selected ? $r('app.color.candidate_accent') : Color.Transparent })
    .gesture(GestureGroup(GestureMode.Exclusive,
      LongPressGesture({ repeat: false, duration: 450 }).onAction(() => this.onHold()),
      TapGesture().onAction(() => this.onTap())
    ))
    .accessibilityText(`${this.selected ? '選択中、' : ''}${this.pinned ? '固定、' : ''}${this.value.substring(0, 80)}`)
    .id(this.cardId)
  }
}
