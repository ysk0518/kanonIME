# kanonIME

HarmonyOS向け日本語・英語キーボード。ArkTSのUIとIME連携、C++ Node-API経由のMozcで構成しています。

## 現在の機能

- 日本語・英語の12キーフリックとQWERTY。使う言語のオン・オフはキーボード内で変更できます。
- 「あA1」で日本語・英語・数字を切り替え、左下の配列キーで12キー／QWERTYを切り替えます。配列キーは日英両方に反映され、言語を変えても配列と数字モードを保ちます。
- 日本語の予測・変換候補、英語の単語補完、数字・記号入力。
- クリップボード履歴・ピン留め、テキスト編集。
- 上部ショートカットの追加・削除・並び替え。初期配置は設定とクリップボード。
- その他の設定はアプリアイコンから専用ページで開きます。キーボードの設定ボタンからの起動は、端末の入力法セキュリティモードにより制限される場合があります。
- 端末設定に追従するライト／ダーク配色、画面サイズに応じたレイアウト。
- キーボード内のメニュー →「サイズ」で高さを80〜150％に調整。上端をドラッグして「決定」で保存します。

開発中です。実機で確認した結果と未確認の項目は [検証記録](docs/KANON_VALIDATION.md) に記録しています。純正IMEと同じ未確定下線の表示にはOS側の制約があります。
入力法の基本モードでは、アプリの専用ページとIMEの設定データを共有できません。専用ページから変更した配列や操作設定のIMEへの反映には、共有サンドボックスの設定が必要です。

英語入力も日本語と共通の未確定表示・確定処理を使います。候補が出ているときはSpaceで候補を選択・巡回し、Enterで確定できます。候補がなければSpaceは入力中の文字を確定して空白を追加します。単語の確定に使ったEnterでは検索・送信を実行せず、確定後のEnterで入力欄のアクションを実行します。未確定表示に非対応の入力欄とパスワード欄では直接入力します。

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

### キーボード設定

下部の「入力」「外観」「操作感」で設定カテゴリを切り替えます。編集内容はタブ間で保持され、上部の「保存」でまとめて反映します。使用する言語のオン・オフは、キーボード左上のメニュー →「使用する言語」で変更し、即時反映します。設定アプリには言語の切り替えを置きません。

設定関連の文言は `entry/src/main/resources/base/element/string.json` で管理します。翻訳の追加方法は [文言・翻訳の管理](docs/LOCALIZATION.md) を参照してください。

各タブの「初期値に戻す」で、そのタブの編集値を戻せます。「保存」で反映します。入力は配列・フリック感度・長押し時間、外観は文字プレビュー、操作感は振動・ショートカット配置が対象です。背景画像・GIFは専用編集画面の復元操作を使います。

### QWERTYの配置とフリック切り替え

QWERTYの最下段は「配列／記号・あA1・読点・スペース・句点・Enter」です。左右カーソルキーは置かず、スペースを広くしています。キー幅は行の幅に対する比率で調整します。日本語の句読点は「、。」、英語は「,.」です。

日本語の未変換入力中は、フリックまたはテキスト編集画面の左右矢印で未確定の挿入位置を移動し、途中へ文字を追加できます。途中の位置は候補欄に「│」で表示します。変換キーを押した後の左右矢印は、変換範囲の縮小・拡大になります。範囲調整後の候補タップは対象文節だけを確定し、残りを未確定のまま残します。

QWERTYではスペースを長押しして左右へドラッグすると、同じ入力位置・変換範囲の調整を使えます。長押し時間は既存の設定に従います。短いタップはスペース／変換で、長押し後に離してもスペースや変換を追加しません。

設定の「入力」で12キー／QWERTYの配列を選びます。「フリック入力」のオン／オフは別に切り替え、保存します。オフではQWERTYを使い、左下のキーは「#+=」で記号画面を開きます。「ABC」で文字へ戻れます。オンにすると12キーへの切り替えを使えます。

通常設定は一つの設定データとして保存し、設定アプリからIMEへ同期します。保存とIMEへの反映確認は区別して表示し、同期待ちの場合は再試行できます。IME内の言語・配列・高さの変更も同じ経路を使い、未同期の変更を保持します。詳細は[設定保存とIMEへの反映](docs/SETTINGS_SYNC.md)を参照してください。デバッグログの`config`で保存・受信・適用の版を確認できます。

### キーボードの背景画像

キーボード左上のメニュー →「背景画像」、またはアプリの設定 →「背景画像を変更」から開きます。画像を1枚選び、プレビューで拡大率・横位置・縦位置・明るさ・キーの不透明度を調整して「保存」します。「標準に戻す」も保存すると反映されます。画像は縦横比を保って領域全体を覆い、拡大すると位置を移動できます。

静止画は長辺1280px以下のJPEGへ変換してアプリ内へコピーします。GIFは5MB以下・長辺1280px以下・120フレーム以下に対応します。GIFを選ぶと「アニメーションを再生」のON／OFFが表示され、OFFでは先頭フレームを表示します。設定画面とIMEは、送信元・宛先を自身のbundleに限定した共通イベントで画像と設定を分割同期し、それぞれの保存領域へ保持します。元の写真URIへの継続アクセス権やクリップボードは使いません。画像や設定をサーバーへ送信する処理はありません。

GIFの長辺を1〜1280px、FPS上限を1〜100fpsで指定し、「GIFに適用」で縮小・フレーム間引きを反映してから「保存」します。新しく選ぶGIFは元の解像度とフレームのタイミングをそのまま使用し、スライダーの初期値も元GIFに合わせます。元画像を拡大したり再生速度を上げたりはせず、GIFの10ms単位の制約に合わせたFPS上限として扱います。元GIFは設定アプリ内に保存し、再調整に使います。IMEへ送るのは調整後のGIFです。設定値によって変換後5MBや変換用メモリの上限を超える場合は、値を下げる案内を表示します。GIFの再出力には[ImagePackerのGIFエンコードAPI](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-image-kit/arkts-apis-image-ImagePacker.md#packtodatafrompixelmapsequence18)を使います。

GIFはキーボードが表示されている間に再生し、閉じた場合や設定・クリップボードなどのパネルを開いた場合は静止画へ切り替えます。設定画面のプレビューも、画面外や他のアプリへ移ったときは停止します。表示には[ArkUIのImageコンポーネント](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-basic-components-image.md)を使います。

設定画面の画像プレビューと、下の入力欄で開く確認用キーボードには、保存前の調整値も反映します。プレビュー画像を直接ドラッグして位置を、2本指のピンチで拡大率（100〜250％）を調整できます。スライダーによる調整も使えます。移動範囲は画像が表示領域からはみ出す部分までです。拡大すると移動範囲も広がります。調整中の値は一時表示で、保存せず画面を閉じたり他のアプリへ移った場合は保存済みの背景へ戻ります。

「キーボードに反映済み」はIME側での保存完了を受け取ったときに表示します。反映待ちの場合は背景設定画面の入力欄をタップしてkanonを表示してください。必要なら入力方式をkanonへ切り替えてから保存を再試行できます。

背景の変更が反映されない場合は、設定画面・背景編集画面の下部にある「デバッグログ」をオンにすると、保存・転送・描画の処理を確認できます。コンソールのテキストは長押しでコピーできます。詳しくは[背景変更の診断ログ](docs/BACKGROUND_DIAGNOSTICS.md)を参照してください。

確認用の入力欄は画像プレビューのすぐ下にあります。画像のある設定画面を開くか画像を選ぶと、ドラッグとピンチを示す短いアニメーションを表示します。プレビューに触れると案内が消え、そのまま画像を調整できます。

プレビュー上部の「12キー／QWERTY」で配列の見え方を切り替えられます。背景の位置・拡大率・明るさ・キーの不透明度を保ったまま比較できます。

GIFの調整欄では「元GIF」と「反映中」の解像度・平均FPS・フレーム数・1周の再生時間・容量を並べて表示します。画素数・フレーム数・容量の増減率も確認できます。平均FPSは設定の上限値ではなく、GIFに記録されたフレーム数と再生時間から計算します。

「GIF設定を標準に戻す」で、選択した元GIFの解像度・フレームのタイミングと再生ONへ戻します。元GIFデータを復元するため、再エンコードによる画質変化はありません。プレビューへの反映後、「保存」で確定します。

背景プレビューと配列切り替えは画面上部に固定されます。その下の設定項目をスクロールしながら、変更後の背景を確認できます。

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
