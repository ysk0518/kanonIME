> 履歴資料です。現在の仕様とビルド手順はルートのREADMEおよびdocs/KANON_SPEC.mdを参照してください。

# 和音IME 実装担当への依頼

2026-09-27。今回の担当は仕様に従ってWinPC側で実装するエージェント。本文作成時点では実装エージェントへの送信・起動は行っていない。

## 読む順番と目的

1. 作業先に適用されるAGENTS.md。
2. [KANON_SPEC.md](../KANON_SPEC.md) — **現在の実装仕様の正本**。
3. [SIGNING_VALIDATION_RESULT.md](SIGNING_VALIDATION_RESULT.md) — 署名とネイティブIME起動は成功済み。
4. [KANON_VALIDATION.md](../KANON_VALIDATION.md) — 実証・受入結果の記録先。

ユーザーの目的はGboardの操作・入力体験の再現。Gboard本体はAncoの実装制限により断念し、候補の内容・順位・学習結果が一致しないことは了承済み。独自の操作を勝手に増やさず、Gboardとの差を記録して進める。

QWERTYローマ字先行、入力先の下線付き未確定表示、日→英で表示文字を確定して切替はユーザー明示合意。入力中の予測・変換候補とタップ選択を省いてSpace必須のIMEにしない。

## 作業範囲

- bundle `local.yplic.kanon`、HarmonyOSネイティブ、ArkTS + C++ Node-API、同一プロセス内Mozc。
- Windows / DevEco 6.1系、SDK/APIは実際の環境で記録。前回成功構成はHarmonyOS API24。Linux側CLIはAPI18なので混同しない。
- ソフトウェアQWERTY、日英、変換・編集・切替、数字記号、エラー時の復帰。
- フリック、英語予測、永続学習等はv1.0の対象外。将来機能のために最初から全般的なプラグイン基盤を作らない。
- ストア公開・Gboard制限解除・自作CA署名の再調査はしない。

## 使える成果物

| 場所（Linux側） | 状態 |
|---|---|
| `harmony-ime/native-ime-probe/` | 実機登録・選択・文字入力に成功したKika由来のサンプル |
| `harmony-ime/kanon-ime.zip` | 引継ぎ用既存zip。内容と版は担当側で確認し、名称だけで完成コードと見なさない |
| `harmony-ime/from-winpc/` | WinPC側からの成果物。実際の構成を確認 |
| `harmony-ime/KikaInputMethod/` | 古いOpenHarmony/API18のサンプル。新規ベースとして無条件に使わない |
| `harmony-ime/signing2/` | 自作CAによる失敗実験。成功した署名材料ではない |
| `harmony-ime-bridge/` | 終了済みのGboard中継調査。通常は触らない |

WinPCの実パス・作業中コード・署名材料の所在地は未確認。既存変更を調べてからプロジェクトを選ぶ。動いているサンプルを残し、kanonの作業場所を明確にする。ログインや署名の本人操作が必要なときだけ具体的に依頼する。

## 実装順と各段階の終了条件

### M0: 環境・プロジェクトの確認

既存kanonプロジェクトがあれば利用。なければ実機成功サンプルから複製し、bundleの整合を確認して自動署名する。Celiaへ戻す手順を確認。結果をVALIDATIONへ記入する。サンプルの `hel` デモ置換、本文ログ、未awaitの重複編集を本実装へ移植しない。

### M1: G-01 入力先のAPI実証

実辞書なしの固定文字列で、プレビュー作成→更新→候補文字へ置換→確定→取消を検証。選択範囲、フォーカス移動、API非対応、API失敗、削除方向、UTF-16、Enterアクションを調べる。

終了条件: EditorAdapterの各操作の意味・成功/失敗判定が文書化され、二重挿入なし。下線付き表示が未実現なら、キーボード内表示へ黙って仕様変更しない。対象アプリで何が不可能かを切り分ける。

### M2: G-02 Mozc移植の実証

Mozcと依存のcommit固定、ホスト生成物と端末向けコンパイルを分離。まずホストの同一プロセス変換、次にarm64/HarmonyOSと辞書読込、最後にNode-APIで実機の実変換。

埋め込みレシピ（fcitx/mozc mozc_direct_client準拠、IPC不使用）: Engine::CreateEngine(make_unique<oss::OssDataManager>()) → SessionHandler → EvalCommandへcommands::Inputを渡しcommands::Outputを受ける。埋め込み側はKeyEvent＋Context詰め・Output読解のみでSession内部へ触れない。辞書ソースはsrc/data/dictionary_oss/dictionary00〜09.txt＋connection_single_column.txt等、リポジトリ内蔵（約100MB、外部DL不要）。

終了条件: ダミー辞書ではない入力→候補→選択→確定の実証、dictionary hash・ABI・依存版・ライセンスが記録済み。ビルド方式はBazel/CMakeの名前ではなく再現可能性で判断する。Android向けlibmozc.soをそのまま流用しない。

### M3: Coordinatorと通信契約

SPECの単一dispatch応答モデルを実装。editorEpoch/sequence/revision、部分確定、失敗時整合回復、モード変更の順序を制御する。UIとOSへの書き込みを分離し、偽EditorAdapterで遅延・順序・失敗を注入した試験を行う。

終了条件: REQ-01〜10に対応する試験があり、古い候補と遅延応答を誤適用しない。

### M4: Gboardに近いQWERTY操作

候補バー・展開、入力中の候補更新、タップ選択、Space、確定/送信の分離、地球儀、Shift、数字記号、Backspace反復、カーソル移動を実装。

終了条件: 「Spaceなしの候補確定」と「未確定ありの日英切替」を実機で確認。参照Gboardと照合できなかった操作は未確認として残す。候補内容の一致で合否を決めない。

### M5: 受入・運用

AT-01〜19を実施。テスト入力欄だけでなく、標準アプリ・WebView・Android互換アプリで確認する。失敗と未実施を区別する。Celiaへの復帰、署名期限、再署名・上書き更新の結果も記録。

終了条件: 必須ケースの結果が揃い、未対応の利用先・意図的な差分がユーザーへ提示可能。日本語が1回入力できただけで完成としない。

### M6: Gboard寄せの操作追加（受入中断・ユーザー指示で先行）

- Delete長押し連続消去：タップは1削除、250ms保持で90ms間隔の連続消去。指離し停止。単一キューへ直列投入（DeleteItem.ets）。
- Space長押し日英切替：Spaceに現言語（あ/A）小表示。250ms長押しでJP⇔EN、離した時の余分な空白は抑制。キー配置不動。地球儀キーの代用（SpaceItem.ets・kanonIme.switchMode）。
- 候補バーGboard風：青ボタン→左詰め素テキスト列＋区切り線、先頭（変換対象）を太字＋青下線。表示上限9→20、横スクロール。▾/▴で折りたたみ（畳むとキーボードが上に詰まる）。
- preview末尾カーソル配置：setPreview後にgetTextIndexAtCursorでpreview末尾へmoveCursor。確定後のcaretずれ改善。
- 未確定下線（D-02）の実機調査：純正IMEは自前欄に青下線を出す（同一欄・同一APIで再現）。Sync版/範囲スパン/カーソル明示の組合せでは再現せず。三者IMEからは届かない要因と判断し深追い停止。バー側の先頭候補下線で代用。

終了条件: 各操作をlive実機で確認しHAP shaをVALIDATIONに記録。AT凍結範囲はM5再開時に合意する。

## 変更・報告ルール

- 仕様ID→実装→試験結果を対応付ける。観測事実、提案、未確認を分ける。
- API名やスレッド構成等の内部実装は担当判断で詰める。入力体験の変更、同梱辞書からオンライン化、対象言語変更は仕様変更として相談する。
- 性能数値は仮目標。測定環境と結果を残して調整し、性能を達成したと先に宣言しない。
- 端末内の実文章をテストデータやログへ使わない。固定fixtureを使う。
- 署名秘密材料・個人IDは公開成果物へ含めない。サンプル・既存IMEを削除しない。
- 別エージェントとの共同作業が必要なら、担当ファイル・境界を先に決める。共有ファイルを同時に編集しない。

## そのまま渡す依頼文

> `harmony-ime/KANON_SPEC.md` と `harmony-ime/KANON_IMPLEMENTATION.md` を読んで和音IMEを実装してください。目標はGboardの操作体験を再現するHarmonyOSネイティブIMEです。候補内容・順位・学習結果の完全一致は不要です。QWERTY先行、入力先の未確定表示、入力中の候補表示とタップ確定、日英切替を必須とします。既にネイティブIMEの署名・実機起動は成功しています。入力先APIとMozc移植を先に実証し、M0〜M5に沿って進め、`KANON_VALIDATION.md` に要求IDごとの結果を残してください。実装都合でSpace必須やキーボード内だけの未確定表示へ仕様を縮小しないでください。
