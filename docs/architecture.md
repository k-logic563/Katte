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

### Firebase Cloud Messaging

Push通知。

### Cloud Functions for Firebase

Firestoreイベントを起点とした通知送信など。

### Firebase Crashlytics

クラッシュ監視。

### Firebase Analytics

利用状況確認。

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
photoUrl
createdAt
updatedAt
```

FCM tokenは複数端末対応を考慮し、
サブコレクションで管理する。

```text
users/{userId}/devices/{deviceId}

fcmToken
platform
updatedAt
```

---

## groups

```text
groups/{groupId}

name
createdBy
createdAt
updatedAt
```

---

## group members

```text
groups/{groupId}/members/{userId}

userId
displayName
role
joinedAt
```

role:

```text
owner
member
```

MVPではroleによる複雑な制御は行わない。

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

---

## shopping sessions

```text
groups/{groupId}/shoppingSessions/{sessionId}

startedBy
startedByName
startedAt

endedAt
status
```

status:

```text
active
completed
```

原則として同一グループで同時に複数セッションを開始できる設計にしておき、
UI上の扱いは後から調整する。

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
```

必要になってから追加：

```yaml
freezed:
freezed_annotation:
json_serializable:
```

未経験の段階で依存パッケージを増やしすぎない。

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
