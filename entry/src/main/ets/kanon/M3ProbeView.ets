/*
 * Kanon IME: M3ProbeView (M3)
 * SPEC §10-4: 偽Editor/偽Engineによる順序・失敗・入力先変更の契約試験。
 * 結果行は試験ID・成否・件数・符号のみ。本文・候補内容は出さない（REQ-07）。
 */

import { ImeCoordinator, UiEvent } from './ImeCoordinator';
import { FakeEditor, FakeEngine, reply, replyError } from './M3Fakes';
import { SubMenuType } from '../model/KeyboardKeyData';

interface Rig {
  coord: ImeCoordinator;
  editor: FakeEditor;
  engine: FakeEngine;
}

function ev(kind: string): UiEvent {
  return { kind: kind };
}

function evText(t: string): UiEvent {
  return { kind: 'text', text: t };
}

@Component
export struct M3ProbeView {
  @StorageLink('submenuType') submenuType: number = SubMenuType.NORMAL;
  @State results: string[] = [];
  @State lastLine: string = '未実行';
  @State busy: boolean = false;

  private fmtErr(e: Object): string {
    try {
      return String(e);
    } catch (ex) {
      return 'unknown';
    }
  }

  private push(line: string): void {
    this.lastLine = line;
    if (this.results.length >= 30) {
      this.results.shift();
    }
    this.results.push(line);
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

  private newRig(): Rig {
    const editor: FakeEditor = new FakeEditor();
    const engine: FakeEngine = new FakeEngine();
    const coord: ImeCoordinator = new ImeCoordinator(editor);
    coord.setEngine(engine);
    const rig: Rig = { coord: coord, editor: editor, engine: engine };
    return rig;
  }

  /** T1 REQ-01: 同一効果の重複適用を抑止する。 */
  private async t1(): Promise<boolean> {
    const rig: Rig = this.newRig();
    const coord: ImeCoordinator = rig.coord;
    const editor: FakeEditor = rig.editor;
    const engine: FakeEngine = rig.engine;
    engine.setScript([
      reply(1, true, 1, 0, [], 0),
      reply(1, false, 0, 0, ['e1'], 1),
      reply(1, false, 0, 0, ['e1'], 1)
    ]);
    await coord.postEvent(evText('a'));
    await coord.postEvent(ev('convert'));
    await coord.postEvent(ev('convert'));
    const s = coord.getSnapshot();
    return editor.count('insert') === 1 && s.dupSuppressed >= 1;
  }

  /** T2 REQ-02/AT-06: 世代ずれ応答を新入力先へ適用しない。 */
  private async t2(): Promise<boolean> {
    const rig: Rig = this.newRig();
    const coord: ImeCoordinator = rig.coord;
    const editor: FakeEditor = rig.editor;
    const engine: FakeEngine = rig.engine;
    engine.setScript([reply(1, false, 0, 0, ['e1'], 1)]);
    engine.hold();
    const p: Promise<void> = coord.postEvent(evText('a'));
    editor.bumpEpoch();
    coord.onEditorChanged();
    engine.releaseHeld();
    await p;
    const s = coord.getSnapshot();
    return s.droppedStale === 1 && editor.count('insert') === 0;
  }

  /** T3 REQ-03: 未確定中のBackspaceは確定済み本文に触れない。 */
  private async t3(): Promise<boolean> {
    const rig: Rig = this.newRig();
    const coord: ImeCoordinator = rig.coord;
    const editor: FakeEditor = rig.editor;
    const engine: FakeEngine = rig.engine;
    engine.setScript([reply(1, true, 1, 0, [], 0), reply(1, true, 0, 0, [], 0)]);
    await coord.postEvent(evText('a'));
    editor.clear();
    await coord.postEvent(ev('backspace'));
    const gotBackspace: boolean = engine.received.indexOf('2:backspace') >= 0;
    return gotBackspace && editor.count('deleteFwd') === 0;
  }

  /** T4 REQ-04: プレビュー確定はfinish＋insert各1回。重複応答で増えない。 */
  private async t4(): Promise<boolean> {
    const rig: Rig = this.newRig();
    const coord: ImeCoordinator = rig.coord;
    const editor: FakeEditor = rig.editor;
    const engine: FakeEngine = rig.engine;
    await coord.loadPreviewSupport();
    engine.setScript([
      reply(1, true, 1, 0, [], 0),
      reply(1, false, 0, 0, ['e1'], 2),
      reply(1, false, 0, 0, ['e1'], 2)
    ]);
    await coord.postEvent(evText('a'));
    await coord.postEvent(ev('submit'));
    await coord.postEvent(ev('submit'));
    return editor.count('finish') === 1 && editor.count('insert') === 1;
  }

  /** T5 REQ-05/AT-18: awaitなし連打でもエンジン到着順を維持する。 */
  private async t5(): Promise<boolean> {
    const rig: Rig = this.newRig();
    const coord: ImeCoordinator = rig.coord;
    const editor: FakeEditor = rig.editor;
    const engine: FakeEngine = rig.engine;
    engine.setScript([
      reply(1, true, 1, 0, [], 0),
      reply(2, true, 2, 0, [], 0),
      reply(3, true, 3, 0, [], 0)
    ]);
    const p1: Promise<void> = coord.postEvent(evText('a'));
    const p2: Promise<void> = coord.postEvent(evText('a'));
    const p3: Promise<void> = coord.postEvent(evText('a'));
    await p1;
    await p2;
    await p3;
    const want: string[] = ['1:text', '2:text', '3:text'];
    if (engine.received.length !== 3) {
      return false;
    }
    for (let i: number = 0; i < 3; i++) {
      if (engine.received[i] !== want[i]) {
        return false;
      }
    }
    return editor.count('insert') === 0;
  }

  /** T6 REQ-06/AT-09: 書込失敗は再送せず回復保留。resetで復帰。 */
  private async t6(): Promise<boolean> {
    const rig: Rig = this.newRig();
    const coord: ImeCoordinator = rig.coord;
    const editor: FakeEditor = rig.editor;
    const engine: FakeEngine = rig.engine;
    engine.setScript([reply(1, false, 0, 0, ['e1'], 1)]);
    editor.failNextWrites = 1;
    await coord.postEvent(evText('a'));
    const s1 = coord.getSnapshot();
    const recvBefore: number = engine.received.length;
    await coord.postEvent(evText('a'));
    const recvAfter: number = engine.received.length;
    await coord.postEvent(ev('reset'));
    const s2 = coord.getSnapshot();
    return editor.count('insert') === 1 && s1.needsRecovery &&
      recvBefore === recvAfter && !s2.needsRecovery;
  }

  /** T7 REQ-08/AT-07: 古いrevisionの候補タップを無効化する。 */
  private async t7(): Promise<boolean> {
    const rig: Rig = this.newRig();
    const coord: ImeCoordinator = rig.coord;
    const editor: FakeEditor = rig.editor;
    const engine: FakeEngine = rig.engine;
    engine.setScript([
      reply(1, true, 1, 2, [], 0),
      reply(2, true, 2, 2, [], 0)
    ]);
    await coord.postEvent(evText('a'));
    await coord.postEvent(ev('convert'));
    const sel: UiEvent = { kind: 'select', candidateId: 0, expectedRevision: 1 };
    await coord.postEvent(sel);
    const s = coord.getSnapshot();
    let hasSelect: boolean = false;
    for (let i: number = 0; i < engine.received.length; i++) {
      if (engine.received[i].indexOf(':select') >= 0) {
        hasSelect = true;
      }
    }
    return !hasSelect && s.lastError === 'stale-revision';
  }

  /** T8 REQ-10/AT-04: 未確定の確定成功後にENへ。失敗時はJPのまま。 */
  private async t8(): Promise<boolean> {
    // 成功系。
    const rig1: Rig = this.newRig();
    const c1: ImeCoordinator = rig1.coord;
    const e1: FakeEditor = rig1.editor;
    const g1: FakeEngine = rig1.engine;
    g1.setScript([
      reply(1, true, 2, 0, [], 0),
      reply(1, false, 0, 0, ['e9'], 2)
    ]);
    await c1.postEvent(evText('a'));
    const modeEv: UiEvent = { kind: 'mode', text: 'EN' };
    await c1.postEvent(modeEv);
    const s1 = c1.getSnapshot();
    const okPath: boolean = s1.mode === 'EN' && s1.state === 'DIRECT_EN' && e1.count('insert') === 1;
    // 失敗系：確定のinsertが失敗したら切替しない。
    const rig2: Rig = this.newRig();
    const c2: ImeCoordinator = rig2.coord;
    const e2: FakeEditor = rig2.editor;
    const g2: FakeEngine = rig2.engine;
    g2.setScript([
      reply(1, true, 2, 0, [], 0),
      reply(1, false, 0, 0, ['e9'], 2)
    ]);
    await c2.postEvent(evText('a'));
    e2.failNextWrites = 1;
    await c2.postEvent(modeEv);
    const s2 = c2.getSnapshot();
    const ngPath: boolean = s2.mode === 'JP' && s2.needsRecovery;
    return okPath && ngPath;
  }

  /** T9 REQ-09/AT-13: 回復不能エンジン失敗はENGINE_ERROR。EN退避は可。 */
  private async t9(): Promise<boolean> {
    const rig: Rig = this.newRig();
    const coord: ImeCoordinator = rig.coord;
    const editor: FakeEditor = rig.editor;
    const engine: FakeEngine = rig.engine;
    engine.setScript([replyError(99, false)]);
    await coord.postEvent(evText('a'));
    const s1 = coord.getSnapshot();
    await coord.postEvent(evText('a'));
    const modeEv: UiEvent = { kind: 'mode', text: 'EN' };
    await coord.postEvent(modeEv);
    const s2 = coord.getSnapshot();
    return s1.state === 'ENGINE_ERROR' && s2.mode === 'EN' && s2.state === 'DIRECT_EN';
  }

  /** T10: 未確定なしBackspaceは本文へ直接削除し、エンジンを呼ばない。 */
  private async t10(): Promise<boolean> {
    const rig: Rig = this.newRig();
    const coord: ImeCoordinator = rig.coord;
    const editor: FakeEditor = rig.editor;
    const engine: FakeEngine = rig.engine;
    await coord.postEvent(ev('backspace'));
    const s = coord.getSnapshot();
    return editor.count('deleteFwd') === 1 && engine.received.length === 0 && s.lastError === 'ok';
  }

  /** T11: 未確定なしEnterはempty-submitを返し、エンジンを空振りさせない。 */
  private async t11(): Promise<boolean> {
    const rig: Rig = this.newRig();
    const coord: ImeCoordinator = rig.coord;
    const editor: FakeEditor = rig.editor;
    const engine: FakeEngine = rig.engine;
    await coord.postEvent(ev('submit'));
    const s = coord.getSnapshot();
    return engine.received.length === 0 && editor.count('insert') === 0 && s.lastError === 'empty-submit';
  }

  /** T12: 確立済みpreviewの確定は置換＋finishでinsertを重ねない（実機の二重確定防止）。 */
  private async t12(): Promise<boolean> {
    const rig: Rig = this.newRig();
    const coord: ImeCoordinator = rig.coord;
    const editor: FakeEditor = rig.editor;
    const engine: FakeEngine = rig.engine;
    await coord.loadPreviewSupport();
    engine.setScript([
      reply(1, true, 1, 0, [], 0),
      reply(1, false, 0, 0, ['e1'], 2)
    ]);
    await coord.postEvent(evText('a'));
    // 実機のKanonIme相当：preview範囲を確立させる。
    await coord.refreshPreview('p', 0, 1);
    const nSetBefore: number = editor.count('setPreview');
    await coord.postEvent(ev('submit'));
    return editor.count('finish') === 1 && editor.count('insert') === 0 &&
      editor.count('setPreview') === nSetBefore + 1;
  }

  /** T13: 直前サロゲートペアのBackspaceは2単位削除する（AT-11機構）。 */
  private async t13(): Promise<boolean> {
    const rig: Rig = this.newRig();
    const coord: ImeCoordinator = rig.coord;
    const editor: FakeEditor = rig.editor;
    const engine: FakeEngine = rig.engine;
    editor.beforeText = String.fromCharCode(0x61, 0xD83D, 0xDE00);
    editor.cursorPos = editor.beforeText.length;
    await coord.postEvent(ev('backspace'));
    const s = coord.getSnapshot();
    return editor.count('deleteFwd') === 2 && engine.received.length === 0 &&
      editor.beforeText.length === 1 && s.lastError === 'ok';
  }

  private async runAll(): Promise<void> {
    const names: string[] = ['T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8', 'T9', 'T10', 'T11', 'T12', 'T13'];
    let pass: number = 0;
    const results: boolean[] = [];
    try {
      results.push(await this.t1());
      results.push(await this.t2());
      results.push(await this.t3());
      results.push(await this.t4());
      results.push(await this.t5());
      results.push(await this.t6());
      results.push(await this.t7());
      results.push(await this.t8());
      results.push(await this.t9());
      results.push(await this.t10());
      results.push(await this.t11());
      results.push(await this.t12());
      results.push(await this.t13());
    } catch (e) {
      this.push(`run ERR ${this.fmtErr(e).slice(0, 60)}`);
      return;
    }
    for (let i: number = 0; i < results.length; i++) {
      this.push(`${names[i]} ${results[i] ? 'ok' : 'NG'}`);
      if (results[i]) {
        pass++;
      }
    }
    this.push(`m3 ${pass}/${results.length} pass`);
  }

  build() {
    Column() {
      Text('M3 契約試験 (偽物)')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .id('m3_title')
      Text(this.lastLine)
        .fontSize(13)
        .backgroundColor(Color.White)
        .width('100%')
        .height(28)
        .id('m3_last')
      Grid() {
        GridItem() {
          Button('実行').onClick(() => {
            this.guard(async (): Promise<void> => {
              await this.runAll();
            });
          }).id('m3_run')
        }
        GridItem() {
          Button('戻る').onClick(() => {
            this.submenuType = SubMenuType.NORMAL;
          }).id('m3_back')
        }
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(8)
      .rowsGap(8)
      .width('100%')
      .height('20%')
      List() {
        ForEach(this.results, (line: string, idx: number) => {
          ListItem() {
            Text(line).fontSize(11)
          }
        })
      }
      .width('100%')
      .height('60%')
      .backgroundColor(Color.White)
    }
    .width('100%')
    .height('100%')
    .padding(8)
  }
}
