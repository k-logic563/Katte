# Phase 7 Review Notes

## Monitoring data

Crashlyticsへ送るアプリ指定情報は、Release buildの未処理例外・stack traceとFirebase UIDのみ。
Logout時はUIDを消去する。Analyticsの独自eventはparameterを持たず、次だけを記録する。

- `login`
- `group_created`
- `group_joined`
- `shopping_item_added`
- `shopping_item_purchased`
- `shopping_item_undo`
- `group_left`
- `group_deleted`

商品名、Group名、招待コード、email、displayName、FCM Token、UIDはAnalyticsへ送らない。

## Manual setup and validation

1. Firebase ConsoleのProject settings > IntegrationsでGoogle Analyticsを有効化する。
2. Crashlytics画面を開き、Release buildから一時的なtest crashを送って初回有効化を完了する。
3. Analytics DebugViewで画面表示と上記eventを確認する。確認用Crash UIは本番へ追加しない。
4. Java Runtimeを用意してFirestore Emulator Rules testを実行する。
5. Apple Developer Program加入後、APNs KeyとPush Notifications capabilityを設定して実機2台で確認する。

## Security Rules manual cases

- 未認証／非MemberはGroupをreadできない。
- Memberは自Groupだけをreadし、自Groupへ正しいschemaのItemを作成できる。
- Member documentのupdateとownerへのrole昇格は拒否される。
- 他UserのDevice collectionはreadできない。
- member本人の退出deleteだけが許可され、ownerや他Memberのdeleteは拒否される。

## Validation status

- `flutter analyze`: issueなし。
- `flutter test`: 32件成功。
- iOS release build (`--no-codesign`): 成功。
- Functions Node 22 build/test: 成功、6件成功。
- `npm audit`: moderate 7件。`firebase-admin`等の破壊的downgradeを伴う提案のため、`--force`は未実行。
- `npm outdated`: `@types/node`と`typescript`に次期majorあり。自動更新は未実施。
- Firebase deploy dry-run: Rules compileとFunctions predeploy buildに成功。実deployは未実施。
- Rules Emulator: Java Runtime未導入のため未実施。上記manual casesで補完する。
- Android build: Android SDK未導入のため未実施。

## Technical debt

### Must fix before release

- App Icon / SplashのSimulator・実機ホーム画面での最終目視確認。
- Crashlytics test crash、Analytics DebugView、Rules Emulator testの完了。
- iOS Push capability / APNs設定と実機2ユーザー通知確認。
- Group削除Callableと最新Rulesの開発Projectへのdeploy・実データcleanup確認。

### Should fix

- Privacy Policy / Termsの正式URLと表示導線。
- Android Emulatorまたは実機でのrelease smoke test。
- Offline復帰と同時編集の手動回帰テスト。

### Can wait

- 購入履歴100件を超える場合のpagination。
- Crashlytics以外のPerformance Monitoring導入。
- 大規模なState／Repository設計変更。
