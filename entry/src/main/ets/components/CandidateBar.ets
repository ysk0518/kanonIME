import { StyleConfiguration, KeyStyle } from '../common/StyleConfiguration';
import { kanonIme } from '../kanon/KanonIme';
import { SubMenuType } from '../model/KeyboardKeyData';
import { KeyboardToolbar } from './KeyboardToolbar';
import { DEFAULT_TOOLBAR_HEIGHT } from '../common/KeyboardLayout';
import { candidateAreaHeight, candidateRowHeight, DEFAULT_CANDIDATE_FONT_SIZE, DEFAULT_CANDIDATE_ROWS } from '../common/CandidateLayout';
import { DEFAULT_LONG_PRESS_MS } from '../common/KeyboardConfigValues';
import { CandidateLabel } from '../kanon/ImeCoordinator';
import { CandidateDeletionResult } from '../kanon/ImeSession';

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
  @StorageLink('kanonMode') @Watch('modeChanged') mode: string = 'JP';
  @StorageLink('kanonLongPressMs') longPressMs: number = DEFAULT_LONG_PRESS_MS;
  @StorageLink('kanonList') @Watch('candidatesChanged') candList: string[] = [];
  @StorageLink('kanonIdList') candIds: number[] = [];
  @StorageLink('kanonSel') @Watch('selectionChanged') sel: number = 0;
  @StorageLink('kanonCandidatesExpanded') @Watch('closeDeleteMenu') expanded: boolean = false;
  @StorageLink('kanonJapaneseComposing') japaneseComposing: boolean = false;
  @StorageLink('kanonConversionReading') conversionReading: string = '';
  @StorageLink('kanonCompositionCursor') compositionCursor: string = '';
  @State private deleteMenuAnchor: string = '';
  @State private deleteNotice: Resource | undefined = undefined;
  private deleteTarget: CandidateLabel | undefined = undefined;
  private deleteNoticeTimer: number = -1;
  private deleteNoticeRequest: number = 0;
  private stripScroller: Scroller = new Scroller();
  private expandedScroller: Scroller = new Scroller();
  private expandedPositions: Map<number, ExpandedCandidatePosition> = new Map();

  private rowHeight(): number { return candidateRowHeight(this.fontSize, this.fontScale); }
  private barHeight(): number { return candidateAreaHeight(this.toolbarHeight, this.fontSize, this.rows, this.fontScale); }
  private columnCount(): number { return Math.ceil(this.candList.length / this.rows); }
  private columns(): CandidateColumn[] {
    const result: CandidateColumn[] = [];
    const count: number = this.columnCount();
    // Fill each column top then bottom, so the best candidates stay in the
    // visible left columns however many candidates Mozc returns.
    for (let column: number = 0; column < count; column++) {
      const index: number = column * this.rows;
      const secondIndex: number = this.rows === 2 && index + 1 < this.candList.length ? index + 1 : -1;
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
    if (this.deleteTarget !== undefined && !kanonIme.getCandidates().includes(this.deleteTarget)) {
      this.closeDeleteMenu();
    }
    if (this.candList.length === 0) { this.expanded = false; }
    else if (this.sel <= 0) { this.stripScroller.scrollTo({ xOffset: 0, yOffset: 0 }); }
  }
  private selectionChanged(): void {
    if (this.sel < 0 || this.sel >= this.candList.length) { return; }
    if (this.expanded) { this.revealExpandedSelection(); }
    else { this.stripScroller.scrollToIndex(Math.floor(this.sel / this.rows), true, ScrollAlign.CENTER); }
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

  private candidateAnchor(index: number, full: boolean): string {
    return `${full ? 'cand_expanded_slot' : 'cand_slot'}_${index}`;
  }

  private holdCandidate(label: string, index: number, full: boolean): void {
    if (this.mode !== 'JP') { return; }
    const item: CandidateLabel | undefined = kanonIme.getCandidates()[index];
    if (item === undefined || item.id !== this.candIds[index] || item.label !== label) { return; }
    this.closeDeleteMenu();
    this.deleteTarget = item;
    this.deleteMenuAnchor = this.candidateAnchor(index, full);
  }

  private closeDeleteMenu(): void {
    this.deleteTarget = undefined;
    this.deleteMenuAnchor = '';
  }

  private async confirmDelete(): Promise<void> {
    const item: CandidateLabel | undefined = this.deleteTarget;
    this.closeDeleteMenu();
    if (item === undefined) { return; }
    const request: number = ++this.deleteNoticeRequest;
    const result: CandidateDeletionResult = await kanonIme.deleteLearnedCandidate(item);
    if (request === this.deleteNoticeRequest) { this.showDeleteNotice(result); }
  }

  private showDeleteNotice(result: CandidateDeletionResult): void {
    this.clearDeleteNotice();
    this.deleteNotice = result === 'deleted' ? $r('app.string.candidate_delete_success') :
      result === 'not-learned' ? $r('app.string.candidate_not_learned') : $r('app.string.candidate_delete_failed');
    this.deleteNoticeTimer = setTimeout(() => {
      this.deleteNotice = undefined;
      this.deleteNoticeTimer = -1;
    }, 2000);
  }

  private clearDeleteNotice(): void {
    if (this.deleteNoticeTimer >= 0) {
      clearTimeout(this.deleteNoticeTimer);
      this.deleteNoticeTimer = -1;
    }
    this.deleteNotice = undefined;
  }

  private modeChanged(): void {
    this.closeDeleteMenu();
    this.deleteNoticeRequest++;
    this.clearDeleteNotice();
  }

  aboutToDisappear(): void {
    this.modeChanged();
  }

  @Builder
  deleteMenu() {
    Row({ space: 4 }) {
      Button($r('app.string.candidate_delete_learning')).fontSize(14)
        .onClick(() => { this.confirmDelete(); }).id('candidate_delete_confirm')
      Button($r('app.string.candidate_delete_cancel')).fontSize(14)
        .onClick(() => { this.closeDeleteMenu(); }).id('candidate_delete_cancel')
    }.padding(6).id('candidate_delete_menu')
  }

  @Builder
  candidate(label: string, index: number, full: boolean) {
    Text(label)
      .fontSize(full ? this.fontSize + 3 : this.fontSize).maxFontScale(2)
      .fontColor(index === this.sel ? $r('app.color.candidate_accent') : $r('app.color.candidate_text'))
      .fontWeight(index === this.sel ? FontWeight.Medium : FontWeight.Normal)
      .backgroundColor(index === this.sel ? $r('app.color.candidate_selected') : Color.Transparent)
      .borderRadius(6).padding(full ? { left: 16, right: 16, top: 12, bottom: 12 } : { left: 12, right: 12, top: 3, bottom: 3 })
      .maxLines(full ? 3 : 1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ minHeight: this.rowHeight(), maxWidth: full ? '100%' : 280 })
      .onAreaChange((_oldArea: Area, area: Area) => {
        if (full) {
          this.expandedPositions.set(index, { top: Number(area.position.y), height: Number(area.height) });
          if (this.expanded && index === this.sel) { this.revealExpandedSelection(); }
        }
      })
      .gesture(GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false, duration: this.longPressMs })
          .onAction(() => this.holdCandidate(label, index, full)),
        TapGesture().onAction(() => this.tapCandidate(index))
      ))
      .onGestureJudgeBegin((info: GestureInfo): GestureJudgeResult =>
        this.mode !== 'JP' && info.type === GestureControl.GestureType.LONG_PRESS_GESTURE ?
          GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE)
      .bindPopup(this.deleteMenuAnchor === this.candidateAnchor(index, full), {
        builder: this.deleteMenu,
        placement: Placement.Top,
        onStateChange: (event) => {
          if (!event.isVisible && this.deleteMenuAnchor === this.candidateAnchor(index, full)) {
            this.closeDeleteMenu();
          }
        }
      })
      .id(this.candidateAnchor(index, full))
  }

  @Builder
  candidateContents() {
    Column() {
      Row() {
        if (this.candList.length === 0 && !(this.mode === 'JP' && this.japaneseComposing)) {
          KeyboardToolbar()
        } else {
          // While composing, candidates use the whole bar like Samsung Keyboard;
          // the toolbar returns once the composition ends. Only the cursor or
          // segment reading keeps a narrow column on the left when present.
          if (this.rows === 2 && (this.compositionCursor.length > 0 || this.conversionReading.length > 0)) {
            Column() {
              if (this.compositionCursor.length > 0) {
                Text(this.compositionCursor).fontSize(12).maxLines(1).width(40)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('app.color.text_secondary')).id('composition_cursor_compact')
              } else {
                Text(this.conversionReading).fontSize(12).maxLines(1).width(40)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('app.color.text_secondary')).id('segment_reading_compact')
              }
            }.width(44).height(this.barHeight()).justifyContent(FlexAlign.Center)
          }
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
          // Samsung Keyboard: a round "…" opens and closes the full list.
          Stack() {
            Stack() {
              Image($r('app.media.ic_more_horiz')).width(20).height(20).fillColor($r('app.color.key_text'))
            }.width(32).height(32).borderRadius(16)
              .backgroundColor(this.expanded ? $r('app.color.candidate_selected') : $r('app.color.key_item_normal'))
          }.width(44).height(this.barHeight())
            .onClick(() => { this.expanded = !this.expanded; })
            .accessibilityText(this.expanded ? $r('app.string.candidate_collapse') : $r('app.string.candidate_expand'))
            .id('cand_expand')
        }
      }.width('100%').height(this.barHeight())
      if (this.expanded && this.candList.length > 0) {
        // Samsung Keyboard's full list: larger candidates centered row by row
        // across the whole width. Close it with the "…" button to use the keys.
        Row() {
          Scroll(this.expandedScroller) {
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center, alignContent: FlexAlign.Start,
              alignItems: ItemAlign.Center }) {
              ForEach(this.candList, (label: string, index: number) => {
                this.candidate(label, index, true)
              })
            }.width('100%').padding({ top: 4, bottom: 8 })
          }.scrollable(ScrollDirection.Vertical).layoutWeight(1).height('100%')
            .scrollBar(BarState.Auto).onAppear(() => { this.selectionChanged(); }).id('cand_expanded_list')
        }.width('100%').height(Math.max(1, this.inputStyle.keyboardHeight))
      }
    }.width('100%').backgroundColor($r('app.color.candidate_background'))
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      this.candidateContents()
      if (this.deleteNotice !== undefined) {
        Text(this.deleteNotice)
          .id('candidate_delete_notice')
          .fontSize(14)
          .fontColor($r('app.color.candidate_text'))
          .backgroundColor($r('app.color.candidate_selected'))
          .padding({ left: 12, right: 12, top: 3, bottom: 3 })
          .margin({ top: 2 })
          .borderRadius(6)
          .hitTestBehavior(HitTestMode.None)
      }
    }.width('100%')
  }
}
