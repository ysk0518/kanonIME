> 履歴資料です。現在の仕様とビルド手順はルートのREADMEおよびdocs/KANON_SPEC.mdを参照してください。

# 署名検証結果 (SIGNING_VALIDATION_RESULT)

作成日: 2026-09-27 JST。IMPLEMENTATION_BRIEF.md の検証記録。

## 環境

- PC: Windows PC + DevEco Studio 6.1系 (modelVersion 6.1.1)
- SDK: targetSdkVersion 6.1.1(24)、compatibleSdkVersion 6.1.1(24)、runtimeOS HarmonyOS
- 実機: HBP-AL00、HarmonyOS 7.0.0.105 (UDID <redacted>)

## 自動署名

- 成功。Signing Configs の自動生成で実名認証・銀行書類は要求されず。
- Hello World (local.hermes.signingsmoke 相当) が実機で起動確認。
- 証明書・Profile の実期限: 10月11日まで (9月27日起算で約14日間、報告通り)。

## 普通のアプリ

- ビルド: 成功
- 署名: 成功 (自動)
- 導入・起動: 成功

## IME

- 素材: KikaInputMethod を native-ime-probe へ複製、bundle local.hermes.nativeime、
  deviceTypes phone、SDK 6.1.1(24)/HarmonyOS に移行。
- 登録: 成功 (IME一覧に表示)
- 選択・文字入力: 成功 (キーボード表示・入力確認)
- Celia復帰: 試験終了時に実施のこと (標準IMEの削除・無効化はしない)。

## 更新

- 再署名・期限切れ挙動は未検証。期限が来たら再生成・再導入が必要な見込み。

## 残件

- 証明書・Profile の実期限の確認 (約14日説の照合)。
- 日本語変換・操作感の試作は別工程 (段階C)。
- 成果物: harmony-ime/native-ime-probe/、配布zip native-ime-probe.zip。
- 秘密材料 (.cer/.p12/.p7b のパスワード等) は公開リポジトリに入れない。
