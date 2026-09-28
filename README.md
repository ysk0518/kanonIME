# kanonIME

HarmonyOS向け日本語・英語キーボード。ArkTSのUIとIME連携、C++ Node-API経由のMozcで構成しています。

## 現在の機能

- 日本語・英語の12キーフリックとQWERTY。言語ごとに配列を設定できます。
- 日本語の予測・変換候補、英語の単語補完、数字・記号入力。
- クリップボード履歴・ピン留め、テキスト編集。
- 上部ショートカットの追加・削除・並び替え。初期配置は設定とクリップボード。
- 端末設定に追従するライト／ダーク配色、画面サイズに応じたレイアウト。

開発中です。実機で確認した結果と未確認の項目は [検証記録](docs/KANON_VALIDATION.md) に記録しています。純正IMEと同じ未確定下線の表示にはOS側の制約があります。

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
| `docs/archive` | 初期設計・引継ぎ資料・元サンプルの説明 |
| `.local` | 公開しない実機画像・ログ・旧署名テンプレート |

## ビルドと端末への導入

現在の構成はWindows / DevEco Studio 6.1系 / HarmonyOS SDK 6.1.1 (API 24) / arm64です。

1. 初回のみ、設定テンプレートをコピーします。既存の署名設定がある場合は上書きしないでください。

   ```powershell
   Copy-Item build-profile.example.json5 build-profile.json5
   ```

2. DevEco Studioでプロジェクトを開き、依存関係を同期します。
3. Signing Configsで自分の端末向け署名を設定します。クリップボード履歴の `ohos.permission.READ_PASTEBOARD` に対応するProfileが必要です。
4. DevEco Studioでビルドするか、インストール先に合わせて以下を実行します。

   ```powershell
   $env:DEVECO_SDK_HOME = 'C:/Program Files/Huawei/DevEco Studio/sdk'
   $env:JAVA_HOME = 'C:/Program Files/Huawei/DevEco Studio/jbr'
   & 'C:/Program Files/Huawei/DevEco Studio/tools/node/node.exe' 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js' assembleApp --no-daemon
   ```

5. HDCで署名済みHAPを導入し、IMEを選択します。複数端末接続時は `-t <target>` を指定してください。

   ```powershell
   hdc install entry/build/default/outputs/default/entry-default-signed.hap
   hdc shell ime -s local.yplic.kanon
   ```

`build-profile.json5` は端末固有の署名設定を含むためGit管理から除外しています。共有する設定は `build-profile.example.json5` を更新してください。

## ネイティブ部分

アプリのビルドには同梱済みの `.so` を使います。`libkanon_bridge.so` は辞書を含み約58 MBあります。

ブリッジの更新用ツールは `tools/build-native-bridge.ps1` です。別途構成済みのエンジンビルドを必要とし、既定パスは `D:/kanon-engine` です。Mozc・依存ライブラリ全体をこのリポジトリだけで一から再ビルドする手順はまだ揃っていません。

## ライセンス・使用OSS

kanonIMEの独自部分は [MIT License](LICENSE) です。OpenHarmonyの元サンプルに由来するコードはApache-2.0の表記を保持しています。

Mozcと辞書データ、Abseil、Protobuf、utf8_range、C++ランタイムの著作権表記・ライセンスは [使用OSS一覧](third_party/README.md) と [NOTICE](NOTICE) を参照してください。各OSSにはそれぞれのライセンスが適用されます。

## 資料

- [実装仕様](docs/KANON_SPEC.md)
- [検証・差分台帳](docs/KANON_VALIDATION.md)
- [フリックと英語補完](docs/KANON_FLICK_PREDICTION.md)
- [純正IMEのシグナル観測](docs/KANON_NATIVE_SIGNAL_OBSERVATION.md)
- [手元検証シート](docs/AT_SHEET.md)

過去の検証記録は当時の結果です。現在の仕様は実装仕様を参照してください。実機画像・生ログは `.local/screenshots` に保管し、Gitには含めません。
