# 実Mozcのホスト確認

## 実行

PC用にビルドしたMozcの `session_handler_main` が必要です。Harmony用の `.so` をNodeに読み込む試験ではありません。
通常の `npm test` とCIからは分離しています。

```powershell
node tests/native-host.cjs --mozc 'D:/path/to/session_handler_main.exe'
```

ホスト実行ファイルはこのリポジトリに同梱していません。実行ファイルの準備は別途必要です。
Mozcソースの `src/session/session_handler_main.cc` と `session_handler_tool.cc` がTSV命令と期待値の契約です。
`--test` だけではmock辞書になるため、ランナーは必ず `--dictionary=oss` を指定します。

ケースごとに `.local/native-host/run-*/<case>/profile` を新しく作らせます。既存の学習データを使いません。
Windows版ツールは既存profileディレクトリで失敗するため、ランナー側ではそのディレクトリを先に作りません。
入力・出力・結果は同じrunディレクトリに残します。固定したテスト用文字列だけを扱います。

終了コードは、0＝全ケース合格、1＝期待値不一致または子プロセスの失敗、2＝ランナーの引数／準備エラーです。
結果の `passed`、`exitCode`、`error` と各 `output.log` を確認します。クラッシュ・タイムアウト・assert失敗は合格になりません。
誤ったEXPECT_PREEDITで `Expected preedit:` と `[ FAILED ]` が返る対照試験を毎回実行し、期待値が実際に検査されることも確認します。

## ケース

| ID | 内容 | 期待値の根拠 |
|---|---|---|
| H01 | k→iの途中表示と「き」 | 母音入力後のかなは入力契約。子音の全角表示は現Mozcの暫定表現 |
| H02 | nihongo→候補「日本語」の確定→ki | 固定OSS辞書の候補存在、確定後の新しい入力に文字を残さない |
| H03 | ten→記号候補「・」→追加入力 | ユーザー報告の記号候補と、その後もセッションが生存すること |
| H04 | 「き」にliteralの？を追加→く | 記号を未確定に含め、追加入力で消さない合意 |
| H05 | 「かき」の途中に「さ」を挿入 | 元の後続文字を保持する編集契約 |
| H06 | 範囲縮小→「今日」だけ確定→残り「は」に「が」 | 部分確定の残りを保持。追加入力前のliteral再構築はMozcEngineの既存経路 |
| H07 | 非BMP文字のliteral入力・削除 | Unicode文字単位のカーソルと削除。UTF-16のJSON変換は別確認 |
| H08 | reset後の再入力 | 以前の未確定を再送・復活させない |

候補の順位や数の完全一致は要求しません。H02では複数候補と対象候補の存在を確認します。
辞書の更新で候補が変わった場合は、辞書版・期待する入力動作を確認してfixtureを更新します。

## 今回の環境と結果（2026-10-10）

- Windowsホストの8ケース＋検出用対照1ケースが合格。
- 確認したMozcソースHEAD: `b9c3fcbd6d76b19649ef572324fa9da2559bc18e`。ホストツールの2ソースは変更なし。
- ホストexe SHA256: `8a885655114e8547978adc706ca4f682ece7922d318394adedaf74954d2832b2`。
- ホスト側／OHOS側の生成 `mozc_data.inc` は同じSHA256: `c0f4375297e3cfaf3d0a1389f70d8332f3776823148af8f87ad7c49fe3e6c1e5`。
- 実行ごとのexe・fixture・ブリッジソース・アプリ同梱.soのhashは `report.json` に記録。記録した.so自体をこの試験で実行したとは扱いません。
- 初回は既存profileディレクトリで全ケースが準備失敗。上記のツール契約に合わせて修正。
- H06の最初の案は、部分確定後の変換状態にそのままgaを送って「はが」を期待し不一致。製品と同じreset＋残りのliteral再構築へ合わせて合格。製品のロジック自体を変更したものではありません。
- 新規プロファイルで履歴／暗号化キー／終了時ファイル処理の診断がstderrに出ています。assertの合格とプロファイル保存の検証は区別します。履歴保存・再起動時の復元は未確認です。

## 全体回帰での再実行（2026-10-11、P28）

同じホストexeで8ケースと誤ったEXPECT_PREEDITを検出する対照が合格しました。新規プロファイルを使い、結果は`.local/native-host/run-kJsAJM/report.json`に保存しています。
これはupstreamのホスト実行で、アプリの同梱.soを実行した結果とは区別します。製品ブリッジは[NATIVE_BRIDGE.md](NATIVE_BRIDGE.md)の別試験で10件を確認しました。

## 確認できない範囲

この試験はupstreamのSessionHandlerとOSS辞書を実行します。NativeMozcBridge、製品C++のExecuteOperation、
JSONのUTF-8／UTF-16変換、N-APIの非同期完了、MozcEngine全体、EditorAdapter・HarmonyOSは実行していません。
setup.tsvはブリッジの主要Requestに合わせますが、能力宣言・提案抑制・矢印後の候補再表示などの全経路は再現しません。
ホストexeの再現ビルドと同梱.soの生成由来の照合も未整備です。
製品ブリッジ経由の操作・候補ID・JSON・結果の確認は [実機結合確認](NATIVE_BRIDGE.md) へ追加し、10ケースを実施しました。
実機確認は [実機手順](../device/README.md) に従い、別の結果として記録します。
