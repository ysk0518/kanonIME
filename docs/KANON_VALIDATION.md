# 和音IME 検証・差分台帳

2026-09-28追記: 比較対象をHarmonyOS純正とした観測・再現実装は[KANON_NATIVE_SIGNAL_OBSERVATION.md](KANON_NATIVE_SIGNAL_OBSERVATION.md)に記録。未確定範囲指定を(-1,-1)へ変更し、候補列・一覧・パネル高さを調整した。入力欄の青下線は引き続き未達。以下の旧HAPの受入結果は当時の結果として保持する。

対象仕様: [KANON_SPEC.md v1.0](KANON_SPEC.md)。作成2026-09-27。
**本書作成時点ではkanonの以下の試験は未実施。** サンプルの起動成功を転記して合格にしない。

## 環境

| 項目 | 値 |
|---|---|
| ソースcommit / 作業パス | git管理あり（06db63c〜） / <workspace>/KanonIME |
| PC OS / DevEco / SDK / API / runtimeOS | Windows 10 / DevEco 6.1系 / HarmonyOS 6.1.1 / API 24 (target・compatible) / HarmonyOS |
| 端末 / OS / アプリ版 | 実機 UDID <device-id> / OpenHarmony-7.0.0.105 / 後述HAP |
| Mozc / protobuf / abseil等の固定版 | mozc b9c3fcbd6d76b19649ef572324fa9da2559bc18e (google/mozc HEAD 2026-09-27, D:/kanon-mozc) / abseil-cpp 255c84dadd029fd8ad25c5efb5933e47beaa00c7 (20260107.1) / protobuf 4b0c3aacf0657fbf38253b38918d3358dd4319ec (v34.1) / Bazel 9.0.2 / MSVC 14.44 / 参照 fcitx5-mozc(fcitx-contrib) 1a85618 |
| 辞書版 / SHA256 / 配置方式 | 未記録 |
| HAP hash / 容量 / ABI | 2026-09-27 M1ビルド: entry-default-signed.hap, SHA256 10d564eb…（G-01実証済みEditorAdapter、署名済み・導入済み） |
| 署名とProfileの期限 | CLIビルドでSignHap/SignApp成功（自動署名）。実期限は約10月11日の説のまま、未再検証 |
| 参照Gboard版 / レイアウト / 設定 / 端末 | 未記録 |

## M0: 環境・プロジェクトの確認（2026-09-27）

- 既存プロジェクトをそのまま利用。bundle `local.yplic.kanon`、API 24、inputMethod拡張あり。oh-package名は `kikainput` のまま（改名未実施）。
- `hvigorw assembleApp` がCLIで成功（約13.5秒、ArkTS警告のみ）。SignHap/SignAppまで通過し署名済みHAPを生成。
- `hdc install` 成功。`ime -l` にkanonが現れた。再導入後にkanonが現在のIMEへ自動切替した（導入前はCelia）。Celiaへの復帰手順（`ime -s com.huawei.hmos.inputmethod`）は未実行。
- 現コードの問題点（本実装へ移植しないもの）: `hel`→`hello world` デモ置換、入力文字のログ蓄積（REQ-07違反）、insert/deleteの非await発行（REQ-05違反の恐れ）、KEYCODE_DELとdeleteForward/deleteBackwardの対応付けが名称頼み（G-01で実機固定が必要）。

## 実証

| ID | 状態 | 証拠と結論 |
|---|---|---|
| G-01 入力先プレビュー/編集API | 実証済み | 2026-09-27 実機（Preview Text欄、pattern=-1/enter=6）。setPreview作成[0,0]/更新/置換・finishPreview・insert・属性取得すべて成功。ただし下線スタイルは未表示（切替直後のsendPrivateCommandが12800010で失敗した影響の可能性）。delete方向は名称と逆：deleteBackward(n)=カーソル右をn文字、deleteForward(n)=カーソル左をn文字（4事例＋Kikaの写像と一致）。削除のnは文字単位でサロゲートペアを分割しない（空欄’a😀b’・cursor1へのbackward(1)でペア全体が消えloneSurrogate=falseを確認）。getForward=カーソル前、getBackward=カーソル後で長さはUTF-16単位（idx=1でfwd1/bwd1、idx=0でfwd0/bwd2を校正）。insertTextはカーソル位置へ挿入（長さはUTF-16単位）。insert直後のカーソル位置は仮定せずqueryすること。sendKeyFunction(6)は本文不変でキーボードを閉じた。FLG_FIXEDパネルはmoveTo不可（OSエラーを無視して表示継続）。パスワード欄はOSがCeliaへ強制切替（kanonの検出対象外）。EditorAdapterに3秒タイムアウト＋attach時キュー再生成を追加（HAP 10d564eb） |
| G-02 Mozc同一プロセス・クロスビルド・辞書 | 実機実証済み | ホスト(Win x64, clang-cl): session_handler_main --dictionary ossで同一プロセス変換ループ実証（nihongo→[日本語/日本語と英語/日本語教育]→選択→確定）。cross: D:/kanon-engineでohos.toolchain.cmake/arm64-v8a・host protoc 34.1・host生成mozc_data.inc再利用。libmozc-static.a 86.8MB・ELF64 AArch64・sha256 cf61693f…・SessionHandler/Engine::CreateEngine/OssDataManager含有確認。mozcへのpatch2件（structured-bindings・clang15 paren-aggregate、D:/kanon-engine/patches＋apply-patches.bat）。OHOS clang 15.0.4はP0960非対応・structured-bindingのlambda捕獲不可に注意。fcitx5-mozc cmake流用差分はprocess.cc除外・aggregator削除・bash/python明示。実機(HAP 7400897f・udid <device-id>・M2画面)：init OK→conv OK ncand=3 prelen=12→sel OK ncand=0 prelen=15→commit OK rlen=5（nihongo固定fixtureのみ、内容非表示・件数/長さのみ記録）。Node-API bridgeはlibkanon_bridge.so（libc++静的リンク・-static-libstdc++、58MB・NEEDEDはhilog/ace_napi/libz/libcのみ）。実機投入の要点3件：(1)静的importはundefinedになるため動的import＋m.default経由で取得する（静的失敗は無警告、動的はresolve＋default undefinedで検出可）。(2)hvigorはentry/libsの.soを4K非アラインで格納するため署名前にzip extraでページアラインする（scratch alignhap.py＋SignAppのみ再実行）。(3)C++製.soはlibc++_sharedが解決できず無警告ロード失敗するため-static-libstdc++で静的リンクする（純Cのmini2はロード可で切り分けに使用）。 |
| M3 Coordinator契約試験 | 実証済み | 実機(HAP b429c051・偽Editor/偽Engine・M3画面)：T1重複抑止/T2世代ずれ破棄/T3未確定Backspace/T4プレビュー確定単発/T5順序維持/T6失敗時無再送＋reset復帰/T7古revision候補棄却/T8切替は確定成功後のみ/T9 ENGINE_ERROR＋EN退避の9件全pass（m3 9/9 pass）。HAP 4618f6d6でT10未確定なしBackspace直接削除/T11未確定なしEnter空振り抑止/T12確立済みpreview確定の置換＋finish単発（insert重ねず二重確定防止）を追加しm3 12/12 pass（全行ok）。ImeCoordinatorが単一dispatch・FIFO・effectId重複抑止・epoch/revisionふるい・回復保留を実装。実EditorAdapter/実Engine接続はM4へ持ち越し |
| M4 実接続スライス（QWERTY・候補・確定） | 実証済み | 実機(HAP 4618f6d6・実EditorAdapter＋実Engine・NORMAL画面・固定fixture)：(1)n連打でpreedit＋予測3件表示。(2)Spaceで変換開始し9件メモリ化（初回変換はcandidate_window空のためSET_REQUESTでtalkback可視を先送りするBridgeSpace、host実証：Space→0件・talkback後→3件）。(3)先頭タップで単独確定（FIELD len 3、二重確定はapplyCommitの置換→finish順序で解消）。(4)確定後再入力が継続。(5)戻すでpreview消去・確定分保持（FIELD 4→3・JP_EMPTY）。表示はAppStorage追跡配列＋素関数排除で更新（ForEach残留はkanonList/kanonIdList化で解消）。Backspace/Enterの実機分岐・EN直接入力は残件 |
| M4 仕上げ（Backspace・EN・Enter・空遷移消去） | 実証済み | 実機(HAP 043ccdd1・固定fixture・毎手dumpで座標再取得)：(1)未確定中Backspaceでpreedit短縮→空でJP_EMPTY・欄も0化（空遷移時の残像previewをKanonIme.postで範囲消去に一般化。確定系submit/selectはfinish済みとして追跡のみ閉じる）。(2)未確定なしBackspaceは本文直接削除（T10実機一致）。(3)EN切替→DIRECT_EN・直書き・エンジン不動（rev/seq不変）。(4)変換中Enterで強調候補を単独確定（重複なし・JP_EMPTY）。運用知見：installは実行中IMEへ反映されないため切替か再起動で新HAPを読み込む。キーy座標は候補バー有無で動くため毎手dumpから再取得（使い回しで隣キー誤打：j/l混入をhilogで特定、一時console.logは除去済み） |
| M4 固定バー（候補出し入れでキー不動） | 実証済み | 実機(HAP aa4d9dae・毎手dump)：候補Scrollの高さ44を常時確保し条件分岐を撤去。空欄時n=(888,2446)→未確定1件表示後もn=(888,2446)で不動（従来は約150pxずれ毎手再取得が必要だった）。IME切替リロードを実証：install後にime -sでHuawei往復→Kanonプロセス再生成（pid交代・ime -g FULL_EXPERIENCE）し再起動なしで新HAPが動く |
| M5 未変換確定の墜落と確定範囲の修正 | 実証済み | 実機(HAP 18f3db95)：未変換preeditへの素Enter-submitでIMEプロセス死亡を確認（onProcessDied→再生成・残像previewがFIELD残留）。対策としてcomposing確定は表示中読みの効果確定＋resetに迂回しnativeへ送らない。ついでに確定置換範囲の1手遅れ（previewEnd=置換前end）をstart+text.lengthに修正し未確定Enter単独確定を確認（FIELD 1のまま・JP_EMPTY）。AT-02/04/05/15/16合格・AT-03部分合格を記録 |

G-01にはAPIの実名・版、置換/確定の操作順、オフセット単位、削除方向、取消、クライアント失効、非対応時のエラーを記録する。G-02にはホスト生成ツールとターゲットバイナリの区別、再現ビルド手順、ライセンス一覧を記録する。

## 受入結果

状態は「未実施 / 合格 / 不合格 / 環境待ち」。API制限がある場合は不合格または対象アプリの制限として理由を残し、未実施を合格扱いしない。

| ID | 状態 | 対象アプリ・版 | 実際の結果 / 証拠 |
|---|---|---|---|
| AT-01 | 合格 | 自前テスト欄・HAP 53c9b97f | EditViewの矢印・行頭・行末を単一キュー結線（doMove＋未確定の先確定）。ENでab→左でc2→c1→BSでlen 1（位置指定削除）→行頭でc0→行末でc1。選択モードは従来経路のまま |
| AT-02 | 合格 | 自前テスト欄・HAP 4618f6d6 | nihongo→Space→先頭タップでFIELD len 3の単独確定（件数/長さのみ） |
| AT-03 | 合格 | ブラウザ検索欄・HAP 18f3db95 | 未確定Enterで読み単独確定（JP_EMPTY）→2回目Enterで検索実行・結果頁遷移・プロセス生存（前半は自前欄でも確認） |
| AT-04 | 合格 | 自前テスト欄・HAP 18f3db95 | 未確定n→EN切替で先表示1回確定＋DIRECT_EN（FIELD 1→2・プロセス生存） |
| AT-05 | 合格 | 自前テスト欄・HAP 043ccdd1 | 未確定中Backspaceで短縮→空（欄0化）、未確定なしで本文直接削除 |
| AT-06 | 部分合格 | M3偽物T2＋実機反復attach | 世代ずれ応答の破棄はT2でpass。実機は同期エンジンのため計算中の欄移動競合は発生せず、aa起動反復でattach世代切替＋残像なしを確認 |
| AT-07 | 部分合格 | M3偽物T7・HAP b429c051 | revision不一致タップの棄却はT7でpass。実UIは常に現行revを添える構造のため古rev提示は不可 |
| AT-08 | 部分合格 | 読了＋M3 T4/T12 | preview非対応時はrefreshPreviewを出さずinsert直確定する機構（読了確認・T4/T12のinsert経路でpass）。実機に非対応欄が見当たらずliveは未実施 |
| AT-09 | 部分合格 | M3偽物T6/T9・HAP b429c051 | 無応答エンジンの無再送＋reset復帰はT6、ENGINE_ERROR→EN退避はT9でpass。live破壊注入は未実施 |
| AT-10 | 合格 | 自前テスト欄・HAP bc648a88 | fixture 7打鍵（読み7）→Spaceで9候補（FIELD 4・g2）→分確で先頭文節確定＋残り継続（FIELD 4・COMPOSING・g1・確定2＋残り表示2）→Spaceで残り変換（n9）→先頭タップで残り確定（FIELD 4・JP_EMPTY・g0）。Enter版も同結果・プロセス生存。改修：bridge SUBMIT_CANDIDATE＋MozcEngine partial/segcount＋commitLength再アンカー（旧起点＋確定長・カーソル再問合せ不使用） |
| AT-11 | 部分合格 | 実機・HAP b5fd3097＋M3 T13 | uitest text注入は非BMPを??化（画像確認）し実ペアが欄に入らないためliveペア削除は未実施。live ??→BSは正常（件数・生存）。ペア機構はM3 T13でpass（m3 13/13・直前ペア→deleteFwd×2）。残件：実ペアlive・結合文字・100単位超・文中ペアはn=1退避 |
| AT-12 | 部分合格 | 設定WLAN画面・HAP 18f3db95 | ネットワーク詳細画面ではKanonパネル自体が出現せず（欄なし＝不装着を確認）。password欄はSPEC §8想定（OSがCeliaへ強制）で入力自体がKanon対象外。資格情報を触らないためlive入力は未実施 |
| AT-13 | 未実施（破壊試験のため保留、M3 T9のENGINE_ERROR→EN退避で機構は検証済み） | | |
| AT-14 | 部分合格 | 実機・HAP aa4d9dae〜 | ime切替によるpanel破棄→再生成で状態残留なし（pid交代・初回attachはJP_EMPTY）。OS主導の表示/非表示反復は未実施 |
| AT-15 | 合格 | 実機・HAP aa4d9dae | ime -sでHuawei往復→Kanon再生成・FULL_EXPERIENCE（Celia単体は一覧になし） |
| AT-16 | 合格 | 自前テスト欄・HAP 4618f6d6 | Spaceなしで予測タップ→単独確定（FIELD len 3） |
| 標準アプリ確認 | 合格相当 | メモ帳・ブラウザ・HAP 18f3db95 | メモ帳：nihongo→3候補→Spaceで9候補→先頭タップで本文len 3の単独確定・JP_EMPTY（他社欄への実接続）。ブラウザ検索欄：AT-03に記録 |
| AT-17 | 部分合格 | 自前テスト欄・HAP 18f3db95 | 追加入力で候補n1[1]→n2に変化、状態CONVERTING維持・自動確定なし。打鍵精度が混ざったため厳密な読別は未分離 |
| AT-18 | 部分合格 | 自前テスト欄・HAP 18f3db95 | ENで5連打→件数+5・重複欠落なし・エンジン不動。異種キー順序はREQ-07上内容照合不可（単一queue＋M3 T5が機構保証） |
| AT-19 | 部分合格 | 自前テスト欄・HAP 18f3db95 | Shiftでキー表示a→A同期・タップで+1、数字面で1→+1・ABCでQWERTY復帰。大小の内容照合はREQ-07上不可（upperContent経路は読了確認） |

## Gboardとの差分

| 操作・機能 | 分類 | 観測またはスコープ理由 | 対応する仕様 |
|---|---|---|---|
| 候補の内容・順位 | 意図的な差 | Mozcの候補完全一致は求めない | D-09 |
| 永続学習 | 意図的な差 | パイロット対象外 | D-05 |
| フリック | 意図的な差 | 次段階 | D-01 |
| 英語予測・Spaceドラッグ | 意図的な差 | パイロット対象外 | §3/§12 |
| 地球儀キー | 意図的な差 | Space長押し切替で代用（M6再現済み）。単独キーは配置変動のため見送り | D-03 |
| 欄内の未確定下線 | 不具合（OS/特権依存・代替あり） | 同一API・同一欄で純正のみ青下線。Sync/範囲/カーソルで再現せず。先頭候補の下線＋太字で代用（M6再現済み） | D-02 |
| 候補タップ・Space・Enter | 再現済み | M4〜M6で実機確認 | D-04/§4 |

## M6実証（Gboard寄せ・HAP別）

| 操作 | HAP | 実証 |
|---|---|---|
| Delete長押し連続消去 | 2613e775 | 9文字→空をlive確認 |
| Space長押し日英切替 | 47768f9c | JP→EN→JP往復をlive確認（閾値250ms。400msはuitest longClickで不安定） |
| 候補バーGboard風＋上限20 | fb0f7b52 | 左詰め素テキスト＋区切り＋先頭太字を画像確認 |
| 候補バー折りたたみ | 8f400116 | ▾畳み・▴展開をlive＋画像確認 |
| 先頭候補の青下線＋preview末尾カーソル | a06fe417 | 画像確認（caret末尾配置も改善） |

分類: 再現済み / 意図的な差 / 未確認 / 不具合。既定値を本物のGboardの内部仕様と表現しない。

## 性能・運用

冷/温起動、キー→表示p95、メモリ、初回辞書配置、辞書更新、再署名、上書き更新、Celia復帰の結果をここに追記する。入力fixtureのみを証拠に使う。

## 仕様変更記録

| 日付 | ID | 変更理由・承認者/設計判断 | 影響する受入ケース |
|---|---|---|---|
| 2026-09-27 | v1.0 | ユーザー合意のGboard操作再現をベースライン化 | 全体 |
