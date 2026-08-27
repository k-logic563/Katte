import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/application/auth_providers.dart';
import '../auth/application/auth_service.dart';
import '../groups/group_providers.dart';
import 'models/shopping_item.dart';
import 'shopping_repository.dart';

final shoppingRepositoryProvider = Provider<ShoppingRepository>((ref) {
  return FirestoreShoppingRepository();
});

final pendingShoppingItemsProvider = StreamProvider<List<ShoppingItem>>((
  ref,
) async* {
  final group = ref.watch(currentGroupProvider);
  if (ref.watch(authStateProvider).value == null || group == null) {
    yield const [];
    return;
  }

  try {
    yield* ref.watch(shoppingRepositoryProvider).watchPendingItems(group.id);
  } on Object catch (error, stackTrace) {
    _logLoadError('Pending shopping items', error, stackTrace);
    Error.throwWithStackTrace(_safeLoadError(error), stackTrace);
  }
}, retry: (_, _) => null);

final purchasedShoppingItemsProvider = StreamProvider<List<ShoppingItem>>((
  ref,
) async* {
  final group = ref.watch(currentGroupProvider);
  if (ref.watch(authStateProvider).value == null || group == null) {
    yield const [];
    return;
  }

  try {
    yield* ref.watch(shoppingRepositoryProvider).watchPurchasedItems(group.id);
  } on Object catch (error, stackTrace) {
    _logLoadError('Purchased shopping items', error, stackTrace);
    Error.throwWithStackTrace(_safeLoadError(error), stackTrace);
  }
}, retry: (_, _) => null);

void _logLoadError(String source, Object error, StackTrace stackTrace) {
  debugPrint('$source load failed: $error\n$stackTrace');
}

class ShoppingLoadException implements Exception {
  const ShoppingLoadException(this.message);

  final String message;

  @override
  String toString() => message;
}

ShoppingLoadException _safeLoadError(Object error) {
  if (error is FirebaseException && error.code == 'permission-denied') {
    return const ShoppingLoadException('Firestoreへのアクセスが拒否されました。');
  }
  return const ShoppingLoadException('買い物リストを読み込めませんでした。');
}

final shoppingControllerProvider =
    NotifierProvider<ShoppingController, AsyncValue<void>>(
      ShoppingController.new,
    );

class ShoppingController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> addItem({
    required String name,
    required int quantity,
    required String note,
  }) {
    return _run(
      (repository, user) => repository.addItem(
        groupId: _currentGroupId(),
        user: user,
        name: name,
        quantity: quantity,
        note: note,
      ),
    );
  }

  Future<bool> setPurchased({
    required String itemId,
    required bool isPurchased,
  }) {
    return _run(
      (repository, user) => repository.setPurchased(
        groupId: _currentGroupId(),
        user: user,
        itemId: itemId,
        isPurchased: isPurchased,
      ),
    );
  }

  Future<bool> deleteItem(String itemId) {
    return _run(
      (repository, _) =>
          repository.deleteItem(groupId: _currentGroupId(), itemId: itemId),
    );
  }

  String _currentGroupId() {
    final group = ref.read(currentGroupProvider);
    if (group == null) {
      throw const ShoppingOperationException('グループを確認できませんでした。');
    }
    return group.id;
  }

  Future<bool> _run(
    Future<void> Function(ShoppingRepository repository, AuthUser user) action,
  ) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) {
      state = AsyncError(
        const ShoppingOperationException('ログイン状態を確認できませんでした。'),
        StackTrace.current,
      );
      return false;
    }

    state = const AsyncLoading();
    try {
      await action(ref.read(shoppingRepositoryProvider), user);
      state = const AsyncData(null);
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('Shopping operation failed: $error\n$stackTrace');
      state = AsyncError(_safeOperationError(error), stackTrace);
      return false;
    }
  }
}

class ShoppingOperationException implements Exception {
  const ShoppingOperationException(this.message);

  final String message;

  @override
  String toString() => message;
}

ShoppingOperationException _safeOperationError(Object error) {
  if (error is FirebaseException && error.code == 'unavailable') {
    return const ShoppingOperationException('通信状態を確認して、もう一度お試しください。');
  }
  return const ShoppingOperationException('更新できませんでした。もう一度お試しください。');
}
