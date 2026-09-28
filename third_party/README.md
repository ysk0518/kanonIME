# 使用OSSとライセンス

kanonIME独自部分のMITライセンスと、以下のOSSのライセンスはそれぞれの対象に適用されます。元の著作権表記を保持し、ライセンス文書は上流ソースまたは使用SDKからコピーしています。

| OSS | 使用箇所・バージョン | ライセンス・通知 |
| --- | --- | --- |
| OpenHarmony KikaInputMethod | ArkTS・リソース・設定の元サンプル。Copyright 2023-2024 Huawei Device Co., Ltd. | Apache-2.0 / [全文](licenses/Apache-2.0-LICENSE)。各ファイルの元の表記を保持 |
| [Mozc](https://github.com/google/mozc) | 同一プロセスの日本語変換エンジン。`b9c3fcbd6d76b19649ef572324fa9da2559bc18e` | BSD-3-Clauseと辞書の通知 / [Mozc-LICENSE](licenses/Mozc-LICENSE) |
| Mozc OSS辞書 | NAIST/IPAdic、ICOT、沖縄辞書等のデータを含む | [Mozc-LICENSE](licenses/Mozc-LICENSE)、[辞書README・通知](licenses/Mozc-dictionary-README.txt) |
| [Abseil](https://github.com/abseil/abseil-cpp) | Mozc・Protobufの依存。`255c84dadd029fd8ad25c5efb5933e47beaa00c7` | Apache-2.0 / [Abseil-LICENSE](licenses/Abseil-LICENSE) |
| [Protobuf](https://github.com/protocolbuffers/protobuf) | セッションコマンド・設定等。`4b0c3aacf0657fbf38253b38918d3358dd4319ec` | BSD-3-Clause / [Protobuf-LICENSE](licenses/Protobuf-LICENSE) |
| utf8_range | 上記Protobufソースに同梱されるUTF-8処理 | MIT / [utf8_range-LICENSE](licenses/utf8_range-LICENSE) |
| LLVM libc++ / libc++abi等のランタイム | HarmonyOS SDK 6.1.1のOHOS clang 15.0.4を使用しC++ランタイムを静的リンク | SDK付属のApache-2.0 WITH LLVM-exceptionおよび旧ランタイム通知 / [LLVM-NOTICE](licenses/LLVM-NOTICE) |
| @ohos/hypium | 元サンプルのテスト依存、1.0.6。パッケージ本体はGitに含めない | Apache-2.0。依存の解決先はルートのoh-package-lock.json5を参照 |

同梱済み `.so` のビルド経緯は [検証記録](../docs/KANON_VALIDATION.md) を参照してください。LLVM-NOTICEは使用SDKの通知全文を保持しています。通知に挙がるすべてのSDKコンポーネントをアプリへ同梱するという意味ではありません。

OpenHarmony/HarmonyOSのNode-API・hilog・libc・zlib等は端末提供の共有ライブラリとして利用します。SDK・DevEco Studio・Bazel・CMake・Ninjaの本体はこのリポジトリに再配布していません。fcitx5-mozcのCMake構成を参考にした外部ビルド環境も、このリポジトリには含みません。

ソース・ネイティブライブラリを再配布する際は、ルートのLICENSE・NOTICEとこのディレクトリのライセンス文書を保持してください。
