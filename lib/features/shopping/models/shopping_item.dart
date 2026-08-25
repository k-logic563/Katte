class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.note,
    required this.createdBy,
    required this.createdAt,
    required this.isPurchased,
    required this.purchasedBy,
  });

  final String id;
  final String name;
  final int? quantity;
  final String? note;
  final String createdBy;
  final DateTime createdAt;
  final bool isPurchased;
  final String? purchasedBy;

  ShoppingItem withPurchaseStatus({required bool isPurchased}) {
    return ShoppingItem(
      id: id,
      name: name,
      quantity: quantity,
      note: note,
      createdBy: createdBy,
      createdAt: createdAt,
      isPurchased: isPurchased,
      purchasedBy: isPurchased ? '康平' : null,
    );
  }
}
