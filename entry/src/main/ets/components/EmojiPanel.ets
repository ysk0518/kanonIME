import { emojiHistory } from '../common/EmojiHistoryStorage';
import { keyboardHaptics } from '../common/KeyboardHaptics';
import { KeyStyle, StyleConfiguration } from '../common/StyleConfiguration';
import { kanonIme } from '../kanon/KanonIme';
import { EMOJI_CATEGORIES, EmojiCategory } from '../model/EmojiData';
import { SubMenuType } from '../model/KeyboardKeyData';
import { DeleteItem } from './DeleteItem';
import { KeyItemGray } from './KeyItemGray';

@Component
export struct EmojiPanel {
  @StorageLink('submenuType') submenuType: number = SubMenuType.EMOJI;
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageProp('kanonEmojiHistory') @Watch('refreshRecent') savedRecent: string = '[]';
  @State private recent: string[] = [];
  @State private selected: number = 0;
  @State private viewportHeight: number = 0;
  private scroller: Scroller = new Scroller();
  private labels: Resource[] = [
    $r('app.string.emoji_recent'), $r('app.string.emoji_faces'), $r('app.string.emoji_people'),
    $r('app.string.emoji_nature'), $r('app.string.emoji_food'), $r('app.string.emoji_travel'),
    $r('app.string.emoji_activities'), $r('app.string.emoji_objects'), $r('app.string.emoji_symbols'),
    $r('app.string.emoji_flags')
  ];

  aboutToAppear(): void { this.refreshRecent(); }

  private refreshRecent(): void { this.recent = emojiHistory.getRecent(); }

  private keyId(value: string, isRecent: boolean): string {
    // The visible copy gets the standard ID when a value appears in both sections.
    if (isRecent && this.selected !== 0) { return `emoji_recent_key_${value}`; }
    if (!isRecent && this.selected === 0 && this.recent.includes(value)) { return `emoji_catalog_key_${value}`; }
    return `emoji_key_${value}`;
  }

  @Builder
  grid(values: string[], isRecent: boolean) {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start, alignContent: FlexAlign.Start }) {
      ForEach(values, (value: string) => {
        Text(value)
          .width('12.5%').height(Math.max(32, Math.min(48, this.inputStyle.subMenuWidth / 8)))
          .fontSize(Math.min(28, this.inputStyle.subMenuWidth / 12)).maxFontScale(1)
          .textAlign(TextAlign.Center).maxLines(1).fontColor($r('app.color.key_text'))
          .id(this.keyId(value, isRecent))
          .onClick(() => { kanonIme.keyEmoji(value); })
      }, (value: string) => value)
    }.width('100%')
  }

  @Builder
  recentSection() {
    if (this.recent.length === 0) {
      Text($r('app.string.emoji_recent_empty')).fontSize(14).fontColor($r('app.color.text_secondary'))
        .width('100%').padding(12).id('emoji_recent_empty')
    } else {
      Text($r('app.string.emoji_clear_recent')).fontSize(13).fontColor($r('app.color.candidate_accent'))
        .padding(8).onClick(() => emojiHistory.clear()).id('emoji_clear_recent')
      this.grid(this.recent, true)
    }
  }

  build() {
    Column() {
      Column() {
        Row() {
          ForEach(EMOJI_CATEGORIES, (category: EmojiCategory, index: number) => {
            Text(category.icon)
              .fontSize(Math.min(20, this.inputStyle.subMenuWidth / 15)).maxFontScale(1).maxLines(1)
              .textAlign(TextAlign.Center).layoutWeight(1).height('100%').borderRadius(6)
              .fontColor($r('app.color.key_text'))
              .backgroundColor(this.selected === index ? $r('app.color.candidate_selected') : Color.Transparent)
              .accessibilityText(this.labels[index])
              .accessibilitySelected(this.selected === index)
              .id(`emoji_tab_${category.id}`)
              .onClick(() => {
                this.selected = index;
                this.scroller.scrollToIndex(index, false, ScrollAlign.START);
              })
          }, (category: EmojiCategory) => category.id)
        }.width('100%').height(36)

        List({ scroller: this.scroller }) {
          ForEach(EMOJI_CATEGORIES, (category: EmojiCategory, index: number) => {
            ListItem() {
              Column() {
                if (index === 0) { this.recentSection() }
                else { this.grid(category.values, false) }
              }
              .width('100%')
              // Let the final tab align to the top even in a tall keyboard.
              .constraintSize({ minHeight: category.id === 'flags' ? this.viewportHeight : 0 })
              .alignItems(HorizontalAlign.Start)
            }
          }, (category: EmojiCategory) => category.id)
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Auto)
        .onAreaChange((_old: Area, area: Area) => { this.viewportHeight = Number(area.height); })
        .onScrollIndex((start: number) => { this.selected = start; })

        Row({ space: this.inputStyle.bottomKeyGap }) {
          Column() {
            KeyItemGray({ keyValue: 'ABC', keyWidth: '100%', keyId: 'emoji_back',
              onActivate: () => { this.submenuType = SubMenuType.NORMAL; } })
          }.layoutWeight(1).height('100%')
          Text($r('app.string.keyboard_space'))
            .textAlign(TextAlign.Center).fontSize(15).maxFontScale(1.25).maxLines(1)
            .fontColor($r('app.color.key_text')).backgroundColor($r('app.color.key_item_normal'))
            .borderRadius(4).layoutWeight(4).height('100%').id('spaceItem')
            .onClick(() => {
              keyboardHaptics.key();
              kanonIme.keyPaste(' ');
            })
          Column() {
            DeleteItem({ keyWidth: '100%' })
          }.layoutWeight(1).height('100%')
        }
        .width('100%').height(Math.min(44, this.inputStyle.basicButtonHeight))
        .padding({ left: 6, right: 6, bottom: 4 })
      }.width(this.inputStyle.subMenuWidth).height('100%')
    }.width('100%').height('100%').backgroundColor($r('app.color.menu_background'))
  }
}
