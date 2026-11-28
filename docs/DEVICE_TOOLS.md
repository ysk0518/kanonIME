# 開発用の端末操作

Windows PowerShell 5.1 または Windows の `pwsh` でリポジトリのルートから実行します。DevEco Studio 標準パスの `hdc.exe` を使用します。端末が 1 台なら `-Target` は省略できます。複数台では `hdc list targets` の ID を指定してください。

## 状態を確認する

```powershell
Import-Module ./tools/device/KanonDevice.psm1
$target = '<hdc の端末 ID>'

Get-KanonDeviceState -Target $target -SkipLayout | Format-List
Assert-KanonDeviceReady -Target $target
Get-KanonDeviceState -Target $target | Format-List
```

`Connected`、`ScreenOn`、`Locked`、前面のアプリと Ability、選択中の IME を確認できます。通常は、点灯・ロック解除済みの画面から Kanon キーボードの表示有無、入力モード（`JP` / `EN`）、配列（`QWERTY` / `12KEY`）も読みます。画面構造の取得を省くには `-SkipLayout` を付けます。取得を省いた項目や判定できなかった項目は空欄になります。

接続、点灯、ロック解除を確認できる状態で操作できます。画面が消えていたら手動で点灯し、ロックされていたら解除してから再実行してください。`-IncludeColorMode` は設定アプリを開いて表示モードを読み、元の前面アプリへ戻ります。

## 文字や ID でタップする

Kanon のプレビューを前面に開いた状態で実行します。

```powershell
Find-KanonUiNode -Target $target -Id 'kanon_validation_input' |
  Select-Object -ExpandProperty attributes
Invoke-KanonUiTap -Target $target -Id 'kanon_validation_input'
```

文字を使う場合は、たとえば OS 設定の一覧で次のように指定します。この例は、対象が見つかるまで最大 3 回、画面左端で上方向にスワイプします。

```powershell
Invoke-KanonUiTap -Target $target -Text 'ディスプレイと画面の明るさ' `
  -ScrollUntilFound -MaxScrolls 3
```

`-Text` は完全一致、`-TextLike` は正規表現です。複数一致した場合は、画面構造の順で 0 から数える `-Index` を指定できます。タップはノード中央です。必要に応じて `-XFraction` と `-YFraction` を 0～1 で指定します。非表示や画面外のノード、ロック画面でのタップは拒否します。

## 表示と入力の設定を一時的に変える

Kanon が選択され、プレビューの入力欄でキーボードが表示された状態から開始すると、現在の入力モードも記録できます。表示モードの取得・変更には、日本語表示の OS 設定画面を使用します。操作中に設定アプリが入力欄のフォーカスを外した場合は、入力モードを切り替える前に入力欄を表示し直してください。

```powershell
Use-KanonDeviceSession -Target $target {
  param($session)
  Set-KanonColorMode -Target $session.Target -Mode Dark
  Get-KanonColorMode -Target $session.Target
  Invoke-KanonUiTap -Target $session.Target -Id 'kanon_validation_input'
  Set-KanonInputMode -Target $session.Target -Mode EN
  Get-KanonInputMode -Target $session.Target
}
```

セッションは画面の自動消灯を一時停止し、記録した表示モード、IME、Kanon の入力モードを終了時に戻します。`Use-KanonDeviceSession` はブロックで例外が起きた場合も復元処理を呼びます。個別に操作する場合は `$session = Start-KanonDeviceSession -Target $target` と `Stop-KanonDeviceSession -Session $session` を使えます。

復元途中で端末が切断・ロックされた場合は、同じ PowerShell で接続・点灯・解除を済ませ、`Stop-KanonDeviceSession -Target $target` を再実行します。入力モードの復元に必要な入力欄を開けない場合は、手動で Kanon キーボードを表示してから再実行してください。PowerShell を強制終了した場合は、端末で `power-shell setmode 600` を実行して通常の自動消灯へ戻してください。

## 撮影する

```powershell
Save-KanonScreenshot -Target $target -Path '.local/screenshots/preview.jpeg'
Save-KanonBurst -Target $target -Count 14 -IntervalMs 300 `
  -OutDir '.local/screenshots/keyboard' -Crop '0,1640,1260,2760' `
  -SheetPath '.local/screenshots/keyboard-sheet.jpeg' -Columns 4
```

各フレームは JPEG で保存されます。撮影間隔には端末の状態確認と撮影コマンドの所要時間も加わります。フレームは撮影を終えてから PC に転送します。`-Crop` はシートに載せる範囲を左・上・右・下の座標で指定します。切り出しの右端と下端は境界の外側を指します。`-Crop` だけを指定すると、出力先に `sheet.jpeg` を作ります。`-SheetPath` は JPEG と PNG に対応します。

## 端末を使わないテスト

```powershell
powershell -NoProfile -File tools/device/KanonDevice.Tests.ps1
node tests/run.cjs --test-name-pattern 'DT:'
```

Node のテストは `powershell`、次に `pwsh` を探し、どちらも見つからない環境ではスキップします。見本と模擬応答で解析と操作のガードを確認します。
