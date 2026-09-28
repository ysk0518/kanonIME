# 純正IMEの入力中シグナル観測

2026-09-28、HDC接続実機 `<device-id>`。入力先はKanonのEntryAbilityのPreview Text欄。純正 `com.huawei.hmos.inputmethod` と `local.yplic.kanon` を切り替えて比較した。Android側との比較は今回実施していない。

## 後続修正：未確定文字の重複

同日06:48頃、ユーザーの入力欄で、候補は4文字の読みなのに途中の読みが本文に残る現象を観察した。エンジンのpreedit更新ログは1→2→3→4文字で、すべて自動範囲`[-1,-1]`。自動範囲に依存した更新が当該ケースで置換になっていないと判断し、EditorAdapterがCoordinatorの追跡するUTF-16範囲を実際に送るように修正した。OS内部でpreview範囲が失われる理由までは未特定。

修正版をビルド・実機導入し、フリックで「よろしく」を入力すると、範囲`[0,0]→[0,1]→[0,2]→[0,3]`で入力欄は4文字になった。候補確定でも4文字のまま。続けて同じ読みを入力すると範囲`[4,4]→[4,5]→[4,6]→[4,7]`で8文字になり、確定済みの先頭4文字を維持した。編集キーと削除も観察した。更新の自動範囲は純正の観測結果として下記に残すが、現在のKanon実装は明示範囲を使う。

観察画像: `.local/screenshots/harmony-native/preview-explicit-yoroshiku.png`、`preview-explicit-edit.png`、`preview-explicit-after-commit.png`、`preview-explicit-cancel.png`。ユーザーの入力中画面の一時画像はリポジトリに保存していない。

## 確認できた通知

純正のn入力時（端末ログ02:21:54.391）:

```text
HMKeyboard_PrivateCommandManage: sendPrivateCommand: {"previewTextStyle":"underline"}
HMKeyboard_JapanEngine: setPreviewText start: -1, end: -1, cursor: undefined
AceTextField: SetPreviewText length :1 in range (-1, -1)
```

同じ欄のスクリーンショット `.signal-native-n.png` で青い下線と末尾カーソルを確認した。続けてi、Spaceをソフトキーで入力すると、02:22:08.617にFinishTextPreviewが呼ばれ、`.signal-native-convert.png` では「に」が下線なしで表示された。この短いケースのSpaceは確定として動いており、長い読みの変換挙動は未検証。

純正切替時には `{"previewTextStyle":"normal"}` も観測した。純正は表示スタイルの切替通知を送っている。

Kanonの同じ通知は02:22:24.237に拒否された:

```text
insertText sendPrivateCommand catch error: 12800010 not the preconfigured default input method.
```

ローカルSDKの `@ohos.inputMethodEngine.d.ts` のsendPrivateCommand説明も、OSが事前設定した標準IME専用で、12800010をその制限として定義している。「ユーザーが現在選択したIME」とは条件が異なる。

Kanonのn入力時（02:22:50.978）:

```text
AceTextField: SetPreviewText length :1 in range (0, 1)
KanonEditor: kanon: setPreview ok len=1 range=[0,1] moved=1
```

## 結論と未確認事項

- 純正が入力中の下線スタイルをprivate commandで通知することは実機ログで確認した。
- Kanonは同じ通知を試みているが、実機OSの標準IME判定で拒否される。
- 純正の範囲指定は(-1,-1)、Kanonは明示範囲と手動カーソル移動。実装経路にも差がある。
- 下線の唯一の原因がprivate commandか、範囲指定やカーソル移動も影響するかは、今回の比較だけでは確定できない。
- 前の記録の「OS/特権依存」は通知拒否について裏付けが得られたが、第三者IMEでは下線を一切実現できないという断定には足りない。
- 候補のUI・変換中の状態遷移は別途比較が必要。

抽出ログと観測画像は `.local/screenshots/harmony-native/` に保存。上記の初回観測時点ではアプリの実装コードは変更していない。

## 再現実装と実機確認

ユーザーの指定によりHarmonyOS純正を比較対象として実装した。

- EditorAdapterのsetPreviewTextを純正と同じ範囲(-1,-1)へ変更し、毎回の手動moveCursorを取り除いた。更新・確定置換・取消を同じプレビューへ適用する。
- KanonImeのイベント処理をプレビュー表示更新まで含めて直列化。入力先が変わったときはプレビュー対応属性を読み直し、待機中の旧入力先イベントを破棄する。
- 通常入力中の診断表示・青い操作ボタンを取り除き、ツール列と候補列を同じ44vpの行で切り替える。選択中候補を青で強調し、候補一覧を展開できる。取消・文節確定は展開した一覧に配置する。
- キーボードパネルをキー領域と候補列の高さに合わせて調整。HarmonyOSのresourceManager.getNumberByNameが寸法リソースをピクセルで返すことを実機の数値833.625=247×3.375で確認した。
- ネイティブライブラリの4KB配置調整を署名前のPackageHapへ組み込み、通常のassembleAppで更新用HAPを生成できるようにした。

HDCでソフトキーをタップして確認した結果:

| 操作 | 実機結果 |
|---|---|
| nihongo入力 | 欄の読み4文字・予測候補3件。未確定の更新で本文の重複なし |
| Spaceなしで先頭候補タップ | 確定3文字・候補消失。二重挿入なし |
| Space変換と候補展開 | 変換された未確定3文字・候補一覧表示 |
| 取消 | 未確定分だけ消去。既存の確定本文を保持 |
| ni→Backspace→Enter | 1文字の読みを確定。確定済み本文3文字から合計4文字 |
| ni→Space長押し日英切替 | 未確定読みを1回確定して英語モードへ移行。合計5文字 |
| 通常の候補出現・消失 | 候補行の高さを固定。通常のキー位置が変わらない |
| 入力欄の青い下線 | **未達**。純正範囲指定だけでは出ない。スタイル通知は引き続き12800010で拒否される |

この確認は自前のPreview Text欄と接続実機での結果。下線通知の拒否については証拠があるが、別APIによる実現可能性を一切否定する結果ではない。標準アプリ・WebView・横画面・文中のカーソル移動について、変更後の受入はまだ実施していない。

確認用スクリプト: `tools/harmony-probe.ps1`。固定fixtureの操作列と文字数・候補数のみを表示し、期待する数の確認も行える。

最終表示の画像: `.harmony-final-empty.png`、`.harmony-final-composing.png`、`.harmony-final-expanded.png`、`.harmony-final-commit.png`（いずれも.local/screenshots/harmony-native内）。

最終更新HAP: `entry/build/default/outputs/default/entry-default-signed.hap`。SHA256 `ae5a598eb4ee80653b0901572f0e38b5a237d08c89dc91eb7e75e201f68455bc`。ビルド・署名・hdc install成功、純正との往復切替で再読込後、入力→一覧展開→候補確定を再確認。終了時はKanon / FULL_EXPERIENCE_MODE。
