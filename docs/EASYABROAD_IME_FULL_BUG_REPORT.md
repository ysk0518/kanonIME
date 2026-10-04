# EasyAbroad 内 Chrome と HarmonyOS IME FULL モードの応答欠落

作成日: 2026-10-04。EasyAbroad / Huawei の入力ブリッジ担当者へ渡すための再現情報。入力本文、端末 ID、アカウント情報は含めない。

**13:40 更新:** 同じ main ソースとデバッグ署名Profileで release → debug → release を比較し、release の2回はカーソル取得と仮表示の応答・画面入力が成功、debug は `IInputMethodAgent` の `operation not permitted` とタイムアウトを再現した。release でも署名Profile種別は debug のままで、アプリ属性 `app.debug` は false になった。実機確認の対応はリリースビルド採用。以下は失敗したデバッグビルドの記録で、OS側にはデバッグアプリへの返信を拒否する条件の確認を依頼したい。詳細は [ビルド種別の対照結果](EASYABROAD_IME_FULL_CAUSE_HYPOTHESES.md) を参照。

## 環境と再現手順

- 実機: `HBP-AL00`、`OpenHarmony-7.0.0.105`。
- EasyAbroad: `com.huawei.hmos.skytone`、`7.0.2.303`。対象はその中で動く Chrome の検索・URL 欄。
- 入力法: kanon `local.yplic.kanon`、`1.1.10`、`ime -g` は `FULL_EXPERIENCE_MODE`。
- Chrome の検索・URL 欄を空にしてフォーカスする。入力法 extension の `inputStart` で受け取った `InputClient` に対し、`getTextIndexAtCursor(callback)` を1回呼ぶ。

期待: 取得値またはエラーが callback に返る。実際: callback は来ず、kanon 側の3秒待機がタイムアウトする。同じ欄への `insertText('x', callback)` と `setPreviewText('あ', {start:-1,end:-1})` は画面に反映されるが、完了 callback / Promise は来ない。`getEditorAttribute()` は約7 msで完了する。

同じ kanon HAP と同じ IME プロセスから kanon 内の通常の ArkUI `TextInput` に入力すると、カーソル取得、文字挿入、プレビュー設定、プレビュー終了はすべて数 ms で完了する。EasyAbroad 内 Chrome でも BASIC モードは入力できる。WeChat 入力法は同じ Chrome 欄の FULL モードで入力できる。公開ログに現れない初期化処理は不明。

追加の同一欄比較で、WeChat 入力法は `getForwardSync(2000)`、`getBackwardSync(2000)`、`insertTextSync` を呼び、要求 ID と一致する `code: 0` の応答を受けていた。候補確定の `insertTextSync` は 02:07:30.447 の ID `142902187` に対して 02:07:30.454 に成功応答が届き、欄にも反映された。対して kanon の診断 HAP では、WeChat と同じ `compatibleSdkVersion=5.0.3(15)` にして `getForwardSync(1)` と `insertTextSync('x')` を直接呼んでも、いずれもブリッジへ届いた後に約3秒で `12800003`。後者は `x` が欄に反映されたが、ID `143471915` の応答は届かなかった。両 IME の対象 API は `6.1.1(24)`。要求長と入力文字は異なるため完全に同一の要求ではないが、同じ同期 API で応答に差がある。

## 要求 ID の照合

`ImsaKit` タグを一時的に DEBUG にした実機ログから、入力文字列を含まない行だけを抜粋した。調査後、タグのログレベルは INFO に戻した。

| 入力先 | 時刻 | 観測 |
| --- | --- | --- |
| EasyAbroad 内 Chrome | 01:54:29.576 | kanon: `Request info id: 142112911 sync: 0 event code: 14 ret: 0` |
| EasyAbroad 内 Chrome | 01:54:29.576 | `anco_service_broker`: `GetTextIndexAtCursor,start.` |
| EasyAbroad 内 Chrome | 約3秒後 | kanon: `qIndex timeout`。ID `142112911` の `msg info` は観測できない |
| kanon 内 `PrivatePreview` | 01:55:41.432 | kanon: `Request info id: 142212410 sync: 0 event code: 14 ret: 0` |
| kanon 内 `PrivatePreview` | 01:55:41.433 | kanon: `msg info id: 142212410 event code: 14 sync: 0 code: 0` |
| kanon 内 `PrivatePreview` | 01:55:41.433–.434 | `setPreviewText` の ID `142212411` も `code: 0` で完了 |
| EasyAbroad 内 Chrome、再接続後 | 01:56:27.695–.696 | ID `142281014` を発行。`anco_service_broker` に `GetTextIndexAtCursor,start.`、返信なし |

Chrome 欄の `GetTextConfig` に対する `anco_service_broker` の DEBUG ログは `windowId/y/height: 0/0/0`。一方、IME が取得した `EditorAttribute.windowId` はそのセッションで非ゼロ（例: 566）。これは別フィールドなので直ちに矛盾とは言えないが、Chrome 欄で `setCallingWindow` が届かない観測と整合する。

WeChat を同じ欄に接続した際も `GetTextConfig` の `windowId/y/height: 0/0/0` を観測した。従って `windowId=0` 単独では両 IME の応答差を説明できない。

## 入力法切り替え直後の対照（08:21–08:22）

同じ Chrome の検索・URL 欄で kanon から WeChat へ入力法を切り替えた。WeChat の `StartInputInner` は `bindFromClient:0`、`SetInputDataChannel start` と `OnInputStart begin` が記録された。これは前に kanon へ切り替えたときと同じ `bindFromClient:0` であり、接続開始理由の違いだけでは結果を説明できない。両者の `GetTextConfig` は `windowId/y/height: 0/0/0`、入力属性の `windowId` は 566 だった。

kanon で検索欄を開き直して「あ」キーを押した際は、08:21:45.847 に `getTextIndexAtCursor` の要求 ID `165280374`（`sync:0`, `event code:14`, `ret:0`）が発行され、同時刻に `anco_service_broker` が `GetTextIndexAtCursor,start.` を記録した。08:21:48.849 に kanon 側で `qIndex timeout`。一致する応答 ID は確認できなかった。

一方 WeChat へ切り替えて同じ欄の `ABC` キーを押すと、08:22:28.862 の `getForwardSync(2000)` 要求 ID `165439565`（`event code:3`）に 10 ms 後 `code:0` の応答が返った。直後の `getBackwardSync(2000)` ID `165439566`（`event code:4`）にも 8 ms 後に成功応答が返った。同じ操作中の ID `165439567` と `165439568` にもそれぞれ応答があった。`bindFromClient:0` と `windowId=0` はどちらの IME にも見られたため、現時点で重要な差は編集チャネルの返信経路にある。

## 同一 API・引数と開始時刻の対照（08:42–08:49）

kanon の通常版では 08:42:29.857 に `StartInputInner` と `SetInputDataChannel start`、08:42:29.859 に `OnInputStart begin` が記録された。約 25.6 秒後の 08:42:55.435 に `getTextIndexAtCursor` の ID `166644316` を送信し、ブローカーが `GetTextIndexAtCursor,start.` を記録したが、08:42:58.437 に `qIndex timeout` となった。入力開始直後だけの競合ではない。

同じ欄で WeChat を起動し直すと、08:45:33.974–.978 に `SetCoreAndAgent` 成功、`StartInputInner`、`SetInputDataChannel start`、`OnInputStart begin` が記録された。最初に観測できた編集 data channel 要求は、その約 33 ms 後の `getForwardSync(2000)`、ID `166828506`（`sync:1`, `event code:3`）で、08:45:34.014 に同じ ID の `code:0` が返った。続く `getBackwardSync(2000)` の ID `166828507` も約 2 ms で成功した。この開始時ログには先行する特別な編集 data channel 要求は見えない。ただし公開ログに現れない初期化処理は否定できない。

kanon の同じソース版（`1038937`）の一時診断ビルドで **同じ `getForwardSync(2000)`** を Chrome の同じ空欄へ直接発行した。08:49:08.035 に ID `167019576`（`sync:1`, `event code:3`, `ret:0`）を発行し、ブローカーが `GetLeft,start, length:2000` を記録した。対応する `msg info` は観測できず、08:49:11.035 に SDK が `12800003` を返した。したがって API 名と長さの違いだけでも応答差は説明できない。診断コードは調査用 worktree から撤去し、実機には通常版 HAP を戻している。

公開ログから確認できるのは「kanon の要求をブローカーが受けたこと」と「IME に同じ ID の応答が届かなかったこと」まで。ブローカー内部で応答を生成したか、どの `agentObject` へ送信したかを示すログは得られず、失敗地点は確定できない。

## PR #5 前のコミットでの再確認（09:20）

利用者の記憶では 2026-10-03 午前 02:30 頃まで入力できた。当時の `main` は `a308e8c`（前日 23:34）、PR #5 のマージは同日 12:44。再起動後の実機へそのコミットを再ビルドして入れたが、同じ Chrome の空欄への「あ」は候補欄にだけ現れ、入力欄には出なかった。09:20:32.841 の `getTextIndexAtCursor` 要求 ID `1231859` はブローカーへ到達し、09:20:35.843 にタイムアウトした。旧コミット単独での成功は再現していない。当時の未コミット変更やセッション状態は復元できていないため、PR #5 の影響をこの結果だけで完全に否定するものではない。検証後、実機には通常版を戻した。

## 確認してほしい点

1. `GetTextIndexAtCursor` の要求 ID と返信先 `agentObject` がブリッジのどこまで届くか。
2. Chrome 側の編集処理後に `ResponseDataChannel(agent, msgId, ret)` 相当の返信が呼ばれるか。呼ばれるなら、IME 側へ同じ ID が届くか。
3. `TextTotalConfig.windowId=0` になる理由と、返信経路への影響。
4. 同じブリッジが WeChat の `insertTextSync` には返信し、kanon の `insertTextSync` には返信しない理由。IME ごとのセッション登録・返信先・権限や互換設定に追加の契約があるか。
5. 新規接続時の `IInputMethodAgent` IPC エラー `29201`、`subErr:4`、`outer:operation not permitted` が発生したメソッド番号、送信先プロセスと拒否条件。11:19:01.013 に kanon の `attach epoch=4`、11:19:01.050 にブローカーのエラー、11:19:03.468 にカーソル取得 ID `7435806` の受信、11:19:06.468 に kanon のタイムアウトを観測した。エラー自体にはメソッド番号と要求 ID がないため、カーソル等の通知か完了応答かを判断できない。
6. 製品版で `IInputMethodAgent` のメソッド番号を取得できる IPC 計測方法。`hitrace` の `rpc` カテゴリーを有効にした既存採取と、13:30 の `ime -g` 対照採取には、公開 IPC 実装の `SendRequest:<interface>_<handle>_<proxy>_<code>` 記録が出なかった。製品版の計測制約があるか。

公開の [OpenHarmony IME 側 data channel 実装](https://github.com/openharmony/inputmethod_imf/blob/master/frameworks/native/inputmethod_ability/src/input_data_channel_proxy_wrap.cpp) では、要求 ID と返信ハンドラを登録して編集先へ渡し、同じ ID の応答で非同期 API を完了させる。[通常の編集欄側の実装](https://github.com/openharmony/inputmethod_imf/blob/master/frameworks/native/inputmethod_controller/src/input_data_channel_service_impl.cpp) は処理後に成否を返信する。Huawei 実機の独自ブリッジが同じ実装とは限らないため、原因層の確定には上記のブリッジ内トレースが必要。

詳細な API 別の観測と比較条件は [CONTAINER_INPUT_API_MATRIX.md](CONTAINER_INPUT_API_MATRIX.md) を参照。
