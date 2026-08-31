import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/application/auth_service.dart';
import 'models/item_suggestion.dart';
import 'models/shopping_item.dart';

const fallbackUserDisplayName = 'ユーザー';

abstract interface class ShoppingRepository {
  Stream<List<ShoppingItem>> watchPendingItems(String groupId);

  Stream<List<ShoppingItem>> watchPurchasedItems(String groupId);

  Future<List<ItemSuggestion>> fetchItemSuggestions(String groupId);

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

  CollectionReference<Map<String, dynamic>> _suggestionsCollection(
    String groupId,
  ) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('itemSuggestions');
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
      limit: 100,
    );
  }

  @override
  Future<List<ItemSuggestion>> fetchItemSuggestions(String groupId) async {
    final snapshot = await _suggestionsCollection(groupId)
        .orderBy('lastUsedAt', descending: true)
        .limit(30)
        .get();
    return snapshot.docs
        .map(ItemSuggestion.fromFirestore)
        .toList(growable: false);
  }

  Stream<List<ShoppingItem>> _watchItems({
    required String groupId,
    required ShoppingItemStatus status,
    required String orderBy,
    int? limit,
  }) {
    var query = _itemsCollection(groupId)
        .where('status', isEqualTo: status.name)
        .orderBy(orderBy, descending: true);
    if (limit != null) {
      query = query.limit(limit);
    }
    return query.snapshots().map(
      (snapshot) =>
          snapshot.docs.map(ShoppingItem.fromFirestore).toList(growable: false),
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
    final displayName = name.trim();
    final normalizedName = normalizeSuggestionName(displayName);
    final item = ShoppingItem(
      id: '',
      name: displayName,
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
    final itemReference = _itemsCollection(groupId).doc();
    final suggestionReference = _suggestionsCollection(groupId)
        .doc(itemSuggestionDocumentId(normalizedName));
    final batch = _firestore.batch()
      ..set(itemReference, data)
      ..set(suggestionReference, {
        'name': displayName,
        'normalizedName': normalizedName,
        'useCount': FieldValue.increment(1),
        'lastUsedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    await batch.commit();
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
