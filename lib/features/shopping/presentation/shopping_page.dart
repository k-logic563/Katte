import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/shopping_item.dart';
import '../shopping_providers.dart';

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
    final items = ref.watch(shoppingItemsProvider);
    final isShopping = ref.watch(shoppingModeProvider);
    final pendingItems = items.where((item) => !item.isPurchased);
    final purchasedItems = items.where((item) => item.isPurchased);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Text('岩田家', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 24),
        if (isShopping) ...[
          const _ShoppingModeCard(),
          const SizedBox(height: 24),
        ],
        Text('買ってきてほしいもの', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _EmptyState(onAdd: () => _openAddItemSheet(context))
        else ...[
          for (final item in pendingItems) _ShoppingItemTile(item: item),
          for (final item in purchasedItems)
            Opacity(opacity: 0.55, child: _ShoppingItemTile(item: item)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('open-add-item-sheet-button'),
              onPressed: () => _openAddItemSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('買ってきてほしいもの'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (!isShopping)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('start-shopping-button'),
              onPressed: () => ref.read(shoppingModeProvider.notifier).toggle(),
              icon: const Icon(Icons.shopping_cart_outlined),
              label: const Text('買い物をはじめる'),
            ),
          ),
      ],
    );
  }
}

class _ShoppingItemTile extends ConsumerWidget {
  const _ShoppingItemTile({required this.item});

  final ShoppingItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quantity = item.quantity == null ? '' : ' ×${item.quantity}';
    final detail = item.isPurchased
        ? '${item.createdBy} → ${item.purchasedBy}が購入'
        : '${item.createdBy} ・ ${_timeAgo(item.createdAt)}';
    final details = [detail, ?item.note];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        key: Key('purchase-${item.id}'),
        controlAffinity: ListTileControlAffinity.leading,
        value: item.isPurchased,
        onChanged: (_) {
          ref.read(shoppingItemsProvider.notifier).togglePurchased(item.id);
        },
        title: Text(
          '${item.name}$quantity',
          style: TextStyle(
            decoration: item.isPurchased ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(details.join('\n')),
      ),
    );
  }
}

class _ShoppingModeCard extends ConsumerWidget {
  const _ShoppingModeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_cart),
                const SizedBox(width: 8),
                Text('買い物中', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 8),
            const Text('買い忘れがないか確認しよう'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('finish-shopping-button'),
                onPressed: () =>
                    ref.read(shoppingModeProvider.notifier).toggle(),
                child: const Text('買い物を終了'),
              ),
            ),
          ],
        ),
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

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final quantityText = _quantityController.text.trim();
    final note = _noteController.text.trim();
    ref
        .read(shoppingItemsProvider.notifier)
        .addItem(
          name: _nameController.text.trim(),
          quantity: quantityText.isEmpty ? null : int.parse(quantityText),
          note: note.isEmpty ? null : note,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
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
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('add-item-button'),
              onPressed: _submit,
              child: const Text('追加する'),
            ),
          ],
        ),
      ),
    );
  }
}

String _timeAgo(DateTime createdAt) {
  final minutes = DateTime.now().difference(createdAt).inMinutes;
  if (minutes < 1) {
    return 'たった今';
  }
  if (minutes < 60) {
    return '$minutes分前';
  }
  return '${minutes ~/ 60}時間前';
}
