/*
 * Kanon IME: G-01 プローブ画面 (M1)
 * SPEC §5「プレビューのAPI実証」用。固定fixtureのみを使い、入力内容を表示・ログへ出さない。
 * 結果行に含めるのは操作名・成否・コード・長さ・真偽のみ。
 */

import inputMethodEngine from '@ohos.inputMethodEngine';
import { SubMenuType } from '../model/KeyboardKeyData';
import { editorAdapter, EditorResult, EditorValue, AttributeSnapshot } from './EditorAdapter';

// 固定fixture。端末内の実文章は使わない。
const FIX_READ: string = 'にほんご';
const FIX_READ2: string = 'にほんごのへんかん';
const FIX_CAND: string = '日本語';
const FIX_AB: string = 'AB';
const FIX_EMOJI: string = 'a' + String.fromCharCode(0xD83D, 0xDE00) + 'b';

function fmt(res: EditorResult): string {
  return `${res.op} ${res.ok ? 'OK' : 'NG'} code=${res.code} ${res.detail}`;
}

function hasLoneSurrogate(s: string): boolean {
  for (let i: number = 0; i < s.length; i++) {
    const c: number = s.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF) {
      const n: number = i + 1 < s.length ? s.charCodeAt(i + 1) : 0;
      if (n < 0xDC00 || n > 0xDFFF) {
        return true;
      }
      i++;
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      return true;
    }
  }
  return false;
}

@Component
export struct G01ProbeView {
  @StorageLink('submenuType') submenuType: number = SubMenuType.NORMAL;
  @State results: string[] = [];
  @State lastLine: string = '未実行';
  @State busy: boolean = false;
  @State lastStart: number = -1;
  @State lastEnd: number = -1;
  @State enterType: number = -1;

  private push(line: string): void {
    this.lastLine = line;
    const next: string[] = this.results.concat([line]);
    this.results = next.length > 40 ? next.slice(next.length - 40) : next;
  }

  private async guard(fn: () => Promise<void>): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      await fn();
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column() {
      Text('G-01 API実証（固定文のみ）').fontSize(14).fontWeight(FontWeight.Bold)
      Text(this.lastLine)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .height(40)
        .backgroundColor(Color.White)
        .padding(4)
        .id('g01_last')
      Grid() {
        GridItem() {
          Button('属性取得').onClick(() => {
            this.guard(async (): Promise<void> => {
              const r: EditorValue<AttributeSnapshot> = await editorAdapter.queryAttribute();
              if (r.ok && r.value !== undefined) {
                this.enterType = r.value.enterKeyType;
                this.push(`attr OK pattern=${r.value.inputPattern} enter=${r.value.enterKeyType} preview=${r.value.isTextPreviewSupported}`);
              } else {
                this.push(`attr NG code=${r.code}`);
              }
            });
          })
        }
        GridItem() {
          Button('作成P').onClick(() => {
            this.guard(async (): Promise<void> => {
              const q: EditorValue<number> = await editorAdapter.queryIndex();
              if (!q.ok || q.value === undefined) {
                this.push(`qIndex NG code=${q.code}`);
                return;
              }
              const idx: number = q.value;
              const r: EditorResult = await editorAdapter.setPreview(FIX_READ, idx, idx);
              if (r.ok) {
                this.lastStart = idx;
                this.lastEnd = idx + FIX_READ.length;
              }
              this.push(fmt(r));
            });
          })
        }
        GridItem() {
          Button('更新P').onClick(() => {
            this.guard(async (): Promise<void> => {
              if (this.lastStart < 0) {
                this.push('updateP skip no-range');
                return;
              }
              const r: EditorResult = await editorAdapter.setPreview(FIX_READ2, this.lastStart, this.lastEnd);
              if (r.ok) {
                this.lastEnd = this.lastStart + FIX_READ2.length;
              }
              this.push(fmt(r));
            });
          })
        }
        GridItem() {
          Button('置換P').onClick(() => {
            this.guard(async (): Promise<void> => {
              if (this.lastStart < 0) {
                this.push('replaceP skip no-range');
                return;
              }
              const r: EditorResult = await editorAdapter.setPreview(FIX_CAND, this.lastStart, this.lastEnd);
              if (r.ok) {
                this.lastEnd = this.lastStart + FIX_CAND.length;
              }
              this.push(fmt(r));
            });
          })
        }
        GridItem() {
          Button('確定').onClick(() => {
            this.guard(async (): Promise<void> => {
              const r: EditorResult = await editorAdapter.finishPreview();
              if (r.ok) {
                this.lastStart = -1;
                this.lastEnd = -1;
              }
              this.push(fmt(r));
            });
          })
        }
        GridItem() {
          Button('取消削除').onClick(() => {
            this.guard(async (): Promise<void> => {
              if (this.lastStart < 0) {
                this.push('cancelDel skip no-range');
                return;
              }
              const n: number = this.lastEnd - this.lastStart;
              const r: EditorResult = await editorAdapter.deleteBackward(n);
              if (r.ok) {
                this.lastStart = -1;
                this.lastEnd = -1;
              }
              this.push(fmt(r));
            });
          })
        }
        GridItem() {
          Button('挿入AB').onClick(() => {
            this.guard(async (): Promise<void> => {
              this.push(fmt(await editorAdapter.insert(FIX_AB)));
            });
          })
        }
        GridItem() {
          Button('左へ').onClick(() => {
            this.guard(async (): Promise<void> => {
              this.push(fmt(await editorAdapter.moveCursor(inputMethodEngine.Direction.CURSOR_LEFT)));
            });
          })
        }
        GridItem() {
          Button('方向確認').onClick(() => {
            this.guard(async (): Promise<void> => {
              // 挿入AB→左への後に実行。前=A・後=Bのはず（対応付けの仮説）。
              const qi: EditorValue<number> = await editorAdapter.queryIndex();
              const idx: number = (qi.ok && qi.value !== undefined) ? qi.value : -1;
              const r: EditorValue<string[]> = await editorAdapter.queryAround(5, 5);
              if (!r.ok || r.value === undefined) {
                this.push(`around NG code=${r.code} idx=${idx}`);
                return;
              }
              const fwd: string = r.value[0];
              const bwd: string = r.value[1];
              const fwdIsA: boolean = fwd === 'A';
              const bwdIsB: boolean = bwd === 'B';
              this.push(`around OK idx=${idx} fwdLen=${fwd.length} bwdLen=${bwd.length} fwdIsA=${fwdIsA} bwdIsB=${bwdIsB}`);
            });
          })
        }
        GridItem() {
          Button('B削除').onClick(() => {
            this.guard(async (): Promise<void> => {
              const r: EditorResult = await editorAdapter.deleteBackward(1);
              const qi: EditorValue<number> = await editorAdapter.queryIndex();
              const idx: number = (qi.ok && qi.value !== undefined) ? qi.value : -1;
              this.push(`${fmt(r)} idx=${idx}`);
            });
          })
        }
        GridItem() {
          Button('F削除').onClick(() => {
            this.guard(async (): Promise<void> => {
              const r: EditorResult = await editorAdapter.deleteForward(1);
              const qi: EditorValue<number> = await editorAdapter.queryIndex();
              const idx: number = (qi.ok && qi.value !== undefined) ? qi.value : -1;
              this.push(`${fmt(r)} idx=${idx}`);
            });
          })
        }
        GridItem() {
          Button('絵文字挿入').onClick(() => {
            this.guard(async (): Promise<void> => {
              this.push(fmt(await editorAdapter.insert(FIX_EMOJI)));
            });
          })
        }
        GridItem() {
          Button('絵1削除').onClick(() => {
            this.guard(async (): Promise<void> => {
              const qi: EditorValue<number> = await editorAdapter.queryIndex();
              const before: number = (qi.ok && qi.value !== undefined) ? qi.value : -1;
              const d: EditorResult = await editorAdapter.deleteBackward(1);
              const r: EditorValue<string[]> = await editorAdapter.queryAround(5, 5);
              if (!r.ok || r.value === undefined) {
                this.push(`${fmt(d)} | around NG code=${r.code} idxBefore=${before}`);
                return;
              }
              const lone: boolean = hasLoneSurrogate(r.value[0]) || hasLoneSurrogate(r.value[1]);
              this.push(`${fmt(d)} | idxBefore=${before} loneSurrogate=${lone} fwdLen=${r.value[0].length} bwdLen=${r.value[1].length}`);
            });
          })
        }
        GridItem() {
          Button('Enter').onClick(() => {
            this.guard(async (): Promise<void> => {
              if (this.enterType < 0) {
                this.push('enter skip need-attr');
                return;
              }
              this.push(fmt(await editorAdapter.sendEnterAction(this.enterType)));
            });
          })
        }
        GridItem() {
          Button('結果消去').onClick(() => {
            this.results = [];
          })
        }
        GridItem() {
          Button('戻る').onClick(() => {
            this.submenuType = SubMenuType.NORMAL;
          })
        }
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .rowsGap(8)
      .columnsGap(8)
      .padding(8)
      List() {
        ForEach(this.results, (line: string, index: number) => {
          ListItem() {
            Text(line).fontSize(11).fontFamily('monospace')
          }
        })
      }
      .width('100%')
      .height('45%')
      .backgroundColor(Color.White)
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
  }
}
