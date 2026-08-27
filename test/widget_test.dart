import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katte/app.dart';
import 'package:katte/features/auth/application/auth_providers.dart';
import 'package:katte/features/auth/application/auth_service.dart';
import 'package:katte/features/groups/group_providers.dart';
import 'package:katte/features/groups/group_repository.dart'
    hide fallbackUserDisplayName;
import 'package:katte/features/groups/models/katte_group.dart';
import 'package:katte/features/notifications/application/notification_service_provider.dart';
import 'package:katte/features/notifications/services/notification_service.dart';
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
  testWidgets('未ログイン時はLoginを表示する', (tester) async {
    await _pumpApp(tester);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.textTheme.bodyMedium?.fontFamily, contains('NotoSansJP'));
    expect(find.text('Katte'), findsOneWidget);
    expect(find.text('家族の「買っといて」を、\nリアルタイムで共有。'), findsOneWidget);
    expect(find.text('Googleで続ける'), findsOneWidget);
  });

  testWidgets('Google Login後に所属GroupのShoppingへ進む', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byKey(const Key('google-login-button')));
    await tester.pumpAndSettle();

    expect(find.text('岩田家'), findsOneWidget);
    expect(find.byKey(const Key('purchase-history-button')), findsOneWidget);
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
    await _pumpApp(
      tester,
      initialUser: testUser,
      groupRepository: groupRepository,
    );

    await tester.tap(find.byKey(const Key('open-create-group-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('group-name-field')), '康平家');
    await tester.tap(find.byKey(const Key('create-group-button')));
    await tester.pumpAndSettle();

    expect(find.text('康平家'), findsOneWidget);
    expect(groupRepository.createdBy, testUser.uid);
    expect(groupRepository.ensureUserCount, 1);
  });

  testWidgets('招待コードでGroup参加後にShoppingへ進む', (tester) async {
    final groupRepository = FakeGroupRepository(const []);
    await _pumpApp(
      tester,
      initialUser: testUser,
      groupRepository: groupRepository,
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
    await _pumpApp(
      tester,
      initialUser: testUser,
      shoppingRepository: repository,
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

  testWidgets('購入済みにすると一覧から消えUndoで戻る', (tester) async {
    await _pumpSignedInApp(tester);

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

  testWidgets('Settingsに現在Groupとログアウト導線を表示する', (tester) async {
    await _pumpSignedInApp(tester);

    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();

    expect(find.text('テスト太郎'), findsOneWidget);
    expect(find.text('taro@example.com'), findsOneWidget);
    expect(find.text('岩田家'), findsOneWidget);
    expect(find.byKey(const Key('logout-button')), findsOneWidget);
  });

  testWidgets('ログアウトするとLoginへ戻り前UserのGroupを表示しない', (tester) async {
    final notifications = FakeNotificationService();
    await _pumpApp(
      tester,
      initialUser: testUser,
      notificationService: notifications,
    );
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    final logoutButton = find.byKey(const Key('logout-button'));
    await tester.ensureVisible(logoutButton);
    await tester.tap(logoutButton);
    await tester.pumpAndSettle();

    expect(find.text('Katte'), findsOneWidget);
    expect(find.text('Googleで続ける'), findsOneWidget);
    expect(find.text('岩田家'), findsNothing);
    expect(notifications.unregisteredUserIds, [testUser.uid]);
  });

  testWidgets('通知タップ時は既存Routingに従ってShoppingへ戻る', (tester) async {
    final notifications = FakeNotificationService();
    await _pumpApp(
      tester,
      initialUser: testUser,
      notificationService: notifications,
    );
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    expect(find.text('設定'), findsWidgets);

    notifications.emitTap();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('purchase-history-button')), findsOneWidget);
    expect(find.text('買い物'), findsOneWidget);
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
        secondGroup.id: [_item(id: 'soap', name: '洗剤')],
      },
    );
    await _pumpApp(
      tester,
      initialUser: testUser,
      groupRepository: groupRepository,
      shoppingRepository: shoppingRepository,
    );

    expect(find.text('牛乳'), findsOneWidget);
    await tester.tap(find.byKey(const Key('group-switch-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('select-group-group-parents')));
    await tester.pumpAndSettle();

    expect(find.text('洗剤'), findsOneWidget);
    expect(find.text('牛乳'), findsNothing);
    expect(shoppingRepository.watchedGroupIds, contains(secondGroup.id));
  });
}

Future<FakeAuthService> _pumpApp(
  WidgetTester tester, {
  AuthUser? initialUser,
  List<KatteGroup>? initialGroups,
  List<ShoppingItem>? initialItems,
  GroupRepository? groupRepository,
  ShoppingRepository? shoppingRepository,
  NotificationService? notificationService,
}) async {
  final authService = FakeAuthService(initialUser);
  final groups =
      groupRepository ??
      FakeGroupRepository(initialGroups ?? const [testGroup]);
  final shopping =
      shoppingRepository ??
      FakeShoppingRepository(initialItems ?? _defaultItems());
  final notifications = notificationService ?? FakeNotificationService();
  addTearDown(authService.dispose);
  if (groups is FakeGroupRepository) {
    addTearDown(groups.dispose);
  }
  if (shopping is FakeShoppingRepository) {
    addTearDown(shopping.dispose);
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
        notificationServiceProvider.overrideWithValue(notifications),
      ],
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
  Future<void> signInWithGoogle() async => _setUser(testUser);

  @override
  Future<void> signOut() async => _setUser(null);

  void _setUser(AuthUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  void dispose() => _controller.close();
}

class FakeNotificationService implements NotificationService {
  final _tapController = StreamController<void>.broadcast();
  final List<String> registeredUserIds = [];
  final List<String> unregisteredUserIds = [];

  @override
  Stream<void> get notificationTaps => _tapController.stream;

  @override
  Future<void> registerForUser(AuthUser user) async {
    registeredUserIds.add(user.uid);
  }

  @override
  Future<void> unregisterForUser(AuthUser user) async {
    unregisteredUserIds.add(user.uid);
  }

  void emitTap() => _tapController.add(null);

  @override
  void dispose() => _tapController.close();
}

class FakeGroupRepository implements GroupRepository {
  FakeGroupRepository(List<KatteGroup> groups) : _groups = [...groups];

  final _controller = StreamController<List<KatteGroup>>.broadcast();
  List<KatteGroup> _groups;
  var ensureUserCount = 0;
  String? createdBy;
  String? lastJoinedCode;

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
    if (normalized != testGroup.inviteCode) {
      throw GroupNotFoundException();
    }
    _groups = [..._groups, testGroup];
    _controller.add(List.unmodifiable(_groups));
    return testGroup;
  }

  @override
  Stream<List<GroupMember>> watchMembers(String groupId) {
    return Stream.value(const [
      GroupMember(
        userId: 'test-user',
        displayName: 'テスト太郎',
        photoUrl: null,
        role: GroupMemberRole.owner,
      ),
    ]);
  }

  void dispose() => _controller.close();
}

class FakeShoppingRepository implements ShoppingRepository {
  FakeShoppingRepository(
    List<ShoppingItem> initialItems, {
    Map<String, List<ShoppingItem>>? itemsByGroup,
    this.purchaseCompletion,
  }) : _itemsByGroup = {
         testGroup.id: [...initialItems],
         for (final entry in (itemsByGroup ?? {}).entries)
           entry.key: [...entry.value],
       };

  final _controller = StreamController<String>.broadcast();
  final Map<String, List<ShoppingItem>> _itemsByGroup;
  final Completer<void>? purchaseCompletion;
  final List<String> watchedGroupIds = [];
  var _nextId = 1;
  String? lastWrittenGroupId;

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
  Future<void> addItem({
    required String groupId,
    required AuthUser user,
    required String name,
    required int quantity,
    required String note,
  }) async {
    lastWrittenGroupId = groupId;
    final items = _itemsByGroup.putIfAbsent(groupId, () => []);
    items.insert(
      0,
      ShoppingItem(
        id: 'new-${_nextId++}',
        name: name,
        quantity: quantity,
        note: note,
        status: ShoppingItemStatus.pending,
        createdBy: user.uid,
        createdByName: user.displayName ?? fallbackUserDisplayName,
        createdAt: DateTime.now(),
        purchasedBy: null,
        purchasedByName: null,
        purchasedAt: null,
        updatedAt: DateTime.now(),
      ),
    );
    _controller.add(groupId);
  }

  @override
  Future<void> setPurchased({
    required String groupId,
    required AuthUser user,
    required String itemId,
    required bool isPurchased,
  }) async {
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
  Future<void> deleteItem({
    required String groupId,
    required String itemId,
  }) async {
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
  Future<void> addItem({
    required String groupId,
    required AuthUser user,
    required String name,
    required int quantity,
    required String note,
  }) async {}

  @override
  Future<void> setPurchased({
    required String groupId,
    required AuthUser user,
    required String itemId,
    required bool isPurchased,
  }) async {}

  @override
  Future<void> deleteItem({
    required String groupId,
    required String itemId,
  }) async {}
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
}) {
  final now = DateTime.now();
  return ShoppingItem(
    id: id,
    name: name,
    quantity: quantity,
    note: '',
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
