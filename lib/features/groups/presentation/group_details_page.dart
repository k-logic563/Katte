import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../group_providers.dart';
import '../models/katte_group.dart';

class GroupDetailsPage extends ConsumerWidget {
  const GroupDetailsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(currentGroupProvider);
    final members = ref.watch(groupMembersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(group?.name ?? 'グループ')),
      body: group == null
          ? const Center(child: Text('グループを確認できませんでした。'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                Text('メンバー', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                members.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (_, _) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('メンバーを読み込めませんでした。'),
                  ),
                  data: (members) => Column(
                    key: const Key('group-member-list'),
                    children: [
                      for (final member in members)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(member.displayName),
                          trailing: member.role == GroupMemberRole.owner
                              ? const Text('オーナー')
                              : null,
                        ),
                    ],
                  ),
                ),
                const Divider(height: 40),
                Text('招待コード', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                SelectableText(
                  group.inviteCode,
                  key: const Key('group-invite-code'),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text('家族にこのコードを共有してください', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const Key('copy-invite-code-button'),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: group.inviteCode),
                    );
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('招待コードをコピーしました')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('コピー'),
                ),
              ],
            ),
    );
  }
}
