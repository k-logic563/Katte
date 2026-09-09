# App Store Review Fix — Guidelines 4.8 / 5.1.1(v)

## Manual configuration before submission

1. Apple DeveloperのIdentifier `jp.katte.app` でSign in with Appleを有効化する。
2. XcodeのRunner targetでTeam `5X4237AQY6` とBundle ID `jp.katte.app` を確認し、
   Sign in with Apple capabilityを有効にしたprovisioning profileを再生成する。
3. Firebase project `katte-dev-jp` のAuthentication > Sign-in methodでApple providerを有効化する。
   Firebase Consoleが要求するApple Team ID、Key ID、Services ID、private keyはApple Developerで
   発行してConsoleのsecret欄へ登録し、GitやDart sourceへ保存しない。
4. `checkAccountDeletion` / `deleteAccount` Callable Functionを`us-central1`へdeployする。
5. Firebase AuthenticationのApple設定に表示されるredirect URIを、Apple DeveloperのServices ID
   Web Authentication設定へ正確に登録する（ConsoleがServices IDを要求する構成の場合）。

## Physical-device validation

- Google: 新規/既存login、削除時の再認証、削除後Login復帰
- Apple: 新規/既存login、「メールを非公開」、cancel、削除時の再認証とcredential revoke
- Account deletion: 通常member、単独owner、他Memberがいるownerのblock
- 削除後: Firebase Auth user、user document、devices、両側membershipが消えていること
- Regression: Group作成/参加/切替/削除/退出、商品CRUD、カテゴリ、購入/Undo/履歴、Push通知

## Review screen recording

物理iPhoneで1本の動画として次を撮影する。

1. Katteを起動し、GoogleまたはAppleでログインする。
2. 下部の「設定」を開く。
3. 画面下部の「アカウント管理」までscrollする。
4. 「アカウントを削除」→確認Dialogの「アカウントを削除」を選ぶ。
5. 再認証を完了し、Login画面へ戻るところまで映す。

他MemberがいるGroupのowner accountは動画に使用しない。App Review Informationへ動画を添付する。

## App Review response draft

Hello App Review Team,

Thank you for your feedback. We have addressed both issues in build 2:

- Sign in with Apple has been added as an equivalent login option alongside Google Sign-In.
- Account deletion is now available inside the app. The navigation path is: Settings > Account Management > Delete Account.
- The deletion flow removes the Firebase Authentication account and the user's associated account data and memberships. It also revokes the Apple credential for Sign in with Apple users.
- A physical-device screen recording showing the complete in-app account deletion flow has been attached to App Review Information.

Thank you for reviewing the updated build.
