import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../groups/group_providers.dart';
import '../models/shopping_item.dart';
import '../shopping_providers.dart';
import '../shopping_repository.dart';

class PurchaseHistoryPage extends ConsumerWidget {
  const PurchaseHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(purchasedShoppingItemsProvider);
    final groupId = ref.watch(currentGroupProvider)?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('購入履歴')),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _HistoryLoadError(
          onRetry: () {
            if (groupId != null) {
              ref.invalidate(purchasedShoppingItemsByGroupProvider(groupId));
            }
          },
        ),
        data: (items) => items.isEmpty
            ? const Center(child: Text('購入履歴はまだありません'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) =>
                    _HistoryItemTile(item: items[index]),
              ),
      ),
    );
  }
}

class _HistoryItemTile extends ConsumerStatefulWidget {
  const _HistoryItemTile({required this.item});

  final ShoppingItem item;

  @override
  ConsumerState<_HistoryItemTile> createState() => _HistoryItemTileState();
}

class _HistoryItemTileState extends ConsumerState<_HistoryItemTile> {
  var _isUpdating = false;

  Future<void> _restore() async {
    if (_isUpdating) {
      return;
    }
    setState(() => _isUpdating = true);
    final succeeded = await ref
        .read(shoppingControllerProvider.notifier)
        .setPurchased(itemId: widget.item.id, isPurchased: false);
    if (!mounted) {
      return;
    }
    setState(() => _isUpdating = false);
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            succeeded
                ? '${widget.item.name}を買い物リストに戻しました'
                : '未購入に戻せませんでした。もう一度お試しください。',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final quantity = item.quantity == 1 ? '' : ' ×${item.quantity}';
    final purchaser = item.purchasedByName ?? fallbackUserDisplayName;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: const Icon(Icons.check_circle_outline),
      title: Text(
        '${item.name}$quantity',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: Text(
        '$purchaser ・ ${_formatPurchasedAt(item.purchasedAt)}',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      trailing: PopupMenuButton<_HistoryAction>(
        key: Key('history-menu-${item.id}'),
        tooltip: '商品メニュー',
        enabled: !_isUpdating,
        onSelected: (action) async {
          if (action != _HistoryAction.restoreToPending) {
            return;
          }
          await _restore();
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            key: Key('restore-history-item'),
            value: _HistoryAction.restoreToPending,
            child: Text('未購入に戻す'),
          ),
        ],
      ),
    );
  }
}

enum _HistoryAction { restoreToPending }

class _HistoryLoadError extends StatelessWidget {
  const _HistoryLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('購入履歴を読み込めませんでした。'),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('再試行')),
        ],
      ),
    );
  }
}

String _formatPurchasedAt(DateTime? purchasedAt) {
  if (purchasedAt == null) {
    return '購入日時不明';
  }

  final local = purchasedAt.toLocal();
  final now = DateTime.now();
  final isToday =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  final yesterday = now.subtract(const Duration(days: 1));
  final isYesterday =
      local.year == yesterday.year &&
      local.month == yesterday.month &&
      local.day == yesterday.day;
  final date = isToday
      ? '今日'
      : isYesterday
      ? '昨日'
      : '${local.month}/${local.day}';
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$date $hour:$minute';
}
