import { StyleConfiguration, KeyStyle } from '../common/StyleConfiguration';
/* HarmonyOSの入力中表示: ツール列と候補列を同じ高さで切り替える。 */
import { kanonIme } from '../kanon/KanonIme';
import { SubMenuType } from '../model/KeyboardKeyData';
import { KeyboardToolbar } from './KeyboardToolbar';
import { DEFAULT_TOOLBAR_HEIGHT } from '../common/KeyboardLayout';

@Component
export struct CandidateBar {
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('kanonToolbarHeight') toolbarHeight: number = DEFAULT_TOOLBAR_HEIGHT;
  @StorageLink('submenuType') submenuType: number = SubMenuType.NORMAL;
  @StorageLink('kanonMode') mode: string = 'JP';
  @StorageLink('kanonList') @Watch('candidatesChanged') candList: string[] = [];
  @StorageLink('kanonIdList') candIds: number[] = [];
  @StorageLink('kanonSel') sel: number = 0;
  @StorageLink('kanonCandidatesExpanded') expanded: boolean = false;

  private candidatesChanged(): void {
    if (this.candList.length === 0) { this.expanded = false; }
  }

  private tapCandidate(index: number): void {
    if (index >= 0 && index < this.candIds.length) {
      kanonIme.selectCandidate(this.candIds[index]);
    }
  }

  @Builder
  candidate(label: string, index: number) {
    Text(label)
      .fontSize(18)
      .fontColor(index === this.sel ? $r('app.color.candidate_accent') : $r('app.color.candidate_text'))
      .fontWeight(index === this.sel ? FontWeight.Medium : FontWeight.Normal)
      .backgroundColor(index === this.sel ? $r('app.color.candidate_selected') : Color.Transparent)
      .borderRadius(6)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .maxLines(1)
      .onClick(() => this.tapCandidate(index))
      .id(`cand_slot_${index}`)
  }

  build() {
    Column() {
      Row() {
        if (this.candList.length === 0) {
          KeyboardToolbar()
        } else {
          Stack() {
            Image($r('app.media.ic_more')).width(20).height(20).fillColor($r('app.color.key_text'))
          }
          .width(40).height(this.toolbarHeight).margin({ left: 8 })
          .onClick(() => { this.submenuType = SubMenuType.MENU; })
          .accessibilityText('キーボードメニュー').id('candidate_keyboard_menu')
          Scroll() {
            Row({ space: 4 }) {
              ForEach(this.candList, (label: string, index: number) => {
                this.candidate(label, index)
              })
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .height(this.toolbarHeight)
          .id('cand_list')
          Text(this.expanded ? '‹' : '›')
            .fontSize(28)
            .fontColor($r('app.color.text_secondary'))
            .width(36)
            .height(this.toolbarHeight)
            .textAlign(TextAlign.Center)
            .onClick(() => { this.expanded = !this.expanded; })
            .id('cand_expand')
        }
      }
      .width('100%')
      .height(this.toolbarHeight)
      if (this.expanded && this.candList.length > 0) {
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap, alignContent: FlexAlign.Start, alignItems: ItemAlign.Start }) {
            ForEach(this.candList, (label: string, index: number) => {
              this.candidate(label, index)
            })
          }
          .width('100%')
        }
        .height(Math.max(1, this.inputStyle.keyboardHeight - Math.max(36, this.toolbarHeight)))
        .scrollBar(BarState.Off)
        .id('cand_expanded_list')
        Row({ space: 20 }) {
          Text('取消')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .padding(8)
            .onClick(() => { kanonIme.cancelCompose(); })
            .id('cand_cancel')
          if (this.mode === 'JP') {
          Text('文節確定')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .padding(8)
            .onClick(() => { kanonIme.partialCommit(); })
            .id('cand_partial')
          }
        }
        .height(Math.max(36, this.toolbarHeight))
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.candidate_background'))
  }
}
