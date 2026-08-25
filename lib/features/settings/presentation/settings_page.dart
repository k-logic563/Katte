import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../auth/application/auth_service.dart';
import '../settings_providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationSettings = ref.watch(notificationSettingsProvider);
    final authAction = ref.watch(authControllerProvider);
    final user = switch (ref.watch(authStateProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final email = _userEmail(user);

    ref.listen(authControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, stackTrace) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(error.toString())));
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
        const _SectionTitle('通知'),
        SwitchListTile(
          key: const Key('item-added-notification-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('商品追加'),
          value: notificationSettings.itemAdded,
          onChanged: ref
              .read(notificationSettingsProvider.notifier)
              .setItemAdded,
        ),
        SwitchListTile(
          key: const Key('shopping-started-notification-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('買い物開始'),
          value: notificationSettings.shoppingStarted,
          onChanged: ref
              .read(notificationSettingsProvider.notifier)
              .setShoppingStarted,
        ),
        const Divider(),
        const _SectionTitle('グループ'),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.group_outlined),
          title: Text('岩田家'),
        ),
        const Divider(),
        const _SectionTitle('その他'),
        const ListTile(contentPadding: EdgeInsets.zero, title: Text('利用規約')),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('プライバシーポリシー'),
        ),
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
