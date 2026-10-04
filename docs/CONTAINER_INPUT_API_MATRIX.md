# EasyAbroad 内 Chrome に対する InputClient API 実機調査

**2026-10-04 解決扱い:** 同じソース・同じデバッグ署名Profileの release → debug → release 比較で、release のAPI応答と入力が成功した。実機用ビルドを release 標準に変更した。以下の応答欠落の観測はデバッグビルドを対象とした過去の記録。最新の対照結果は [EASYABROAD_IME_FULL_CAUSE_HYPOTHESES.md](EASYABROAD_IME_FULL_CAUSE_HYPOTHESES.md) を参照。OS内部の拒否条件は未特定。

調査日: 2026-10-04。対象は HarmonyOS 実機の EasyAbroad 内 Chrome 検索・URL 欄、kanonIME の `FULL_EXPERIENCE_MODE`。同じ入力欄を空にし、`inputStart` で受け取った `InputClient` に対して各 API を単独で発行した。画面反映と callback / Promise の完了を別々に観測した。診断ログには操作番号・応答状態・エラーコードなどを記録し、入力文字列は記録していない。

## 観測結果

| 操作 | 画面上の結果 | callback / Promise |
| --- | --- | --- |
| `getEditorAttribute()` | 属性の取得のみ | 約 5 ms で resolve |
| `getTextIndexAtCursor(callback)` | 変化なし | callback なし |
| `getForward(3, callback)` | 変化なし | callback なし |
| `getBackward(3, callback)` | 変化なし | callback なし |
| `insertText('a', callback)` → `insertText('b', callback)` | 順に反映され、欄は `ab` | 両方とも callback なし |
| `selectByRange({start:0,end:1})` | 先頭の `a` を選択。続く `insertText('c')` で `cb` になった | Promise は pending のまま。後続の `insertText` callback もなし |
| `setPreviewText('あ', {-1,-1})` | `cb` の `c` と `b` の間に下線付きの `あ` が出た | Promise は pending のまま |
| `setPreviewText('あか', {-1,-1})` | 同じプレビュー範囲が `あか` に更新された | Promise は pending のまま |
| `finishTextPreview()` | 下線が消え、表示上は `cあかb` のまま | Promise は pending のまま |
| `deleteForward(1, callback)` | カーソル左側の `か` が消え、`cあb` になった | callback なし |
| `getCallingWindowInfo()` | ウィンドウ状態取得のみ | 約 5 ms で resolve、`status=1` |

いずれの操作も同期的な例外や非同期エラー通知は観測しなかった。応答がない操作は、その後の複数キー操作と画面確認の間も完了通知がなかった。「永遠に返らない」という保証ではなく、この実機・欄・観測時間内の結果である。`getCallingWindowInfo()` で取得できる SDK の `WindowInfo` にアプリの bundle 名は含まれない。

この結果は「すべての API 呼び出しが無効」という説明には合わない。編集要求は入力欄へ届き、画面に反映される。一方、編集結果を読む要求と多くの編集完了通知が戻らない。kanon の通常経路は、最初の日本語プレビューと英語直接入力の前に `getTextIndexAtCursor()` を待つうえ、以後の編集を直列化して Promise の完了を待つ。したがって最初の読み取りで進めず、読み取りを省いても編集完了待ちで後続キーが止まる。

## 他条件との照合

- 2026-10-04 の同一診断 HAP 対照: kanon 自身の `PrivatePreview` にある通常の ArkUI `TextInput` では、`getEditorAttribute()` 約 3 ms、`getTextIndexAtCursor(callback)` 約 5 ms（位置 0）、`insertText('x', callback)` 約 2 ms（`ok=true`）、`setPreviewText('あ')` 約 8 ms、`finishTextPreview()` 約 6 ms で完了した。直後に同じ HAP・同じ IME プロセスで EasyAbroad 内 Chrome の空欄へ戻すと、`getEditorAttribute()` 約 7 ms のみ完了し、残り 4 操作の通知は来なかった。`EditorAdapter` の接続世代は通常欄が 1、Chrome 欄が 2。つまり同じ JS callback 登録方法が通常欄では機能する。
- Chrome 欄で `insertText` 後、端末ログの `anco_service_broker/ImsaKit` は `OnSelectionChange` を記録し、`setPreviewText` / `finishTextPreview` 時には `anco_service_broker/Broker` の `ImfBrokerTextChangeListener` に各操作が入った記録がある。これはブリッジ層まで編集要求が届いた根拠になる。ただし応答 ID がどこで失われたかを示すログはまだ取得できていない。
- `ImsaKit` の DEBUG ログを一時的に有効にして、**同じ通常版 kanon HAP** で要求 ID を照合した。Chrome 欄では 01:54:29.576 に kanon 側が `GetTextIndexAtCursor` の `Request info id: 142112911 sync: 0 event code: 14 ret: 0` を記録し、同時刻に `anco_service_broker/ImsaKit` が `GetTextIndexAtCursor,start.` を記録した。同じ ID の `msg info` は観測できず、kanon の3秒待機後に `qIndex timeout` となった。再接続後も 01:56:27.695 の `id: 142281014` で同じ経過だった。対照の kanon 内 `PrivatePreview` では 01:55:41.432 の `id: 142212410` に対して 01:55:41.433 に `msg info id: 142212410 event code: 14 sync: 0 code: 0` が届き、続く `setPreviewText` の `id: 142212411` にも成功応答が届いた。要求の同期送信エラーや JS callback 登録ミスだけで Chrome 欄の差を説明するのは難しい。ただしブリッジ内部で応答が作られなかったのか、その後の IPC で失われたのかは分からない。
- 同じ欄の BASIC モードでは、以前の実機調査でカーソル取得・挿入・プレビュー更新が成功した。
- PR #5 前の kanon と振動を無効にした kanon でも、同じ FULL 欄でカーソル取得が応答しなかった。
- kanon の互換 API 値を WeChat 入力法と同じにした診断 HAP でも、挿入は反映されるが完了通知は欠けた。
- WeChat 入力法は同じ欄の FULL モードで実際に文字を入力できた。後述の DEBUG ログで、少なくとも `getForwardSync`、`getBackwardSync`、`insertTextSync` を使い、同じ要求 ID の成功応答を受けていることまで確認した。その他の内部実装は未確認。
- `bm dump` では WeChat と kanon はどちらも非システムアプリで、入力法 extension の `extensionTypeName=inputMethod`、`needCreateSandbox=true`、`isolationProcess=false`、専用 `:inputMethod` プロセスという基本構成が一致した。WeChat の要求権限は多いが、列挙された中に専用の IME 編集権限はない。これだけで権限差を完全に否定はできないが、システムアプリ資格や extension 種別の差では説明できない。
- 同じ Chrome 欄への入力法切り替え直後、WeChat と kanon は両方とも `StartInputInner ... bindFromClient:0`、`SetInputDataChannel start`、`OnInputStart begin` を記録した。WeChat はこの状態でも `getForwardSync` / `getBackwardSync` の同じ要求 ID への成功応答を 2–10 ms で受けた。kanon は `getTextIndexAtCursor` の要求がブローカーへ届いた後、3 秒でタイムアウトした。従って `bindFromClient:0` は単独の原因ではない。詳細な時刻と ID は [EASYABROAD_IME_FULL_BUG_REPORT.md](EASYABROAD_IME_FULL_BUG_REPORT.md) に記録した。
- `bm dump` で確認した配布種別には WeChat の `app_gallery` と kanon の `none` という差がある。現時点では、これが data channel の返信処理に関係する証拠はない。Huawei 側のセッション登録・返信先の診断で検証すべき候補として扱う。
- OS 純正キーボードでも入力できた。第三者 IME を一律に拒む仕組みとは断定できない。

## API 契約と実装への含意

ローカル SDK の `@ohos.inputMethodEngine.d.ts` には各 API の Promise / callback シグネチャがあり、`inputStart` で `InputClient` を受け取る。kanon はその契約に沿う形で接続している。[Huawei の IME FAQ](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-ime-7) のプレビュー例は `setPreviewText` と `insertText` を使い、事前のカーソル問い合わせは要求しない。したがってカーソル問い合わせを最初の入力の必須条件とするのは kanon の設計上の選択である。

「完了通知を待つ条件を取り違えた」という仮説も確認した。SDK の `insertText(text, callback)` は戻り値を返す非同期 callback 版で、`insertText(text): Promise<boolean>` とは同じ操作の別形式である。`selectionChange` / `textChange` は別の `KeyboardDelegate` イベントで、これらの発火を `insertText` の完了条件とする定義はない。診断では Promise 版だけでなく callback 版も直接呼び、文字の反映後に callback が来ないことを確認した。同一 HAP・同一 IME プロセスの通常欄では同じ callback が返るため、kanon の callback シグネチャや JS 登録方法が常に誤っているという説明は成り立たない。`getEditorAttribute()` と `getCallingWindowInfo()` は Chrome 欄でも resolve しており、クライアント全体が無効という説明にも合わない。

[OpenHarmony の JS 実装](https://github.com/openharmony/inputmethod_imf/blob/master/frameworks/js/napi/inputmethodability/js_text_input_client_engine.cpp) と [ネイティブ実装](https://github.com/openharmony/inputmethod_imf/blob/master/frameworks/native/inputmethod_ability/src/input_method_ability.cpp) では、編集要求の送信と応答受信が別段階になっている。画面に編集が反映されても完了通知がない、という実測と整合する。ただし OpenHarmony の公開コードが Huawei 実機の非公開部分と完全に同じとは限らず、EasyAbroad・OS・IME サービスのどの層が応答を失わせたかは未確定である。

公開実装の `insertText` と `getTextIndexAtCursor` は、要求発行時のエラーか、data channel の応答 callback を受けたときに JS 側を完了させる。`InputMethodAbility::OnResponse(msgId, ...)` は応答 ID を channel の `HandleResponse` に渡す。対して `getEditorAttribute` は `GetTextConfig` を通る別経路なので、その成功だけで編集操作の応答経路まで正常とは言えない。実機ログではコンテナ用ブリッジが編集を受けたところまでは見えたが、応答 ID の送信・受信は確認できていない。

公開実装の応答経路をさらに追った結果、[IME 側の `InputDataChannelProxyWrap`](https://github.com/openharmony/inputmethod_imf/blob/master/frameworks/native/inputmethod_ability/src/input_data_channel_proxy_wrap.cpp) は編集要求ごとに `msgId` と応答ハンドラを登録し、返信先の `agentObject` を編集側へ渡す。[通常の編集欄側の `InputDataChannelServiceImpl`](https://github.com/openharmony/inputmethod_imf/blob/master/frameworks/native/inputmethod_controller/src/input_data_channel_service_impl.cpp) は `InsertText`、`GetTextIndexAtCursor`、`SetPreviewText`、`FinishTextPreview` の処理後、成功・失敗を問わず同じ ID で `ResponseDataChannel(agent, msgId, ret)` を呼ぶ。`ResponseDataChannel` は `agentObject` が null なら送れない。IME 側の `HandleResponse(msgId, ...)` が登録ハンドラを見つけて初めて Promise / callback が完了する。このため、コンテナ欄の現象は「編集処理が失敗したので通知がない」という通常のエラー契約ではなく、返信先・ID・返信呼び出しのいずれかが成立していない可能性が高い。ただし Huawei 独自のコンテナ用ブリッジの実装は未公開で、どの段階が欠けるかは未確認。

## 接続シグナル仮説（2026-10-04）

`InputMethodAbility` のイベントと `InputClient.getAttachOptions()` を診断 HAP で観測した。同じ IME プロセスにおける入力先ごとの差は次の通り。

| シグナル | EasyAbroad 内 Chrome | 通常の ArkUI `TextInput` |
| --- | --- | --- |
| `inputStart` | 到着 | 到着 |
| `getAttachOptions().requestKeyboardReason` | `NONE=0`（タップで開いた直後に `TOUCH=2` への更新も一度観測） | `TOUCH=2` |
| `keyboardShow` | 到着 | 到着 |
| パネルの UI 準備 | 完了 | 完了済み |
| `setCallingWindow` | 当該入力開始では観測せず。通常欄から戻っても観測せず | 有効なウィンドウ ID を伴って到着 |
| `getEditorAttribute()` の識別情報 | `bundleName` は空文字、`windowId=566`、`displayId=0` | `bundleName=local.yplic.kanon`、`windowId=637`、`displayId=0` |
| 編集 API の完了通知 | 上表の通り欠落 | 上表の対照実験では到着 |

この差は、コンテナが通常欄と異なる識別情報・入力開始理由を渡していることを示す。Chrome 欄の `EditorAttribute.windowId` は数値を持つため、`setCallingWindow` 欠落を単純に「ウィンドウ ID がない」とは説明できない。公開実装では `EditorAttribute` に相当する `inputAttribute.windowId` と、`setCallingWindow` の発火条件になる `TextTotalConfig.windowId` は別のフィールドである。ただし `setCallingWindow` が欠けることが応答欠落の原因かは不明で、両者が同じブリッジ経路の症状である可能性もある。SDK に、IME がこのイベントを受けた後に「準備完了」を返信する専用 API は見当たらない。`sendMessage` / `recvMessage` はアプリと IME のカスタムメッセージ用で、汎用のセッション確立 API としては定義されていない。

追加の `ImsaKit` DEBUG ログでは、`anco_service_broker` が Chrome 欄の `GetTextConfig` に `windowId/y/height: 0/0/0` を記録した。これは上表の `getEditorAttribute().windowId=566` と同じ欄で観測された値だが、別フィールドなので単純な矛盾ではない。`TextTotalConfig.windowId=0` は `setCallingWindow` が来ないことと整合する。これが編集結果の返信先に影響するかは公開 API とログだけでは断定できない。

## WeChat との同一欄比較（2026-10-04）

EasyAbroad 内 Chrome の同じ検索欄で WeChat 入力法を FULL にして、12キーから1文字の候補を確定した。`ImsaKit` DEBUG ログでは、WeChat の `getForwardSync(2000)`（`event code: 3`）と `getBackwardSync(2000)`（`event code: 4`）が繰り返し同じ要求 ID の `msg info ... code: 0` を受け取った。候補確定時の `insertTextSync`（`event code: 0`）は 02:07:30.447 に ID `142902187` を発行し、ブリッジの `ACE InsertText` を経て 02:07:30.454 に同じ ID の `code: 0` を受けた。入力欄にも1文字反映した。従って、Chrome 欄の FULL モードで編集 API の返信が一律に欠けるわけではない。

kanon の診断 HAP で `getForwardSync(1)` と `insertTextSync('x')` を通常の入力経路から直接呼んだ。`compatibleSdkVersion` は WeChat と同じ `5.0.3(15)` にし、対象 API は両者とも `6.1.1(24)` のままにした。kanon の `getForwardSync` は 02:16:06.631 に ID `143471914` を発行し、ブリッジの `GetLeft` に到達したが返信はなく、約3秒後に `12800003`。`insertTextSync` は 02:16:09.634 に ID `143471915` を発行し、ブリッジの `ACE InsertText` が実行され、入力欄に `x` が出たものの、返信はなく約3秒後に `12800003`。続く非同期カーソル取得 ID `143471916` も返信なし。`getForwardSync` の要求長は WeChat と異なるが、`insertTextSync` の同じ API で結果が分かれ、互換 API 値だけでは解消しなかった。

WeChat の入力開始時にもブリッジの `GetTextConfig` は `windowId/y/height: 0/0/0` を記録した。したがって、この値がゼロであること単独では kanon の返信欠落を説明できない。IME ごとの返信先・セッション登録・ブリッジ経路の違いを調べる必要がある。WeChat の公開ログから使用 API と応答は分かるが、内部の初期化コードや独自契約までは分からない。

[OpenHarmony の公開実装](https://github.com/openharmony/inputmethod_imf/blob/master/frameworks/native/inputmethod_ability/src/input_method_ability.cpp) では `StartInputInner` が data channel を設定してから `inputStart` を通知する。`setCallingWindow` はウィンドウ ID が有効な場合に通知する別イベントで、編集 API 実行の前提条件とはされていない。Huawei 実機の非公開実装まで同一と断定はできないが、現時点で「kanon が欠けたシグナルを送れば接続できる」という契約上の根拠はない。必要なのは、コンテナのウィンドウ ID と data channel 応答の双方をブリッジ側で照合すること。

単純に編集 Promise を待たず次のキーを送る方法は、この欄でプレビュー更新と確定文字の表示順序を進められることを確認した。しかし、編集の成否、削除、選択、カーソル移動、急速な連続入力、欄の切り替え時の整合性は保証できない。タイムアウト後に同じ編集を再送すると、既に反映された文字を重複させる恐れがある。

kanon と WeChat の extension 基本構成、通常入力欄との API 対照、Chrome 欄での両 IME の同期 API 応答差は確認済み。次に必要なのは、EasyAbroad / OS のブリッジ実装側で、同じ Chrome 欄から WeChat には返信できるのに kanon には返信できない理由を、`msgId` と返信先 `agentObject` の登録・転送・`ResponseDataChannel` 実行で照合すること。公開ログだけではこの差の原因を特定できない。

診断用ビルドとキー割り当ては撤去した。実機には通常の kanon HAP を再導入し、`ime -g` で `local.yplic.kanon` / `FULL_EXPERIENCE_MODE` を確認した。
