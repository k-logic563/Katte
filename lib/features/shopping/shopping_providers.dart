import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/shopping_item.dart';

final shoppingItemsProvider =
    NotifierProvider<ShoppingItemsNotifier, List<ShoppingItem>>(
      ShoppingItemsNotifier.new,
    );

class ShoppingItemsNotifier extends Notifier<List<ShoppingItem>> {
  @override
  List<ShoppingItem> build() {
    final now = DateTime.now();
    return [
      ShoppingItem(
        id: 'milk',
        name: '牛乳',
        quantity: null,
        note: null,
        createdBy: '由美',
        createdAt: now.subtract(const Duration(minutes: 2)),
        isPurchased: false,
        purchasedBy: null,
      ),
      ShoppingItem(
        id: 'eggs',
        name: '卵',
        quantity: 2,
        note: null,
        createdBy: '康平',
        createdAt: now.subtract(const Duration(minutes: 10)),
        isPurchased: false,
        purchasedBy: null,
      ),
      ShoppingItem(
        id: 'tissues',
        name: 'ティッシュ',
        quantity: null,
        note: null,
        createdBy: '由美',
        createdAt: now.subtract(const Duration(minutes: 20)),
        isPurchased: false,
        purchasedBy: null,
      ),
    ];
  }

  void addItem({
    required String name,
    required int? quantity,
    required String? note,
  }) {
    state = [
      ShoppingItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        quantity: quantity,
        note: note,
        createdBy: '康平',
        createdAt: DateTime.now(),
        isPurchased: false,
        purchasedBy: null,
      ),
      ...state,
    ];
  }

  void togglePurchased(String id) {
    state = [
      for (final item in state)
        if (item.id == id)
          item.withPurchaseStatus(isPurchased: !item.isPurchased)
        else
          item,
    ];
  }
}

final shoppingModeProvider = NotifierProvider<ShoppingModeNotifier, bool>(
  ShoppingModeNotifier.new,
);

class ShoppingModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}
