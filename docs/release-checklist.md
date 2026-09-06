# Katte 1.0.0 Release Checklist

更新日: 2026-09-05。`[x]` はリポジトリまたはFirebase CLIで確認済み、`[ ]` は手動作業または
BLOCKER。全BLOCKERが解消するまでRelease Candidateとはしない。

## Build and identity

- [x] App Version `1.0.0`
- [x] Build Number `1`
- [x] App Name `Katte`
- [x] Bundle ID / Application ID `jp.katte.app`
- [x] iOS / Android正式App IconとSplash
- [x] Zen Kaku Gothic Newを同梱しruntime fetchを無効化
- [x] iOS versionをFlutter build name / numberから取得
- [x] Android versionName / versionCodeをFlutterから取得
- [x] Android compileSdk / targetSdk 36（Flutter 3.47.1既定値）
- [x] Android releaseからdebug signingを除去
- [x] iOS App Store IPA作成（37.9 MB、production Push entitlement、`get-task-allow=false`）
- [x] Paid TeamのApp Store provisioning profileを自動生成（Team `5X4237AQY6`）
- [ ] **BLOCKER:** production upload keystoreと`android/key.properties`を安全に作成
- [ ] **BLOCKER:** Android SDK（API 36 / build tools）をインストールしてFlutterへ設定
- [ ] **BLOCKER:** `flutter build appbundle --release`成功

## Firebase

- [x] 接続先は`katte-dev-jp`
- [x] Firestore Rules deploy済み
- [x] `deleteGroup`（callable、us-central1、v2）deploy済み
- [x] `sendShoppingItemCreatedNotification`（us-central1、v2）deploy済み
- [x] Google Sign-In / Auth / Firestore / FCM / Analytics / Crashlytics構成あり
- [ ] **BLOCKER (iOS):** App Review Guideline 4.8を満たす同等のLogin Service
  （通常はSign in with Apple）を実装・実機検証
- [x] Emulator、localhost、mock、test accountのproduction混入なし
- [ ] **MUST FIX:** `katte-dev-jp`を正式公開にも使うかProduction projectを分離するか決定
- [x] APNs key登録と2ユーザーiPhoneでPush E2E成功
- [x] Artifact Registry `gcf-artifacts`にFirebase管理cleanup policy設定済み（1日超を削除）

## Privacy and policy

- [x] App Privacy / Data Safetyのコード監査表を本書に記録
- [x] Privacy Policyドラフトを`docs/privacy-policy.md`に作成
- [x] ATT対象となる広告・クロスアプリtrackingなし
- [x] 不要なCamera / Location / Contacts権限なし
- [x] 依存SDKのPrivacy ManifestがRelease app bundleへ格納されることを確認
- [ ] **BLOCKER:** アプリ内のアカウント・関連データ削除導線を実装・検証
- [ ] **BLOCKER:** Google Play向けWeb削除申請ページを公開
- [ ] **BLOCKER:** Privacy Policyの運営者・連絡先・保存/削除期間を確定して公開URLを用意
- [ ] **BLOCKER (iOS):** 公開Privacy Policyへの見つけやすいアプリ内導線を追加
- [ ] Terms of Serviceを法務・運用判断し、採用する場合は公開URLとアプリ内導線を用意

### App Store App Privacy申告案

| Data type | 実データ | Purpose | Linked to identity | Tracking |
| --- | --- | --- | --- | --- |
| Contact Info: Name / Email | Google表示名、email | App Functionality | Yes | No |
| User ID | Firebase UID | App Functionality、Developer Communications/Diagnostics相当 | Yes | No |
| User Content: Other User Content | group名、買い物商品、履歴、候補 | App Functionality | Yes | No |
| Identifiers: Device ID | FCM token、Firebase installation/app instance identifiers | App Functionality、Analytics | YesまたはSDK仕様に従い最終確認 | No |
| Usage Data: Product Interaction | screen view、固定名の主要操作event | Analytics | Firebase Console設定とSDK仕様で最終確認 | No |
| Diagnostics: Crash Data | crash、stack trace、Firebase UID | App Functionality / Analytics | Yes | No |
| Diagnostics: Performance/Other Diagnostic Data | Firebase SDKが付加する診断情報 | Analytics | SDK仕様で最終確認 | No |

App Store Connectの最新質問文とFirebaseの開示資料を提出直前に照合する。Google profile
photo URLもAuthentication profile情報として扱う。広告、Third-Party Advertising、Data
Broker用途、クロスアプリtrackingはない。

### Google Play Data Safety申告案

| Category | Data | Collected | Shared | Purpose |
| --- | --- | --- | --- | --- |
| Personal info | name、email、user ID、profile photo URL | Yes | No（service provider処理を除く） | Account / App functionality |
| App activity | app interactions | Yes | No | Analytics |
| App info and performance | crash logs、diagnostics | Yes | No | Analytics / Developer communications |
| Device or other IDs | FCM token、installation/app instance ID | Yes | No | Notifications / Analytics |
| User-generated content | group名、買い物商品・状態・履歴・候補 | Yes | 同一groupメンバーへ機能上共有 | App functionality |

通信時暗号化はYes。削除申請は未実装のため現時点で準拠不可。Firebaseをservice providerとして
扱う前提だが、Play Consoleの定義とFirebaseの最新開示を提出直前に再確認する。

## Permissions and SDKs

- iOS: 通知（ユーザー許可）、remote-notification background mode、Push entitlement
- Android: main manifestの`POST_NOTIFICATIONS`。`INTERNET`はFirebase等の依存manifestとの
  release merge結果をAndroid SDK導入後に最終確認する
- 不使用: Camera、Location、Contacts、Microphone、Photos
- Firebase: Core、Auth、Firestore、Functions、Messaging、Analytics、Crashlytics
- Google Sign-In、Google Fonts（font asset同梱）、Riverpod、go_router、SharedPreferences、
  flutter_local_notifications

## Store metadata and test

- [x] Store copy、Subtitle、Keywords、Review Notes、Screenshot storyを`docs/store-listing.md`に作成
- [x] Support / Privacy静的ページを`/katte/support`、`/katte/privacy`に実装
- [ ] **BLOCKER:** 公開用DomainへSupport / Privacyページをdeployし、到達確認
- [x] Support / Privacyページの運営者名・問い合わせメールを確定
- [ ] **MUST FIX:** 個人情報を含まない正式Screenshotを実機で作成
- [ ] App Store Connect app record / App Privacy / metadata / screenshots
- [ ] Play Console app record / Data Safety / app access / rating / audience / ads
- [ ] Play Console personal accountのclosed testing要件をConsoleで確認
- [ ] TestFlight Internal build installと主要flow
- [ ] 必要に応じExternal TestingとBeta App Review
- [ ] Small / Standard / Large iPhone、最低2実機
- [ ] Wi-Fi、mobile network、offline→online
- [ ] fresh install
- [ ] Build 1→2 upgradeでAuth / group / shopping dataを維持
- [ ] CrashlyticsへTestFlight crash/dSYMが到達
- [ ] Analytics DebugView/Realtimeでscreenと固定eventのみ確認

## Security and release hygiene

- [x] `.p8`、private key、keystore、password、service accountをGit ignore
- [x] tracked file名と秘密鍵signatureを走査（Firebase client configは公開client設定として保持）
- [x] FCM token、invite code、商品名、email、displayNameをlog出力しない
- [x] Firestore group/member authorization rules
- [x] Group削除はserverでAuth・membership・ownerを検証
- [x] Flutter outdated確認（直接依存はfirebase_auth patch、go_router majorのみ）
- [x] Functions build / 6 tests成功、outdatedはdev dependency majorのみ
- [ ] **SHOULD FIX:** Functions依存ツリーの`qs` / `uuid` moderate 8件を、互換性を検証した
  上流更新で解消（`npm audit fix --force`は`firebase-admin`のbreaking downgradeとなるため未適用）

## Release commands

```bash
flutter pub get
flutter analyze
flutter test
flutter pub outdated
flutter build ipa --release
flutter build appbundle --release

cd functions
npm run build
npm audit
npm outdated
```

Android signingは`android/key.properties.example`をローカルで複製し、本番upload keyの値を設定する。
keystoreと`key.properties`はcommitしない。Google Play App Signingを有効にし、upload keyは暗号化した
パスワード管理・バックアップを行う。

## Blocker classification

### BLOCKER

- Android SDK / production upload key / signed AAB
- iOSのGoogle Sign-Inに対するApp Review Guideline 4.8準拠（通常はSign in with Apple）
- account deletion（in-app + Google Play Web）
- public Privacy Policy URL / Support URL、およびiOSアプリ内のPrivacy Policy導線
- TestFlight主要flowおよびStore Console提出物の実機・手動確認

### MUST FIX

- Firebase production project方針の決定
- App Privacy / Data SafetyのConsole入力と最終照合
- store screenshots、age/content/target audience設定

### SHOULD FIX

- Terms of Serviceの運用・法務判断
- FunctionsのFirebase/Google依存ツリーに残る`qs` / `uuid` moderate advisory 8件（強制修正は
  firebase-admin 10系へのbreaking downgradeとなるため未適用）
- screenshot device matrixとnetwork/upgrade coverageの拡張

### CAN WAIT

- Release blockerではない機能・UI改善はPhase 9以降
