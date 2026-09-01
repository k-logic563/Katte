# Katte

![Katte brand thumbnail](assets/branding/katte_thumbnail.png)

家族や同居人と「買ってきてほしいもの」をリアルタイム共有するFlutterアプリです。

ブランドアイコンは、家族から届く依頼を表す「吹き出し」と、購入完了を表す
「チェック」を組み合わせています。Brand Colorは `#3B9C8F` です。
Primary Fontは、やさしく読みやすい印象の `Zen Kaku Gothic New` です。
使用ウェイトをアプリへ同梱し、フォント表示はネットワーク接続に依存しません。

プロダクト仕様と開発方針は [docs/README.md](docs/README.md) を参照してください。

## 開発

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

iOSでの実行にはXcode、Androidでの実行にはAndroid StudioとAndroid SDKが必要です。

## iOS Push通知

Push通知のClient・Cloud Functions実装とiOS Capabilityはリポジトリで管理しています。
実機利用には、XcodeでPaid Apple Developer Teamを選択してAutomatic Signingを有効にし、
Apple Developerで作成したAPNs Authentication KeyをFirebase Consoleの
Project Settings → Cloud Messaging → Apple app configurationへ登録してください。

APNs設定とiPhone実機2台でのEnd-to-End確認が終わるまでは、Phase 5の状態を
`IMPLEMENTED / MANUAL VALIDATION PENDING`とします。

## Release

Phase 8のStore申請、署名、Privacy、TestFlightの進捗と手動作業は
[Release Checklist](docs/release-checklist.md)を参照してください。現時点ではRelease blockerが
残っているため、`1.0.0+1`をRelease Candidateとは判定していません。
