import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/application/auth_providers.dart';
import '../auth/application/auth_service.dart';
import '../monitoring/monitoring_providers.dart';
import '../monitoring/monitoring_services.dart';
import 'group_repository.dart';
import 'models/katte_group.dart';

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return FirestoreGroupRepository();
});

final userGroupsProvider = StreamProvider<List<KatteGroup>>((ref) async* {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    yield const [];
    return;
  }

  final repository = ref.watch(groupRepositoryProvider);
  try {
    await repository.ensureUser(user);
    yield* repository.watchUserGroups(user);
  } on Object catch (error, stackTrace) {
    if (error is FirebaseException) {
      debugPrint(
        'Group load failed [${error.code}]: ${error.message}\n$stackTrace',
      );
    } else {
      debugPrint('Group load failed: $error\n$stackTrace');
    }
    Error.throwWithStackTrace(
      const GroupOperationException('グループを読み込めませんでした。'),
      stackTrace,
    );
  }
}, retry: (_, _) => null);

final currentGroupIdProvider =
    NotifierProvider<CurrentGroupController, String?>(
      CurrentGroupController.new,
    );

class CurrentGroupController extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(authStateProvider).value?.uid;
    return null;
  }

  void select(String groupId) {
    state = groupId;
  }

  void clear() {
    state = '';
  }
}

final currentGroupProvider = Provider<KatteGroup?>((ref) {
  final groups = ref.watch(userGroupsProvider).value ?? const [];
  if (groups.isEmpty) {
    return null;
  }
  final selectedId = ref.watch(currentGroupIdProvider);
  if (selectedId == '') {
    return null;
  }
  return groups.where((group) => group.id == selectedId).firstOrNull ??
      groups.first;
});

final groupMembersProvider = StreamProvider<List<GroupMember>>((ref) {
  final group = ref.watch(currentGroupProvider);
  if (group == null) {
    return Stream.value(const []);
  }
  return ref.watch(groupRepositoryProvider).watchMembers(group.id);
}, retry: (_, _) => null);

final groupControllerProvider =
    NotifierProvider<GroupController, AsyncValue<void>>(GroupController.new);

class GroupController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> createGroup(String name) {
    return _run(
      (repository, user) => repository.createGroup(user: user, name: name),
      failureMessage: 'グループを作成できませんでした。',
      successEvent: KatteAnalyticsEvent.groupCreated,
    );
  }

  Future<bool> joinGroup(String inviteCode) {
    return _run(
      (repository, user) =>
          repository.joinGroup(user: user, inviteCode: inviteCode),
      failureMessage: 'グループに参加できませんでした。',
      successEvent: KatteAnalyticsEvent.groupJoined,
    );
  }

  Future<bool> deleteCurrentGroup() {
    return _runRemoval(
      (repository, user, group) => repository.deleteGroup(groupId: group.id),
      failureMessage: 'グループを削除できませんでした。',
      successEvent: KatteAnalyticsEvent.groupDeleted,
    );
  }

  Future<bool> leaveCurrentGroup() {
    return _runRemoval(
      (repository, user, group) =>
          repository.leaveGroup(groupId: group.id, user: user),
      failureMessage: 'グループから退出できませんでした。',
      successEvent: KatteAnalyticsEvent.groupLeft,
    );
  }

  Future<bool> _run(
    Future<KatteGroup> Function(GroupRepository repository, AuthUser user)
    action, {
    required String failureMessage,
    required KatteAnalyticsEvent successEvent,
  }) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) {
      state = AsyncError(
        const GroupOperationException('ログイン状態を確認できませんでした。'),
        StackTrace.current,
      );
      return false;
    }

    state = const AsyncLoading();
    try {
      final group = await action(ref.read(groupRepositoryProvider), user);
      ref.read(currentGroupIdProvider.notifier).select(group.id);
      await ref.read(analyticsServiceProvider).log(successEvent);
      state = const AsyncData(null);
      return true;
    } on GroupNotFoundException catch (_, stackTrace) {
      state = AsyncError(
        const GroupOperationException('グループが見つかりませんでした。'),
        stackTrace,
      );
      return false;
    } on AlreadyGroupMemberException catch (_, stackTrace) {
      state = AsyncError(
        const GroupOperationException('このグループには参加済みです。'),
        stackTrace,
      );
      return false;
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Group operation failed: $error\n$stackTrace');
      state = AsyncError(GroupOperationException(failureMessage), stackTrace);
      return false;
    } on Object catch (error, stackTrace) {
      debugPrint('Group operation failed: $error\n$stackTrace');
      state = AsyncError(GroupOperationException(failureMessage), stackTrace);
      return false;
    }
  }

  Future<bool> _runRemoval(
    Future<void> Function(
      GroupRepository repository,
      AuthUser user,
      KatteGroup group,
    )
    action, {
    required String failureMessage,
    required KatteAnalyticsEvent successEvent,
  }) async {
    final user = ref.read(authStateProvider).value;
    final group = ref.read(currentGroupProvider);
    if (user == null || group == null) {
      state = AsyncError(
        const GroupOperationException('グループを確認できませんでした。'),
        StackTrace.current,
      );
      return false;
    }

    state = const AsyncLoading();
    try {
      await action(ref.read(groupRepositoryProvider), user, group);
      final remainingGroups = (ref.read(userGroupsProvider).value ?? const [])
          .where((candidate) => candidate.id != group.id)
          .toList(growable: false);
      final selection = ref.read(currentGroupIdProvider.notifier);
      if (remainingGroups.isEmpty) {
        selection.clear();
      } else {
        selection.select(remainingGroups.first.id);
      }
      ref.invalidate(groupMembersProvider);
      ref.invalidate(userGroupsProvider);
      await ref.read(analyticsServiceProvider).log(successEvent);
      state = const AsyncData(null);
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('Group removal failed: $error\n$stackTrace');
      state = AsyncError(GroupOperationException(failureMessage), stackTrace);
      return false;
    }
  }
}

class GroupOperationException implements Exception {
  const GroupOperationException(this.message);

  final String message;

  @override
  String toString() => message;
}
