import 'package:cloud_firestore/cloud_firestore.dart';

class ShoppingCategory {
  const ShoppingCategory({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.sortOrder,
    required this.createdAt,
    this.isDeleting = false,
  });

  factory ShoppingCategory.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw const FormatException('Category data is missing.');
    }
    return ShoppingCategory(
      id: document.id,
      name: data['name'] as String,
      normalizedName: data['normalizedName'] as String,
      sortOrder: data['sortOrder'] as int,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      isDeleting: data['deleting'] == true,
    );
  }

  final String id;
  final String name;
  final String normalizedName;
  final int sortOrder;
  final DateTime? createdAt;
  final bool isDeleting;
}

String normalizeCategoryName(String name) => name.trim().toLowerCase();

const categoryNameMaxLength = 40;

String? validateCategoryName(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) {
    return 'カテゴリ名を入力してください';
  }
  if (name.contains('\n') || name.contains('\r')) {
    return '改行は使用できません';
  }
  if (name.length > categoryNameMaxLength) {
    return '$categoryNameMaxLength文字以内で入力してください';
  }
  return null;
}
