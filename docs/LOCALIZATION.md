# 設定画面の文言

設定本体、背景画像・GIF編集、ショートカット編集の表示文言は、HarmonyOSの文字列リソースで管理します。

## 文言の変更

標準の日本語は `entry/src/main/resources/base/element/string.json` にあります。
各項目は `settings_`、`background_`、`gif_`、`shortcut_`、共通操作は `common_` から始まる名前で参照します。
表示文言を変える場合は `value` を変更し、コードが参照する `name` は維持してください。

## 翻訳の追加

対象言語の `element/string.json` に、同じ `name` の翻訳を追加します。
例えば英語は既存の `entry/src/main/resources/en_US/element/string.json` に追加できます。
端末の言語設定に従ってリソースが選ばれ、翻訳がないキーは `base` の日本語に戻ります。

```json
{
  "string": [
    { "name": "settings_tab_input", "value": "Input" },
    { "name": "settings_tab_appearance", "value": "Appearance" },
    { "name": "settings_tab_feedback", "value": "Feedback" },
    { "name": "settings_long_press_seconds", "value": "Long press for symbols: %s seconds" }
  ]
}
```

既存の言語ファイルへ追加する場合は、既存のキーを保持し、同じ名前を重複させないでください。
この変更では翻訳全文は追加していません。

## 数値・名前を含む文言

可変部分は `%s`（文字列）や `%d`（整数）の引数として渡します。
翻訳でも引数の型・数・順序を維持してください。
例: `background_gif_original_defaults` は解像度、FPS上限の順に整数を2つ受け取ります。
`shortcut_move_left` はショートカット名を1つ受け取ります。
翻訳対象の文をコード内で連結せず、文全体をリソースに置きます。

背景処理の例外は `BackgroundPhotoError.displayMessage` に表示用リソースを持ちます。
例外の技術用 `message` とユーザーへ表示する文言を分け、画面では `displayMessage` を参照します。

## 対象範囲

今回の対象は設定関連画面です。キーの入力文字列、変換候補、ユーザーが入力した文字列は翻訳対象にしません。
設定以外の画面には従来の直接記述が残っています。
