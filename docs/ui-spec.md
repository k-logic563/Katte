# Katte UI Specification

## 1. Design Principle

Katteは毎日の買い物で使うため、
操作説明がなくても分かるUIを目指す。

キーワード：

- Simple
- Friendly
- Fast
- Lightweight

機能を見せるより、
買い物リストそのものを主役にする。

---

# 2. Main Navigation

MVPではBottom Navigationを増やしすぎない。

基本：

```text
Shopping
Settings
```

グループ切り替えはShopping画面上部から行う。

---

# 3. Login

```text
Katte

家族の「買っといて」を、
リアルタイムで共有。

[ Googleで続ける ]
```

iOS / AndroidともにGoogleログインを表示する。
Apple Sign InはPhase 2.5またはリリース前対応とする。

---

# 4. First Group Setup

ログイン済みでグループ未参加の場合：

```text
Katte

家族と買い物リストを共有しよう

[ グループを作成 ]

または

[ 招待コードで参加 ]
```

作成時はグループ名、参加時は6文字の大文字英数字の招待コードを入力する。
作成・参加後はそのGroupを現在GroupとしてShoppingへ進む。

---

## 4.1 Group Switcher

Shopping上部の現在Group名とchevronをタップすると、Safe Area内のBottom Sheetを表示する。
`users/{uid}/groups`から取得済みの所属Groupだけを一覧化し、現在Groupを先頭・選択状態で示す。

```text
グループを切り替え

✓ 岩田家
  実家

＋ 新しいグループを作る
＋ 招待コードで参加
```

作成・参加は初回Group Setupと同じBottom Sheetを再利用し、成功後は対象Groupへ切り替える。
長いGroup名は2行までとしてellipsisし、一覧取得中・失敗時はSheet内だけに状態を表示する。

---

# 5. Shopping List

Katteのメイン画面。

商品一覧はFirestoreの `groups/{currentGroupId}/items` のうち、未購入商品のみ表示する。
初回読み込み中は進捗表示、読み込み失敗時は簡潔なエラーと再試行導線を表示する。
Security Rules未反映などの読込失敗時もLoadingを終了し、Firebaseの詳細は画面へ表示しない。

```text
岩田家 ▼                  [ メンバー ] [ 履歴 ]

○ 牛乳
  由美 ・ 2分前

○ 卵 ×2
  康平 ・ 10分前

○ ティッシュ
  由美 ・ 20分前


[ ＋ 追加 ]
```

Shopping画面内には「買ってきてほしいもの」というセクション見出しを置かない。
商品追加・購入・Undoはsnapshot listenerにより同じGroupの別端末へ自動反映する。

---

# 6. Add Item

可能な限り軽いUIにする。

Bottom Sheet例：

```text
買ってきてほしいもの

商品名
[ 牛乳 ]

個数
[ 1 ]

メモ
[ 任意 ]

最近使ったもの
[ 牛乳 ] [ 卵 ] [ ティッシュ ]

[ 追加する ]
```

商品名以外は任意。

追加後は即座に閉じる。

Shopping一覧の各 `pending` 商品にはtrailing menuを表示し、「編集」「削除」の順に並べる。
「編集」では追加時と同じ入力様式のBottom Sheetで商品名・個数・メモを更新する。
購入済みへの変更は左側のCheckboxだけで行い、商品名や行全体のtapでは変更しない。「削除」を選ぶと
「この商品を削除しますか？」という確認Dialogを表示し、確定後にDocumentを削除する。
購入履歴の `purchased` 商品には編集・削除導線を表示しない。

Firestoreへの保存に失敗した場合はBottom Sheetを閉じず、入力内容を保持して簡潔なエラーを表示する。

候補はMaterial 3のChipで折り返して表示し、未入力時は最近使用した商品名、入力中は
前方一致する候補を最大8件表示する。履歴が空、読み込み中、または候補取得に失敗した場合は
候補領域を表示せず、通常の商品追加を妨げない。候補タップは商品名だけを入力欄へ反映し、
個数・メモを維持する。タップだけで追加処理は実行しない。

---

# 7. Purchased

商品をタップまたはチェックする。

```text
牛乳を購入済みにしました       [ 元に戻す ]
```

購入後は現在の一覧から除外する。
Undoでは同じDocumentを `pending` へ戻し、通常一覧へ再表示する。

MVPでは削除せず履歴として保持する。

購入履歴画面は購入日時の新しい順に、商品名・個数・購入者・購入日時を表示する。

```text
購入履歴

✓ ティッシュ
  康平 ・ 今日 18:32
```

履歴が0件の場合は「購入履歴はまだありません」と表示する。
各履歴行のメニューから「未購入に戻す」を選ぶと、同じDocumentを `pending` へ戻す。
Realtime Syncにより履歴から消え、Shopping一覧へ再表示される。

---

# 8. Members

```text
岩田家

メンバー

康平
由美

招待コード
K7P4XQ

[ コピー ]

家族にこのコードを共有してください
```

Member一覧と招待コードに続けて、ownerには「グループを削除」、memberには
「グループから退出」を危険操作として表示する。どちらも確認Dialogを必須とする。
owner移譲・role変更・他Memberの削除は行わない。
招待リンクとQR Codeは追加しない。

---

# 9. Settings

```text
設定

アカウント
  康平
  example@example.com

[ ログアウト ]

グループ
  ✓ 岩田家（現在使用中）
    実家                 ›
    旅行                 ›

  ＋ 新しいグループを作る
  ＋ 招待コードで参加

その他
  利用規約
  プライバシーポリシー
  バージョン
```

Settingsは`userGroupsProvider`の全所属Groupを表示する管理導線とする。Group Rowを開いても
現在Groupは切り替えず、選択したGroup IDのMembers、Invite Code、Delete / Exitを表示する。
一覧更新後もSettingsの表示位置を維持する。使用Groupの切り替えはShopping上部のSwitcherで行う。

Phase 5ではダミーの通知Toggleを置かない。ログイン後にOSの通知権限を要求し、
許可された端末へ同じGroupの別Memberによる商品追加を通知する。
Foregroundでも通知を表示し、通知タップ時はShoppingを開く。

---

# 10. Empty State

商品なし：

```text
今日はまだ何もありません

買ってきてほしいものを
追加してみよう。

[ ＋ 追加する ]
```

---

# 11. Error UX

通信エラー：

```text
更新できませんでした

通信状態を確認して
もう一度お試しください。

[ 再試行 ]
```

ユーザーが入力した内容を可能な限り失わない。

---

# 12. Interaction Principles

## 商品追加

最重要。

1〜2タップで入力開始できる。

## 購入

誤操作を防ぎつつ速くする。

候補：

- Checkbox
- Swipe
- Tap

Phase 1で触って決定する。

## Delete

即時完全削除ではなく、
Undoを検討する。

---

# 13. Visual Direction

初期方向性：

- 明るい
- 白ベース
- 大きめの余白
- 丸みのあるUI
- 少しポップ
- 子どもっぽくしすぎない

Primary FontはZen Kaku Gothic Newとし、Light / Dark Theme全体へ適用する。
Regular・Medium・Boldをアプリへ同梱し、実行時のネットワーク取得には依存しない。
Material 3の役割差を維持し、次の階層を基本とする。

- 画面タイトル: 28px / Bold
- セクションタイトル: 18px / SemiBold
- 商品名: 16px / Medium
- 補助情報: 13px / Regular
- ボタン: 16px / SemiBold

招待コードもZen Kaku Gothic Newを使用し、文字間隔を広げて英数字の識別性を確保する。

## Brand Identity

Katte App Iconは「吹き出し + チェック」で構成する。

- 吹き出し: 家族から届く「買ってきて」と共有・コミュニケーション
- チェック: 購入完了と確認
- Primary brand color: Muted Blue Green `#3B9C8F`
- Supporting color: Deep Teal `#155E57`
- Light background: Warm Off-white `#F7FBFA`

文字、ショッピングカート、買い物袋をIconへ入れず、小サイズでも判別できる
太いシルエットを使う。ブランド表示はApp Icon、Splash、Loginを基本とし、
Shopping ListやSettingsの各項目には反復配置しない。
