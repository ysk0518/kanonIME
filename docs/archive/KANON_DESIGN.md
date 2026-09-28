> 履歴資料です。現在の仕様とビルド手順はルートのREADMEおよびdocs/KANON_SPEC.mdを参照してください。

# 和音IME (kanon) 設計書 v1

> 履歴資料。本書の後継は [パイロット仕様v1.0](../KANON_SPEC.md)。実装時は [実装依頼書](KANON_IMPLEMENTATION.md) と後継仕様を優先する。以下には旧API案や候補表示の省略が残っている。

- bundle: local.yplic.kanon
- 目標: Mozc内蔵の日本語IME。store公開なし、デバッグ導入のみ。
- 前提: DevEco 6.1自動署名 (約14日) が利用可能。実機 HBP-AL00 / HarmonyOS 7。
- 状態: 設計のみ。実装はWinPC側エージェントへ引き継ぐ。

## 構成

ArkTS (UI + IME連携) と C++ (変換) の二層。プロセス分離なし。

- entry (ArkTS)
  - ServiceExtAbility (type: inputMethod): キー入力受付、候補表示、確定文字挿入。
  - EntryAbility: 設定画面・動作確認用。
  - KeyboardPanel: QWERTY/フリック切替、地球儀で日英切替 (段階C)。
- libkanon (C++, NDK)
  - Mozc の Engine + SessionHandler をプロセス内埋め込み。
  - 参考実装: fcitx5-mozc (SessionHandler + OssDataManager、IPCなし)。
  - Node-API で ArkTS と接続。関数: createSession, sendKey, getCandidates, commit, delete。
- 辞書データ
  - Mozc OSS辞書をアプリ資源として同梱。OssDataManager で読み込み。
  - サイズ・配置は実装時に測定。hap肥大時は分割検討。

## 動作

1. キー押下 → ArkTS がローマ字を C++ へ送る。
2. SessionHandler が変換・候補を返す。
3. ArkTS が候補表示。確定で insertText。
4. 削除・カーソル移動は InputMethodExtensionContext 経由。

## ビルド

- WinPC + DevEco 6.1。hvigorw CLI ビルド可 (DEVECO_SDK_HOME 必須、空白注意は `set "VAR=..."` 形式)。
- NDK: ohos.toolchain.cmake で libkanon をビルドし hap に同梱。
- 署名: 自動署名。bundle変更時は再生成。
- 導入: hdc install。確認: ime -l、選択、abc確定・削除・移動、Celia復帰。

## 制約・注意

- IME拡張はサンドボックス。ネットワーク・サブプロセス不可 (設計上不要)。
- 辞書ファイルの読み込み可否は実機で確認 (未検証)。
- Mozc は Bazel 前提。CMake/NDK への移植が最大の難所。abseil・protobuf の調達を含む。
- 証明書は約14日 (10月11日期限)。期限切れ前に再生成。
- Gboard・Celia の流用は不可 (別途確定済み)。

## 受入条件

- 実機で日本語変換・候補選択・確定・削除ができる。
- 日英切替ができる。
- Celia へ戻せる。

## 作業分割 (WinPC側への依頼順)

1. 空プロジェクト local.yplic.kanon で自動署名・実機起動 (段階A相当)。
2. Kika 由来の inputMethod 拡張で英字入力まで (段階B相当)。
3. libkanon の NDK ビルドと Node-API 接続 (ダミー応答で疎通)。
4. Mozc 組み込みと辞書同梱。日本語変換の実機確認。
5. キーボードUI整備 (段階C)。
