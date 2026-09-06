import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/application/auth_providers.dart';
import '../groups/group_providers.dart';
import 'category_repository.dart';
import 'models/shopping_category.dart';

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return FirestoreCategoryRepository();
});

final categoriesByGroupProvider = StreamProvider.autoDispose
    .family<List<ShoppingCategory>, String>((ref, groupId) async* {
      if (ref.watch(authStateProvider).value == null) {
        yield const [];
        return;
      }
      try {
        yield* ref.watch(categoryRepositoryProvider).watchCategories(groupId);
      } on Object catch (error, stackTrace) {
        debugPrint('Categories load failed: $error\n$stackTrace');
        Error.throwWithStackTrace(error, stackTrace);
      }
    }, retry: (_, _) => null);

final categoriesProvider = Provider<AsyncValue<List<ShoppingCategory>>>((ref) {
  final groupId = ref.watch(currentGroupProvider)?.id;
  if (groupId == null) return const AsyncData([]);
  return ref.watch(categoriesByGroupProvider(groupId));
});

final categoryControllerProvider =
    NotifierProvider<CategoryController, AsyncValue<void>>(
      CategoryController.new,
    );

class CategoryController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> create(String groupId, String name) => _run((repository) {
    final user = ref.read(authStateProvider).value;
    if (user == null) {
      throw const CategoryOperationException('ログイン状態を確認できませんでした。');
    }
    return repository.createCategory(
      groupId: groupId,
      userId: user.uid,
      name: name,
    );
  });

  Future<bool> rename(String groupId, ShoppingCategory category, String name) =>
      _run(
        (repository) => repository.renameCategory(
          groupId: groupId,
          category: category,
          name: name,
        ),
      );

  Future<bool> delete(String groupId, String categoryId) => _run(
    (repository) =>
        repository.deleteCategory(groupId: groupId, categoryId: categoryId),
  );

  Future<bool> _run(
    Future<void> Function(CategoryRepository repository) action,
  ) async {
    state = const AsyncLoading();
    try {
      await action(ref.read(categoryRepositoryProvider));
      state = const AsyncData(null);
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('Category operation failed: $error\n$stackTrace');
      final safeError = error is DuplicateCategoryException
          ? const CategoryOperationException('同じ名前のカテゴリがあります。')
          : error is FirebaseException && error.code == 'unavailable'
          ? const CategoryOperationException('通信状態を確認して、もう一度お試しください。')
          : const CategoryOperationException('更新できませんでした。もう一度お試しください。');
      state = AsyncError(safeError, stackTrace);
      return false;
    }
  }
}

class CategoryOperationException implements Exception {
  const CategoryOperationException(this.message);
  final String message;
  @override
  String toString() => message;
}
