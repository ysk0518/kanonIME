# KanonIME 手元検証シート（M5残件）

- HAP: `entry-default-signed.hap` sha256 `b5fd3097bd9f12aa808b25c72075326f7269700a57fb114d2d12a28aaa65debb`（AT-11部分・M3 T13入り・デバッグログ除去済み）
- 端末: <device-id> / bundle local.yplic.kanon / 使用中=Kanon
- 新HAP後は必ず IME再生成（Huawei往復: `ime -s com.huawei.hmos.inputmethod` → `ime -s local.yplic.kanon`）
- 記録は長さ・件数・真偽のみ。本文・候補の書き写し禁止（REQ-07）
- 結果欄に ○/× と実測値を記入。×はhilogのkanon-行（partial/preview/select/submit）を添付

## AT-10 部分確定フロー（改修対象）

前提：自アプリEntryAbility、欄タップ→Kanon表示。diagは `n件数[…]#ids/… c- gN eM` を読む。

| # | 操作 | 期待 | 結果 |
|---|---|---|---|
| 1 | かな7打鍵（n:198,2055 a:138,2250 h:568,2055 o:1062,2055 n:888,2446 g:321,2055 o:1062,2055） | FIELD 7・JP_COMPOSING | |
| 2 | Space(569,2617) | FIELD 4・JP_CONVERTING・n9・g2 | |
| 3 | 分確(798,1713) | FIELD 4維持・JP_COMPOSING・n0・g1（確定2＋残り表示2） | |
| 4 | Space(569,2617) | FIELD 4→変換表示に置換・JP_CONVERTING・n9 | |
| 5 | 候補先頭(128,1835)タップ | FIELD 4（確定2＋残り確定2）・JP_EMPTY・g0 | |
| 6 | 手順1〜2→分確→Space→Enter(1104,2617) | FIELD 4・残り確定・パネル維持 | |

×時のhilog確認：`hilog -x | grep kanon-select` → `id= sel=ok/ng done= res=` を記録。
既知異常：手順5でFIELD 2・JP_EMPTYになる（残り確定のresult空 or sel失敗）。原因切り分け中。

## AT-11 未確定Enter（回帰・墜落注意）

| # | 操作 | 期待 | 結果 |
|---|---|---|---|
| 1 | かな数打鍵→未変換のままEnter(1104,2617) | 読みのまま1回確定のみ。素Enterを送らない | |
| 2 | 2回目Enter | カーソル移動等の通常動作。IME生存（pid変化なし） | |

注意：過去に未変換Enterで墜落2回（タップ瞬間・画面on・操作中）。再発したら時刻＋`hilog -x`のdied/FATAL行を記録。

## 回帰（合格済み・通し確認用）

| # | 項目 | 期待 | 結果 |
|---|---|---|---|
| R1 | AT-01: ENでab→←→BS→行頭→行末 | diag c2→c1→len1→c0→c1 | |
| R2 | AT-03: ブラウザ検索欄で未確定Enter→確定→再Enter | 2回目で検索実行・結果頁遷移 | |
| R3 | メモ帳: nihongo→Space→先頭タップ | 本文len3単独確定・JP_EMPTY | |
| R4 | 候補タップ全体確定（toukyou→Space→先頭） | FIELD維持・確定のみ | |

## デバッグログ消去チェック（出荷前）

- [ ] MozcEngine.ets / KanonIme.ets の `kanon-partial/preview/select/submit` hilogを除去
- [ ] HAP再ビルド＋hilog無音確認
