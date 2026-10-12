# 開発ガイド

ArkTSでUI・IME連携を実装し、C++ Node-APIのブリッジを通してMozcを使います。

## ディレクトリ

| 場所 | 内容 |
| --- | --- |
| `entry/src/main/ets/components` | キーボード・設定・クリップボードのUI |
| `entry/src/main/ets/common` | 配列・ショートカット・表示・保存の設定 |
| `entry/src/main/ets/kanon` | IME処理、エディター操作、Mozcとの接続 |
| `entry/libs/arm64-v8a` | アプリに同梱するネイティブライブラリ |
| `native/bridge` | Node-APIブリッジのC++ソース |
| `tools` | HAP整列、ネイティブビルド、実機調査用ツール |
| `docs` | 仕様・検証記録 |
| `docs/media` | READMEに掲載するスクリーンショット・GIF |
| `docs/archive` | 初期設計・引継ぎ資料・元サンプルの説明 |
| `.local` | 公開しない実機画像・ログ・旧署名テンプレート |

## ビルドと端末への導入

現在の構成はWindows / DevEco Studio 6.1系 / HarmonyOS SDK 6.1.1 (API 24) / arm64です。

1. DevEco Studioでリポジトリのルートを開き、依存関係を同期します。署名なしの `build-profile.json5` は同梱済みです。
2. 実機へ導入する場合は、Signing Configsで自分の端末向け署名を設定します。クリップボード履歴の `ohos.permission.READ_PASTEBOARD` に対応するProfileが必要です。
3. DevEco Studioでビルドするか、インストール先に合わせて以下を実行します。

   ```powershell
   $env:DEVECO_SDK_HOME = 'C:/Program Files/Huawei/DevEco Studio/sdk'
   $env:JAVA_HOME = 'C:/Program Files/Huawei/DevEco Studio/jbr'
   & 'C:/Program Files/Huawei/DevEco Studio/tools/node/node.exe' 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js' assembleApp -p buildMode=release --no-daemon
   ```

4. HDCで署名済みHAPを導入し、IMEを選択します。複数端末接続時は `-t <target>` を指定してください。

   ```powershell
   hdc install entry/build/default/outputs/default/entry-default-signed.hap
   hdc shell ime -s local.yplic.kanon
   ```

`build-profile.json5` は署名情報を含まない標準設定としてGit管理しています。DevEco Studioで署名を設定した場合は、このファイルに追加された端末固有の署名情報をコミットしないでください。安全な初期状態は `build-profile.example.json5` にも保存しています。

### 実機での反復確認

`tools/fast-device.ps1` は接続中のUSB端末を優先して選び、リリースビルド・導入を一回で実行します。引数なしで両方実行します。Hvigorの継続起動を使うため、初回起動後の変更なしビルドは短くなります。

```powershell
powershell -NoProfile -File tools/fast-device.ps1
powershell -NoProfile -File tools/fast-device.ps1 -Status
powershell -NoProfile -File tools/fast-device.ps1 -SelectKanon -OpenPreview
powershell -NoProfile -File tools/fast-device.ps1 -Tap '370,2035;1125,2400' -Screenshot 'convert-check'
```

`-Build`、`-Install` は個別にも指定できます。`-Target` で端末を明示できます。画像はGit管理外の `.local/screenshots` に保存します。`-OpenPreview` で入力方式の選択画面が出た場合は、端末上で選択してください。

EasyAbroad 内 Chrome の FULL モードは、同じソース・同じデバッグ署名Profileの比較で、デバッグビルド（`app.debug=true`）ではブローカーの `IInputMethodAgent` 通信が `operation not permitted` となり、リリースビルド（`app.debug=false`）では応答と入力が成功しました。実機確認ではリリースビルドを使ってください。DevEco Studio から導入する場合も build mode を `release` にします。署名Profileの種別を変更する必要は、この比較ではありませんでした。製品版OS内部の拒否条件は未確認です。

デバッガーを使うときは `-BuildMode debug` を明示できます。`-Install` はHAPのデバッグ属性が指定したモードと一致することを確認してから導入するため、古いデバッグHAPを意図せず再導入することを防ぎます。
通常のアプリ起動では設定ページを開きます。入力確認用ページは `-OpenPreview` で開けます。

## 単体テスト

PC上で入力ロジックとレイアウト計算を確認できます。Node.js 18.20以上で、`tests` ディレクトリから `npm ci` → `npm test` を実行します。
実行対象・回帰テスト・製品ビルドとの役割分担は [テストの実行方法](../tests/README.md) を参照してください。
PRとmainへのpushでは [PC tests](../.github/workflows/unit-tests.yml) が通常テストと不具合検出チェックを自動実行します。HAPビルドと実機確認は別途行います。
実Mozcを使う [ホスト確認](../tests/integration/README.md) と、ネイティブ・Web・コンテナ向けの [固定入力手順](../tests/device/README.md) も用意しています。

## ネイティブ部分

アプリのビルドには同梱済みの `.so` を使います。`libkanon_bridge.so` は辞書を含み約58 MBあります。

ブリッジの更新用ツールは `tools/build-native-bridge.ps1` です。別途構成済みのエンジンビルドを必要とし、既定パスは `D:/kanon-engine` です。Mozc・依存ライブラリ全体をこのリポジトリだけで一から再ビルドする手順はまだ揃っていません。
