# Katte Development Roadmap

Flutter未経験からKatteをリリースするため、
段階的に実装する。

各Phaseでは「動く状態」を必ず作ってから次へ進む。

---

# Phase 0 — Flutter Setup

## Goal

Flutter開発環境を作り、
iOS / Androidでサンプルアプリを起動できる。

## Tasks

- Flutter SDK導入
- flutter doctor確認
- Xcode設定
- Android Studio / SDK設定
- iOS Simulator起動
- Android Emulator起動
- Flutterプロジェクト作成
- Git初期化

## Done

```text
flutter run
```

でiOS Simulator上にアプリが表示される。

---

# Phase 1 — Static UI

## Goal

Firebaseを使わずKatteの主要UIを作る。

## Learn

- Widget
- StatelessWidget
- StatefulWidget
- Scaffold
- Column
- Row
- ListView
- TextField
- Button
- Theme
- Navigator / go_router

## Screens

- Login mock
- Shopping List
- Settings

## Done

ダミーデータで買い物リストを操作できる。

---

# Phase 2 — Firebase Setup & Authentication

## Goal

Firebaseを接続し、
ユーザー識別ができる。

## Tasks

- Firebase Project作成
- FlutterFire CLI
- firebase_core
- firebase_auth
- Google Sign In
- Login / Logout

## Learn

- Future
- async / await
- Provider
- Firebase user state

## Done

実際のユーザーとしてログインできる。

Apple Sign InはPhase 2.5またはリリース前対応として別途実装する。

---

# Phase 3 — Firestore Shopping List

## Goal

Firestoreへ商品を保存する。

## Tasks

- Group作成
- Item追加
- Item一覧
- Item更新
- Item削除
- 購入済み

## Learn

- Firestore Collection
- Document
- Query
- Timestamp
- Stream

## Done

アプリを再起動してもデータが残る。

---

# Phase 4 — Realtime & Group

## Goal

複数端末で同じリストをリアルタイム共有する。

## Tasks

- Group Member
- 招待方式
- Firestore listener
- StreamProvider
- メンバー別表示
- createdBy表示

## Test

端末A：

```text
牛乳を追加
```

端末B：

```text
画面更新なしで牛乳が表示
```

となること。

## Done

リアルタイム共有が成立する。

---

# Phase 5 — Push Notification

## Goal

アプリを開いていなくても追加に気づける。

## Tasks

- Firebase Cloud Messaging
- Notification permission
- Device token登録
- Cloud Functions
- Item create trigger
- Group member token取得
- Push送信
- 通知タップ時のDeep Link

## Notification

```text
由美が「牛乳」を追加しました
```

## Done

別ユーザーが追加した商品がPush通知される。

---

# Phase 6 — Shopping Mode

## Goal

「今買い物している」を共有できる。

## Tasks

- 買い物開始
- Shopping Session作成
- グループへ通知
- 買い物中表示
- 買い物終了

## Notification

```text
康平が買い物を始めました
買ってきてほしいものがあればKatteに追加してね
```

## Done

買い物中の家族へ商品を追加できる体験が成立する。

---

# Phase 7 — UX Polish

## Goal

毎日使える品質へ仕上げる。

## Tasks

- Loading
- Empty State
- Error State
- Undo
- Swipe action
- Keyboard UX
- Haptic feedback
- Dark Mode
- App Icon
- Splash
- Accessibility

---

# Phase 8 — Quality

## Goal

公開できる品質にする。

## Tasks

- Unit Test
- Widget Test
- Firebase Emulator検討
- Crashlytics
- Analytics
- Security Rules Review
- Firestore Index
- Performance確認

---

# Phase 9 — Release

## iOS

- Bundle ID
- Apple Developer
- App Store Connect
- Privacy Manifest確認
- Push Notification Capability
- Screenshots
- App Review
- TestFlight
- Production Release

## Android

- Application ID
- Google Play Console
- Signing
- Internal Test
- Store Listing
- Production Release

---

# Development Rule

各Phaseごとに、

1. 仕様確認
2. 実装
3. 動作確認
4. コードレビュー
5. docs更新
6. Git commit

まで行ってから次に進む。

Codexを使う場合も、
一度に複数Phaseを実装させない。

Flutterを理解しながら進めるため、
各Phaseで生成されたコードの重要部分は人間側でも確認する。
