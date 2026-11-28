# P63 入力開始時の性能計測

Kanon のプレビュー入力欄で、表示と最初の打鍵と初回起動の基準値を取ります。イベントはすべて端末の `Date.now()` を使うため、アプリと IME のプロセスをまたいで引き算できます。計測中に時計が変わった回はログを確認してください。負の区間は除外されます。

## 計測点

| イベント | `entry/src/main/ets/` 以下のファイル | 時点 |
| --- | --- | --- |
| `field.focus` | `pages/PrivatePreview.ets` | プレビュー入力欄の `onFocus` |
| `ime.create` | `ServiceExtAbility/ServiceExtAbility.ets` | IME 拡張の `onCreate` 入口 |
| `mozc.init.start` | `kanon/NativeMozcBridge.ets` | ネイティブの動的ロード直前 |
| `mozc.init.end` | `kanon/NativeMozcBridge.ets` | ネイティブの `init` が成功し、Mozc セッションを確保した後 |
| `ime.inputStart` | `model/KeyboardController.ets` | InputMethodEngine の `inputStart` 入口 |
| `kb.show` | `model/KeyboardController.ets` | パネルの `show` 通知 |
| `kb.frame` | `pages/Index.ets`、`model/KeyboardController.ets` | パネルが表示され、ルートが最初に有効なサイズを持った時点。レイアウト済みのルートを再利用するときは `show` 通知時。表示 1 回に 1 件 |
| `kb.hide` | `model/KeyboardController.ets` | パネルの `hide` 通知、または表示中のパネル破棄 |
| `key.down` | `kanon/KanonIme.ets` | `keyText`、`keyKana`、`keyToggleTap` の入口。タッチ処理から文字入力が渡された時点 |
| `key.done` | `kanon/KanonIme.ets` | 同じ文字入力の既存 `ImeSession` 処理が完了した時点 |

`kb.frame` はルートのレイアウトを使う描画の目安です。`key.done` は編集 API を含む IME 側の処理を計測します。画面への実際の提示には端末の描画タイミングも関わります。

ログ本文は `P63 <event> <epoch-ms> <detail>` です。打鍵と Mozc の初期化はプロセス内の通し番号を振り、PID と番号で開始と終了を対応づけます。`kb.frame` には入力モード、配列、表示時点の背景画像の有無を記録します。画像フラグが未取得の場合は「不明」とします。

## DEBUG を有効にする

ドメインは `0x4B50`、タグは `KanonPerf` です。Huawei の公開資料に LOG_APP ドメイン指定とタグ指定の書式が掲載されています。スクリプトはドメイン指定を使います。通常のリリース設定では DEBUG の記録が制限されるため、P63 を含むデバッグビルドを使い、対象端末で成功応答とマーカーの出力を確認してください。 [HiLog コマンド](https://developer.huawei.com/consumer/cn/doc/harmonyOS-guides/hilog/) [HiLog ArkTS API](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V13/js-apis-hilog-V13/)

```powershell
hdc shell hilog -b D -D 0x4B50
hdc shell hilog -x -L D -T KanonPerf
```

ドメイン指定で取得できない場合は `hdc shell hilog -h` で対象端末のオプションを調べ、タグ指定の `hdc shell hilog -b D -T KanonPerf` も試せます。手動で有効にした場合は `-SkipDebugSetup` を指定します。計測後は設定を元に戻してください。元が INFO でドメイン指定を使った場合の例は `hdc shell hilog -b I -D 0x4B50` です。

## 計測する

P63 のデバッグビルドを入れて Kanon を選択し、画面を点灯してロックを解除します。リポジトリのルートから Windows PowerShell 5.1 または Windows の `pwsh` で実行します。端末が 1 台なら `-Target` は省略できます。既定は各場面 10 回です。別チェックアウトの HAP を使う場合は、そのビルドのコミットを `-Commit` に渡します。

```powershell
./tools/device/measure-cold-path.ps1 -Target '<hdc の端末 ID>' -Repeat 10
```

計測中は同じ端末の手動操作や別の自動操作を止めてください。スクリプトは試行ごとに `hilog -r` で端末のログバッファを消去します。

- **M1** はプレビューで一度キーボードを開き、ツールバーの `kikaInputDown` で閉じて、同じ入力欄をタップします。フォーカスが残る場合はプレビューを開き直します。IME の PID が変わった回や再生成を記録した回は M1 から除外します。入力欄の再フォーカスで IME が終了する場合や、再表示で `ime.inputStart` が通知されない場合は、回数と除外理由を確認してください。
- **M2** は M1 と同じ表示に続き、QWERTY なら `k → a → n`、日本語 12 キーなら `あ → か → さ`、英語 12 キーなら `a → d → g` を ID でタップし、最後に Delete を 3 回押します。次の試行は空の欄から始まります。ID 解決と端末操作は各キーの計測区間外です。表示から最初の文字入力までの間隔は JSON の `FirstKeyAfterFrameMs` で確認できます。
- **M3** は `aa force-stop local.yplic.kanon` で終了後、選択中の IME が Kanon のままであることを確認して、プレビューを開きます。選択が外れた時点で停止します。フォーカスに続く IME 生成と、同じ IME プロセスでの Mozc 初期化成功を確認します。初期化と表示は並行するため、`mozc.init.end` は `kb.frame` より後に来ることがあります。

## 結果を読む

出力先は実行した worktree の `.local/perf/<日時>/` です。`warmup.txt`、`M1-M2-*.txt`、`M3-*.txt` は `hilog -x` で取得した未加工の KanonPerf 行です。`results.json` に試行ごとの値と診断、`results.md` に中央値、p90、最大、回数が出ます。p90 は値を昇順に並べた `ceil(0.9 × 件数)` 番目です。モード、配列、背景画像の条件ごとに集計し、端末 ID、インストール済み HAP の `versionName`、コミットを添えます。コミットは `-Commit` または作業ツリーの HEAD です。

| 場面 | 比較する区間 |
| --- | --- |
| M1 | `field.focus → ime.inputStart`、`ime.inputStart → kb.frame`、`field.focus → kb.frame` |
| M2 | 1、2、3 文字目ごとの `key.down → key.done` |
| M3 | `field.focus → ime.create`、`ime.create → mozc.init.end`、`mozc.init.start → mozc.init.end`、`field.focus → kb.frame` |

基準値を取る前に `-Repeat 1` で、閉じる ID が取得できること、再フォーカスで M1 が成立すること、3 打鍵の未確定表示と Delete によるクリア、強制停止後の IME 選択と M3 のイベント順を確認します。失敗時も取得済みのログと集計を参照できます。

端末なしでログ解析を確認するには `node tests/run.cjs --test-name-pattern 'P63:'` を実行します。 [端末操作ツール](DEVICE_TOOLS.md)
