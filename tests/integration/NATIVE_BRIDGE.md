# 製品ブリッジの実機結合確認

`entry/src/ohosTest/ets/test/NativeBridge.test.ets` が実際の `NativeMozcBridge` と
HAP同梱の `libkanon_bridge.so` を読み、固定入力を送ります。N09／N10は製品の `MozcEngine` も実行します。
[Hypium](https://github.com/openharmony/testfwk_arkxtest/blob/master/README_en.md) を使うSDK／実機用の試験で、PCテストのCIとは分けています。

## 実行

DevEco SDK、開発用署名、Connected状態のHDC端末が必要です。
プロジェクト直下の `build-profile.json5` にローカル署名を設定してから実行します。

```powershell
powershell -NoProfile -File tools/test-native-bridge.ps1
# 複数端末なら明示
powershell -NoProfile -File tools/test-native-bridge.ps1 -Target '<HDCの接続先>' -RestoreHap 'entry/build/default/outputs/default/entry-default-signed.hap'
# 実機なしでビルドだけ
powershell -NoProfile -File tools/test-native-bridge.ps1 -BuildOnly
# 作業checkoutとは別に署名済みprofileを持っている場合
powershell -NoProfile -File tools/test-native-bridge.ps1 -SigningProfile '<ローカルprofileのパス>' -RestoreHap '<通常の署名済みrelease HAP>'
```

別profileを渡した場合、ビルド後に元のprofileをバイト単位で復元します。認証情報をリポジトリへ追加しません。
`entry@ohosTest`・`isOhosTest=true`・`buildMode=release` を指定してビルドし、テストモジュール `entry_test` を追加します。
SDKのohosTest HAPはこの指定でも `app.debug=true` です。通常のrelease HAPと同じ実行権限を保証する試験ではありません。

テストは専用プロセスで直接実行し、UIやIMEセッションを開始しません。実行ごとにアプリfilesDir内の
`native-contract-<時刻>/mozc` を使います。通常のIME学習プロファイルは使いません。
ケース間では同じ専用セッションをresetします。学習・候補順位の完全な独立は要求せず、候補はラベルで探します。
プロファイルは障害調査用に残します。再実行では新しい名前を使います。

終了時は `bm uninstall -n local.yplic.kanon -m entry_test -k` でテストモジュールだけを取り外します。
通常の `entry` やユーザーデータをアンインストールする処理はありません。ただし、この端末ではテストモジュール取り外し後にkanonがIME一覧から消えました。
実機実行には `-RestoreHap` を必須とし、取り外し後に指定された通常release HAPを再インストールします。事前に通常版をビルドし、戻したい版を明示してください。
実行前のIME選択とモードを記録し、終了後に復元・照合します。復元できない場合は試験全体を成功にしません。

## 判定と証拠

`.local/native-device/<日時>/report.json` に結果とOS版、HAP・同梱.so・入力元.so・テストソース・ブリッジソースのhashを記録します。
`build.log`・`test.log`・`install.log`・`cleanup.log`・`restore.log` も同じディレクトリに残します。
ビルド／環境エラーと期待値不一致を分け、BuildOnlyは `built-not-run` とします。

`aa test` はassert失敗やApp diedでもシェル終了コード0を返す場合があります。
スクリプトは終了コードだけで合格にせず、`Tests run: 10, Failure: 0, Error: 0, Pass: 10, Ignore: 0` を要求します。
結果なし・0ケース・無視されたケースも合格にしません。後片付けの失敗は結果に残し、スクリプトも失敗させます。

## ケース

| ID | 確認 |
|---|---|
| N01 | k→i、JSONのUTF-8バイト長とUTF-16カーソル |
| N02 | 変換候補のIDを使って日本語を確定、その後のkiに残骸なし |
| N03 | てん→・の候補ページを巡回して確定し、次の入力でもセッション生存 |
| N04 | literalの？を未確定に含め、次のかなを保持 |
| N05 | 未確定の途中に挿入し、後続文字を保持 |
| N06 | 範囲縮小→部分確定→残りのliteral再構築→追加入力 |
| N07 | 非BMP文字のバイト長4・UTF-16カーソル2、文字単位の削除 |
| N08 | reset後の再入力に旧文字なし |
| N09 | 製品MozcEngine＋実ブリッジでQWERTY「き」をDelete、ｋに戻らない |
| N10 | 製品MozcEngine＋実ブリッジで「今日」だけ確定し、残り「は」に「が」を追加 |

共通してnative成功、JSONの候補件数と配列長、候補IDの整数、カーソル範囲を確認します。
部分確定効果の件数と本文も照合します。候補ページ巡回は160回を上限とし、見つからなければ失敗にします。

## 実施結果（2026-10-10）

- OS: OpenHarmony-7.0.0.105。10ケースが合格、失敗0・エラー0・無視0。最終実行は約2.6秒。
- 証拠: `.local/native-device/20261010-160842-4670/`。テストモジュールの取り外しも成功。
- テストHAP SHA256: `d43134cf771886e82fa9b14d2f0c4f11842c96d6354e6d84b3b36b731207b844`。
- 同梱.so SHA256: `909e116c7952f6e84a566277dc3c22f8490e23d3b74789a00ad0c353aaade168`。通常HAP内の.soと一致。
- 最初は旧TestRunnerディレクトリをSDKが見つけられずApp died。`testrunner` とArkTS拡張子へ合わせて修正。
- 旧HAP整列処理はdefaultだけを対象としていたため、ohosTestのPackageHapにも適用。
- N03の初案は最初の候補ページだけから「・」を探して失敗。ホストの全候補検索と異なるため、実Space操作でページ巡回するfixtureへ修正。製品入力ロジックを変更したものではない。
- PCテスト221件合格、通常releaseビルド2.7秒・warningなし。テストHAPでは既存Hypium／旧サンプル由来のwarningが残る。
- テストモジュール取り外し後、通常アプリのdebug=falseを確認。現在のIMEは純正BASIC。試験前のIME選択は未記録なので、選択が維持されたとは扱わない。

## 全体回帰での再実行（2026-10-11、P28）

10ケース合格、失敗0・エラー0・無視0。証拠は`.local/native-device/20261011-212507-7195/`です。
初回のテストHAPビルドでは、P23で必須にした候補版番号がN10に欠けていることを検出。`resized.candidateRevision`を渡すようテストを更新して再実行しました。通常IMEの処理を変更した修正ではありません。

テストモジュールを取り外し、通常release HAP `d06000e8d96cba2480279e6c7e3b466509ba5d8137dd60fdc405cef746870f50`と`local.yplic.kanon / FULL_EXPERIENCE_MODE`の復元まで合格しました。テストHAPと通常HAPの同梱.soはどちらも`909e116c7952f6e84a566277dc3c22f8490e23d3b74789a00ad0c353aaade168`です。
通常releaseはwarningなし。テストHAPに残るHypium／既存テストAbility由来のwarningは通常版と区別します。GitHubでのPC CI初回実行はPR公開後に確認します。

## 残る範囲

同日17:16の再実行も10件合格しました。証拠は `.local/native-device/20261010-171617-3435/`。
指定した通常release HAP（SHA256 `a45b24afc273c69ea7bf0ecc5e8ef16eeabf552e5230ef62169f7b2675f43215`）の再導入、
実行前後の `local.yplic.kanon / FULL_EXPERIENCE_MODE` 一致、テストモジュールの取り外しまで確認しています。

この試験はInputClient／EditorAdapterや表示中のIMEを操作しません。FULLモードの入力接続、ネイティブ／Web／コンテナ欄への
実際の本文反映、UIジェスチャー、入力先切替中の遅延・タイムアウトは [固定入力手順](../device/README.md) で別途確認します。
負の候補IDの網羅、nativeワーカーの競合・取消、履歴保存／再起動の復元、各SDK／端末への互換性も別の確認です。
