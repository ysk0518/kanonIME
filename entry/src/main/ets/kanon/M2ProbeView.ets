/*
 * Kanon IME: M2 変換プローブ画面
 * 実OSS辞書の同一プロセス変換を実機で実証する。固定fixture 'nihongo' のみ。
 * 入力内容・候補全文のログ出力はしない。結果行は操作名・成否・件数・長さのみ。
 */

import { SubMenuType } from '../model/KeyboardKeyData';
import fs from '@ohos.file.fs';

interface BridgeApi {
  init(profile: string): boolean;
  convert(keys: string): string;
  selectCandidate(id: number): string;
  submit(): string;
  reset(): boolean;
}

// 固定fixture。端末内の実文章は使わない。
const FIX_KEYS: string = 'nihongo';

class Cand {
  id: number = -1;
  value: string = '';
}

class ConvOut {
  ok: boolean = false;
  preedit_len: number = -1;
  preedit: string = '';
  ncand: number = -1;
  candidates: Cand[] = [];
  result: string = '';
}

function parseOut(json: string): ConvOut {
  const out = new ConvOut();
  try {
    const o = JSON.parse(json) as ConvOut;
    out.ok = o.ok === true;
    out.preedit_len = o.preedit_len ?? -1;
    out.preedit = o.preedit ?? '';
    out.ncand = o.ncand ?? -1;
    if (o.candidates instanceof Array) {
      out.candidates = o.candidates as Cand[];
    }
    out.result = o.result ?? '';
  } catch (e) {
  }
  return out;
}

@Component
export struct M2ProbeView {
  @StorageLink('submenuType') submenuType: number = SubMenuType.NORMAL;
  @State results: string[] = [];
  @State lastLine: string = '未実行';
  @State busy: boolean = false;
  private bridgeObj: BridgeApi | null = null;

  private async ensureBridge(): Promise<boolean> {
    if (this.bridgeObj !== null) {
      return true;
    }
    try {
      const m: ESObject = await import('libkanon_bridge.so');
      const ns: ESObject = m as ESObject;
      const d: ESObject = ns.default as ESObject;
      this.push(`ns keys=${Object.keys(ns).join(',').slice(0, 40)} deftype=${typeof d}`);
      const api = (d ?? ns) as BridgeApi;
      if (api === null || api === undefined) {
        this.push('bridge ERR api noteq');
        return false;
      }
      this.bridgeObj = api;
      return true;
    } catch (e) {
      this.push(`bridge ERR ${this.fmtErr(e).slice(0, 60)}`);
      return false;
    }
  }

  private push(line: string): void {
    this.lastLine = line;
    const next: string[] = this.results.concat([line]);
    this.results = next.length > 40 ? next.slice(next.length - 40) : next;
  }

  private fmtErr(e: Object): string {
    try {
      return String(e);
    } catch (ex) {
      return 'unknown';
    }
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

  aboutToAppear(): void {
    this.lastLine = '未実行';
  }

  build() {
    Column() {
      Text('M2 実変換（nihongo固定）').fontSize(14).fontWeight(FontWeight.Bold)
      Text(this.lastLine)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .height(40)
        .backgroundColor(Color.White)
        .padding(4)
        .id('m2_last')
      Grid() {
        GridItem() {
          Button('初期化').onClick(() => {
            this.guard(async (): Promise<void> => {
              try {
                if (!(await this.ensureBridge())) {
                  return;
                }
                const api: BridgeApi = this.bridgeObj as BridgeApi;
                const ok: boolean = api.init('');
                this.push(`init ${ok ? 'OK' : 'NG'}`);
              } catch (e) {
                this.push(`init ERR ${this.fmtErr(e).slice(0, 60)}`);
              }
            });
          }).id('m2_init')
        }
        GridItem() {
          Button('変換').onClick(() => {
            this.guard(async (): Promise<void> => {
              try {
                if (!(await this.ensureBridge())) {
                  return;
                }
                const api: BridgeApi = this.bridgeObj as BridgeApi;
                const out: ConvOut = parseOut(api.convert(FIX_KEYS));
                this.push(`conv ${out.ok ? 'OK' : 'NG'} ncand=${out.ncand} prelen=${out.preedit_len}`);
              } catch (e) {
                this.push(`conv ERR ${this.fmtErr(e).slice(0, 60)}`);
              }
            });
          }).id('m2_conv')
        }
        GridItem() {
          Button('選択2').onClick(() => {
            this.guard(async (): Promise<void> => {
              try {
                if (!(await this.ensureBridge())) {
                  return;
                }
                const api: BridgeApi = this.bridgeObj as BridgeApi;
                const out: ConvOut = parseOut(api.selectCandidate(2));
                this.push(`sel ${out.ok ? 'OK' : 'NG'} ncand=${out.ncand} prelen=${out.preedit_len}`);
              } catch (e) {
                this.push(`sel ERR ${this.fmtErr(e).slice(0, 60)}`);
              }
            });
          }).id('m2_sel')
        }
        GridItem() {
          Button('確定').onClick(() => {
            this.guard(async (): Promise<void> => {
              try {
                if (!(await this.ensureBridge())) {
                  return;
                }
                const api: BridgeApi = this.bridgeObj as BridgeApi;
                const out: ConvOut = parseOut(api.submit());
                const rlen: number = out.result ? out.result.length : -1;
                this.push(`commit ${out.ok ? 'OK' : 'NG'} rlen=${rlen}`);
              } catch (e) {
                this.push(`commit ERR ${this.fmtErr(e).slice(0, 60)}`);
              }
            });
          }).id('m2_commit')
        }
        GridItem() {
          Button('取消').onClick(() => {
            this.guard(async (): Promise<void> => {
              try {
                if (!(await this.ensureBridge())) {
                  return;
                }
                const api: BridgeApi = this.bridgeObj as BridgeApi;
                const ok: boolean = api.reset();
                this.push(`reset ${ok ? 'OK' : 'NG'}`);
              } catch (e) {
                this.push(`reset ERR ${this.fmtErr(e).slice(0, 60)}`);
              }
            });
          }).id('m2_reset')
        }
        GridItem() {
          Button('診断').onClick(() => {
            this.guard(async (): Promise<void> => {
              try {
                const ctx: ESObject = getContext(this) as ESObject;
                const dir: string = ctx.bundleCodeDir as string;
                const tail: string = dir.length > 40 ? dir.slice(dir.length - 40) : dir;
                let msg: string = `code=${tail}`;
                const cands: string[] = [dir + '/libs/arm64', dir + '/libs/arm64-v8a', dir + '/entry/libs/arm64'];
                for (let i: number = 0; i < cands.length; i++) {
                  try {
                    const names: string[] = fs.listFileSync(cands[i]);
                    let detail: string = '';
                    for (let j: number = 0; j < names.length && j < 4; j++) {
                      try {
                        const st: fs.Stat = fs.statSync(cands[i] + '/' + names[j]);
                        detail += `${names[j].slice(0, 12)}:${st.size},`;
                      } catch (e2) {
                        detail += `${names[j].slice(0, 12)}:?,`;
                      }
                    }
                    msg = `ls${i}=${names.length}件 ${detail}`.slice(0, 80);
                    break;
                  } catch (e) {
                    if (i === cands.length - 1) {
                      msg = `ls ERR ${this.fmtErr(e).slice(0, 40)}`;
                    }
                  }
                }
                this.push(msg);
              } catch (e) {
                this.push(`diag ERR ${this.fmtErr(e).slice(0, 60)}`);
              }
            });
          }).id('m2_diag')
        }
        GridItem() {
          Button('戻る').onClick(() => {
            this.submenuType = SubMenuType.NORMAL;
          }).id('m2_back')
        }
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(8)
      .rowsGap(8)
      .width('100%')
      .height('45%')
      List() {
        ForEach(this.results, (line: string, idx: number) => {
          ListItem() {
            Text(line).fontSize(11)
          }
        })
      }
      .width('100%')
      .height('40%')
      .backgroundColor(Color.White)
    }
    .width('100%')
    .height('100%')
    .padding(8)
  }
}
