import 'package:cloud_firestore/cloud_firestore.dart';

enum ShoppingItemStatus { pending, purchased }

class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.note,
    this.categoryId,
    required this.status,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    required this.purchasedBy,
    required this.purchasedByName,
    required this.purchasedAt,
    required this.updatedAt,
  });

  factory ShoppingItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw const FormatException('Shopping item data is missing.');
    }

    return ShoppingItem(
      id: document.id,
      name: _requiredString(data, 'name'),
      quantity: _requiredInt(data, 'quantity'),
      note: _requiredString(data, 'note'),
      categoryId: data['categoryId'] as String?,
      status: _statusFromFirestore(data['status']),
      createdBy: _requiredString(data, 'createdBy'),
      createdByName: _requiredString(data, 'createdByName'),
      createdAt: _dateTimeFromFirestore(data['createdAt']),
      purchasedBy: data['purchasedBy'] as String?,
      purchasedByName: data['purchasedByName'] as String?,
      purchasedAt: _dateTimeFromFirestore(data['purchasedAt']),
      updatedAt: _dateTimeFromFirestore(data['updatedAt']),
    );
  }

  final String id;
  final String name;
  final int quantity;
  final String note;
  final String? categoryId;
  final ShoppingItemStatus status;
  final String createdBy;
  final String createdByName;
  final DateTime? createdAt;
  final String? purchasedBy;
  final String? purchasedByName;
  final DateTime? purchasedAt;
  final DateTime? updatedAt;

  bool get isPurchased => status == ShoppingItemStatus.purchased;

  Map<String, Object?> toFirestore() {
    return {
      'name': name,
      'quantity': quantity,
      'note': note,
      'categoryId': categoryId,
      'status': status.name,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'purchasedBy': purchasedBy,
      'purchasedByName': purchasedByName,
      'purchasedAt': purchasedAt == null
          ? null
          : Timestamp.fromDate(purchasedAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
    };
  }
}

String _requiredString(Map<String, dynamic> data, String field) {
  final value = data[field];
  if (value is! String) {
    throw FormatException('$field is invalid.');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> data, String field) {
  final value = data[field];
  if (value is! int) {
    throw FormatException('$field is invalid.');
  }
  return value;
}

ShoppingItemStatus _statusFromFirestore(Object? value) {
  return switch (value) {
    'pending' => ShoppingItemStatus.pending,
    'purchased' => ShoppingItemStatus.purchased,
    _ => throw const FormatException('status is invalid.'),
  };
}

DateTime? _dateTimeFromFirestore(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! Timestamp) {
    throw const FormatException('timestamp is invalid.');
  }
  return value.toDate();
}
