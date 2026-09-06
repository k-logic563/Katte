import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_providers.dart';
import '../group_providers.dart';
import '../models/katte_group.dart';

class GroupDetailsPage extends ConsumerWidget {
  const GroupDetailsPage({this.groupId, super.key});

  final String? groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(userGroupsProvider).value ?? const [];
    final group = groupId == null
        ? ref.watch(currentGroupProvider)
        : groups.where((candidate) => candidate.id == groupId).firstOrNull;
    final members = group == null
        ? const AsyncValue<List<GroupMember>>.data([])
        : ref.watch(groupMembersByGroupProvider(group.id));
    final userId = ref.watch(authStateProvider).value?.uid;
    final currentMember = members.value
        ?.where((member) => member.userId == userId)
        .firstOrNull;
    final isProcessing = ref.watch(groupControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('グループ設定')),
      body: group == null
          ? const Center(child: Text('グループを確認できませんでした。'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                Text(
                  group.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                Text('メンバー', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                members.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (_, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        const Text('メンバーを読み込めませんでした。'),
                        const SizedBox(height: 4),
                        const Text('もう一度お試しください。'),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => ref.invalidate(
                            groupMembersByGroupProvider(group.id),
                          ),
                          child: const Text('再試行'),
                        ),
                      ],
                    ),
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
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(letterSpacing: 4),
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
                const Divider(height: 40),
                ListTile(
                  key: const Key('category-management-button'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('カテゴリ管理'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      context.push('/group-details/${group.id}/categories'),
                ),
                if (currentMember != null) ...[
                  const Divider(height: 48),
                  _GroupDangerAction(
                    role: currentMember.role,
                    isProcessing: isProcessing,
                    onPressed: () => _confirmGroupAction(
                      context: context,
                      ref: ref,
                      group: group,
                      role: currentMember.role,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _confirmGroupAction({
    required BuildContext context,
    required WidgetRef ref,
    required KatteGroup group,
    required GroupMemberRole role,
  }) async {
    final isOwner = role == GroupMemberRole.owner;
    final succeeded = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _GroupActionDialog(
        groupName: group.name,
        isOwner: isOwner,
        onConfirm: isOwner
            ? () =>
                  ref.read(groupControllerProvider.notifier).deleteGroup(group)
            : () =>
                  ref.read(groupControllerProvider.notifier).leaveGroup(group),
      ),
    );
    if (succeeded == true && context.mounted) {
      if (groupId != null) {
        context.go('/settings');
      } else {
        context.go('/shopping');
      }
    }
  }
}

class _GroupDangerAction extends StatelessWidget {
  const _GroupDangerAction({
    required this.role,
    required this.isProcessing,
    required this.onPressed,
  });

  final GroupMemberRole role;
  final bool isProcessing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isOwner = role == GroupMemberRole.owner;
    return OutlinedButton(
      key: Key(isOwner ? 'delete-group-button' : 'leave-group-button'),
      onPressed: isProcessing ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
        side: BorderSide(color: Theme.of(context).colorScheme.error),
      ),
      child: Text(isOwner ? 'グループを削除' : 'グループから退出'),
    );
  }
}

class _GroupActionDialog extends StatefulWidget {
  const _GroupActionDialog({
    required this.groupName,
    required this.isOwner,
    required this.onConfirm,
  });

  final String groupName;
  final bool isOwner;
  final Future<bool> Function() onConfirm;

  @override
  State<_GroupActionDialog> createState() => _GroupActionDialogState();
}

class _GroupActionDialogState extends State<_GroupActionDialog> {
  var _isSubmitting = false;
  String? _errorMessage;

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final succeeded = await widget.onConfirm();
    if (!mounted) {
      return;
    }
    if (succeeded) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _isSubmitting = false;
      _errorMessage = widget.isOwner ? 'グループを削除できませんでした' : 'グループから退出できませんでした';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.isOwner
            ? '${widget.groupName}を削除しますか？'
            : '${widget.groupName}から退出しますか？',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isOwner
                ? 'このグループの買い物リストや購入履歴も削除されます。\nこの操作は取り消せません。'
                : '退出すると、このグループの買い物リストは表示されなくなります。',
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
        TextButton(
          key: Key(
            widget.isOwner ? 'confirm-delete-group' : 'confirm-leave-group',
          ),
          onPressed: _isSubmitting ? null : _submit,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: _isSubmitting
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(widget.isOwner ? '削除中...' : '退出中...'),
                  ],
                )
              : Text(widget.isOwner ? '削除する' : '退出する'),
        ),
      ],
    );
  }
}
