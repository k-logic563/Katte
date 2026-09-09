import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:katte/app.dart';
import 'package:katte/features/auth/application/auth_providers.dart';
import 'package:katte/features/auth/application/auth_service.dart';
import 'package:katte/features/categories/category_providers.dart';
import 'package:katte/features/categories/category_repository.dart';
import 'package:katte/features/categories/models/shopping_category.dart';
import 'package:katte/features/groups/group_providers.dart';
import 'package:katte/features/groups/group_repository.dart'
    hide fallbackUserDisplayName;
import 'package:katte/features/groups/current_group_selection_store.dart';
import 'package:katte/features/groups/models/katte_group.dart';
import 'package:katte/features/monitoring/monitoring_providers.dart';
import 'package:katte/features/monitoring/monitoring_services.dart';
import 'package:katte/features/notifications/application/notification_service_provider.dart';
import 'package:katte/features/notifications/services/notification_service.dart';
import 'package:katte/features/shopping/models/item_suggestion.dart';
import 'package:katte/features/shopping/models/shopping_item.dart';
import 'package:katte/features/shopping/shopping_providers.dart';
import 'package:katte/features/shopping/shopping_repository.dart';

const testUser = AuthUser(
  uid: 'test-user',
  displayName: 'テスト太郎',
  email: 'taro@example.com',
  photoUrl: 'https://example.com/photo.png',
);

const testGroup = KatteGroup(
  id: 'group-iwata',
  name: '岩田家',
  createdBy: 'test-user',
  inviteCode: 'K7P4XQ',
);

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('Analytics event名はparameterを持たない固定snake_caseである', () {
    expect(KatteAnalyticsEvent.values.map((event) => event.eventName), [
      'login',
      'group_created',
      'group_joined',
      'shopping_item_added',
      'shopping_item_purchased',
      'shopping_item_undo',
      'group_left',
      'group_deleted',
    ]);
  });

  test('Suggestion名を正規化し安全なdocument IDへ変換する', () {
    final normalized = normalizeSuggestionName('  MILK / 1L  ');

    expect(normalized, 'milk / 1l');
    expect(itemSuggestionDocumentId(normalized), isNot(contains('/')));
  });

  test('Category名はtrim・単純なcase正規化と入力Validationを行う', () {
    expect(normalizeCategoryName('  FOOD  '), 'food');
    expect(categoryNameDocumentId('  FOOD  '), categoryNameDocumentId('food'));
    expect(categoryNameDocumentId('食品/日用品'), isNot(contains('/')));
    expect(validateCategoryName('   '), isNotNull);
    expect(validateCategoryName('食材\n日用品'), isNotNull);
    expect(validateCategoryName('食材'), isNull);
  });

  testWidgets('Shopping ListはCategory順でSection表示し未分類を最後にする', (tester) async {
    final food = ShoppingCategory(
      id: 'food',
      name: '食材',
      normalizedName: '食材',
      sortOrder: 1,
      createdAt: DateTime.now(),
    );
    await _pumpApp(
      tester,
      initialUser: testUser,
      initialItems: [
        _item(id: 'battery', name: '電池'),
        _item(id: 'milk', name: '牛乳', categoryId: food.id),
      ],
      categoryRepository: FakeCategoryRepository(
        categoriesByGroup: {
          testGroup.id: [food],
        },
      ),
    );

    expect(find.text('食材  1'), findsOneWidget);
    expect(find.text('未分類  1'), findsOneWidget);
    final foodY = tester.getTopLeft(find.text('食材  1')).dy;
    final uncategorizedY = tester.getTopLeft(find.text('未分類  1')).dy;
    expect(foodY, lessThan(uncategorizedY));
  });

  testWidgets('Category登録後にRealtime更新してDialogを安全に閉じる', (tester) async {
    final categories = FakeCategoryRepository();
    await _pumpApp(
      tester,
      initialUser: testUser,
      categoryRepository: categories,
    );

    await tester.tap(find.byKey(const Key('group-details-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('category-management-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-category-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('category-name-field')), '食材');
    await tester.tap(find.byKey(const Key('save-category-button')));
    await tester.pumpAndSettle();

    expect(find.text('食材'), findsOneWidget);
    expect(find.byKey(const Key('category-name-field')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('Suggestionは完全一致、最近使用、useCountの順で並ぶ', () {
    final now = DateTime.now();
    final suggestions = [
      _suggestion(name: '牛乳 1L', useCount: 10, lastUsedAt: now),
      _suggestion(
        name: '牛乳',
        useCount: 1,
        lastUsedAt: now.subtract(const Duration(days: 1)),
      ),
      _suggestion(name: '牛乳 500ml', useCount: 2, lastUsedAt: now),
      _suggestion(name: '卵', useCount: 20, lastUsedAt: now),
    ];

    expect(rankItemSuggestions(suggestions, '牛乳').map((item) => item.name), [
      '牛乳',
      '牛乳 1L',
      '牛乳 500ml',
    ]);
  });

  testWidgets('Auth確認中はLoadingを表示する', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(PendingAuthService()),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
          analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
          crashReportingServiceProvider.overrideWithValue(
            FakeCrashReportingService(),
          ),
        ],
        child: const KatteApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Katte'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('未ログイン時はLoginを表示する', (tester) async {
    await _pumpApp(tester);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      app.theme?.textTheme.bodyMedium?.fontFamily,
      contains('ZenKakuGothicNew'),
    );
    expect(
      app.darkTheme?.textTheme.bodyMedium?.fontFamily,
      contains('ZenKakuGothicNew'),
    );
    expect(find.byKey(const Key('brand-app-icon')), findsOneWidget);
    expect(find.text('Katte'), findsOneWidget);
    expect(find.text('家族の「買っといて」を、\nもっと気軽に。'), findsOneWidget);
    expect(find.text('続行する方法を選択'), findsOneWidget);
    expect(find.text('Googleで続ける'), findsNothing);
    expect(find.text('Appleでサインイン'), findsNothing);
    expect(find.byKey(const Key('google-logo')), findsOneWidget);
    expect(find.byKey(const Key('apple-logo')), findsOneWidget);
    expect(find.bySemanticsLabel('Googleで続ける'), findsOneWidget);
    expect(find.bySemanticsLabel('Appleでサインイン'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('google-login-button'))),
      tester.getSize(find.byKey(const Key('apple-login-button'))),
    );
    final googleFinder = find.byKey(const Key('google-login-button'));
    final appleFinder = find.byKey(const Key('apple-login-button'));
    final googleRect = tester.getRect(googleFinder);
    final appleRect = tester.getRect(appleFinder);
    final googleCenter = googleRect.center;
    final appleCenter = appleRect.center;
    expect(googleRect.height, 64);
    expect(googleRect.width, greaterThan(120));
    expect(googleCenter.dy, appleCenter.dy);
    expect(appleRect.left - googleRect.right, 16);
    final googleButton = tester.widget<OutlinedButton>(googleFinder);
    final appleButton = tester.widget<OutlinedButton>(appleFinder);
    expect(
      googleButton.style?.side?.resolve(<WidgetState>{}),
      appleButton.style?.side?.resolve(<WidgetState>{}),
    );
  });

  testWidgets('小さいiPhoneでもLogin選択肢が崩れない', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpApp(tester);

    expect(find.byKey(const Key('brand-app-icon')), findsOneWidget);
    expect(find.byKey(const Key('google-login-button')), findsOneWidget);
    expect(find.byKey(const Key('apple-login-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Login中は両Providerを無効化して進捗を表示する', (tester) async {
    final auth = await _pumpApp(tester);
    auth.googleSignInCompleter = Completer<void>();

    await tester.tap(find.byKey(const Key('google-login-button')));
    await tester.pump();

    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('google-login-button')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('apple-login-button')))
          .onPressed,
      isNull,
    );
    expect(find.bySemanticsLabel('ログインしています'), findsOneWidget);

    auth.googleSignInCompleter!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('Google Login後に所属GroupのShoppingへ進む', (tester) async {
    final analytics = FakeAnalyticsService();
    await _pumpApp(tester, analyticsService: analytics);

    await tester.tap(find.byKey(const Key('google-login-button')));
    await tester.pumpAndSettle();

    expect(find.text('岩田家'), findsOneWidget);
    expect(find.byKey(const Key('purchase-history-button')), findsOneWidget);
    expect(analytics.events, contains(KatteAnalyticsEvent.login));
  });

  testWidgets('Apple Login後に所属GroupのShoppingへ進む', (tester) async {
    final auth = await _pumpApp(tester);

    await tester.tap(find.byKey(const Key('apple-login-button')));
    await tester.pumpAndSettle();

    expect(find.text('岩田家'), findsOneWidget);
    expect(auth.appleSignInCount, 1);
  });

  testWidgets('Apple Loginのキャンセルはエラー表示せずLoginに留まる', (tester) async {
    final auth = await _pumpApp(tester);
    auth.appleSignInError = AuthCancelledException();

    await tester.tap(find.byKey(const Key('apple-login-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('apple-login-button')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ログイン後に通知Permission・Token登録処理を開始する', (tester) async {
    final notifications = FakeNotificationService();
    await _pumpApp(
      tester,
      initialUser: testUser,
      notificationService: notifications,
    );

    expect(notifications.registeredUserIds, [testUser.uid]);
  });

  testWidgets('Group未所属時にGroup Setupを表示する', (tester) async {
    await _pumpApp(tester, initialUser: testUser, initialGroups: const []);

    expect(find.text('家族と買い物リストを共有しよう'), findsOneWidget);
    expect(find.byKey(const Key('open-create-group-button')), findsOneWidget);
    expect(find.byKey(const Key('open-join-group-button')), findsOneWidget);
  });

  testWidgets('Group作成後にShoppingへ進む', (tester) async {
    final groupRepository = FakeGroupRepository(const []);
    final analytics = FakeAnalyticsService();
    await _pumpApp(
      tester,
      initialUser: testUser,
      groupRepository: groupRepository,
      analyticsService: analytics,
    );

    await tester.tap(find.byKey(const Key('open-create-group-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('group-name-field')), '康平家');
    await tester.tap(find.byKey(const Key('create-group-button')));
    await tester.pumpAndSettle();

    expect(find.text('康平家'), findsOneWidget);
    expect(groupRepository.createdBy, testUser.uid);
    expect(groupRepository.ensureUserCount, 1);
    expect(analytics.events, contains(KatteAnalyticsEvent.groupCreated));
  });

  testWidgets('招待コードでGroup参加後にShoppingへ進む', (tester) async {
    final groupRepository = FakeGroupRepository(const []);
    final analytics = FakeAnalyticsService();
    await _pumpApp(
      tester,
      initialUser: testUser,
      groupRepository: groupRepository,
      analyticsService: analytics,
    );

    await tester.tap(find.byKey(const Key('open-join-group-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invite-code-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('invite-code-field')),
      'k7p4xq',
    );
    await tester.tap(find.byKey(const Key('join-group-button')));
    await tester.pumpAndSettle();

    expect(find.text('岩田家'), findsOneWidget);
    expect(groupRepository.lastJoinedCode, 'K7P4XQ');
    expect(analytics.events, contains(KatteAnalyticsEvent.groupJoined));
  });

  testWidgets('存在しない招待コードは安全なエラーを表示する', (tester) async {
    await _pumpApp(tester, initialUser: testUser, initialGroups: const []);

    await tester.tap(find.byKey(const Key('open-join-group-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('invite-code-field')),
      'XXXXXX',
    );
    await tester.tap(find.byKey(const Key('join-group-button')));
    await tester.pumpAndSettle();

    expect(find.text('グループが見つかりませんでした。'), findsOneWidget);
    expect(find.textContaining('FirebaseException'), findsNothing);
  });

  testWidgets('短すぎる招待コードは送信せず入力エラーを表示する', (tester) async {
    final repository = FakeGroupRepository(const []);
    await _pumpApp(tester, initialUser: testUser, groupRepository: repository);

    await tester.tap(find.byKey(const Key('open-join-group-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('invite-code-field')), 'abc');
    await tester.tap(find.byKey(const Key('join-group-button')));
    await tester.pump();

    expect(find.text('招待コードは6〜8文字で入力してください'), findsOneWidget);
    expect(repository.lastJoinedCode, isNull);
  });

  testWidgets('Shopping画面は現在Groupのpending商品だけ表示する', (tester) async {
    await _pumpSignedInApp(tester);

    expect(find.text('買ってきてほしいもの'), findsNothing);
    expect(find.text('牛乳'), findsOneWidget);
    expect(find.text('卵 ×2'), findsOneWidget);
    expect(find.text('ティッシュ'), findsNothing);

    final itemName = tester.widget<Text>(find.text('牛乳'));
    final itemDetail = tester.widget<Text>(find.textContaining('由美 ・').first);
    expect(itemName.style?.fontWeight, FontWeight.w500);
    expect(itemDetail.style?.fontSize, 13);
  });

  testWidgets('商品0件の場合はEmpty Stateを表示する', (tester) async {
    await _pumpApp(tester, initialUser: testUser, initialItems: const []);

    expect(find.text('今日はまだ何もありません'), findsOneWidget);
    expect(find.text('追加する'), findsOneWidget);
  });

  testWidgets('小さい画面でも長い商品名を省略可能な複数行で表示する', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const longName = '北海道産の低脂肪タイプの牛乳を2本買ってきてほしい';

    await _pumpApp(
      tester,
      initialUser: testUser,
      initialItems: [_item(id: 'long-name', name: longName)],
    );

    final name = tester.widget<Text>(find.text(longName));
    expect(name.maxLines, 3);
    expect(name.overflow, TextOverflow.ellipsis);

    await tester.tap(find.byKey(const Key('item-menu-long-name')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-shopping-item')));
    await tester.pumpAndSettle();

    final dialogName = tester.widget<Text>(find.text(longName).last);
    expect(dialogName.maxLines, 3);
    expect(dialogName.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('小さい画面と1.3倍の文字サイズでもShopping一覧が崩れない', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpSignedInApp(tester);

    expect(find.text('牛乳'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Firestoreの権限エラー時はError Stateを表示する', (tester) async {
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: PermissionDeniedShoppingRepository(),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('買い物リストを読み込めませんでした。'), findsOneWidget);
    expect(find.text('もう一度お試しください。'), findsOneWidget);
    expect(find.textContaining('permission-denied'), findsNothing);
  });

  testWidgets('Bottom Sheetから現在Groupへ商品を追加できる', (tester) async {
    final repository = FakeShoppingRepository(_defaultItems());
    final analytics = FakeAnalyticsService();
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
      analyticsService: analytics,
    );

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
    expect(repository.lastWrittenGroupId, testGroup.id);
    expect(repository.suggestion(testGroup.id, 'パン')?.useCount, 1);
    expect(analytics.events, contains(KatteAnalyticsEvent.shoppingItemAdded));
  });

  testWidgets('商品追加時にCategoryを選択して保存できる', (tester) async {
    final repository = FakeShoppingRepository(_defaultItems());
    final food = ShoppingCategory(
      id: 'food',
      name: '食材',
      normalizedName: '食材',
      sortOrder: 1,
      createdAt: DateTime.now(),
    );
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
      categoryRepository: FakeCategoryRepository(
        categoriesByGroup: {
          testGroup.id: [food],
        },
      ),
    );

    final openButton = find.byKey(const Key('open-add-item-sheet-button'));
    await tester.ensureVisible(openButton);
    await tester.tap(openButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('item-name-field')), 'りんご');
    await tester.ensureVisible(find.byKey(const Key('item-category-field')));
    await tester.tap(find.byKey(const Key('item-category-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('食材').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('add-item-button')));
    await tester.tap(find.byKey(const Key('add-item-button')));
    await tester.pumpAndSettle();

    expect(repository.item(testGroup.id, 'new-1')?.categoryId, food.id);
    expect(find.text('食材  1'), findsOneWidget);
  });

  testWidgets('履歴0件ではSuggestion sectionを表示しない', (tester) async {
    await _pumpSignedInApp(tester);

    await tester.ensureVisible(
      find.byKey(const Key('open-add-item-sheet-button')),
    );
    await tester.tap(find.byKey(const Key('open-add-item-sheet-button')));
    await tester.pumpAndSettle();

    expect(find.text('最近使ったもの'), findsNothing);
    expect(find.text('候補'), findsNothing);
  });

  testWidgets('最近使った候補をタップすると商品名だけInputへ反映する', (tester) async {
    final repository = FakeShoppingRepository(
      _defaultItems(),
      suggestionsByGroup: {
        testGroup.id: [_suggestion(name: '牛乳'), _suggestion(name: '卵')],
      },
    );
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    await tester.ensureVisible(
      find.byKey(const Key('open-add-item-sheet-button')),
    );
    await tester.tap(find.byKey(const Key('open-add-item-sheet-button')));
    await tester.pumpAndSettle();
    expect(find.text('最近使ったもの'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('item-quantity-field')), '3');
    await tester.tap(_suggestionFinder('牛乳'));
    await tester.pump();

    final nameField = tester.widget<TextFormField>(
      find.byKey(const Key('item-name-field')),
    );
    final quantityField = tester.widget<TextFormField>(
      find.byKey(const Key('item-quantity-field')),
    );
    expect(nameField.controller?.text, '牛乳');
    expect(quantityField.controller?.text, '3');
    expect(find.byKey(const Key('add-item-button')), findsOneWidget);
    expect(repository.lastWrittenGroupId, isNull);
  });

  testWidgets('入力中は取得済みSuggestionを前方一致filterする', (tester) async {
    final repository = FakeShoppingRepository(
      _defaultItems(),
      suggestionsByGroup: {
        testGroup.id: [
          _suggestion(name: '牛乳'),
          _suggestion(name: '牛乳 1L'),
          _suggestion(name: '卵'),
        ],
      },
    );
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    await tester.ensureVisible(
      find.byKey(const Key('open-add-item-sheet-button')),
    );
    await tester.tap(find.byKey(const Key('open-add-item-sheet-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('item-name-field')), '牛');
    await tester.pump();

    expect(find.text('候補'), findsOneWidget);
    expect(_suggestionFinder('牛乳'), findsOneWidget);
    expect(_suggestionFinder('牛乳 1L'), findsOneWidget);
    expect(_suggestionFinder('卵'), findsNothing);
    expect(repository.fetchedSuggestionGroupIds, [testGroup.id]);
  });

  testWidgets('Suggestion取得失敗でも商品名を入力できる', (tester) async {
    final repository = FakeShoppingRepository(
      _defaultItems(),
      failSuggestions: true,
    );
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    await tester.ensureVisible(
      find.byKey(const Key('open-add-item-sheet-button')),
    );
    await tester.tap(find.byKey(const Key('open-add-item-sheet-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('item-name-field')), 'りんご');

    final nameField = tester.widget<TextFormField>(
      find.byKey(const Key('item-name-field')),
    );
    expect(nameField.controller?.text, 'りんご');
    expect(find.text('最近使ったもの'), findsNothing);
    expect(find.byKey(const Key('add-item-button')), findsOneWidget);
  });

  testWidgets('同じ商品を再登録するとSuggestion useCountが増える', (tester) async {
    final repository = FakeShoppingRepository(_defaultItems());
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    for (var count = 1; count <= 2; count++) {
      await tester.ensureVisible(
        find.byKey(const Key('open-add-item-sheet-button')),
      );
      await tester.tap(find.byKey(const Key('open-add-item-sheet-button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('item-name-field')), '牛乳');
      await tester.tap(find.byKey(const Key('add-item-button')));
      await tester.pumpAndSettle();
      expect(repository.suggestion(testGroup.id, '牛乳')?.useCount, count);
    }
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

  testWidgets('商品名が空白だけの場合も追加できない', (tester) async {
    await _pumpSignedInApp(tester);

    await tester.ensureVisible(
      find.byKey(const Key('open-add-item-sheet-button')),
    );
    await tester.tap(find.byKey(const Key('open-add-item-sheet-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('item-name-field')), '   ');
    await tester.tap(find.byKey(const Key('add-item-button')));
    await tester.pump();

    expect(find.text('商品名を入力してください'), findsOneWidget);
  });

  testWidgets('pending商品を確認後に削除してRealtime一覧から消す', (tester) async {
    final repository = FakeShoppingRepository(_defaultItems());
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    await tester.tap(find.byKey(const Key('item-menu-eggs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-shopping-item')));
    await tester.pumpAndSettle();

    expect(find.text('この商品を削除しますか？'), findsOneWidget);
    expect(find.text('卵'), findsWidgets);

    await tester.tap(find.byKey(const Key('confirm-delete-item-button')));
    await tester.pumpAndSettle();

    expect(find.text('卵 ×2'), findsNothing);
    expect(find.text('削除しました'), findsOneWidget);
    expect(repository.lastDeletedGroupId, testGroup.id);
    expect(repository.lastDeletedItemId, 'eggs');
  });

  testWidgets('商品名と行余白のtapでは購入せずCheckboxだけで購入する', (tester) async {
    final repository = FakeShoppingRepository(_defaultItems());
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    await tester.tap(find.text('牛乳'));
    await tester.pumpAndSettle();
    expect(find.text('牛乳'), findsOneWidget);
    expect(repository.lastWrittenGroupId, isNull);

    final tile = find.byKey(const Key('purchase-milk'));
    final tileRect = tester.getRect(tile);
    await tester.tapAt(Offset(tileRect.right - 64, tileRect.bottom - 8));
    await tester.pumpAndSettle();
    expect(find.text('牛乳'), findsOneWidget);
    expect(repository.lastWrittenGroupId, isNull);

    await tester.tap(
      find.descendant(of: tile, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    expect(find.text('牛乳'), findsNothing);
    expect(find.text('牛乳を購入済みにしました'), findsOneWidget);
    expect(repository.lastWrittenGroupId, testGroup.id);
  });

  testWidgets('商品メニューを開いても購入処理を実行しない', (tester) async {
    final repository = FakeShoppingRepository(_defaultItems());
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    await tester.tap(find.byKey(const Key('item-menu-milk')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('edit-shopping-item')), findsOneWidget);
    expect(find.byKey(const Key('delete-shopping-item')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('edit-shopping-item'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('delete-shopping-item'))).dy,
      ),
    );
    expect(find.text('牛乳'), findsOneWidget);
    expect(repository.lastWrittenGroupId, isNull);
  });

  testWidgets('編集Sheetへ現在値を設定し商品名・数量・メモをRealtime更新する', (tester) async {
    final repository = FakeShoppingRepository(_defaultItems());
    final original = repository.item(testGroup.id, 'eggs')!;
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    await tester.tap(find.byKey(const Key('item-menu-eggs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-shopping-item')));
    await tester.pumpAndSettle();

    expect(find.text('商品を編集'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('edit-item-name-field')))
          .controller
          ?.text,
      '卵',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('edit-item-quantity-field')),
          )
          .controller
          ?.text,
      '2',
    );

    await tester.enterText(
      find.byKey(const Key('edit-item-name-field')),
      '  平飼い卵  ',
    );
    await tester.enterText(
      find.byKey(const Key('edit-item-quantity-field')),
      '3',
    );
    await tester.enterText(
      find.byKey(const Key('edit-item-note-field')),
      '  10個入り  ',
    );
    final saveButton = find.byKey(const Key('save-edit-item-button'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('商品を編集'), findsNothing);
    expect(find.text('平飼い卵 ×3'), findsOneWidget);
    expect(find.textContaining('10個入り'), findsOneWidget);
    expect(repository.lastEditedGroupId, testGroup.id);
    final edited = repository.item(testGroup.id, 'eggs')!;
    expect(edited.createdBy, original.createdBy);
    expect(edited.createdByName, original.createdByName);
    expect(edited.createdAt, original.createdAt);
    expect(edited.status, ShoppingItemStatus.pending);
  });

  testWidgets('編集をキャンセルすると商品を更新しない', (tester) async {
    final repository = FakeShoppingRepository(_defaultItems());
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    await tester.tap(find.byKey(const Key('item-menu-milk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-shopping-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-item-name-field')),
      '変更しない牛乳',
    );
    await tester.tap(find.byKey(const Key('cancel-edit-item-button')));
    await tester.pumpAndSettle();

    expect(find.text('牛乳'), findsOneWidget);
    expect(find.text('変更しない牛乳'), findsNothing);
    expect(repository.editCallCount, 0);
  });

  testWidgets('商品名が空の編集は保存できない', (tester) async {
    final repository = FakeShoppingRepository(_defaultItems());
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    await tester.tap(find.byKey(const Key('item-menu-milk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-shopping-item')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-item-name-field')), ' ');
    final saveButton = find.byKey(const Key('save-edit-item-button'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pump();

    expect(find.text('商品名を入力してください'), findsOneWidget);
    expect(find.text('商品を編集'), findsOneWidget);
    expect(repository.editCallCount, 0);
  });

  testWidgets('編集保存の連打を一度の更新に限定する', (tester) async {
    final completion = Completer<void>();
    final repository = FakeShoppingRepository(
      _defaultItems(),
      editCompletion: completion,
    );
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    await tester.tap(find.byKey(const Key('item-menu-milk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-shopping-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-item-name-field')),
      '低脂肪牛乳',
    );
    final saveButton = find.byKey(const Key('save-edit-item-button'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pump();
    await tester.tap(saveButton);
    await tester.pump();

    expect(repository.editCallCount, 1);
    completion.complete();
    await tester.pumpAndSettle();
    expect(find.text('低脂肪牛乳'), findsOneWidget);
  });

  testWidgets('編集失敗時はSheetと入力内容を維持して安全なエラーを表示する', (tester) async {
    final repository = FakeShoppingRepository(_defaultItems(), failEdit: true);
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    await tester.tap(find.byKey(const Key('item-menu-milk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-shopping-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-item-name-field')),
      '低脂肪牛乳',
    );
    final saveButton = find.byKey(const Key('save-edit-item-button'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('商品を編集'), findsOneWidget);
    expect(find.text('低脂肪牛乳'), findsOneWidget);
    expect(find.byKey(const Key('edit-item-error')), findsOneWidget);
    expect(find.textContaining('Sensitive Firebase error'), findsNothing);
    expect(repository.item(testGroup.id, 'milk')?.name, '牛乳');
  });

  testWidgets('編集中にGroupが変わった場合は旧Groupの商品を更新しない', (tester) async {
    const secondGroup = KatteGroup(
      id: 'group-parents',
      name: '実家',
      createdBy: 'test-user',
      inviteCode: 'P4R3NT',
    );
    final repository = FakeShoppingRepository(
      _defaultItems(),
      itemsByGroup: {
        secondGroup.id: [_item(id: 'other-milk', name: '実家の牛乳')],
      },
    );
    await _pumpApp(
      tester,
      initialUser: testUser,
      initialGroups: const [testGroup, secondGroup],
      shoppingRepository: repository,
    );

    await tester.tap(find.byKey(const Key('item-menu-milk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-shopping-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-item-name-field')),
      '更新してはいけない牛乳',
    );
    final saveButton = find.byKey(const Key('save-edit-item-button'));
    final container = ProviderScope.containerOf(tester.element(saveButton));
    container.read(currentGroupIdProvider.notifier).select(secondGroup.id);
    await tester.pumpAndSettle();
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('表示中のグループが変わりました。'), findsOneWidget);
    expect(repository.editCallCount, 0);
    expect(repository.item(testGroup.id, 'milk')?.name, '牛乳');
    expect(repository.item(secondGroup.id, 'other-milk')?.name, '実家の牛乳');
  });

  testWidgets('編集中に別端末で購入済みになった商品をpendingへ戻さない', (tester) async {
    final repository = FakeShoppingRepository(_defaultItems());
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    await tester.tap(find.byKey(const Key('item-menu-milk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-shopping-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-item-name-field')),
      '低脂肪牛乳',
    );
    await repository.setPurchased(
      groupId: testGroup.id,
      user: testUser,
      itemId: 'milk',
      isPurchased: true,
    );
    await tester.pumpAndSettle();
    final saveButton = find.byKey(const Key('save-edit-item-button'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('この商品はすでに購入済みです。'), findsOneWidget);
    expect(
      repository.item(testGroup.id, 'milk')?.status,
      ShoppingItemStatus.purchased,
    );
    expect(repository.lastEditedGroupId, isNull);
  });

  testWidgets('編集中に別端末で削除された場合は商品が見つからないErrorを表示する', (tester) async {
    final repository = FakeShoppingRepository(_defaultItems());
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    await tester.tap(find.byKey(const Key('item-menu-milk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-shopping-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-item-name-field')),
      '低脂肪牛乳',
    );
    await repository.deleteItem(groupId: testGroup.id, itemId: 'milk');
    await tester.pumpAndSettle();
    final saveButton = find.byKey(const Key('save-edit-item-button'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('商品が見つかりません。'), findsOneWidget);
    expect(repository.item(testGroup.id, 'milk'), isNull);
    expect(repository.lastEditedGroupId, isNull);
  });

  testWidgets('購入失敗時は商品を残して安全なエラーを表示する', (tester) async {
    final repository = FakeShoppingRepository(
      _defaultItems(),
      failPurchase: true,
    );
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    final tile = find.byKey(const Key('purchase-milk'));
    await tester.tap(
      find.descendant(of: tile, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();

    expect(find.text('牛乳'), findsOneWidget);
    expect(find.text('更新できませんでした。'), findsOneWidget);
    expect(find.textContaining('Sensitive Firebase error'), findsNothing);
  });

  testWidgets('削除失敗時は安全なメッセージを表示して商品を残す', (tester) async {
    final repository = FakeShoppingRepository(
      _defaultItems(),
      failDeletion: true,
    );
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    await tester.tap(find.byKey(const Key('item-menu-milk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-shopping-item')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-item-button')));
    await tester.pumpAndSettle();

    expect(find.text('牛乳'), findsOneWidget);
    expect(find.text('削除に失敗しました。'), findsOneWidget);
    expect(find.textContaining('Sensitive Firebase error'), findsNothing);
  });

  testWidgets('確認中にGroupが変わった場合は別Groupの商品を削除しない', (tester) async {
    const secondGroup = KatteGroup(
      id: 'group-parents',
      name: '実家',
      createdBy: 'test-user',
      inviteCode: 'P4R3NT',
    );
    final repository = FakeShoppingRepository(
      _defaultItems(),
      itemsByGroup: {
        secondGroup.id: [_item(id: 'milk', name: '実家の牛乳')],
      },
    );
    await _pumpApp(
      tester,
      initialUser: testUser,
      initialGroups: const [testGroup, secondGroup],
      shoppingRepository: repository,
    );

    await tester.tap(find.byKey(const Key('item-menu-milk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-shopping-item')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('confirm-delete-item-button'))),
    );
    container.read(currentGroupIdProvider.notifier).select(secondGroup.id);
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-delete-item-button')));
    await tester.pumpAndSettle();

    expect(repository.lastDeletedGroupId, isNull);
    expect(find.text('実家の牛乳'), findsOneWidget);
    expect(find.text('削除に失敗しました。'), findsOneWidget);
  });

  testWidgets('購入済みにすると一覧から消えUndoで戻る', (tester) async {
    final analytics = FakeAnalyticsService();
    await _pumpApp(tester, initialUser: testUser, analyticsService: analytics);

    final milkTile = find.byKey(const Key('purchase-milk'));
    await tester.tap(
      find.descendant(of: milkTile, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    expect(find.text('牛乳'), findsNothing);
    expect(find.text('牛乳を購入済みにしました'), findsOneWidget);

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(find.text('牛乳'), findsOneWidget);
    expect(
      analytics.events,
      containsAll([
        KatteAnalyticsEvent.shoppingItemPurchased,
        KatteAnalyticsEvent.shoppingItemUndo,
      ]),
    );
  });

  testWidgets('Realtime更新で商品行が先に消えてもSnackBarを表示する', (tester) async {
    final purchaseCompletion = Completer<void>();
    final repository = FakeShoppingRepository(
      _defaultItems(),
      purchaseCompletion: purchaseCompletion,
    );
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    final milkTile = find.byKey(const Key('purchase-milk'));
    await tester.tap(
      find.descendant(of: milkTile, matching: find.byType(Checkbox)),
    );
    await tester.pump();

    expect(find.text('牛乳'), findsNothing);
    expect(find.text('牛乳を購入済みにしました'), findsNothing);

    purchaseCompletion.complete();
    await tester.pumpAndSettle();

    expect(find.text('牛乳を購入済みにしました'), findsOneWidget);
    expect(find.text('元に戻す'), findsOneWidget);
  });

  testWidgets('購入済みSnackBarは4秒後に自動的に消える', (tester) async {
    await _pumpSignedInApp(tester);

    final milkTile = find.byKey(const Key('purchase-milk'));
    await tester.tap(
      find.descendant(of: milkTile, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.duration, const Duration(seconds: 4));
    expect(snackBar.persist, isFalse);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('牛乳を購入済みにしました'), findsNothing);
    expect(find.text('元に戻す'), findsNothing);
  });

  testWidgets('連続購入時は古いSnackBarを新しい内容へ置き換える', (tester) async {
    await _pumpSignedInApp(tester);

    final milkTile = find.byKey(const Key('purchase-milk'));
    await tester.tap(
      find.descendant(of: milkTile, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    expect(find.text('牛乳を購入済みにしました'), findsOneWidget);

    final eggsTile = find.byKey(const Key('purchase-eggs'));
    await tester.tap(
      find.descendant(of: eggsTile, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();

    expect(find.text('牛乳を購入済みにしました'), findsNothing);
    expect(find.text('卵を購入済みにしました'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('購入履歴は現在Groupのpurchased商品を表示する', (tester) async {
    await _pumpSignedInApp(tester);

    await tester.tap(find.byKey(const Key('purchase-history-button')));
    await tester.pumpAndSettle();

    expect(find.text('購入履歴'), findsOneWidget);
    expect(find.text('ティッシュ'), findsOneWidget);
    expect(find.byKey(const Key('item-menu-tissues')), findsNothing);
    expect(find.byKey(const Key('edit-shopping-item')), findsNothing);
    expect(find.byKey(const Key('delete-shopping-item')), findsNothing);
    expect(find.text('牛乳'), findsNothing);
  });

  testWidgets('購入履歴から未購入へ戻すと履歴から消えてShoppingへ戻る', (tester) async {
    final repository = FakeShoppingRepository(_defaultItems());
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
    );

    await tester.tap(find.byKey(const Key('purchase-history-button')));
    await tester.pumpAndSettle();
    expect(find.text('ティッシュ'), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-menu-tissues')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未購入に戻す'));
    await tester.pumpAndSettle();

    expect(find.text('ティッシュ'), findsNothing);
    expect(find.text('購入履歴はまだありません'), findsOneWidget);
    expect(repository.lastWrittenGroupId, testGroup.id);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('ティッシュ'), findsOneWidget);
  });

  testWidgets('Group詳細にMemberと招待コードを表示する', (tester) async {
    await _pumpSignedInApp(tester);

    await tester.tap(find.byKey(const Key('group-details-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('group-member-list')), findsOneWidget);
    expect(find.text('テスト太郎'), findsOneWidget);
    expect(find.text('K7P4XQ'), findsOneWidget);
    expect(find.byKey(const Key('copy-invite-code-button')), findsOneWidget);
  });

  testWidgets('ownerは削除確認をキャンセルでき、退出操作は表示されない', (tester) async {
    final repository = FakeGroupRepository(const [testGroup]);
    await _pumpApp(tester, initialUser: testUser, groupRepository: repository);

    await tester.tap(find.byKey(const Key('group-details-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delete-group-button')), findsOneWidget);
    expect(find.byKey(const Key('leave-group-button')), findsNothing);

    await tester.tap(find.byKey(const Key('delete-group-button')));
    await tester.pumpAndSettle();
    expect(find.text('岩田家を削除しますか？'), findsOneWidget);
    expect(find.textContaining('この操作は取り消せません'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(repository.deletedGroupId, isNull);
    expect(find.byKey(const Key('delete-group-button')), findsOneWidget);
  });

  testWidgets('ownerがGroupを削除するとcurrentGroupを破棄してGroup Setupへ進む', (
    tester,
  ) async {
    final repository = FakeGroupRepository(const [testGroup]);
    final analytics = FakeAnalyticsService();
    await _pumpApp(
      tester,
      initialUser: testUser,
      groupRepository: repository,
      analyticsService: analytics,
    );

    await tester.tap(find.byKey(const Key('group-details-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-group-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-group')));
    await tester.pumpAndSettle();

    expect(repository.deletedGroupId, testGroup.id);
    expect(find.text('家族と買い物リストを共有しよう'), findsOneWidget);
    expect(find.text('岩田家'), findsNothing);
    expect(analytics.events, contains(KatteAnalyticsEvent.groupDeleted));
  });

  testWidgets('Group削除後は残っている別Groupへ切り替わる', (tester) async {
    const remainingGroup = KatteGroup(
      id: 'group-remaining',
      name: '実家',
      createdBy: 'test-user',
      inviteCode: 'REMAIN2',
    );
    final repository = FakeGroupRepository(const [testGroup, remainingGroup]);
    await _pumpApp(tester, initialUser: testUser, groupRepository: repository);

    await tester.tap(find.byKey(const Key('group-details-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-group-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-group')));
    await tester.pumpAndSettle();

    expect(repository.deletedGroupId, testGroup.id);
    expect(find.text(remainingGroup.name), findsOneWidget);
    expect(find.byKey(const Key('group-switch-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('group-switch-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('select-group-group-iwata')), findsNothing);
    expect(
      find.byKey(const Key('select-group-group-remaining')),
      findsOneWidget,
    );
  });

  testWidgets('Group削除失敗時は安全なエラーを表示して確認Dialogに留まる', (tester) async {
    final repository = FakeGroupRepository(const [
      testGroup,
    ], failRemoval: true);
    await _pumpApp(tester, initialUser: testUser, groupRepository: repository);

    await tester.tap(find.byKey(const Key('group-details-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-group-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-group')));
    await tester.pumpAndSettle();

    expect(find.text('グループを削除できませんでした'), findsOneWidget);
    expect(find.text('岩田家を削除しますか？'), findsOneWidget);
    expect(find.textContaining('FirebaseException'), findsNothing);
  });

  testWidgets('memberが退出するとcurrentGroupを破棄してGroup Setupへ進む', (tester) async {
    final repository = FakeGroupRepository(const [
      testGroup,
    ], currentUserRole: GroupMemberRole.member);
    final analytics = FakeAnalyticsService();
    await _pumpApp(
      tester,
      initialUser: testUser,
      groupRepository: repository,
      analyticsService: analytics,
    );

    await tester.tap(find.byKey(const Key('group-details-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('leave-group-button')), findsOneWidget);
    expect(find.byKey(const Key('delete-group-button')), findsNothing);
    await tester.tap(find.byKey(const Key('leave-group-button')));
    await tester.pumpAndSettle();
    expect(find.text('岩田家から退出しますか？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-leave-group')));
    await tester.pumpAndSettle();

    expect(repository.leftGroupId, testGroup.id);
    expect(find.text('家族と買い物リストを共有しよう'), findsOneWidget);
    expect(find.text('岩田家'), findsNothing);
    expect(analytics.events, contains(KatteAnalyticsEvent.groupLeft));
  });

  testWidgets('Settingsに現在Groupとログアウト導線を表示する', (tester) async {
    await _pumpSignedInApp(tester);

    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();

    expect(find.text('テスト太郎'), findsOneWidget);
    expect(find.text('taro@example.com'), findsOneWidget);
    expect(find.text('岩田家'), findsOneWidget);
    expect(find.byKey(const Key('logout-button')), findsOneWidget);
    expect(find.text('利用規約'), findsNothing);
    expect(find.text('プライバシーポリシー'), findsNothing);
  });

  testWidgets('Settingsは全Groupを表示し別Group詳細を開いてもcurrentGroupを変えない', (
    tester,
  ) async {
    const secondGroup = KatteGroup(
      id: 'group-settings-second',
      name: '実家',
      createdBy: 'test-user',
      inviteCode: 'SECOND2',
    );
    const thirdGroup = KatteGroup(
      id: 'group-settings-third',
      name: '親戚みんなで使うとても長い旅行グループ',
      createdBy: 'other-user',
      inviteCode: 'THIRD22',
    );
    final repository = FakeGroupRepository(const [
      testGroup,
      secondGroup,
      thirdGroup,
    ]);
    await _pumpApp(tester, initialUser: testUser, groupRepository: repository);

    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-group-group-iwata')), findsOneWidget);
    expect(
      find.byKey(const Key('settings-group-group-settings-second')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('settings-group-group-settings-third')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('settings-group-group-iwata')),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('settings-group-group-settings-second')),
    );
    await tester.pumpAndSettle();

    expect(find.text(secondGroup.name), findsOneWidget);
    expect(find.text(secondGroup.inviteCode), findsOneWidget);
    expect(repository.watchedMemberGroupIds.last, secondGroup.id);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('買い物'));
    await tester.pumpAndSettle();
    expect(find.text(testGroup.name), findsOneWidget);
  });

  testWidgets('SettingsからGroup作成・Invite参加して一覧へ即反映する', (tester) async {
    const joinedGroup = KatteGroup(
      id: 'group-settings-joined',
      name: '旅行仲間',
      createdBy: 'other-user',
      inviteCode: 'TRAVEL2',
    );
    final repository = FakeGroupRepository(const [
      testGroup,
    ], joinableGroup: joinedGroup);
    await _pumpApp(tester, initialUser: testUser, groupRepository: repository);
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-create-group-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('group-name-field')), '旅行');
    await tester.tap(find.byKey(const Key('create-group-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-group-created-group')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('settings-join-group-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('invite-code-field')),
      joinedGroup.inviteCode,
    );
    await tester.tap(find.byKey(const Key('join-group-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-group-group-settings-joined')),
      findsOneWidget,
    );
  });

  testWidgets('Settingsで非current Groupを削除してもcurrentGroupを維持する', (tester) async {
    const managedGroup = KatteGroup(
      id: 'group-managed',
      name: '管理対象',
      createdBy: 'test-user',
      inviteCode: 'MANAGE2',
    );
    final repository = FakeGroupRepository(const [testGroup, managedGroup]);
    await _pumpApp(tester, initialUser: testUser, groupRepository: repository);
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-group-group-managed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-group-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-group')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-group-group-managed')), findsNothing);
    expect(find.byKey(const Key('settings-group-group-iwata')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('settings-group-group-iwata')),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Settingsで非current Groupから退出すると一覧から消える', (tester) async {
    const managedGroup = KatteGroup(
      id: 'group-leave-managed',
      name: '退出対象',
      createdBy: 'other-user',
      inviteCode: 'LEAVE22',
    );
    final repository = FakeGroupRepository(const [
      testGroup,
      managedGroup,
    ], currentUserRole: GroupMemberRole.member);
    await _pumpApp(tester, initialUser: testUser, groupRepository: repository);
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('settings-group-group-leave-managed')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('leave-group-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-leave-group')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('settings-group-group-leave-managed')),
      findsNothing,
    );
    expect(find.byKey(const Key('settings-group-group-iwata')), findsOneWidget);
  });

  testWidgets('ログアウトするとLoginへ戻り前UserのGroupを表示しない', (tester) async {
    final notifications = FakeNotificationService();
    final crashReporting = FakeCrashReportingService();
    await _pumpApp(
      tester,
      initialUser: testUser,
      notificationService: notifications,
      crashReportingService: crashReporting,
    );
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    final logoutButton = find.byKey(const Key('logout-button'));
    await tester.ensureVisible(logoutButton);
    await tester.tap(logoutButton);
    await tester.pumpAndSettle();

    expect(find.text('Katte'), findsOneWidget);
    expect(find.bySemanticsLabel('Googleで続ける'), findsOneWidget);
    expect(find.text('岩田家'), findsNothing);
    expect(notifications.unregisteredUserIds, [testUser.uid]);
    expect(crashReporting.userIdentifiers, contains(testUser.uid));
    expect(crashReporting.userIdentifiers.last, isNull);
  });

  testWidgets('Settingsから確認後にAccountを削除してLoginへ戻る', (tester) async {
    final notifications = FakeNotificationService();
    final auth = await _pumpApp(
      tester,
      initialUser: testUser,
      notificationService: notifications,
    );
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    final deleteButton = find.byKey(const Key('delete-account-button'));
    await tester.scrollUntilVisible(
      deleteButton,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('アカウントを削除しますか？'), findsOneWidget);
    expect(find.textContaining('この操作は元に戻せません。'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete-account')));
    await tester.pumpAndSettle();

    expect(auth.deleteAccountCount, 1);
    expect(notifications.unregisteredUserIds, [testUser.uid]);
    expect(find.bySemanticsLabel('Googleで続ける'), findsOneWidget);
    expect(find.bySemanticsLabel('Appleでサインイン'), findsOneWidget);
  });

  testWidgets('通知タップ時は対象Groupへ切り替えてShoppingへ戻る', (tester) async {
    const targetGroup = KatteGroup(
      id: 'group-target',
      name: '通知先グループ',
      createdBy: 'other-user',
      inviteCode: 'TARGET1',
    );
    final notifications = FakeNotificationService();
    await _pumpApp(
      tester,
      initialUser: testUser,
      initialGroups: const [testGroup, targetGroup],
      notificationService: notifications,
    );
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    expect(find.text('設定'), findsWidgets);

    notifications.emitTap(groupId: targetGroup.id);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('purchase-history-button')), findsOneWidget);
    expect(find.text('買い物'), findsOneWidget);
    expect(find.text(targetGroup.name), findsOneWidget);
  });

  testWidgets('Group Switcherは所属Groupと作成・参加導線を表示する', (tester) async {
    const parents = KatteGroup(
      id: 'group-parents',
      name: '実家',
      createdBy: 'test-user',
      inviteCode: 'PARENT2',
    );
    const work = KatteGroup(
      id: 'group-work',
      name: '仕事場',
      createdBy: 'test-user',
      inviteCode: 'WORK22',
    );
    await _pumpApp(
      tester,
      initialUser: testUser,
      initialGroups: const [work, testGroup, parents],
    );

    await tester.tap(find.byKey(const Key('group-switch-button')));
    await tester.pumpAndSettle();

    expect(find.text('グループを切り替え'), findsOneWidget);
    expect(find.byKey(const Key('select-group-group-iwata')), findsOneWidget);
    expect(find.byKey(const Key('select-group-group-parents')), findsOneWidget);
    expect(find.byKey(const Key('select-group-group-work')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('select-group-group-work')),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('switcher-create-group-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('switcher-join-group-button')), findsOneWidget);
  });

  testWidgets('SwitcherからGroupを作成し新Groupへ切り替える', (tester) async {
    await _pumpApp(tester, initialUser: testUser);

    await tester.tap(find.byKey(const Key('group-switch-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switcher-create-group-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('group-name-field')), '旅行');
    await tester.tap(find.byKey(const Key('create-group-button')));
    await tester.pumpAndSettle();

    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('今日はまだ何もありません'), findsOneWidget);
  });

  testWidgets('SwitcherからInvite参加し参加Groupへ切り替える', (tester) async {
    const joinedGroup = KatteGroup(
      id: 'group-joined',
      name: '親戚の家',
      createdBy: 'other-user',
      inviteCode: 'JOIN22',
    );
    final groups = FakeGroupRepository(const [
      testGroup,
    ], joinableGroup: joinedGroup);
    await _pumpApp(tester, initialUser: testUser, groupRepository: groups);

    await tester.tap(find.byKey(const Key('group-switch-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switcher-join-group-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('invite-code-field')),
      'join22',
    );
    await tester.tap(find.byKey(const Key('join-group-button')));
    await tester.pumpAndSettle();

    expect(groups.lastJoinedCode, joinedGroup.inviteCode);
    expect(find.text(joinedGroup.name), findsOneWidget);
  });

  testWidgets('参加済みGroupのInviteは重複作成せず安全なmessageを表示する', (tester) async {
    await _pumpApp(tester, initialUser: testUser);

    await tester.tap(find.byKey(const Key('group-switch-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switcher-join-group-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('invite-code-field')),
      testGroup.inviteCode,
    );
    await tester.tap(find.byKey(const Key('join-group-button')));
    await tester.pumpAndSettle();

    expect(find.text('このグループには参加済みです。'), findsOneWidget);
  });

  testWidgets('App再起動時はUserごとに最後のGroup選択を復元する', (tester) async {
    const secondGroup = KatteGroup(
      id: 'group-remembered',
      name: '前回のグループ',
      createdBy: 'test-user',
      inviteCode: 'MEMBER2',
    );
    final store = InMemoryCurrentGroupSelectionStore();
    await store.save(testUser.uid, secondGroup.id);

    await _pumpApp(
      tester,
      initialUser: testUser,
      initialGroups: const [testGroup, secondGroup],
      currentGroupSelectionStore: store,
    );

    expect(find.text(secondGroup.name), findsOneWidget);
  });

  testWidgets('currentGroup変更時にShopping providerがGroup単位で切り替わる', (
    tester,
  ) async {
    const secondGroup = KatteGroup(
      id: 'group-parents',
      name: '実家',
      createdBy: 'test-user',
      inviteCode: 'ABCD23',
    );
    final groupRepository = FakeGroupRepository(const [testGroup, secondGroup]);
    final shoppingRepository = FakeShoppingRepository(
      _defaultItems(),
      itemsByGroup: {
        secondGroup.id: [
          _item(id: 'soap', name: '洗剤'),
          _item(
            id: 'parents-history',
            name: '実家履歴',
            status: ShoppingItemStatus.purchased,
          ),
        ],
      },
      suggestionsByGroup: {
        testGroup.id: [_suggestion(name: '牛乳')],
        secondGroup.id: [_suggestion(name: '洗剤')],
      },
    );
    await _pumpApp(
      tester,
      initialUser: testUser,
      groupRepository: groupRepository,
      shoppingRepository: shoppingRepository,
    );

    expect(find.text('牛乳'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('open-add-item-sheet-button')),
    );
    await tester.tap(find.byKey(const Key('open-add-item-sheet-button')));
    await tester.pumpAndSettle();
    expect(_suggestionFinder('牛乳'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-switch-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('select-group-group-parents')));
    await tester.pump();

    expect(find.text('牛乳'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('洗剤'), findsOneWidget);
    expect(
      shoppingRepository.watchedGroupIds.where((id) => id == testGroup.id),
      hasLength(1),
    );

    await tester.tap(find.byKey(const Key('purchase-history-button')));
    await tester.pumpAndSettle();
    expect(find.text('実家履歴'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group-details-button')));
    await tester.pumpAndSettle();
    expect(groupRepository.watchedMemberGroupIds.last, secondGroup.id);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('open-add-item-sheet-button')),
    );
    await tester.tap(find.byKey(const Key('open-add-item-sheet-button')));
    await tester.pumpAndSettle();
    expect(_suggestionFinder('洗剤'), findsOneWidget);
    expect(_suggestionFinder('牛乳'), findsNothing);
    expect(shoppingRepository.watchedGroupIds, contains(secondGroup.id));
    expect(shoppingRepository.fetchedSuggestionGroupIds, [
      testGroup.id,
      secondGroup.id,
    ]);
  });
}

Finder _suggestionFinder(String name) {
  final id = itemSuggestionDocumentId(normalizeSuggestionName(name));
  return find.byKey(Key('item-suggestion-$id'));
}

Future<FakeAuthService> _pumpApp(
  WidgetTester tester, {
  AuthUser? initialUser,
  List<KatteGroup>? initialGroups,
  List<ShoppingItem>? initialItems,
  GroupRepository? groupRepository,
  ShoppingRepository? shoppingRepository,
  CategoryRepository? categoryRepository,
  NotificationService? notificationService,
  AnalyticsService? analyticsService,
  CrashReportingService? crashReportingService,
  CurrentGroupSelectionStore? currentGroupSelectionStore,
}) async {
  final authService = FakeAuthService(initialUser);
  final groups =
      groupRepository ??
      FakeGroupRepository(initialGroups ?? const [testGroup]);
  final shopping =
      shoppingRepository ??
      FakeShoppingRepository(initialItems ?? _defaultItems());
  final categories = categoryRepository ?? FakeCategoryRepository();
  final notifications = notificationService ?? FakeNotificationService();
  final analytics = analyticsService ?? FakeAnalyticsService();
  final crashReporting = crashReportingService ?? FakeCrashReportingService();
  addTearDown(authService.dispose);
  if (groups is FakeGroupRepository) {
    addTearDown(groups.dispose);
  }
  if (shopping is FakeShoppingRepository) {
    addTearDown(shopping.dispose);
  }
  if (categories is FakeCategoryRepository) {
    addTearDown(categories.dispose);
  }
  if (notifications is FakeNotificationService) {
    addTearDown(notifications.dispose);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        groupRepositoryProvider.overrideWithValue(groups),
        shoppingRepositoryProvider.overrideWithValue(shopping),
        categoryRepositoryProvider.overrideWithValue(categories),
        notificationServiceProvider.overrideWithValue(notifications),
        analyticsServiceProvider.overrideWithValue(analytics),
        crashReportingServiceProvider.overrideWithValue(crashReporting),
        currentGroupSelectionStoreProvider.overrideWithValue(
          currentGroupSelectionStore ?? InMemoryCurrentGroupSelectionStore(),
        ),
      ],
      child: const KatteApp(),
    ),
  );
  await tester.pumpAndSettle();
  return authService;
}

class FakeAnalyticsService implements AnalyticsService {
  final List<KatteAnalyticsEvent> events = [];

  @override
  final NavigatorObserver navigatorObserver = NavigatorObserver();

  @override
  Future<void> log(KatteAnalyticsEvent event) async {
    events.add(event);
  }
}

class FakeCrashReportingService implements CrashReportingService {
  final List<String?> userIdentifiers = [];

  @override
  Future<void> setUserIdentifier(String? userId) async {
    userIdentifiers.add(userId);
  }
}

Future<FakeAuthService> _pumpSignedInApp(WidgetTester tester) {
  return _pumpApp(tester, initialUser: testUser);
}

class FakeAuthService implements AuthService {
  FakeAuthService(this._currentUser);

  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;
  int appleSignInCount = 0;
  int deleteAccountCount = 0;
  Completer<void>? googleSignInCompleter;
  Object? appleSignInError;

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield _currentUser;
    yield* _controller.stream;
  }

  @override
  Future<void> signInWithGoogle() async {
    await googleSignInCompleter?.future;
    _setUser(testUser);
  }

  @override
  Future<void> signInWithApple() async {
    appleSignInCount++;
    final error = appleSignInError;
    if (error != null) {
      throw error;
    }
    _setUser(testUser);
  }

  @override
  Future<void> deleteAccount() async {
    deleteAccountCount++;
    _setUser(null);
  }

  @override
  Future<void> signOut() async => _setUser(null);

  void _setUser(AuthUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  void dispose() => _controller.close();
}

class PendingAuthService implements AuthService {
  @override
  Stream<AuthUser?> authStateChanges() => const Stream.empty();

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signInWithApple() async {}

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<void> signOut() async {}
}

class FakeNotificationService implements NotificationService {
  final _tapController = StreamController<NotificationTap>.broadcast();
  final List<String> registeredUserIds = [];
  final List<String> unregisteredUserIds = [];

  @override
  Stream<NotificationTap> get notificationTaps => _tapController.stream;

  @override
  Future<void> registerForUser(AuthUser user) async {
    registeredUserIds.add(user.uid);
  }

  @override
  Future<void> unregisterForUser(AuthUser user) async {
    unregisteredUserIds.add(user.uid);
  }

  void emitTap({String? groupId}) {
    _tapController.add(NotificationTap(groupId: groupId));
  }

  @override
  void dispose() => _tapController.close();
}

class FakeGroupRepository implements GroupRepository {
  FakeGroupRepository(
    List<KatteGroup> groups, {
    this.currentUserRole = GroupMemberRole.owner,
    this.failRemoval = false,
    this.joinableGroup,
  }) : _groups = [...groups];

  final _controller = StreamController<List<KatteGroup>>.broadcast();
  List<KatteGroup> _groups;
  var ensureUserCount = 0;
  String? createdBy;
  String? lastJoinedCode;
  final GroupMemberRole currentUserRole;
  final bool failRemoval;
  final KatteGroup? joinableGroup;
  final List<String> watchedMemberGroupIds = [];
  String? deletedGroupId;
  String? leftGroupId;

  @override
  Future<void> ensureUser(AuthUser user) async {
    ensureUserCount++;
  }

  @override
  Stream<List<KatteGroup>> watchUserGroups(AuthUser user) async* {
    yield List.unmodifiable(_groups);
    yield* _controller.stream;
  }

  @override
  Future<KatteGroup> createGroup({
    required AuthUser user,
    required String name,
  }) async {
    createdBy = user.uid;
    final group = KatteGroup(
      id: 'created-group',
      name: name,
      createdBy: user.uid,
      inviteCode: 'CREATE2',
    );
    _groups = [..._groups, group];
    _controller.add(List.unmodifiable(_groups));
    return group;
  }

  @override
  Future<KatteGroup> joinGroup({
    required AuthUser user,
    required String inviteCode,
  }) async {
    final normalized = inviteCode.trim().toUpperCase();
    lastJoinedCode = normalized;
    if (_groups.any((group) => group.inviteCode == normalized)) {
      throw AlreadyGroupMemberException();
    }
    final group = joinableGroup ?? testGroup;
    if (normalized != group.inviteCode) {
      throw GroupNotFoundException();
    }
    _groups = [..._groups, group];
    _controller.add(List.unmodifiable(_groups));
    return group;
  }

  @override
  Stream<List<GroupMember>> watchMembers(String groupId) {
    watchedMemberGroupIds.add(groupId);
    return Stream.value([
      GroupMember(
        userId: 'test-user',
        displayName: 'テスト太郎',
        photoUrl: null,
        role: currentUserRole,
      ),
    ]);
  }

  @override
  Future<void> deleteGroup({required String groupId}) async {
    if (failRemoval) {
      throw FirebaseException(plugin: 'cloud_functions', code: 'internal');
    }
    deletedGroupId = groupId;
    _groups = _groups.where((group) => group.id != groupId).toList();
    _controller.add(List.unmodifiable(_groups));
  }

  @override
  Future<void> leaveGroup({
    required String groupId,
    required AuthUser user,
  }) async {
    if (failRemoval) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    leftGroupId = groupId;
    _groups = _groups.where((group) => group.id != groupId).toList();
    _controller.add(List.unmodifiable(_groups));
  }

  void dispose() => _controller.close();
}

class FakeShoppingRepository implements ShoppingRepository {
  FakeShoppingRepository(
    List<ShoppingItem> initialItems, {
    Map<String, List<ShoppingItem>>? itemsByGroup,
    Map<String, List<ItemSuggestion>>? suggestionsByGroup,
    this.failSuggestions = false,
    this.failDeletion = false,
    this.failPurchase = false,
    this.failEdit = false,
    this.purchaseCompletion,
    this.editCompletion,
  }) : _itemsByGroup = {
         testGroup.id: [...initialItems],
         for (final entry in (itemsByGroup ?? {}).entries)
           entry.key: [...entry.value],
       },
       _suggestionsByGroup = {
         for (final entry in (suggestionsByGroup ?? {}).entries)
           entry.key: [...entry.value],
       };

  final _controller = StreamController<String>.broadcast();
  final Map<String, List<ShoppingItem>> _itemsByGroup;
  final Map<String, List<ItemSuggestion>> _suggestionsByGroup;
  final bool failSuggestions;
  final bool failDeletion;
  final bool failPurchase;
  final bool failEdit;
  final Completer<void>? purchaseCompletion;
  final Completer<void>? editCompletion;
  final List<String> watchedGroupIds = [];
  final List<String> fetchedSuggestionGroupIds = [];
  var _nextId = 1;
  String? lastWrittenGroupId;
  String? lastDeletedGroupId;
  String? lastDeletedItemId;
  String? lastEditedGroupId;
  var editCallCount = 0;

  @override
  Stream<List<ShoppingItem>> watchPendingItems(String groupId) async* {
    watchedGroupIds.add(groupId);
    yield _itemsForStatus(groupId, ShoppingItemStatus.pending);
    yield* _controller.stream
        .where((id) => id == groupId)
        .map((_) => _itemsForStatus(groupId, ShoppingItemStatus.pending));
  }

  @override
  Stream<List<ShoppingItem>> watchPurchasedItems(String groupId) async* {
    watchedGroupIds.add(groupId);
    yield _itemsForStatus(groupId, ShoppingItemStatus.purchased);
    yield* _controller.stream
        .where((id) => id == groupId)
        .map((_) => _itemsForStatus(groupId, ShoppingItemStatus.purchased));
  }

  @override
  Future<List<ItemSuggestion>> fetchItemSuggestions(String groupId) async {
    fetchedSuggestionGroupIds.add(groupId);
    if (failSuggestions) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return List.unmodifiable(_suggestionsByGroup[groupId] ?? const []);
  }

  @override
  Future<void> addItem({
    required String groupId,
    required AuthUser user,
    required String name,
    required int quantity,
    required String note,
    required String? categoryId,
  }) async {
    lastWrittenGroupId = groupId;
    final now = DateTime.now();
    final items = _itemsByGroup.putIfAbsent(groupId, () => []);
    items.insert(
      0,
      ShoppingItem(
        id: 'new-${_nextId++}',
        name: name,
        quantity: quantity,
        note: note,
        categoryId: categoryId,
        status: ShoppingItemStatus.pending,
        createdBy: user.uid,
        createdByName: user.displayName ?? fallbackUserDisplayName,
        createdAt: now,
        purchasedBy: null,
        purchasedByName: null,
        purchasedAt: null,
        updatedAt: now,
      ),
    );
    final normalizedName = normalizeSuggestionName(name);
    final suggestionId = itemSuggestionDocumentId(normalizedName);
    final suggestions = _suggestionsByGroup.putIfAbsent(groupId, () => []);
    final currentIndex = suggestions.indexWhere(
      (suggestion) => suggestion.id == suggestionId,
    );
    final current = currentIndex < 0 ? null : suggestions[currentIndex];
    final updated = ItemSuggestion(
      id: suggestionId,
      name: name.trim(),
      normalizedName: normalizedName,
      useCount: (current?.useCount ?? 0) + 1,
      lastUsedAt: now,
    );
    if (currentIndex < 0) {
      suggestions.add(updated);
    } else {
      suggestions[currentIndex] = updated;
    }
    _controller.add(groupId);
  }

  ItemSuggestion? suggestion(String groupId, String name) {
    final id = itemSuggestionDocumentId(normalizeSuggestionName(name));
    return (_suggestionsByGroup[groupId] ?? const [])
        .where((suggestion) => suggestion.id == id)
        .firstOrNull;
  }

  @override
  Future<void> setPurchased({
    required String groupId,
    required AuthUser user,
    required String itemId,
    required bool isPurchased,
  }) async {
    if (failPurchase) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'Sensitive Firebase error details',
      );
    }
    lastWrittenGroupId = groupId;
    final items = _itemsByGroup[groupId] ?? [];
    _itemsByGroup[groupId] = [
      for (final item in items)
        if (item.id == itemId)
          ShoppingItem(
            id: item.id,
            name: item.name,
            quantity: item.quantity,
            note: item.note,
            categoryId: item.categoryId,
            status: isPurchased
                ? ShoppingItemStatus.purchased
                : ShoppingItemStatus.pending,
            createdBy: item.createdBy,
            createdByName: item.createdByName,
            createdAt: item.createdAt,
            purchasedBy: isPurchased ? user.uid : null,
            purchasedByName: isPurchased ? user.displayName : null,
            purchasedAt: isPurchased ? DateTime.now() : null,
            updatedAt: DateTime.now(),
          )
        else
          item,
    ];
    _controller.add(groupId);
    if (isPurchased && purchaseCompletion != null) {
      await purchaseCompletion!.future;
    }
  }

  @override
  Future<void> updateItem({
    required String groupId,
    required String itemId,
    required String name,
    required int quantity,
    required String note,
    required String? categoryId,
  }) async {
    editCallCount++;
    if (failEdit) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'Sensitive Firebase error details',
      );
    }
    if (editCompletion != null) {
      await editCompletion!.future;
    }
    final items = _itemsByGroup[groupId] ?? [];
    final index = items.indexWhere((item) => item.id == itemId);
    if (index < 0) {
      throw const ShoppingItemNotFoundException();
    }
    final current = items[index];
    if (current.status != ShoppingItemStatus.pending) {
      throw const ShoppingItemNotPendingException();
    }
    lastWrittenGroupId = groupId;
    lastEditedGroupId = groupId;
    items[index] = ShoppingItem(
      id: current.id,
      name: name.trim(),
      quantity: quantity,
      note: note.trim(),
      categoryId: categoryId,
      status: current.status,
      createdBy: current.createdBy,
      createdByName: current.createdByName,
      createdAt: current.createdAt,
      purchasedBy: current.purchasedBy,
      purchasedByName: current.purchasedByName,
      purchasedAt: current.purchasedAt,
      updatedAt: DateTime.now(),
    );
    _controller.add(groupId);
  }

  ShoppingItem? item(String groupId, String itemId) {
    return (_itemsByGroup[groupId] ?? const [])
        .where((item) => item.id == itemId)
        .firstOrNull;
  }

  @override
  Future<void> deleteItem({
    required String groupId,
    required String itemId,
  }) async {
    if (failDeletion) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'Sensitive Firebase error details',
      );
    }
    lastDeletedGroupId = groupId;
    lastDeletedItemId = itemId;
    _itemsByGroup[groupId] = (_itemsByGroup[groupId] ?? [])
        .where((item) => item.id != itemId)
        .toList();
    _controller.add(groupId);
  }

  List<ShoppingItem> _itemsForStatus(
    String groupId,
    ShoppingItemStatus status,
  ) {
    final items = (_itemsByGroup[groupId] ?? [])
        .where((item) => item.status == status)
        .toList();
    items.sort((left, right) {
      final leftDate = status == ShoppingItemStatus.pending
          ? left.createdAt
          : left.purchasedAt;
      final rightDate = status == ShoppingItemStatus.pending
          ? right.createdAt
          : right.purchasedAt;
      return (rightDate ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        leftDate ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    });
    return List.unmodifiable(items);
  }

  void dispose() => _controller.close();
}

class FakeCategoryRepository implements CategoryRepository {
  FakeCategoryRepository({
    Map<String, List<ShoppingCategory>>? categoriesByGroup,
  }) : _categoriesByGroup = {
         for (final entry in (categoriesByGroup ?? const {}).entries)
           entry.key: [...entry.value],
       };

  final _controller = StreamController<String>.broadcast();
  final Map<String, List<ShoppingCategory>> _categoriesByGroup;

  @override
  Stream<List<ShoppingCategory>> watchCategories(String groupId) async* {
    yield List.unmodifiable(_categoriesByGroup[groupId] ?? const []);
    yield* _controller.stream
        .where((changedGroupId) => changedGroupId == groupId)
        .map((_) => List.unmodifiable(_categoriesByGroup[groupId] ?? const []));
  }

  @override
  Future<void> createCategory({
    required String groupId,
    required String userId,
    required String name,
  }) async {
    final values = _categoriesByGroup.putIfAbsent(groupId, () => []);
    final normalizedName = normalizeCategoryName(name);
    if (values.any((category) => category.normalizedName == normalizedName)) {
      throw const DuplicateCategoryException();
    }
    values.add(
      ShoppingCategory(
        id: 'category-${values.length + 1}',
        name: name.trim(),
        normalizedName: normalizedName,
        sortOrder: values.length,
        createdAt: DateTime.now(),
      ),
    );
    _controller.add(groupId);
  }

  @override
  Future<void> renameCategory({
    required String groupId,
    required ShoppingCategory category,
    required String name,
  }) async {}

  @override
  Future<void> deleteCategory({
    required String groupId,
    required String categoryId,
  }) async {}

  void dispose() => _controller.close();
}

class PermissionDeniedShoppingRepository implements ShoppingRepository {
  @override
  Stream<List<ShoppingItem>> watchPendingItems(String groupId) {
    return Stream.error(
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Sensitive Firebase error details',
      ),
    );
  }

  @override
  Stream<List<ShoppingItem>> watchPurchasedItems(String groupId) {
    return watchPendingItems(groupId);
  }

  @override
  Future<List<ItemSuggestion>> fetchItemSuggestions(String groupId) async {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
  }

  @override
  Future<void> addItem({
    required String groupId,
    required AuthUser user,
    required String name,
    required int quantity,
    required String note,
    required String? categoryId,
  }) async {}

  @override
  Future<void> setPurchased({
    required String groupId,
    required AuthUser user,
    required String itemId,
    required bool isPurchased,
  }) async {}

  @override
  Future<void> updateItem({
    required String groupId,
    required String itemId,
    required String name,
    required int quantity,
    required String note,
    required String? categoryId,
  }) async {}

  @override
  Future<void> deleteItem({
    required String groupId,
    required String itemId,
  }) async {}
}

ItemSuggestion _suggestion({
  required String name,
  int useCount = 1,
  DateTime? lastUsedAt,
}) {
  final normalizedName = normalizeSuggestionName(name);
  return ItemSuggestion(
    id: itemSuggestionDocumentId(normalizedName),
    name: name,
    normalizedName: normalizedName,
    useCount: useCount,
    lastUsedAt: lastUsedAt ?? DateTime.now(),
  );
}

List<ShoppingItem> _defaultItems() {
  final now = DateTime.now();
  return [
    _item(
      id: 'milk',
      name: '牛乳',
      createdBy: 'yumi',
      createdByName: '由美',
      createdAt: now.subtract(const Duration(minutes: 2)),
    ),
    _item(
      id: 'eggs',
      name: '卵',
      quantity: 2,
      createdByName: '康平',
      createdAt: now.subtract(const Duration(minutes: 10)),
    ),
    _item(
      id: 'tissues',
      name: 'ティッシュ',
      status: ShoppingItemStatus.purchased,
      createdBy: 'yumi',
      createdByName: '由美',
      createdAt: now.subtract(const Duration(minutes: 20)),
      purchasedBy: 'yumi',
      purchasedByName: '由美',
      purchasedAt: now.subtract(const Duration(minutes: 5)),
    ),
  ];
}

ShoppingItem _item({
  required String id,
  required String name,
  int quantity = 1,
  ShoppingItemStatus status = ShoppingItemStatus.pending,
  String createdBy = 'test-user',
  String createdByName = 'テスト太郎',
  DateTime? createdAt,
  String? purchasedBy,
  String? purchasedByName,
  DateTime? purchasedAt,
  String? categoryId,
}) {
  final now = DateTime.now();
  return ShoppingItem(
    id: id,
    name: name,
    quantity: quantity,
    note: '',
    categoryId: categoryId,
    status: status,
    createdBy: createdBy,
    createdByName: createdByName,
    createdAt: createdAt ?? now,
    purchasedBy: purchasedBy,
    purchasedByName: purchasedByName,
    purchasedAt: purchasedAt,
    updatedAt: now,
  );
}
