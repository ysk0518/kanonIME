# EasyAbroad 内 Chrome FULL 応答欠落 原因仮説メモ

作成日: 2026-10-04。EASYABROAD_IME_FULL_BUG_REPORT.md と CONTAINER_INPUT_API_MATRIX.md の観測に基づく原因候補の整理。入力本文・端末 ID・アカウント情報は含めない。

**13:37–13:40 更新:** 同じ main ソース・同じデバッグ署名Profileで release → debug → release を比較し、release では非同期APIの応答と入力が成功、debug では `IInputMethodAgent` の `operation not permitted` とタイムアウトを再現した。実機への導入は release を採用する。以下の初期観測・仮説は比較前の記録であり、末尾の対照結果を優先する。

## 確定事項
- kanon の要求は anco_service_broker まで届く（GetTextIndexAtCursor,start. 記録あり）。同じ要求 ID の応答は IME 側で観測できない。返信が生成されないのか、転送中に失われるのかは未確定。
- 書き込み要求では画面反映もされる。要求は編集欄まで届く一方、kanon 側で完了応答を受け取れない。
- getEditorAttribute（GetTextConfig 経路）は通る。応答欠落は編集 data channel の操作で観測される。
- 単独原因として否定できた条件: compatibleSdkVersion（WeChat と同じ 5.0.3(15) にしても再現）、targetSdkVersion（両者とも 6.1.1(24)）、bindFromClient:0（両 IME 同じ）、TextTotalConfig windowId=0（WeChat でも 0/0/0）、extension の sandbox 基本構成（一致）。kanon の通常欄では同じ JS callback / Promise が完了するため、callback 登録方法だけでは説明できない。

## 過去に「入力できた」場面との整理
- EasyAbroad 内 Chrome への kanon / BASIC 入力は実機で成功した。
- kanon / FULL の診断版でも、`insertText` や `setPreviewText` を直接送ると文字は画面に反映された。ただし同じ操作の完了応答は来なかった。「画面に文字が出た」と「IME が編集成功を確認できた」は別である。
- 会話中には同期 API の診断版で「一旦動いてそう」という観察があった。成功した編集要求 ID の応答ログと、その時のビルド・入力先・操作順は保存されていないため、安定した FULL 入力が成立したのか、画面反映だけだったのかは確定できない。後から PR #5 直前のビルドを同じ欄に入れ直すとカーソル取得は失敗した。版だけでなくセッション状態や起動経路で結果が変わる可能性を残す。
- 利用者の記憶では 2026-10-03 午前 02:30 頃まで入力できた。Git 上でその時点の最新 `main` は `a308e8c`（前日 23:34）で、入力経路を統一した PR #5 は同日 12:44 にマージされた。時系列では PR #5 が候補だが、上記の旧版再導入で失敗した観測もあるため、コミットを原因と断定できない。`a308e8c` の画面キーボードの主経路は `EditorAdapter` の非同期 API で、同期呼び出しは旧 `KeyboardController` の物理キー用経路に残っていた。作業途中の未コミット同期API診断ビルドとの混同にも注意する。
- 2026-10-04、再起動後の同じ端末で `a308e8c` を再ビルド・署名して再確認した（HAP SHA-256 `e7426dfe55a5f6dfacbdbf568fd3043693172e7a357fd59e7334bec0edbd8402`）。EasyAbroad 内 Chrome の空欄で「あ」キーを押すと候補欄には「あ」が出たが入力欄は空のまま。09:20:32.841 に `getTextIndexAtCursor` 要求 ID `1231859`（`sync:0`, `event code:14`, `ret:0`）がブローカーへ届き、09:20:35.843 に `qIndex timeout`。同じ ID の成功応答は観測できなかった。従って旧コミットを入れ直すだけでは成功を再現できない。過去の成功が虚偽という意味ではなく、当時のセッション状態か未保存の診断変更が再現条件に含まれる可能性がある。実機には通常版を再導入済み。

## 原因候補（現時点では順位を付けない）
1. 返信先 agentObject / セッションの対応付け
   [OpenHarmony の公開実装](https://github.com/openharmony/inputmethod_imf/blob/master/frameworks/native/inputmethod_ability/src/input_method_ability.cpp) では native 側の `agentStub_` から返信先を作り、data channel proxy に渡す。`msgId` と応答ハンドラも native 側で管理する。kanon の ArkTS `EditorAdapter.attach()` が管理する世代番号は、この native agent の登録を直接変更しない。編集側で応答を作れない、異なる agent / セッションに送る、または返送時の IPC が失敗すると、現在の観測と整合する。ただし、どの段階かを示すログはまだない。
2. 配布種別・署名・権限に応じたブリッジの処理差
   `bm dump` では配布種別が `app_gallery`（WeChat）と `none`（kanon）で異なり、要求権限などにも差がある。配布種別だけが差というわけではない。ブリッジ側に IME ごとの検査や登録差があれば応答差を説明し得るが、現在は検査ログも公開仕様もなく、配布種別を原因とする根拠はない。
3. セッション開始時の競合（単純な待ち時間不足は反証済み）
   kanon は `onInputStart` 直後に `queryAttribute` を投げるが、これは応答が得られている属性取得経路であり、失敗する編集 data channel の最初の要求ではない。[OpenHarmony の公開実装](https://github.com/openharmony/inputmethod_imf/blob/master/frameworks/native/inputmethod_ability/src/input_method_ability.cpp) は `SetInputDataChannel(clientInfo.channel)` を `OnInputStart` 通知前に同期的に呼ぶ。実機でも kanon は設定開始の約 25.6 秒後に編集要求を出して失敗し、WeChat は約 33 ms 後の初回要求で成功した。単純に初回要求を遅らせれば直るという説明は支持されない。別のセッション登録競合までは否定できない。
4. Chrome 側の編集状態ゲート
   Omnibox の状態に応じて応答処理が変わる可能性は残る。ただし kanon の `getForwardSync(2000)` は WeChat と同じ API・長さ・空欄でブローカーの `GetLeft` まで到達しても応答がなく、約3秒後に `12800003` となった。API 種別と長さだけでは差を説明できない。IME ごとの状態や内部セッション条件は未確認。
5. WeChat の未観測の事前操作
   起動直後の `ImsaKit` DEBUG ログでは、`SetInputDataChannel` の約 33 ms 後に `getForwardSync(2000)` が成功し、その前に別の編集 data channel 要求は見えなかった。独自ブリッジに作用する非公開の操作までは否定できないが、`sendMessage` や `getAttachOptions` が標準の編集 channel 登録に必要という公開契約は確認できていない。
6. Sync 呼び出しスレッドの親和性（低）
   WeChat の Sync 連打と kanon 診断の Sync 呼び出し元コンテキストが同じか未確認。ただし通常欄では同じ kanon コードで返るため kanon 側 plumbing 全般の誤りではない。

## 次の検証案
a. Huawei / EasyAbroad 側で、同じ `msgId` について編集処理後の応答生成、agent への送信、IME 側受信までを照合する。公開ログだけではこの境界を越えて特定できない。
b. 初回操作の `ImsaKit` event code を照合済み。さらに必要なら、WeChat / kanon の編集前後のブリッジ呼び出しを内部トレースで比較し、公開ログにない初期化の有無を調べる。
c. kanon の要求遅延だけでは解消しないことを約 25.6 秒の対照で確認済み。続けるなら時間差ではなく、セッション / agent の登録内容を確認する。
d. 権限差の線は同じ `msgId` の前後に denial があるかを確認する。配布種別変更は通常のローカルビルドだけで再現できるとは限らないため、その検証方法が確保できた場合に行う。
e. Huawei への追加質問として、a の応答経路、agent / セッション登録、IME ごとの検査条件を [EASYABROAD_IME_FULL_BUG_REPORT.md](EASYABROAD_IME_FULL_BUG_REPORT.md) の確認点へ反映する。

## 追加観測（11:07–13:30）

- 11:07:56、`insertText` の要求 ID `6514118` はブローカーへ届き、ブローカーの `InsertText end` は約2 ms後に記録された。一致する完了応答は取得したログにない。ブローカーの処理終了ログだけでは入力欄への反映を保証できない。
- 11:12 のキー操作では UI の押下・解放を観測したが、取得した Binder トレースに対応する kanon → ブローカーの編集要求は見つからなかった。利用者も入力欄に文字が出ないと回答した。この採取時は `ImsaKit` が INFO なので、DEBUG の要求ログがないことだけでは API 未呼び出しを証明しない。
- コード上、書き込みがタイムアウトすると `EditorAdapter.unresolvedWriteEpoch` が立ち、同じ接続世代の後続操作を `unresolved-write` で止める。`ImeCoordinator.needsRecovery` も後続入力を `recovery-hold` で止める。これらは「最初の応答欠落後に追加の要求すら見えなくなる」現象を説明し得るが、その時のフラグ値はログで未確認。最初の API 応答欠落の原因にはならない。
- 11:19:01.013 に `attach epoch=4` を観測。11:19:01.050 にブローカーが `IInputMethodAgent` の IPC エラー `29201`、`subErr:4`、`outer:operation not permitted` を記録した。約2.4秒後の `getTextIndexAtCursor` ID `7435806` はブローカーへ届き、約3秒後にタイムアウトした。新しい接続でも応答欠落は続いており、古い未解決書き込みの保護状態だけでは説明できない。
- 11:20 の ID `7435807`（カーソル取得）、`7435808`（左側文字取得）、`7435809`（deleteForward）もタイムアウトした。この操作列を `a` 入力として扱わない。操作確認の返信は取得できていない。
- 13:28 にも同じブローカーの `IInputMethodAgent` への権限エラーを観測。ただしメソッド番号・要求 ID を含まないため、完了応答そのものの拒否か、カーソル等の通知の拒否かは未確定。

### IPC トレースによるメソッド特定の制限

[公開 IPC 実装](https://github.com/openharmony/communication_ipc/blob/master/ipc/native/src/core/framework/source/ipc_object_proxy.cpp) は `ENABLE_IPC_TRACE` 有効時に `SendRequest:<interface>_<handle>_<proxy>_<method code>` を出す。[IPCTrace](https://github.com/openharmony/communication_ipc/blob/master/ipc/native/src/core/framework/source/ipc_trace.cpp) の有効判定は `HITRACE_TAG_RPC` である。

既存の rpc 採取にこのメソッド情報は見つからず、13:30 に `rpc` を有効にして読み取り専用の `ime -g` を実行した短い対照採取にも `SendRequest` は現れなかった。公開ソースの計測が製品版で有効か、採取対象プロセス等に別の制約があるかは不明。単に同じ rpc 採取を繰り返しても拒否メソッドを特定できるとは言えない。調査後は hitrace を停止し、`ImsaKit` は INFO に戻した。

次の比較では、新規接続時の WeChat と kanon の **同じ通知・返信メソッドについて送信先と IPC 成否を照合できる計測手段** が必要。Huawei / EasyAbroad 側へは上記 `IInputMethodAgent` エラーのメソッド番号、返信先の実プロセス、拒否した検査の条件を追加で確認する。debug/release 署名差は候補のままで、必要権限や申請の有無をこのエラーだけで断定しない。

## ビルド種別の対照で成立した対応（13:37–13:40）

ベースソースは main `1038937`。入力処理・module.json5 の権限・署名Profileを変更せず、Hvigor の `buildMode` のみ変えた。各HAPを更新インストールし、同じ EasyAbroad 内 Chrome の検索欄へ接続した。`ime -g` は FULL。release でもインストール後の `appProvisionType` は `debug`、`appDistributionType` は `none` のまま。変わったインストール属性は `app.debug`（release: false / debug: true）。コンパイル方式等もビルド種別で変わるため、OS内の厳密な拒否条件をこの比較だけで断定しない。

| 比較 | 観測 |
| --- | --- |
| release 1回目 | 13:37:16.160 カーソル取得 ID `12373372` → .162 に `code:0`。プレビュー設定 ID `12373373` → .167 に `code:0`。画面にも入力を確認 |
| debug に戻す | 13:39:58.492 カーソル取得 ID `12553184`。13:39:58.494 ブローカーで `IInputMethodAgent` の `29201 / operation not permitted`。13:40:01.493 `qIndex timeout` |
| release に戻す | 13:40:35.736 カーソル取得 ID `12601016` → .738 に `code:0`。プレビュー設定 ID `12601017` → .743 に `code:0`。画面にも入力を再確認 |

保存HAP（Git管理外）:
- release: SHA-256 `837a3ca2a8008c87e87dfab128a7c07af9812501889455c51383107f2527f1e0`
- debug: SHA-256 `8a9f60ab7b7f5d2a1d9cf4e8188aa47d034967f762b31643700f0f5c52383ac0`

読み取りだけでなく、release 1回目の仮表示削除でも ID `12373374` と `12373375` の成功応答を確認した。応答欠落は同期・非同期APIの選択変更をせずに解消した。現時点の対応は実機ビルドの release 採用であり、権限追加、保護処理削除、リリース署名への変更は行わない。`tools/fast-device.ps1` の既定を release にし、インストール前にHAPの `app.debug` を検査する。
