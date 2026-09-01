# Katte Store Listing

## 基本情報

- App Name: `Katte`
- Primary / Default Language: 日本語
- Bundle ID / Application ID: `jp.katte.app`
- Version / Build: `1.0.0 (1)`
- App Store SKU案: `katte-ios-001`（App Store Connect作成時に最終決定）
- Google Play category案: ライフスタイル
- Ads: なし

App Store名が利用できない場合は、別名へ変更せず確認を止める。

## Subtitle候補（30文字以内）

1. 家族の「買っといて」を共有
2. 家族でつながる買い物リスト
3. 買い物を家族とリアルタイム共有

推奨は「家族の「買っといて」を共有」。

## Promotional Text案

家族の買い物リストをリアルタイムで共有。追加・購入状況をすぐ確認できます。

## Description案

家族の「買っといて」を、リアルタイムで共有。

Katteは、家族や同居人と買い物リストを共有するシンプルなアプリです。商品を追加すると
同じグループへすぐ反映され、誰が追加したか、何を買ったかをみんなで確認できます。

主な機能

- 家族・同居人との買い物リスト共有
- 商品追加と購入状態のリアルタイム同期
- 商品が追加されたときのPush通知
- 購入の取り消しと購入履歴
- 過去に入力した商品からの入力候補
- 招待コードによるグループ参加

Googleアカウントでログインし、グループを作成するか、受け取った招待コードで参加できます。

## App Store Keywords案

`買い物,買い物リスト,家族,共有,おつかい,メモ,チェックリスト,shopping`

最終入力時にApp Store Connectの文字数カウントと重複語を再確認する。

## Screenshot story

個人情報のないデモデータ（牛乳、卵、食パン、ティッシュ）を使う。

1. Shopping List — 「家族の『買っといて』を共有」
2. Group / Invite — 「招待コードですぐにつながる」
3. Realtime Sync — 「追加したら、みんなにすぐ反映」
4. Push — 「追加をPushでお知らせ」
5. Purchase / Undo — 「買ったものをみんなで確認」
6. History / Suggestions — 「よく買うものをかんたん再入力」

実機でSmall / Standard / Large相当を確認し、App Store ConnectとPlay Consoleが表示する
最新の必須サイズへ書き出す。通知画面は架空の名前と商品だけを使う。

## Review Notes案

KatteはGoogle Sign-Inを使用する家族向け買い物共有アプリです。レビューでは任意のGoogle
アカウントでログイン後、「グループを作成」を選択してください。作成後、表示される招待コードを
別アカウントの端末で入力すると、リアルタイム同期とPush通知を確認できます。単一端末でも、
商品追加、購入、取り消し、購入履歴、入力候補、グループ削除を確認できます。Push通知は
送信者以外の同一グループメンバーへ届きます。特別な権限や課金はありません。

レビュー提出前に、公開用Support URL、Privacy Policy URL、問い合わせ先、Pushの実機確認結果を
追記する。Backdoorや共通パスワードは用意しない。

## TestFlight scenario / feedback

手順: Google Login、Group作成、Invite Code共有、別User参加、商品追加、Push、Realtime
Sync、Purchase、Undo、Purchase History、Suggestion、Group退出。

- Critical: 起動不能、ログイン不能、データ漏えい・消失、同期不能、主要操作不能
- UX: 導線の迷い、文言、通知頻度、文字サイズ、画面サイズ別の崩れ
- Minor: 軽微な余白、アニメーション、再現性の低い表示差

## Consoleで必要な手動設定

- Apple: App record、SKU、Support/Privacy URL、App Privacy、年齢区分、スクリーンショット、
  Review Notes、TestFlight Internal/External、Beta App Review、最終審査
- Google: App record、Store Listing、Data Safety、App Access、Content Rating、Target Audience、
  Ads declaration、Internal/Closed testing、Production access
- Support page: FAQ、問い合わせ方法、アカウント削除ページへの直接リンク

