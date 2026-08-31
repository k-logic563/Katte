# Katte Architecture

## 1. 技術方針

Katte は Flutter + Firebase を中心に構成する。

Flutter未経験でも理解しやすく、
インフラ構成を必要以上に分散させないことを重視する。

---

# 2. Tech Stack

## Client

- Flutter
- Dart

### State Management

- Riverpod

### Routing

- go_router

### Model

初期段階では単純な Dart class から開始し、
必要になった段階で freezed を導入する。

---

## Backend / Infrastructure

### Firebase Authentication

ログイン・ユーザー認証。

Phase 2ではGoogle Sign Inを利用する。
Flutter側では `firebase_core`、`firebase_auth`、`google_sign_in` を使用し、
認証状態はRiverpod経由で `go_router` の画面制御へ反映する。

Apple Sign InはPhase 2.5またはリリース前対応として別途実装する。

### Cloud Firestore

主要データストア。

Phase 4ではユーザーが作成または招待コードで参加したGroupを利用し、
`groups/{currentGroupId}/items` をsnapshot購読する。
商品の追加・購入・UndoはRiverpodの現在Groupを通じてFirestoreへ反映し、
同じGroupの全Memberへリアルタイム同期する。

### Firebase Cloud Messaging

Phase 5ではログイン後に通知権限を要求し、商品追加Push通知を受信する。
Foregroundでは `flutter_local_notifications`、Background / Terminatedでは
Firebase Cloud MessagingのOS通知を利用する。

### Cloud Functions for Firebase

`groups/{groupId}/items/{itemId}` のonCreateを起点に、同じGroupの
追加者以外のMemberへFirebase Admin SDKから通知する。Regionは `us-central1` とする。

ownerによるGroup削除はCallable Functionで認証とowner roleを再検証してから実行する。
Inviteを無効化し、Group配下をrecursive deleteしたうえで全MemberのUser所属参照を削除する。
member本人の退出はFirestore transactionでMember documentとUser所属参照を同時に削除する。

### Firebase Crashlytics

Release buildのみcollectionを有効にし、Flutter framework errorと未処理async errorを記録する。
ログイン中はFirebase UIDだけを調査用識別子として設定し、Logout時に消去する。

### Firebase Analytics

画面表示と既存の主要操作だけをparameterなしで記録する。

### Firebase Storage

MVPでは必須ではない。
プロフィール画像などが必要になった場合に使用する。

---

# 3. Architecture Overview

```text
Flutter App
    |
    +-- Firebase Authentication
    |
    +-- Cloud Firestore
    |       |
    |       +-- Realtime Listener
    |
    +-- Firebase Cloud Messaging
            ^
            |
    Cloud Functions
            ^
            |
       Firestore Trigger
```

---

# 4. Firestore Data Model

## users

```text
users/{userId}

displayName
email
photoUrl
createdAt
updatedAt
```

現在の所属Groupを安全かつ単純に取得するため、Member documentと同時に
ユーザー配下へ参照を作成する。

```text
users/{userId}/groups/{groupId}

groupId
role
joinedAt
```

FCM tokenは複数端末対応を考慮し、
サブコレクションで管理する。

```text
users/{userId}/devices/{deviceId}

fcmToken
platform
notificationEnabled
createdAt
updatedAt
```

`deviceId` はアプリがRandom.secureで生成した128bit相当の値を
SharedPreferencesへ保存する。IMEI等の端末識別子は使用しない。
FCM Token refresh時は同じDevice documentを更新し、Logout時はDocument削除と
FCM Token削除を行ってからFirebase Authを終了する。

---

## groups

```text
groups/{groupId}

name
createdBy
inviteCode
createdAt
updatedAt
```

---

## group members

```text
groups/{groupId}/members/{userId}

userId
displayName
photoUrl
role
joinedWithInviteCode
joinedAt
```

role:

```text
owner
member
```

ownerはGroup全体を削除でき、memberは本人の操作で退出できる。
owner移譲や他Memberの削除など、roleによる高度な管理は行わない。

`joinedWithInviteCode` はClientからの参加作成をSecurity Rulesで検証するために保持する。

## group invites

```text
groupInvites/{inviteCode}

groupId
createdAt
```

招待コードをDocument IDとして直接getする。Collection一覧は許可せず、
Group情報を招待検索のために公開しない。

---

## shopping items

```text
groups/{groupId}/items/{itemId}

name
quantity
note

status

createdBy
createdByName
createdAt

purchasedBy
purchasedByName
purchasedAt

updatedAt
```

status:

```text
pending
purchased
```

Phase 3実装では `quantity` を数値（未入力は `1`）、`note` を文字列（未入力は空文字）に統一する。
`createdAt`、`purchasedAt`、`updatedAt` にはFirestoreのserver timestampを使用する。
Shopping画面は `status == pending`、購入履歴画面は `status == purchased` のDocumentを購読する。
購入操作とUndoは同じDocumentのstatusと購入者・購入日時フィールドを更新し、Document自体は削除しない。

Shopping / Purchase Historyのqueryは現在選択中Group IDを必ず利用する。
Groupを切り替えるとRiverpodのStreamProviderも新しいGroupのqueryへ切り替わる。
購入履歴のRealtime listenerは直近100件に制限し、長期利用時のread増加を抑える。

## item suggestions

```text
groups/{groupId}/itemSuggestions/{suggestionId}

name
normalizedName
useCount
lastUsedAt
updatedAt
```

`suggestionId` は、空白を整形して小文字化した `normalizedName` のUTF-8値を
URL-safe Base64化した決定的なIDとする。表示用の `name` には最後に入力された表記を保持する。

商品追加時はWriteBatchでitem作成とsuggestionのupsertを同時に行い、`useCount` をincrementし、
`lastUsedAt` と `updatedAt` にserver timestampを設定する。これにより片方だけが保存される状態を防ぐ。

Bottom Sheetを開いたときだけ `lastUsedAt desc`、上限30件で1回取得し、入力中の前方一致は
Client側で処理する。表示は最大8件とし、完全一致、最終使用日時、使用回数の順に優先する。
商品一覧を走査したり、キー入力ごとにFirestore queryを発行したりしない。

Security Rulesは現在のGroup memberだけにread/create/updateを許可し、正規化キーの変更と
不正な使用回数更新を拒否する。Group削除時はCloud Functionのrecursive deleteにより
他のsubcollectionとともに削除され、Group退出だけでは削除されない。

---

# 5. Realtime

Flutter側では Firestore の snapshot stream を利用する。

例：

```dart
FirebaseFirestore.instance
    .collection('groups')
    .doc(groupId)
    .collection('items')
    .where('status', isEqualTo: 'pending')
    .orderBy('createdAt', descending: true)
    .snapshots();
```

購入履歴は次のqueryを利用する。

```dart
FirebaseFirestore.instance
    .collection('groups')
    .doc(groupId)
    .collection('items')
    .where('status', isEqualTo: 'purchased')
    .orderBy('purchasedAt', descending: true)
    .snapshots();
```

`status + createdAt` と `status + purchasedAt` の複合Indexをリポジトリで管理する。

Riverpodでは StreamProvider と組み合わせる。

---

# 6. Push Notification Flow

## Item Created

```text
User A
  |
  | Add "Milk"
  v
Firestore
  |
  | onCreate
  v
Cloud Functions
  |
  | Fetch group members
  | Exclude User A
  | Fetch FCM tokens
  v
Firebase Cloud Messaging
  |
  v
User B / User C
```

Push本文例：

```text
由美が「牛乳」を追加しました
```

payloadには `type: shopping_item_created`、`groupId`、`itemId` のみを付与する。
通知タップは特定ItemへDeep LinkせずShoppingを開く。
Tokenが恒久的に無効とFCMから明示された場合だけ対応するDevice documentを削除する。

---

# 7. Security Rules

最重要ルール：

> グループデータは、そのグループのメンバーだけアクセスできる。

概念：

```text
isGroupMember(groupId)
```

をベースに、

- read
- create
- update
- delete

を制御する。

クライアントから `createdBy` 等を自由に偽装できないよう、
Security Rules と Cloud Functions の責務を分ける。

Phase 5のRulesでは次を適用する。

- User documentとその所属Group参照は本人のみアクセス可能
- Group / Member / ItemはGroup Memberのみread可能
- Itemの作成者・購入者UIDを認証UIDと照合
- 招待コードは認証済みユーザーによるDocument単体getのみ許可
- Member作成は自分自身かつ有効な招待コードとGroup IDが一致する場合のみ許可
- Group作成時のGroup / owner Member / User所属参照 / InviteはTransactionで一括作成
- `users/{uid}/devices` は本人のみread / write可能
- Cloud FunctionsはAdmin SDKを利用し、Clientへ送信用秘密情報を含めない

---

# 8. Offline

Firestore のローカルキャッシュを活用する。

ネットワークが不安定でも、

- 現在のリストを閲覧
- 一時的な更新

ができる構成を目指す。

ただしMVPでは高度な競合解決UIまでは実装しない。

---

# 9. Development Environments

Firebase Projectは最低でも以下を分離する。

```text
Development: katte-dev-jp
Production:  未作成（リリース前に別Projectとして用意）
```

必要に応じてstagingを追加する。

Flutter側ではflavorまたは環境設定で切り替える。

---

# 10. Repository Structure

初期案：

```text
katte/
├ app/
│  └ Flutter application
│
├ functions/
│  └ Firebase Cloud Functions
│
├ docs/
│  ├ README.md
│  ├ product-spec.md
│  ├ architecture.md
│  ├ roadmap.md
│  └ ui-spec.md
│
├ firebase.json
├ firestore.rules
└ README.md
```

Flutterアプリのみで始める場合は、
プロジェクトルートをそのままFlutterプロジェクトにしてもよい。

---

# 11. Flutter Package Candidates

```yaml
firebase_core:
firebase_auth:
cloud_firestore:
firebase_messaging:
firebase_crashlytics:
firebase_analytics:

flutter_riverpod:
go_router:

# build-time brand asset generation only
flutter_launcher_icons:
flutter_native_splash:
```

必要になってから追加：

```yaml
freezed:
freezed_annotation:
json_serializable:
```

未経験の段階で依存パッケージを増やしすぎない。

Brand source assetsは `assets/branding/` に集約する。Launcher IconとNative Splashは
`pubspec.yaml` の設定を正とし、次のコマンドでiOS / Android向けAssetを再生成する。

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

アプリ実行時に読むBrand AssetはLoginで使う `app_icon.png` のみとする。

---

# 12. Architecture Principle

Katteでは、

> 必要になる前に複雑化しない

を基本方針とする。

具体的には、

- Repository Patternを最初から過剰に作らない
- UseCase層を大量に作らない
- DTO / Entityを必要以上に分離しない
- Firebaseをラップするためだけの抽象化を作りすぎない

まずFlutterとFirebaseの標準的な書き方を理解し、
規模が大きくなった段階でリファクタリングする。
