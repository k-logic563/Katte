import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../groups/group_providers.dart';
import '../../groups/models/katte_group.dart';
import '../models/shopping_item.dart';
import '../shopping_providers.dart';
import '../shopping_repository.dart';

class ShoppingPage extends ConsumerWidget {
  const ShoppingPage({super.key});

  Future<void> _openAddItemSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _AddItemSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(pendingShoppingItemsProvider);
    final group = ref.watch(currentGroupProvider);
    final groups = ref.watch(userGroupsProvider).value ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('group-switch-button'),
                  onPressed: groups.isEmpty
                      ? null
                      : () => _openGroupSwitcher(context, ref, groups),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_drop_down),
                  label: Text(
                    group?.name ?? 'グループ',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
              ),
            ),
            IconButton(
              key: const Key('group-details-button'),
              tooltip: 'グループ情報',
              onPressed: () => context.push('/group-details'),
              icon: const Icon(Icons.group_outlined),
            ),
            IconButton(
              key: const Key('purchase-history-button'),
              tooltip: '購入履歴',
              onPressed: () => context.push('/purchase-history'),
              icon: const Icon(Icons.history),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ...items.when(
          loading: () => const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (_, _) => [
            _LoadError(
              onRetry: () => ref.invalidate(pendingShoppingItemsProvider),
            ),
          ],
          data: (items) => _buildItemList(
            items: items,
            onAdd: () => _openAddItemSheet(context),
            onPurchase: (item) => _purchaseItem(context, ref, item),
          ),
        ),
      ],
    );
  }

  Future<void> _openGroupSwitcher(
    BuildContext context,
    WidgetRef ref,
    List<KatteGroup> groups,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          for (final group in groups)
            ListTile(
              key: Key('select-group-${group.id}'),
              title: Text(group.name),
              trailing: group.id == ref.read(currentGroupProvider)?.id
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                ref.read(currentGroupIdProvider.notifier).select(group.id);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }

  List<Widget> _buildItemList({
    required List<ShoppingItem> items,
    required VoidCallback onAdd,
    required ValueChanged<ShoppingItem> onPurchase,
  }) {
    if (items.isEmpty) {
      return [_EmptyState(onAdd: onAdd)];
    }

    return [
      for (final item in items)
        _ShoppingItemTile(item: item, onPurchase: () => onPurchase(item)),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const Key('open-add-item-sheet-button'),
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('追加'),
        ),
      ),
    ];
  }

  Future<void> _purchaseItem(
    BuildContext context,
    WidgetRef ref,
    ShoppingItem item,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(shoppingControllerProvider.notifier);
    final succeeded = await controller.setPurchased(
      itemId: item.id,
      isPurchased: true,
    );
    if (!messenger.mounted) {
      return;
    }
    if (!succeeded) {
      messenger.showSnackBar(const SnackBar(content: Text('更新できませんでした。')));
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          persist: false,
          content: Text('${item.name}を購入済みにしました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () => _undoPurchase(
              controller: controller,
              messenger: messenger,
              itemId: item.id,
            ),
          ),
        ),
      );
  }

  Future<void> _undoPurchase({
    required ShoppingController controller,
    required ScaffoldMessengerState messenger,
    required String itemId,
  }) async {
    final succeeded = await controller.setPurchased(
      itemId: itemId,
      isPurchased: false,
    );
    if (!succeeded && messenger.mounted) {
      messenger.showSnackBar(const SnackBar(content: Text('元に戻せませんでした。')));
    }
  }
}

class _ShoppingItemTile extends ConsumerWidget {
  const _ShoppingItemTile({required this.item, required this.onPurchase});

  final ShoppingItem item;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUpdating = ref.watch(shoppingControllerProvider).isLoading;
    final quantity = item.quantity == 1 ? '' : ' ×${item.quantity}';
    final detail = item.isPurchased
        ? '${item.createdByName} → ${item.purchasedByName ?? fallbackUserDisplayName}が購入'
        : '${item.createdByName} ・ ${_timeAgo(item.createdAt)}';
    final details = [detail, if (item.note.isNotEmpty) item.note];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        key: Key('purchase-${item.id}'),
        controlAffinity: ListTileControlAffinity.leading,
        value: item.isPurchased,
        onChanged: isUpdating ? null : (_) => onPurchase(),
        title: Text(
          '${item.name}$quantity',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            decoration: item.isPurchased ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          details.join('\n'),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Text(
            '買い物リストを読み込めませんでした。',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text('もう一度お試しください。'),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('再試行')),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Text('今日はまだ何もありません', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const Text('買ってきてほしいものを\n追加してみよう。', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('追加する'),
          ),
        ],
      ),
    );
  }
}

class _AddItemSheet extends ConsumerStatefulWidget {
  const _AddItemSheet();

  @override
  ConsumerState<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<_AddItemSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final quantityText = _quantityController.text.trim();
    final note = _noteController.text.trim();
    setState(() => _errorMessage = null);
    final succeeded = await ref
        .read(shoppingControllerProvider.notifier)
        .addItem(
          name: _nameController.text.trim(),
          quantity: quantityText.isEmpty ? 1 : int.parse(quantityText),
          note: note,
        );
    if (!mounted) {
      return;
    }
    if (succeeded) {
      Navigator.of(context).pop();
    } else {
      setState(() => _errorMessage = '追加できませんでした。もう一度お試しください。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(shoppingControllerProvider).isLoading;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '買ってきてほしいもの',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('item-name-field'),
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: '商品名'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '商品名を入力してください';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('item-quantity-field'),
              controller: _quantityController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: '個数（任意）'),
              validator: (value) {
                final text = value?.trim() ?? '';
                final quantity = int.tryParse(text);
                if (text.isNotEmpty && (quantity == null || quantity < 1)) {
                  return '1以上の数字を入力してください';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('item-note-field'),
              controller: _noteController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'メモ（任意）'),
              onFieldSubmitted: (_) {
                if (!isSaving) {
                  _submit();
                }
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('add-item-button'),
              onPressed: isSaving ? null : _submit,
              child: isSaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('追加する'),
            ),
          ],
        ),
      ),
    );
  }
}

String _timeAgo(DateTime? createdAt) {
  if (createdAt == null) {
    return 'たった今';
  }
  final minutes = DateTime.now().difference(createdAt).inMinutes;
  if (minutes < 1) {
    return 'たった今';
  }
  if (minutes < 60) {
    return '$minutes分前';
  }
  return '${minutes ~/ 60}時間前';
}
