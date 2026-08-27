import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/application/auth_service.dart';
import 'models/shopping_item.dart';

const fallbackUserDisplayName = 'ユーザー';

abstract interface class ShoppingRepository {
  Stream<List<ShoppingItem>> watchPendingItems(String groupId);

  Stream<List<ShoppingItem>> watchPurchasedItems(String groupId);

  Future<void> addItem({
    required String groupId,
    required AuthUser user,
    required String name,
    required int quantity,
    required String note,
  });

  Future<void> setPurchased({
    required String groupId,
    required AuthUser user,
    required String itemId,
    required bool isPurchased,
  });

  Future<void> deleteItem({required String groupId, required String itemId});
}

class FirestoreShoppingRepository implements ShoppingRepository {
  FirestoreShoppingRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _itemsCollection(String groupId) {
    return _firestore.collection('groups').doc(groupId).collection('items');
  }

  @override
  Stream<List<ShoppingItem>> watchPendingItems(String groupId) {
    return _watchItems(
      groupId: groupId,
      status: ShoppingItemStatus.pending,
      orderBy: 'createdAt',
    );
  }

  @override
  Stream<List<ShoppingItem>> watchPurchasedItems(String groupId) {
    return _watchItems(
      groupId: groupId,
      status: ShoppingItemStatus.purchased,
      orderBy: 'purchasedAt',
    );
  }

  Stream<List<ShoppingItem>> _watchItems({
    required String groupId,
    required ShoppingItemStatus status,
    required String orderBy,
  }) {
    return _itemsCollection(groupId)
        .where('status', isEqualTo: status.name)
        .orderBy(orderBy, descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(ShoppingItem.fromFirestore)
              .toList(growable: false),
        );
  }

  @override
  Future<void> addItem({
    required String groupId,
    required AuthUser user,
    required String name,
    required int quantity,
    required String note,
  }) async {
    final item = ShoppingItem(
      id: '',
      name: name,
      quantity: quantity,
      note: note,
      status: ShoppingItemStatus.pending,
      createdBy: user.uid,
      createdByName: _displayName(user),
      createdAt: null,
      purchasedBy: null,
      purchasedByName: null,
      purchasedAt: null,
      updatedAt: null,
    );
    final data = item.toFirestore()
      ..['createdAt'] = FieldValue.serverTimestamp()
      ..['updatedAt'] = FieldValue.serverTimestamp();
    await _itemsCollection(groupId).add(data);
  }

  @override
  Future<void> setPurchased({
    required String groupId,
    required AuthUser user,
    required String itemId,
    required bool isPurchased,
  }) {
    return _itemsCollection(groupId).doc(itemId).update({
      'status': isPurchased ? 'purchased' : 'pending',
      'purchasedBy': isPurchased ? user.uid : null,
      'purchasedByName': isPurchased ? _displayName(user) : null,
      'purchasedAt': isPurchased ? FieldValue.serverTimestamp() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deleteItem({required String groupId, required String itemId}) {
    return _itemsCollection(groupId).doc(itemId).delete();
  }
}

String _displayName(AuthUser user) {
  final displayName = user.displayName?.trim();
  return displayName == null || displayName.isEmpty
      ? fallbackUserDisplayName
      : displayName;
}
