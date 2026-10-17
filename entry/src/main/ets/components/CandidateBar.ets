import { StyleConfiguration, KeyStyle } from '../common/StyleConfiguration';
import { kanonIme } from '../kanon/KanonIme';
import { SubMenuType } from '../model/KeyboardKeyData';
import { KeyboardToolbar } from './KeyboardToolbar';
import { DEFAULT_TOOLBAR_HEIGHT } from '../common/KeyboardLayout';
import { candidateAreaHeight, candidateRowHeight, DEFAULT_CANDIDATE_FONT_SIZE, DEFAULT_CANDIDATE_ROWS } from '../common/CandidateLayout';

interface ExpandedCandidatePosition { top: number; height: number; }
interface CandidateColumn {
  firstIndex: number;
  firstLabel: string;
  secondIndex: number;
  secondLabel: string;
  key: string;
}

@Component
export struct CandidateBar {
  @StorageLink('inputStyle') inputStyle: KeyStyle = StyleConfiguration.getSavedInputStyle();
  @StorageLink('kanonToolbarHeight') toolbarHeight: number = DEFAULT_TOOLBAR_HEIGHT;
  @StorageLink('kanonCandidateFontSize') fontSize: number = DEFAULT_CANDIDATE_FONT_SIZE;
  @StorageLink('kanonCandidateDisplayRows') @Watch('selectionChanged') rows: number = DEFAULT_CANDIDATE_ROWS;
  @StorageLink('kanonFontScale') fontScale: number = 1;
  @StorageLink('submenuType') submenuType: number = SubMenuType.NORMAL;
  @StorageLink('kanonMode') mode: string = 'JP';
  @StorageLink('kanonList') @Watch('candidatesChanged') candList: string[] = [];
  @StorageLink('kanonIdList') candIds: number[] = [];
  @StorageLink('kanonSel') @Watch('selectionChanged') sel: number = 0;
  @StorageLink('kanonCandidatesExpanded') expanded: boolean = false;
  @StorageLink('kanonJapaneseComposing') japaneseComposing: boolean = false;
  @StorageLink('kanonConversionReading') conversionReading: string = '';
  @StorageLink('kanonCompositionCursor') compositionCursor: string = '';
  private stripScroller: Scroller = new Scroller();
  private expandedScroller: Scroller = new Scroller();
  private expandedPositions: Map<number, ExpandedCandidatePosition> = new Map();

  private rowHeight(): number { return candidateRowHeight(this.fontSize, this.fontScale); }
  private barHeight(): number { return candidateAreaHeight(this.toolbarHeight, this.fontSize, this.rows, this.fontScale); }
  private columnCount(): number { return Math.ceil(this.candList.length / this.rows); }
  private columns(): CandidateColumn[] {
    const result: CandidateColumn[] = [];
    const count: number = this.columnCount();
    for (let index: number = 0; index < count; index++) {
      const secondIndex: number = this.rows === 2 && index + count < this.candList.length ? index + count : -1;
      const firstLabel: string = this.candList[index];
      const secondLabel: string = secondIndex >= 0 ? this.candList[secondIndex] : '';
      // Equal column counts do not mean equal candidates. Include the displayed
      // values and indices so ForEach cannot retain a previous reading's cells.
      result.push({ firstIndex: index, firstLabel: firstLabel, secondIndex: secondIndex, secondLabel: secondLabel,
        key: `${this.rows}:${index}:${secondIndex}:${JSON.stringify([firstLabel, secondLabel])}` });
    }
    return result;
  }
  private candidatesChanged(): void {
    if (this.candList.length === 0) { this.expanded = false; }
    else if (this.sel <= 0) { this.stripScroller.scrollTo({ xOffset: 0, yOffset: 0 }); }
  }
  private selectionChanged(): void {
    if (this.sel < 0 || this.sel >= this.candList.length) { return; }
    if (this.expanded) { this.revealExpandedSelection(); }
    else { this.stripScroller.scrollToIndex(this.sel % this.columnCount(), true, ScrollAlign.CENTER); }
  }
  private revealExpandedSelection(): void {
    const position: ExpandedCandidatePosition | undefined = this.expandedPositions.get(this.sel);
    if (!position) { return; }
    const viewport: number = Math.max(1, this.inputStyle.keyboardHeight - Math.max(36, this.toolbarHeight));
    const offset: number = this.expandedScroller.currentOffset().yOffset;
    let target: number = offset;
    if (position.top < offset) { target = position.top; }
    else if (position.top + position.height > offset + viewport) { target = position.top + position.height - viewport; }
    if (Math.abs(target - offset) > 0.5) {
      this.expandedScroller.scrollTo({ xOffset: 0, yOffset: Math.max(0, target), animation: false });
    }
  }
  private tapCandidate(index: number): void {
    if (index >= 0 && index < this.candIds.length) {
      kanonIme.selectCandidate(this.candIds[index]);
      this.expanded = false;
    }
  }

  @Builder
  candidate(label: string, index: number, full: boolean) {
    Text(label)
      .fontSize(this.fontSize).maxFontScale(2)
      .fontColor(index === this.sel ? $r('app.color.candidate_accent') : $r('app.color.candidate_text'))
      .fontWeight(index === this.sel ? FontWeight.Medium : FontWeight.Normal)
      .backgroundColor(index === this.sel ? $r('app.color.candidate_selected') : Color.Transparent)
      .borderRadius(6).padding({ left: 12, right: 12, top: 3, bottom: 3 })
      .maxLines(full ? 3 : 1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ minHeight: this.rowHeight(), maxWidth: full ? '100%' : 280 })
      .onAreaChange((_oldArea: Area, area: Area) => {
        if (full) {
          this.expandedPositions.set(index, { top: Number(area.position.y), height: Number(area.height) });
          if (this.expanded && index === this.sel) { this.revealExpandedSelection(); }
        }
      })
      .onClick(() => this.tapCandidate(index)).id(`${full ? 'cand_expanded_slot' : 'cand_slot'}_${index}`)
  }

  build() {
    Column() {
      Row() {
        if (this.candList.length === 0 && !(this.mode === 'JP' && this.japaneseComposing)) {
          KeyboardToolbar()
        } else {
          Column() {
            Stack() { Image($r('app.media.ic_more')).width(20).height(20).fillColor($r('app.color.key_text')) }
              .width(40).height(this.rowHeight())
              .onClick(() => { this.submenuType = SubMenuType.MENU; })
              .accessibilityText($r('app.string.candidate_menu')).id('candidate_keyboard_menu')
            if (this.rows === 2 && (this.compositionCursor.length > 0 || this.conversionReading.length > 0)) {
              if (this.compositionCursor.length > 0) {
                Text(this.compositionCursor).fontSize(12).maxLines(1).width(40)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('app.color.text_secondary')).id('composition_cursor_compact')
              } else {
                Text(this.conversionReading).fontSize(12).maxLines(1).width(40)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('app.color.text_secondary')).id('segment_reading_compact')
              }
            }
          }.width(44).height(this.barHeight())
          if (this.rows === 1 && this.compositionCursor.length > 0) {
            Text(this.compositionCursor).fontSize(14).maxLines(1).constraintSize({ maxWidth: 96 })
              .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('app.color.candidate_accent')).id('composition_cursor')
          } else if (this.rows === 1 && this.conversionReading.length > 0) {
            Text(this.conversionReading).fontSize(12).maxLines(1).width(44)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('app.color.candidate_accent')).id('segment_reading')
          }
          List({ scroller: this.stripScroller, space: 4 }) {
            ForEach(this.columns(), (column: CandidateColumn) => {
              ListItem() {
                Column() {
                  this.candidate(column.firstLabel, column.firstIndex, false)
                  if (column.secondIndex >= 0) {
                    this.candidate(column.secondLabel, column.secondIndex, false)
                  }
                }.alignItems(HorizontalAlign.Start).height(this.barHeight())
              }
            }, (column: CandidateColumn) => column.key)
          }.listDirection(Axis.Horizontal).scrollBar(BarState.Off)
            .layoutWeight(1).height(this.barHeight()).id('cand_list')
          Stack() {
            Image(this.expanded ? $r('app.media.ic_arrow_up') : $r('app.media.ic_arrow_down'))
              .width(20).height(20).fillColor($r('app.color.text_secondary'))
          }.width(40).height(this.barHeight())
            .onClick(() => { this.expanded = !this.expanded; })
            .accessibilityText(this.expanded ? $r('app.string.candidate_collapse') : $r('app.string.candidate_expand'))
            .id('cand_expand')
        }
      }.width('100%').height(this.barHeight())
      if (this.expanded && this.candList.length > 0) {
        Scroll(this.expandedScroller) {
          Flex({ wrap: FlexWrap.Wrap, alignContent: FlexAlign.Start, alignItems: ItemAlign.Start }) {
            ForEach(this.candList, (label: string, index: number) => {
              this.candidate(label, index, true)
            })
          }.width('100%')
        }.scrollable(ScrollDirection.Vertical).height(Math.max(1, this.inputStyle.keyboardHeight - Math.max(36, this.toolbarHeight)))
          .scrollBar(BarState.Auto).onAppear(() => { this.selectionChanged(); }).id('cand_expanded_list')
        Row({ space: 20 }) {
          Text($r('app.string.candidate_cancel')).fontSize(14).fontColor($r('app.color.text_secondary')).padding(8)
            .onClick(() => { kanonIme.cancelCompose(); }).id('cand_cancel')
          if (this.mode === 'JP') {
            Text($r('app.string.candidate_partial')).fontSize(14).fontColor($r('app.color.text_secondary')).padding(8)
              .onClick(() => { kanonIme.partialCommit(); }).id('cand_partial')
          }
        }.height(Math.max(36, this.toolbarHeight))
      }
    }.width('100%').backgroundColor($r('app.color.candidate_background'))
  }
}
