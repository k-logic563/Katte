import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_providers.dart';
import '../../auth/application/auth_service.dart';
import '../../groups/group_providers.dart';
import '../../groups/presentation/group_setup_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAction = ref.watch(authControllerProvider);
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
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text('ログアウトできませんでした。もう一度お試しください。')),
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
            onPressed: authAction.isLoading
                ? null
                : ref.read(authControllerProvider.notifier).signOut,
            icon: const Icon(Icons.logout),
            label: const Text('ログアウト'),
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
      ],
    );
  }
}

String _userName(AuthUser? user) {
  final displayName = user?.displayName?.trim();
  return displayName == null || displayName.isEmpty ? '名前未設定' : displayName;
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
