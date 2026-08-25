import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katte/app.dart';
import 'package:katte/features/auth/application/auth_providers.dart';
import 'package:katte/features/auth/application/auth_service.dart';

const testUser = AuthUser(
  uid: 'test-user',
  displayName: 'テスト太郎',
  email: 'taro@example.com',
  photoUrl: 'https://example.com/photo.png',
);

void main() {
  testWidgets('未ログイン時はLoginを表示する', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Katte'), findsOneWidget);
    expect(find.text('家族の「買っといて」を、\nリアルタイムで共有。'), findsOneWidget);
    expect(find.text('Googleで続ける'), findsOneWidget);
  });

  testWidgets('Google LoginからShoppingへ進む', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byKey(const Key('google-login-button')));
    await tester.pumpAndSettle();

    expect(find.text('岩田家'), findsOneWidget);
    expect(find.text('買ってきてほしいもの'), findsWidgets);
  });

  testWidgets('ログイン済み状態ではShoppingを表示する', (tester) async {
    await _pumpApp(tester, initialUser: testUser);

    expect(find.text('岩田家'), findsOneWidget);
    expect(find.text('牛乳'), findsOneWidget);
    expect(find.text('買い物'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);
  });

  testWidgets('Shopping画面にダミー商品が表示される', (tester) async {
    await _pumpSignedInApp(tester);

    expect(find.text('牛乳'), findsOneWidget);
    expect(find.text('卵 ×2'), findsOneWidget);
    expect(find.text('ティッシュ'), findsOneWidget);
  });

  testWidgets('Bottom Sheetから商品を追加できる', (tester) async {
    await _pumpSignedInApp(tester);

    final openButton = find.byKey(const Key('open-add-item-sheet-button'));
    await tester.ensureVisible(openButton);
    await tester.tap(openButton);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('item-name-field')), 'パン');
    await tester.enterText(find.byKey(const Key('item-quantity-field')), '2');
    await tester.enterText(find.byKey(const Key('item-note-field')), '食パン');
    final addButton = find.byKey(const Key('add-item-button'));
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(find.text('パン ×2'), findsOneWidget);
    expect(find.textContaining('食パン'), findsOneWidget);
    expect(find.byKey(const Key('item-name-field')), findsNothing);
  });

  testWidgets('商品名が空の場合は追加できない', (tester) async {
    await _pumpSignedInApp(tester);

    final openButton = find.byKey(const Key('open-add-item-sheet-button'));
    await tester.ensureVisible(openButton);
    await tester.tap(openButton);
    await tester.pumpAndSettle();
    final addButton = find.byKey(const Key('add-item-button'));
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pump();

    expect(find.text('商品名を入力してください'), findsOneWidget);
  });

  testWidgets('商品を購入済みに変更できる', (tester) async {
    await _pumpSignedInApp(tester);

    final milkTile = find.byKey(const Key('purchase-milk'));
    await tester.tap(
      find.descendant(of: milkTile, matching: find.byType(Checkbox)),
    );
    await tester.pump();

    expect(find.text('由美 → 康平が購入'), findsOneWidget);
  });

  testWidgets('買い物モードを開始して終了できる', (tester) async {
    await _pumpSignedInApp(tester);

    final startButton = find.byKey(const Key('start-shopping-button'));
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pump();

    expect(find.text('買い物中'), findsOneWidget);
    expect(find.text('買い忘れがないか確認しよう'), findsOneWidget);

    final finishButton = find.byKey(const Key('finish-shopping-button'));
    await tester.ensureVisible(finishButton);
    await tester.tap(finishButton);
    await tester.pump();

    expect(find.text('買い物中'), findsNothing);
    expect(find.byKey(const Key('start-shopping-button')), findsOneWidget);
  });

  testWidgets('Settingsにユーザー情報とログアウト導線を表示する', (tester) async {
    await _pumpSignedInApp(tester);

    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();

    expect(find.text('テスト太郎'), findsOneWidget);
    expect(find.text('taro@example.com'), findsOneWidget);
    expect(find.byKey(const Key('logout-button')), findsOneWidget);
  });

  testWidgets('Settingsの通知設定を変更できる', (tester) async {
    await _pumpSignedInApp(tester);
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();

    final itemAddedSwitch = find.byKey(
      const Key('item-added-notification-switch'),
    );
    expect(tester.widget<SwitchListTile>(itemAddedSwitch).value, isTrue);

    await tester.tap(itemAddedSwitch);
    await tester.pump();

    expect(tester.widget<SwitchListTile>(itemAddedSwitch).value, isFalse);
  });

  testWidgets('ログアウトするとLoginへ戻る', (tester) async {
    await _pumpSignedInApp(tester);
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();

    final logoutButton = find.byKey(const Key('logout-button'));
    await tester.ensureVisible(logoutButton);
    await tester.tap(logoutButton);
    await tester.pumpAndSettle();

    expect(find.text('Katte'), findsOneWidget);
    expect(find.text('Googleで続ける'), findsOneWidget);
  });
}

Future<FakeAuthService> _pumpApp(
  WidgetTester tester, {
  AuthUser? initialUser,
}) async {
  final authService = FakeAuthService(initialUser);
  addTearDown(authService.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authServiceProvider.overrideWithValue(authService)],
      child: const KatteApp(),
    ),
  );
  await tester.pumpAndSettle();
  return authService;
}

Future<FakeAuthService> _pumpSignedInApp(WidgetTester tester) {
  return _pumpApp(tester, initialUser: testUser);
}

class FakeAuthService implements AuthService {
  FakeAuthService(this._currentUser);

  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield _currentUser;
    yield* _controller.stream;
  }

  @override
  Future<void> signInWithGoogle() async {
    _setUser(testUser);
  }

  @override
  Future<void> signOut() async {
    _setUser(null);
  }

  void _setUser(AuthUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  void dispose() {
    _controller.close();
  }
}
