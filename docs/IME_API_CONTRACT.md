# kanonIME 入力先 API 契約

更新: 2026-10-03。対象は HarmonyOS の `inputMethodEngine.InputClient` と kanon の `EditorAdapter` 境界。

この文書は [KANON_SPEC.md](KANON_SPEC.md) の REQ-01〜07 を、実装時に確認できる API 契約へ落としたもの。根拠は DevEco Studio 同梱 SDK の `default/openharmony/ets/api/@ohos.inputMethodEngine.d.ts` と [KANON_VALIDATION.md](KANON_VALIDATION.md) の G-01。SDK が明記しない挙動を「仕様」と呼ばず、実機観測または未確認として扱う。

## 1. 結果の区別

| 結果 | 意味 | kanon の扱い |
|---|---|---|
| `Promise<boolean>` が `true` | API が成功を報告 | 成功として次の編集操作へ進む。本文の即時読み取りが同じ状態を返すとは仮定しない |
| `Promise<boolean>` が `false` | API が失敗を報告 | 成功扱いも自動再送もしない。直接入力・削除は次の打鍵を受け付ける。エンジン側が先に確定状態へ進んだ場合は別途整合性を回復する |
| `Promise<string>` が `''` | 読み取りに成功し、結果が空 | 空欄またはカーソル位置に応じた空の結果として扱う |
| Promise の reject / 同期例外 | API がエラーを報告 | エラーコードを保持し、空文字・位置0・成功に変換しない |
| kanon のタイムアウト | 規定時間内に結果が得られない | **成否不明**。元の Promise はキャンセルされない。自動再送も成功扱いもしない |
| 入力先の世代が変化 | 古い `InputClient` への結果 | 古い結果を新しい入力先へ適用しない |

読み取り失敗を `''` や `0` に変換すると、空欄・先頭位置との区別が消える。判定に使う読み取り API は `ok/value/code` を呼び出し側まで維持する。

## 2. API 別の契約

| API / イベント | SDK にある契約 | 実機観測・kanon の規則 |
|---|---|---|
| `inputStart` / `inputStop` | 入力先の接続と終了を通知 | 接続ごとに editorEpoch を更新し、キュー・選択状態・未確定状態を旧欄から持ち越さない |
| `insertText(text)` | `Promise<boolean>`。失敗時に `false` または `BusinessError` | `false` を成功と見なさない。タイムアウトした挿入を自動再送しない |
| `deleteForward(n)` / `deleteBackward(n)` | `Promise<boolean>`。`n >= 0` | **G-01実機観測:** kanon の対象欄では `deleteForward(1)` がカーソル左、`deleteBackward(1)` が右を消した。API 名だけで方向を決めない。選択範囲の削除は通常の1文字削除と区別する |
| `getForward(n)` / `getBackward(n)` | カーソル前 / 後の文字列を返す `Promise<string>` | **G-01実機観測:** 前 / 後の対応を確認。取得文字数の上限や範囲の細部は入力先で差があり得る。読取エラーを空文字にしない |
| `getTextIndexAtCursor()` | `Promise<number>` | 戻り値はカーソル位置。選択の有無や削除の成否を位置だけから断定しない。失敗を位置0にしない |
| `selectionChange` | 変更前後の開始・終了位置を通知 | `newBegin !== newEnd` を選択ありとして保持。入力先切替で破棄する。削除直後のカーソル位置と直前文字数だけで選択削除の成否を判定しない |
| `setPreviewText(text, range)` | `Promise<void>`。非対応欄では `12800011` があり得る | [Huawei の入力法 FAQ](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-ime-7) に従い、作成・更新・消去は `(-1,-1)` でプレビュー全体を対象にする。非負の `range` は既存プレビュー内の位置を指す。文書中のカーソル位置を渡さない |
| `finishTextPreview()` | `Promise<void>`。プレビューを確定 | 候補選択では表示中のプレビューに対して `insertText(候補)` を1回呼び、同じ文字を `finishTextPreview()` で重ねて確定しない。失敗時は確定済みと表示しない |
| `sendKeyFunction(...)` | 入力欄の Enter アクションを送る | 日本語の未確定がある間は先に確定し、空のときにアクションを送る |
| `selectByMovement(...)` / `selectByRange(...)` / `sendExtendAction(SELECT_ALL)` | 選択範囲を変更する `Promise<void>` | 編集メニューからの操作も入力キューで直列化し、日本語の未確定があれば確定後に実行する。API の失敗・タイムアウトを通常の編集操作と同様に扱う |
| `sendPrivateCommand(...)` | SDK に「システム既定の入力方式のみ」と記載。`12800010` があり得る | kanon の通常入力の前提にしない。G-01 でも `12800010` を観測 |

`Promise<void>` の resolve は API 呼び出しの完了報告であり、直後の別 API による画面状態の反映時刻までは SDK に明記されていない。表示更新待ちを独自に設ける場合は、目的・最大待ち時間・失敗時の扱いを別途記録する。

## 3. 実装の境界

1. `EditorAdapter` で API の `true` / `false` / reject / timeout / stale epoch を失わずに分類する。本文はログに出さない。
2. `ImeCoordinator` は編集結果を受け取り、エンジンの確定効果と入力先の状態を管理する。選択の有無は `selectionChange` を使い、文字数の増減から推測しない。
3. `KanonIme` は日本語の未確定範囲と表示を管理する。入力先が変わったら範囲を破棄する。
4. タイムアウトは kanon 独自の待機期限であり、API の失敗通知ではない。期限後も元の操作が完了し得るので、キューを次へ進める条件を再設計するまでは「自動復帰できる」と断定しない。
5. 画面キー、編集メニュー、物理キーの編集操作は `KanonIme → ImeCoordinator → EditorAdapter → InputClient` の順に流す。`InputHandler` はキーボード表示と入力開始通知を担当し、入力先の文字を直接編集しない。

## 4. 現状の差分と未確認事項

| 優先 | 項目 | 現状 |
|---|---|---|
| 対応済み | 削除時の空欄判定 | `queryBeforeResult()` で読み取り成功と空文字を区別する。他の `queryBefore()` 呼び出しは従来の空文字への変換が残る |
| 対応済み | タイムアウト後の直列性 | 書き込みがタイムアウトしても元の Promise が終わるまでは同じ入力先への後続 API を拒否する。復帰操作と表示は引き続き見直し対象 |
| 対応済み | 通常のBackspace | 削除 API の `true` / `false` を採用し、7回・50msの文字数確認とサロゲートペアの二重削除を廃止 |
| 対応済み | 明確な書き込み拒否 | `false`、クライアント不在、旧世代の直接入力・削除では全キー停止をかけない。成否不明のタイムアウトは停止を維持 |
| 対応済み | 英語補完の取り消し | 接頭辞とカーソルを照合後、補完された末尾を範囲選択して1回の削除 API で消す。文字数ポーリングを廃止 |
| 対応済み | `sendPrivateCommand` | システム既定IME専用のため、kanon の入力開始時の呼び出しを削除 |
| 対応済み | 入力先属性の古い応答 | `getEditorAttribute()` の応答を editorEpoch と照合し、失敗も捕捉する |
| 対応済み | 編集メニューと物理キー | 入力・削除・移動・選択を共通キューに統合し、旧 `InputHandler` の直接編集とサンプル予測コードを削除 |
| 再確認中 | QWERTY の子音残り | Huawei の検索欄で `k→i` が `ｋき` になる事例を観測した。診断時、2回の `setPreviewTextSync(..., {-1,-1})` は成功を返していた。空欄からの `k→i` と「き」候補確定→`k→i` の連続5回は `き` / `きき…` と正常だったため、常時起こる変換規則の誤りとは確定できない。同期版への切替、候補確定前のプレビュー消去、明示的なプレビュー内範囲指定はいずれも改善を確認できず、元の非同期版へ戻した。再発時は同一操作でエンジンの未確定長、API完了順、入力先の `textChange` と `selectionChange` の順序を記録し、プレビューが確定文字へ変わる瞬間を特定する |
| 中 | `selectionChange` の到着順 | 選択、削除、プレビュー変更が短時間に重なる場合の通知順は未確認 |
| 中 | コンテナ内の入力欄 | EasyAbroad の一部欄で非同期 API が応答しないことを観測。対象 API と同期版の差は再現時のログで確定する |
| 低 | サロゲートペアの削除単位 | G-01 では `deleteBackward(1)` が絵文字を分割しないことを観測。`deleteForward(1)` と全入力先への一般化は未確認 |

この差分表は実装や実機観測で更新する。未確認の項目を SDK の保証として実装しない。
