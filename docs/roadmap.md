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

## Implementation Status

- `cloud_firestore` を導入し、開発用の固定Group配下に商品を保存
- 初回利用時にTransactionで開発用Groupを存在しない場合のみ作成
- 空の `items` Collectionは事前作成せず、最初の商品追加時に自動作成
- Firestore snapshotをRiverpod経由で一覧表示
- 商品追加、購入済み / 未購入への更新、Repository上の削除操作をFirestore化
- Shopping画面は未購入商品のみ表示し、購入済み商品は履歴画面へ分離
- 購入直後のSnackBarから直前の1件をUndo可能
- 購入履歴の各商品メニューから未購入へ戻す操作を追加
- pending／purchased query用の複合Indexをリポジトリ管理
- 認証済みユーザーのみ開発用Group配下へアクセスできるPhase 3用Rulesを追加
- Firestore読込失敗時のError Stateと再試行導線を追加

Firebase ConsoleとiOS Simulatorでの実接続確認完了後にPhase 3完了とする。

---

# Phase 4 — Realtime & Group

## Goal

複数端末で同じリストをリアルタイム共有する。

## Tasks

- Group作成とMember document作成
- 6文字の招待コードによるGroup参加
- 現在GroupのRiverpod管理
- Group単位のFirestore listener / StreamProvider
- Member一覧と招待コード表示
- MembershipベースのSecurity Rules
- createdBy / purchasedBy表示

## Implementation Status

- 固定の開発用Group依存を廃止
- `users`、`groups`、`members`、`groupInvites` をRepositoryで管理
- Groupとowner Member、User所属参照、InviteをTransactionで一括作成
- Invite documentの直接getとRules検証によりGroup参加を実装
- Shopping / Purchase Historyを現在Group単位のsnapshot購読へ変更
- 未所属時のGroup Setup、Member・招待コード確認画面を追加
- 非MemberのGroup / Itemアクセスを拒否するSecurity Rulesへ強化
- owner向けGroup削除Callable Functionを追加
- member本人のGroup退出TransactionとSecurity Rulesを追加
- 削除・退出後のcurrentGroupとRealtime購読のcleanupを追加
- Shopping上部に複数GroupのSwitcher、作成・招待参加導線を追加
- 最後に選択したGroupをUser単位で端末保存し、無効時は所属Groupへfallback
- Group依存ProviderをGroup ID単位のautoDispose familyへ分離し、旧データflashを防止
- Settingsに全所属Groupと作成・招待参加の管理導線を追加
- Group詳細を明示的なGroup IDで開き、非current Groupの管理でも選択状態を維持

owner移譲、複数owner、Memberの強制削除は未対応とする。

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
- Foreground local notification
- 通知タップ時にShoppingを開く
- Logout時のDevice token削除

## Implementation Status

- `firebase_messaging` と `flutter_local_notifications` を導入
- 端末生成IDごとに `users/{uid}/devices/{deviceId}` へTokenを保存
- Token refresh監視とLogout時削除を実装
- Item onCreateのTypeScript Cloud Functionと通知対象決定テストを追加
- 追加者本人を除外し、同じGroupの通知有効DeviceだけへMulticast送信
- 恒久的に無効なTokenのDevice document cleanupを実装
- 通知タップ時はpayloadのGroupへ切り替え、既存Auth routingに従いShoppingを開く
- iOS Push Notifications / Background Modes / `aps-environment`をProjectへ復旧
- 商品追加Firestore triggerを `katte-dev-jp / us-central1`へdeploy

## Manual Setup Required

- App Store IPAでTeam `5X4237AQY6`のDistribution profileとproduction Push entitlementを確認済み
- Apple Developerで `jp.katte.app` のPush Notificationsを有効化済み
- APNs Authentication KeyをFirebase Consoleへ登録済み
- iPhone実機でFirestore → Eventarc → Functions → FCM → APNsのEnd-to-End通知を確認済み

Phase 5 Push Notificationは`COMPLETE`。

## Notification

```text
由美が「牛乳」を追加しました
```

## Done

別ユーザーが追加した商品がPush通知される。

---

# Phase 6 — UX Polish

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

# Phase 7 — Quality, Monitoring & Security Review

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

## Implementation Status

- Crashlyticsを導入し、Releaseのみcollectionを有効化
- Flutter error / 未処理async errorとFirebase UIDのみをCrashlyticsへ連携
- Analyticsを中央Service経由で導入し、画面表示と主要操作をparameterなしで記録
- Firestore Rulesの必須field・型・role改ざん防止をレビュー、強化
- Group削除Callableと商品追加通知Functionの認証・通知対象・ログをレビュー
- 購入履歴listenerを直近100件へ制限
- Flutter / Functions test、dependency audit、release buildをRelease前検証として実施

## Push Notification Status

FCM / Cloud Functionsは実装済み。Apple Developer Program加入とAPNs設定後の
iOS実機2ユーザー最終検証は引き続き保留する。

---

# Phase 7.5 — Brand Assets & App Icon Integration

## Implementation Status

- 正式Icon「吹き出し + チェック」とBrand Color `#3B9C8F`を確定
- 1024×1024 Master Iconと1200×630 Thumbnailを作成
- iOS AppIcon、Android通常／Adaptive Iconへ反映
- Android 12対応Native Splashへ反映
- Login画面へ控えめなブランド表示を追加
- 表示名 `Katte` とBundle ID / Application ID `jp.katte.app`を維持

iPhone実機へのDebug build・install・launchは成功済み。ホーム画面Iconと一瞬のSplashは
人間による最終目視確認を行う。Simulatorは初回Data Migration後のXcode buildが
環境側で待機状態になったため再確認し、AndroidはSDK導入後に端末確認する。

---

# Phase 7.6 — Shopping Item History Suggestions

## Implementation Status

- Group単位の商品名候補用 `itemSuggestions` collectionを追加
- 商品作成と候補の更新をWriteBatchで原子的に保存
- 最近使用した候補をBottom Sheetで最大8件表示
- 入力中はClient側の前方一致で絞り込み、完全一致・新しさ・使用回数で順位付け
- 候補タップは商品名だけを反映し、自動登録しない
- 候補取得失敗時も通常の商品追加を継続可能
- Group member限定のFirestore Security Rulesを追加
- Group削除の既存recursive deleteで候補も削除

2ユーザー実機での共有・Group切替・削除後データ確認は最終手動検証として実施する。

---

# Typography — Zen Kaku Gothic New

## Implementation Status

- Primary FontをNoto Sans JPからZen Kaku Gothic Newへ変更
- Material 3のTextTheme hierarchyを維持し、Light / Dark Themeへ一括適用
- Regular・Medium・BoldとOFLライセンスをアプリへ同梱
- Runtime font fetchingを無効化し、オフライン表示へ対応
- 商品名、補助情報、画面タイトル、ボタンの既存Weight hierarchyを維持
- 小さい画面と1.3倍のSystem Text SizeをWidget Testで確認

iOS / Android実機での全対象画面の最終目視確認はリリース前に実施する。

---

# Phase 8 — Release

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

Phase 8の具体的な進捗、Store metadata、Privacy申告、署名と手動検証は
[release-checklist.md](./release-checklist.md)で管理する。すべてのBLOCKERが解消するまで
`Katte 1.0.0 Release Candidate`とはしない。

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
