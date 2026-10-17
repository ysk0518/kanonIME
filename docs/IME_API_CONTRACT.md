# kanonIME 入力先 API 契約

更新: 2026-10-17。対象は HarmonyOS の `inputMethodEngine.InputClient` と kanon の `EditorAdapter` 境界。

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

### 未確定内のカーソル配置（P20〜P22）

- SDKのselectByRangeは本文の範囲、setPreviewTextの非負rangeはプレビュー内の範囲を指定する。異なる座標として扱い、空文字のプレビュー挿入でカーソル移動を代用しない。
- OpenHarmony-7.0.0.105のHuaweiブラウザ／固定HTML inputでは、selectByRangeのtarget=1に対してgetTextIndexAtCursorは2を返した。文字更新後もtarget=2、actual=3となった。APIはrejectしなかった。この入力欄で観測した不一致であり、全Web入力欄の非対応とは断定しない。
- 同じ欄でmoveCursor(CURSOR_LEFT)を使う診断版では2→1、3→2を読み戻し、通知も同じ位置になった。固定native TextInputでも途中移動と未確定の継続を確認した。比較結果は [実機手順と記録](../tests/device/README.md) に残す。
- 製品のpreviewCaret経路は、Coordinatorが渡した未確定本文と本文内の開始位置から移動先を計算する。既知の範囲内だけをコードポイントごとに左右移動し、各ステップのUTF-16位置を読み戻す。範囲外・サロゲート内部・期待と異なる位置では停止し、追加の移動や再送で補わない。
- コンテナの比較では、移動API応答の後の照会が旧位置2を返し、API応答の29ms後に位置1のselectionChangeが届いた。各移動の前に目標位置の受領待ちを用意し、SDK応答とcollapsed-positionの観測後に位置を読み戻す。通知に要求IDがあると仮定せず、実際の読み戻しで一致を検証する。
- APIキューの既存期限とattach／detachで移動処理と位置受領待ちを取り消す。発行済みのAPI自体は取り消せないが、遅い完了の後に次の移動を発行しない。SDKエラーは同じ操作キューで分類し、配置不一致はpreview-caret--7として保持する。
- P20の表示末尾通知待ちとP21の配置不一致時の本文保持は維持する。未確定表示の成功、カーソル配置の成功、文字の確定は別の状態として扱う。

公開されている [OpenHarmony WebのIMFアダプタ](https://github.com/openharmony/web_webview/blob/bca62eeacad0d102b7b673267c2736d7c4b28e94/ohos_adapter/inputmethodframework_adapter/src/imf_adapter_impl.cpp) は、範囲指定・左右移動・位置照会を別々のlistenerメソッドへ転送する。
この公開ソースだけではHuaweiブラウザの内部で範囲指定が反映されない条件を特定できない。参照した公開版と端末内バイナリが同一であるとも確認していない。アプリ名によるAPI分岐やプライベートコマンドは追加しない。

## 3. 実装の境界

### アプリ側で入力欄が空になった場合

Discord／Celiaの送信ボタンなどで入力欄だけが空になり、IMEの候補・未確定状態が残る報告への対応。送信ボタン自体を検知するAPIやアプリ名による分岐は使わない。

- `textChange`の空文字、または`selectionChange`の選択なし・位置0を、現在の入力先を読み直すきっかけにする。通知だけで本文の消失や送信を断定しない。
- 実パネルの`show / hide`も再照会のきっかけにする。Celiaでは送信時にパネルの`hide`が来る一方、空文字・位置0・`InputMethodAbility.keyboardHide`は記録されなかった。
- 前の打鍵・プレビュー更新が完了した後、共通の入力キュー内で照会する。表示に成功した未確定、または直接英語の接頭辞がある場合を対象とする。プレビュー非対応でエンジン内だけにある未確定は、空欄であることを理由に捨てない。
- 選択範囲がないこと、`getTextIndexAtCursor() == 0`、`getForward(1) == ''`、`getBackward(1) == ''`、再度の位置0をすべて成功した読み取りで確認する。位置0だけでは先頭へのカーソル移動と区別できず、前後の空文字だけでは全選択と区別できない。
- 各APIを既存の操作キュー・期限・エラー分類で実行する。途中の失敗・期限切れ・入力先切替で後続の照会を打ち切る。読み取り中に文字／選択の通知が増えた場合は、その結果で破棄せず読み直す。
- 空欄を確認した場合はCoordinator、変換エンジン、予測、未確定の表示範囲・カーソル追跡を初期化し、候補表示を更新する。すでに空になった入力欄へ`insertText`、`finishTextPreview`、削除、プレビュー消去を発行しない。
- パネル非表示とSDKの入力先エラー`12800003`だけでは破棄しない。Celiaで両者を観測したが、SDKは同じ符号にフォーカス喪失・未接続・IPC失敗を含めるため、送信や空欄の証拠にはならない。この組み合わせでローカル状態を破棄する試験的な処理は撤去した。
- 新しい`inputStart`で入力先の世代が変わった場合は、内部初期化だけでなく候補・入力中フラグの表示も更新する。次の打鍵まで古い表示を残さない。
- 破棄前の候補選択・部分確定・英語Undoがキューに残っていても、新しい未確定へ適用しない。次の文字入力は新しい未確定として受け付ける。

この処理は空欄の同期を対象とする。本文を別の非空文字列へ外部置換した場合や、アプリ・パネルが通知を出さない場合まで検出できるものではない。Discordはユーザーから改善したようだとの報告があり、経過観察とする。

**2026-10-17の実機結果: 送信後の本文残留は未解消。** Celiaで非表示時のローカル初期化が実行された後も、入力欄を再表示すると`textChange`は空でなく、カーソル位置も0でなかった。初期化後に古い本文を再挿入した操作は記録されていない。候補／エンジンの状態と、入力コンポーネントに残る本文を区別する。

専用の検証画面では、本文を空にしてから未確定を終了すると純正／kanonとも残留し、未確定終了の`onChange`を受けてから本文を空にすると両方で消えた。ユーザーもCeliaで純正の残留を確認した。ただし、専用画面とCelia内部の処理順が同じとは断定しない。比較条件・通知順・HAP識別子は[実機記録](../tests/device/EXTERNAL_SEND.md)を参照。

API 20の`InputMethodAbility.on('discardTypingText')`を登録し、明示的な破棄要求は入力キューで受け付ける。自分の有効なプレビューがあれば既存の`cancelEditorPreview`で消去・終了し、ローカル状態を初期化する。この通知はCeliaの送信操作ではまだ観測されておらず、対応だけで本文残留が解消したとは扱わない。

[公開ArkUI実装](https://github.com/openharmony/arkui_ace_engine/blob/master/frameworks/core/components_ng/pattern/text_field/text_field_pattern.cpp)の`InitValueText`にはプレビュー中の外部値更新を受け付けない経路がある。ただし、公開版と実機内バイナリの同一性は未確認であり、Celiaの残留原因としては仮説。入力再接続時に`finishTextPreview`を1回呼ぶ診断でも本文は空にならなかったため、その追加呼び出しは撤去した。本文全体の削除や、非表示だけを理由にした確定は追加しない。

### 入力データと方向の境界（P23）

`InputEventTypes`がSDKなしの入力契約を所有する。`UiEvent`は未検証の受付形、`InputEvent`は文字列・候補ID／revision・位置・方向などを操作別に必須としたエンジン契約。CoordinatorのFIFOキュー内で世代照合後に検証・複製し、不足値を空文字・0・-1へ補わない。

方向はコアで`left / right / up / down`を使う。UIが渡すSDK方向はKanonImeで変換し、EditorPortからの方向はRealEditorPortでSDKへ変換する。`SdkEditorDirections`がSDKの名前付きDirection定数の対応表を持ち、`EditorDirectionMap`は供給された値との対応を計算する。Adapter内で行う未確定の相対配置には引き続きSDK定数を使う。不正な方向と方向／端の同時指定は拒否する。

`EditorPort.previewCaret`を必須とし、位置確認を行わない範囲指定の代替経路を削除した。現在のRealEditorPortは従来から専用経路を実装しており、成功条件は位置一致のまま。

1. `EditorAdapter` で API の `true` / `false` / reject / timeout / stale epoch を失わずに分類する。本文はログに出さない。
2. `ImeCoordinator` は編集結果を受け取り、エンジンの確定効果と入力先の状態を管理する。選択の有無は `selectionChange` を使い、文字数の増減から推測しない。
3. `KanonIme` は日本語の未確定範囲と表示を管理する。入力先が変わったら範囲を破棄する。
4. タイムアウトは kanon 独自の待機期限であり、API の失敗通知ではない。期限後も元の操作が完了し得るので、キューを次へ進める条件を再設計するまでは「自動復帰できる」と断定しない。
5. 画面キー、編集メニュー、物理キーの編集操作は `KanonIme → ImeCoordinator → EditorAdapter → InputClient` の順に流す。`InputHandler` はキーボード表示と入力開始通知を担当し、入力先の文字を直接編集しない。

## 4. 現状の差分と未確認事項

### プレビュー非対応欄の英語補完（P24）

KanonImeの直接英語処理を`DirectEnglishInput`へ分離した。位置照会と前方文字列の取得は注入されたPortで行い、書き込みは同じCoordinatorの入力契約・キュー・失敗分類を使う。接頭辞がすでに入力欄にあるため、補完では残りの文字だけを挿入する。

位置照会後に入力先世代が変わった場合は、次の本文読み取りを発行しない。本文読み取り後も世代を照合する。候補のrevisionと接頭辞、最後の選択状態、予測許可は照会後にも再確認する。内部モデルの確認であり、SDKが選択通知の発生源や操作IDを提供すると仮定しない。

挿入結果が失敗・期限切れ・古い入力先ならUndoを記録せず、再送しない。Enterアクションは属性取得前後に同じ入力先を照合し、SDK接続側が送る。

読み取り結果の`queryBefore()`は既存の文字列への変換を維持している。`queryBeforeResult()`の全面適用や、同じ欄で読み取り中に起きるすべてのカーソル変更の検出は、この分離だけで完了したとしない。

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
| 対応済み | コンテナ内の入力欄 | EasyAbroad 内 Chrome / FULL は同じソース・同じ署名で release → debug → release を比較し、release で非同期API応答と入力が成功、debug で `IInputMethodAgent` の `operation not permitted` とタイムアウトを再現。実機用ビルドを release 標準に変更し、この実機での入力問題は解決扱いとする。OS内部の厳密な拒否条件は未確定。対照結果は [EASYABROAD_IME_FULL_CAUSE_HYPOTHESES.md](EASYABROAD_IME_FULL_CAUSE_HYPOTHESES.md) |
| 低 | サロゲートペアの削除単位 | G-01 では `deleteBackward(1)` が絵文字を分割しないことを観測。`deleteForward(1)` と全入力先への一般化は未確認 |

この差分表は実装や実機観測で更新する。未確認の項目を SDK の保証として実装しない。

### 英語補完Undoの受付と表示復元（P25）

`EnglishCompletionLifecycle`は補完前の候補・接頭辞・文書起点・入力先世代を保持し、成功時の確定長を使ってUndoを記録する。編集APIはCoordinator、未確定表示の復元はCompositionPreviewが担当する。既存の入力操作キュー内で復元完了まで待機する。

自動Undoの記録が無効なら通常Backspaceへ進む。明示Undoは通常削除へ置き換えない。編集後と表示復元後に入力先世代を照合し、旧入力先の結果を新しい表示へ反映しない。編集中の保護は例外でも解除する。

通常欄では補完末尾を削除し、残った接頭辞を選択して未確定表示へ戻す。直接入力欄では接頭辞の予測情報だけ復元する。固定TextInputでの実機結果は[実機確認手順](../tests/device/README.md)に記録する。通知の到着順・同じ欄でのすべての外部操作・Web／コンテナへの一般化は別途確認する。
