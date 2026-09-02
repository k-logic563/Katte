import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/application/auth_providers.dart';
import '../auth/application/auth_service.dart';
import '../monitoring/monitoring_providers.dart';
import '../monitoring/monitoring_services.dart';
import 'current_group_selection_store.dart';
import 'group_repository.dart';
import 'models/katte_group.dart';

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return FirestoreGroupRepository();
});

final currentGroupSelectionStoreProvider = Provider<CurrentGroupSelectionStore>(
  (ref) {
    return InMemoryCurrentGroupSelectionStore();
  },
);

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
    final userId = ref.watch(authStateProvider).value?.uid;
    if (userId == null) {
      return null;
    }
    return ref.watch(currentGroupSelectionStoreProvider).read(userId);
  }

  void select(String groupId) {
    state = groupId;
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId != null) {
      unawaited(_save(userId, groupId));
    }
  }

  void clear() {
    state = '';
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId != null) {
      unawaited(_clear(userId));
    }
  }

  Future<void> _save(String userId, String groupId) async {
    try {
      await ref.read(currentGroupSelectionStoreProvider).save(userId, groupId);
    } on Object catch (error, stackTrace) {
      debugPrint('Current group selection save failed: $error\n$stackTrace');
    }
  }

  Future<void> _clear(String userId) async {
    try {
      await ref.read(currentGroupSelectionStoreProvider).clear(userId);
    } on Object catch (error, stackTrace) {
      debugPrint('Current group selection clear failed: $error\n$stackTrace');
    }
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

final groupMembersByGroupProvider = StreamProvider.autoDispose
    .family<List<GroupMember>, String>((ref, groupId) {
      return ref.watch(groupRepositoryProvider).watchMembers(groupId);
    }, retry: (_, _) => null);

final groupMembersProvider = Provider<AsyncValue<List<GroupMember>>>((ref) {
  final groupId = ref.watch(currentGroupProvider)?.id;
  if (groupId == null) {
    return const AsyncData([]);
  }
  return ref.watch(groupMembersByGroupProvider(groupId));
});

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
    final group = ref.read(currentGroupProvider);
    if (group == null) {
      return _missingGroup();
    }
    return deleteGroup(group);
  }

  Future<bool> deleteGroup(KatteGroup group) {
    return _runRemoval(
      group,
      (repository, user, group) => repository.deleteGroup(groupId: group.id),
      failureMessage: 'グループを削除できませんでした。',
      successEvent: KatteAnalyticsEvent.groupDeleted,
    );
  }

  Future<bool> leaveCurrentGroup() {
    final group = ref.read(currentGroupProvider);
    if (group == null) {
      return _missingGroup();
    }
    return leaveGroup(group);
  }

  Future<bool> leaveGroup(KatteGroup group) {
    return _runRemoval(
      group,
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
    KatteGroup group,
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
    if (user == null) {
      state = AsyncError(
        const GroupOperationException('グループを確認できませんでした。'),
        StackTrace.current,
      );
      return false;
    }

    final wasCurrent = ref.read(currentGroupProvider)?.id == group.id;
    state = const AsyncLoading();
    try {
      await action(ref.read(groupRepositoryProvider), user, group);
      final remainingGroups = (ref.read(userGroupsProvider).value ?? const [])
          .where((candidate) => candidate.id != group.id)
          .toList(growable: false);
      if (wasCurrent) {
        final selection = ref.read(currentGroupIdProvider.notifier);
        if (remainingGroups.isEmpty) {
          selection.clear();
        } else {
          selection.select(remainingGroups.first.id);
        }
      }
      ref.invalidate(groupMembersByGroupProvider(group.id));
      await ref.read(analyticsServiceProvider).log(successEvent);
      state = const AsyncData(null);
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('Group removal failed: $error\n$stackTrace');
      state = AsyncError(GroupOperationException(failureMessage), stackTrace);
      return false;
    }
  }

  Future<bool> _missingGroup() async {
    state = AsyncError(
      const GroupOperationException('グループを確認できませんでした。'),
      StackTrace.current,
    );
    return false;
  }
}

class GroupOperationException implements Exception {
  const GroupOperationException(this.message);

  final String message;

  @override
  String toString() => message;
}
