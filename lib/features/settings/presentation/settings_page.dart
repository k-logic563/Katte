import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_providers.dart';
import '../../auth/application/auth_service.dart';
import '../../groups/group_providers.dart';
import '../../groups/presentation/group_setup_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

enum _AccountAction { idle, loggingOut, deletingAccount }

class _SettingsPageState extends ConsumerState<SettingsPage> {
  _AccountAction _accountAction = _AccountAction.idle;

  @override
  Widget build(BuildContext context) {
    final isLoggingOut = _accountAction == _AccountAction.loggingOut;
    final isDeletingAccount = _accountAction == _AccountAction.deletingAccount;
    final isAccountActionRunning = _accountAction != _AccountAction.idle;
    final user = switch (ref.watch(authStateProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final email = _userEmail(user);
    final currentGroup = ref.watch(currentGroupProvider);
    final groups = ref.watch(userGroupsProvider);

    ref.listen(authControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, stackTrace) {
          if (error is AccountDeletionBlockedException) {
            showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('アカウントを削除できません'),
                content: const Text(
                  'あなたが管理者になっているグループがあります。\n'
                  'アカウントを削除する前に、対象グループを削除してください。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('閉じる'),
                  ),
                ],
              ),
            );
            return;
          }
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text('処理を完了できませんでした。もう一度お試しください。')),
            );
        },
      );
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Text('設定', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 28),
        const _SectionTitle('アカウント'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: Text(_userName(user)),
          subtitle: email == null ? null : Text(email),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('logout-button'),
            onPressed: isAccountActionRunning ? null : _signOut,
            icon: isLoggingOut
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
            label: Text(isLoggingOut ? 'ログアウト中…' : 'ログアウト'),
          ),
        ),
        const Divider(),
        const _SectionTitle('グループ'),
        ...groups.when(
          skipLoadingOnReload: false,
          skipLoadingOnRefresh: false,
          skipError: false,
          loading: () => const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
          ],
          error: (_, _) => [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  const Text('グループを読み込めませんでした。'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(userGroupsProvider),
                    child: const Text('再試行'),
                  ),
                ],
              ),
            ),
          ],
          data: (groups) {
            final ordered = [...groups]
              ..sort((first, second) {
                if (first.id == currentGroup?.id) return -1;
                if (second.id == currentGroup?.id) return 1;
                return first.name.compareTo(second.name);
              });
            if (ordered.isEmpty) {
              return const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('グループがありません'),
                ),
              ];
            }
            return [
              for (final group in ordered)
                ListTile(
                  key: Key('settings-group-${group.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    group.id == currentGroup?.id
                        ? Icons.check_circle
                        : Icons.group_outlined,
                  ),
                  title: Text(
                    group.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: group.id == currentGroup?.id
                      ? const Text('現在使用中')
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/group-details/${group.id}'),
                ),
            ];
          },
        ),
        ListTile(
          key: const Key('settings-create-group-button'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.add),
          title: const Text('新しいグループを作る'),
          onTap: () => showCreateGroupSheet(context),
        ),
        ListTile(
          key: const Key('settings-join-group-button'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.group_add_outlined),
          title: const Text('招待コードで参加'),
          onTap: () => showJoinGroupSheet(context),
        ),
        const Divider(height: 32),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('バージョン'),
          trailing: Text('1.0.0'),
        ),
        const Divider(height: 32),
        const _SectionTitle('アカウント管理'),
        ListTile(
          key: const Key('delete-account-button'),
          contentPadding: EdgeInsets.zero,
          enabled: !isAccountActionRunning,
          leading: isDeletingAccount
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.delete_forever_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
          title: Text(
            isDeletingAccount ? 'アカウントを削除しています…' : 'アカウントを削除',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          onTap: isAccountActionRunning ? null : _confirmAccountDeletion,
        ),
      ],
    );
  }

  Future<void> _signOut() async {
    if (_accountAction != _AccountAction.idle) return;
    setState(() => _accountAction = _AccountAction.loggingOut);
    try {
      await ref.read(authControllerProvider.notifier).signOut();
    } finally {
      if (mounted) {
        setState(() => _accountAction = _AccountAction.idle);
      }
    }
  }

  Future<void> _confirmAccountDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('アカウントを削除しますか？'),
        content: const Text(
          'この操作を行うと、Katteのアカウント情報が削除されます。\n'
          'この操作は元に戻せません。',
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  key: const Key('confirm-delete-account'),
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  child: const Text('アカウントを削除'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('cancel-delete-account'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('キャンセル'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || _accountAction != _AccountAction.idle) return;

    setState(() => _accountAction = _AccountAction.deletingAccount);
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
    } finally {
      if (mounted) {
        setState(() => _accountAction = _AccountAction.idle);
      }
    }
  }
}

String _userName(AuthUser? user) {
  final displayName = user?.displayName?.trim();
  return displayName == null || displayName.isEmpty ? 'ユーザー' : displayName;
}

String? _userEmail(AuthUser? user) {
  final email = user?.email?.trim();
  return email == null || email.isEmpty ? null : email;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
