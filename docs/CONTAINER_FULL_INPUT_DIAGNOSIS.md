# EasyAbroad 内 Chrome と FULL モードの入力診断

**2026-10-04 解決扱い:** 同じソース・同じデバッグ署名Profileで release → debug → release を比較し、release ではAPI応答と入力が成功、debug では権限エラーとタイムアウトを再現した。実機用ビルドを release 標準に変更した。以下は解決前の診断記録であり、最新の対照結果は [EASYABROAD_IME_FULL_CAUSE_HYPOTHESES.md](EASYABROAD_IME_FULL_CAUSE_HYPOTHESES.md) を参照。OS内部の厳密な拒否条件は未特定。

2026-10-03、実機、kanonIME `main` (`1038937`)。対象は EasyAbroad 内の Chrome の検索／URL 欄。入力した本文はログに記録しない。

## 確認できたこと

| 条件 | 結果 |
| --- | --- |
| kanon / FULL / 現行ビルド | `getEditorAttribute()` は成功する。`getTextIndexAtCursor()` と `insertText()` は約3秒でタイムアウトする。同期版のカーソル取得と挿入は `12800003` を返す。 |
| kanon / BASIC / 現行ビルド | カーソル取得、直前文字の取得、挿入、プレビュー更新が成功し、同じ欄へ入力できた。 |
| kanon / FULL / PR #5 直前 (`a308e8c`) | 同じ欄でカーソル取得がタイムアウトした。PR #5 だけでは説明できない。 |
| kanon / FULL / 振動だけ無効化した診断ビルド | 同じ欄でカーソル取得がタイムアウトした。振動処理は必要条件ではない。 |
| Huawei 純正キーボード / 同じ欄 | 入力できた。 |
| WeChat 入力法 (`com.tencent.wetype.hmos`) / FULL / 同じ欄 | 英語配列で空欄から `a` と空白を入力できた。`ime -g` は `FULL_EXPERIENCE_MODE`。第三者 IME を一律に拒む欄ではない。 |
| kanon / FULL / `insertText('x', callback)` 単独 | エンジン、操作キュー、カーソル取得、プレビューを通さず2回呼ぶと、入力欄は `xx` になった。しかし完了コールバックは一度も届かなかった。 |
| kanon / FULL / `setPreviewText('あ', {-1,-1})` 単独 | カーソル取得や操作キューを通さず呼ぶと、入力欄に「あ」がプレビュー表示された。しかし Promise は解決・拒否されなかった。 |
| kanon / FULL / 互換 API `50003015` の診断版 | WeChat と同じ互換 API、対象 API `60101024` に変更。単独の `insertText('x', callback)` は入力欄に反映されたが、完了コールバックは届かなかった。互換 API の値だけでは解消しない。 |
| kanon / FULL / 応答を待たない連続操作の診断版 | 同じ欄を空にし、カーソル取得なしで `setPreviewText('あ', {-1,-1})` → `setPreviewText('あか', {-1,-1})` → `insertText('赤')` → `setPreviewText('あ', {-1,-1})` をキー操作ごとに送った。画面は「あ」→「あか」→「赤」→「赤あ」と順に変化した。各非同期操作の完了通知は届かなかった。 |

失敗時に `inputStop` は発生していない。`inputStart` で受け取った `InputClient` は残っている。`ime -g` は `FULL_EXPERIENCE_MODE`、`hidumper -s InputMethodService -a '-a'` は kanon を `isCurrentIme: true` と表示した。直接書き込み後には編集欄が変わったが、登録済みの `textChange` と `selectionChange` は発火しなかった。再接続時には `selectionChange` が届いた。したがって、IMEの選択違いやkanon内の世代切れだけでは今回の失敗を説明できない。

## 解釈と未確定部分

SDK の `12800003` は、編集欄のフォーカス喪失、現在のIMEへの編集欄の未接続、またはIPC失敗などを含む。属性取得の成功は、編集欄への読み書きの通信まで保証しない。単独の `insertText` と `setPreviewText` が実際に反映されたため、引数の形やプレビュー範囲が一律に誤っているわけではない。以前の「タイムアウト＝書き込み失敗」という解釈は誤りで、少なくともこの2操作では**反映後の完了通知が返らない**。同期 API の `12800003` と非同期通知欠落が同じ原因かは未確定。

現時点で絞れた境界は、kanon の `InputClient` から EasyAbroad 内の編集欄への操作結果の返送である。WeChat 入力法は同じ欄で FULL 入力できたため、OS やコンテナが第三者 IME を一律に拒むという説明は成り立たない。ただし、WeChat がどの API や互換処理を使うかは確認できておらず、kanon 側の呼び出し方、IME の登録属性、IME サービスとコンテナの組み合わせのどこに差があるかは未確定。`aa dump -l` では Chrome は `com.android.chrome` のミッションとして見えるが、通常の `aa dump -r` のアプリプロセスには見えず、コンテナ側の詳細ログは今回取得できていない。

`bm dump` 上、両者の対象 API は `60101024`。互換 API は通常版 kanon が `60101024`、WeChat が `50003015` で異なる。kanon の診断版で互換 API だけを `50003015` に変更しても完了通知欠落は再現した。

## API 契約と実装の照合（2026-10-04）

| 確認対象 | 結果 |
| --- | --- |
| IME の接続 | `getInputMethodAbility().on('inputStart', ...)` から `InputClient` を受け取り、`EditorAdapter.attach()` に渡している。SDK と Huawei の入力法 FAQ の例と同じ API 系統。`TextInputClient` の旧 API を混用していない。 |
| 引数・戻り値 | `insertText(text)` の Promise 版と callback 版はいずれも SDK の宣言に合う。`setPreviewText(text, {start:-1,end:-1})` はプレビュー全体を置換する正規の範囲。診断版ではこれらをキュー外で直接呼んでも画面に反映された。 |
| 完了の仕組み | OpenHarmony 公開実装では、`insertText`、`getTextIndexAtCursor`、`setPreviewText` の JS 非同期操作はいずれもネイティブ層の応答 callback が来て初めて完了する。`InputMethodAbility::InsertText` は入力先の data channel に要求を渡し、`OnResponse` が応答 ID を返す。画面反映と完了通知は別の段階。 |
| kanon 固有の順序 | 日本語の最初の未確定文字は `KanonIme.refreshPreview()` が `getTextIndexAtCursor()` を待ってから `setPreviewText()` を呼ぶ。公式のプレビュー例は先行カーソル取得を要求しておらず、`setPreviewText(..., {-1,-1})` を直接使う。したがって、この先行読み取りは kanon の設計上の依存である。 |
| 英語の最初の文字 | `KanonIme.post()` が予測補完の種を探すため、最初の英字の挿入前にも `getTextIndexAtCursor()` を待つ。予測機能のための読み取りが、直接入力の表示まで遅らせる構造である。 |
| なお不明な点 | WeChat の内部 API 呼び出しは観測できていない。OpenHarmony 公開実装は HarmonyOS 実機の非公開部分と同一とは限らない。どの応答段階で途切れるかは、EasyAbroad または OS 側のトレースなしに断定できない。 |

根拠: 実機の直接 API 診断（上表）、同梱 SDK `@ohos.inputMethodEngine.d.ts`、[Huawei のプレビュー FAQ](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-ime-7)、OpenHarmony の [JS 非同期 API 実装](https://github.com/openharmony/inputmethod_imf/blob/master/frameworks/js/napi/inputmethodability/js_text_input_client_engine.cpp)と[入力法側の data channel 実装](https://github.com/openharmony/inputmethod_imf/blob/master/frameworks/native/inputmethod_ability/src/input_method_ability.cpp)。

API 呼び出しを適正なシグネチャに変えるだけで直る証拠はない。最初のカーソル取得を省くとプレビュー表示まで進めるが、その操作の完了通知も欠ける。安易に Promise を待たずに次操作を送ると、確定・削除・変換の順序や二重適用を保証できない。互換経路を設計するなら、入力先ごとに利用可能な API と応答を判定し、未確認の書き込みを再送しないことを条件にする。

連続操作の診断で表示上の順序と継続は確認できた。これは「待たない入力経路」の実現可能性を示すが、削除、カーソル移動、選択範囲、連打、入力先切替での正確性までは保証しない。WeChat が実際に同じ API や同じ待機方針を使っているかも不明。

kanon の通常経路は、最初のかな入力で `getTextIndexAtCursor()` の完了を待ってからプレビューを設定する。この欄ではカーソル取得が返らず、実際に表示できるプレビュー API まで進めない。カーソル取得を飛ばすだけでも、プレビューや確定の完了通知が欠けるため、成功と失敗を区別できず安全に次の操作を直列化できない。タイムアウト後の無条件再送は二重入力になり得る。

`KeyboardController.ets` が `inputStop` 時に拡張Contextを破棄する設計は別途見直す余地がある。ただし今回のキー操作中に `inputStop` はなく、この事象の直接原因を示す証拠はない。

次の切り分けは、EasyAbroad 側の入力ブリッジログを得ること、WeChat と kanon が同じ編集 API を呼ぶか確認すること、両 IME の extension 起動・InputClient 受け取りの違いを比較すること。いずれも確認するまで特定の層の不具合とは断定しない。

2026-10-04 追記: その後の `ImsaKit` DEBUG ログで、WeChat は同じ Chrome 欄から `getForwardSync`、`getBackwardSync`、`insertTextSync` の成功応答を受け、kanon の `getForwardSync` と `insertTextSync` は WeChat と同じ互換 API 値にしても応答しないことを確認した。kanon の `insertTextSync` は欄に文字を反映した後、約3秒で `12800003` になる。詳細な要求 ID、比較条件、残る疑問は [CONTAINER_INPUT_API_MATRIX.md](CONTAINER_INPUT_API_MATRIX.md) と [EASYABROAD_IME_FULL_BUG_REPORT.md](EASYABROAD_IME_FULL_BUG_REPORT.md) を参照。上の「WeChat の使用 API は未確認」という記述はこの追記で更新される。
