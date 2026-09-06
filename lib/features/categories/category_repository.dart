import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'models/shopping_category.dart';

abstract interface class CategoryRepository {
  Stream<List<ShoppingCategory>> watchCategories(String groupId);

  Future<void> createCategory({
    required String groupId,
    required String userId,
    required String name,
  });

  Future<void> renameCategory({
    required String groupId,
    required ShoppingCategory category,
    required String name,
  });

  Future<void> deleteCategory({
    required String groupId,
    required String categoryId,
  });
}

class FirestoreCategoryRepository implements CategoryRepository {
  FirestoreCategoryRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  DocumentReference<Map<String, dynamic>> _group(String groupId) =>
      _firestore.collection('groups').doc(groupId);

  @override
  Stream<List<ShoppingCategory>> watchCategories(String groupId) {
    return _group(groupId)
        .collection('categories')
        .orderBy('sortOrder')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(ShoppingCategory.fromFirestore)
              .where((category) => !category.isDeleting)
              .toList(growable: false),
        );
  }

  @override
  Future<void> createCategory({
    required String groupId,
    required String userId,
    required String name,
  }) async {
    final displayName = name.trim();
    if (validateCategoryName(name) != null) {
      throw const InvalidCategoryNameException();
    }
    final normalizedName = normalizeCategoryName(displayName);
    final group = _group(groupId);
    final category = group.collection('categories').doc();
    final nameReservation = group
        .collection('categoryNames')
        .doc(categoryNameDocumentId(normalizedName));
    await _firestore.runTransaction((transaction) async {
      if ((await transaction.get(nameReservation)).exists) {
        throw const DuplicateCategoryException();
      }
      final now = FieldValue.serverTimestamp();
      transaction.set(category, {
        'name': displayName,
        'normalizedName': normalizedName,
        'sortOrder': DateTime.now().microsecondsSinceEpoch,
        'createdBy': userId,
        'deleting': false,
        'createdAt': now,
        'updatedAt': now,
      });
      transaction.set(nameReservation, {
        'categoryId': category.id,
        'normalizedName': normalizedName,
      });
    });
  }

  @override
  Future<void> renameCategory({
    required String groupId,
    required ShoppingCategory category,
    required String name,
  }) async {
    final displayName = name.trim();
    if (validateCategoryName(name) != null) {
      throw const InvalidCategoryNameException();
    }
    final normalizedName = normalizeCategoryName(displayName);
    if (normalizedName == category.normalizedName) {
      await _group(groupId).collection('categories').doc(category.id).update({
        'name': displayName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }
    final group = _group(groupId);
    final oldReservation = group
        .collection('categoryNames')
        .doc(categoryNameDocumentId(category.normalizedName));
    final newReservation = group
        .collection('categoryNames')
        .doc(categoryNameDocumentId(normalizedName));
    final categoryReference = group.collection('categories').doc(category.id);
    await _firestore.runTransaction((transaction) async {
      if ((await transaction.get(newReservation)).exists) {
        throw const DuplicateCategoryException();
      }
      transaction.update(categoryReference, {
        'name': displayName,
        'normalizedName': normalizedName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.delete(oldReservation);
      transaction.set(newReservation, {
        'categoryId': category.id,
        'normalizedName': normalizedName,
      });
    });
  }

  @override
  Future<void> deleteCategory({
    required String groupId,
    required String categoryId,
  }) async {
    await _functions.httpsCallable('deleteCategory').call<void>({
      'groupId': groupId,
      'categoryId': categoryId,
    });
  }
}

class DuplicateCategoryException implements Exception {
  const DuplicateCategoryException();
}

class InvalidCategoryNameException implements Exception {
  const InvalidCategoryNameException();
}

String categoryNameDocumentId(String name) => base64Url
    .encode(utf8.encode(normalizeCategoryName(name)))
    .replaceAll('=', '');
