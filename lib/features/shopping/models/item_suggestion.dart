import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

class ItemSuggestion {
  const ItemSuggestion({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.useCount,
    required this.lastUsedAt,
  });

  factory ItemSuggestion.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return ItemSuggestion(
      id: document.id,
      name: data['name'] as String,
      normalizedName: data['normalizedName'] as String,
      useCount: data['useCount'] as int,
      lastUsedAt: (data['lastUsedAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String name;
  final String normalizedName;
  final int useCount;
  final DateTime? lastUsedAt;
}

String normalizeSuggestionName(String name) {
  return name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

String itemSuggestionDocumentId(String normalizedName) {
  return base64Url.encode(utf8.encode(normalizedName)).replaceAll('=', '');
}

List<ItemSuggestion> rankItemSuggestions(
  List<ItemSuggestion> suggestions,
  String input, {
  int limit = 8,
}) {
  final normalizedInput = normalizeSuggestionName(input);
  final ranked = suggestions
      .where(
        (suggestion) =>
            normalizedInput.isEmpty ||
            suggestion.normalizedName.startsWith(normalizedInput),
      )
      .toList(growable: false);
  ranked.sort((left, right) {
    if (normalizedInput.isNotEmpty) {
      final leftExact = left.normalizedName == normalizedInput;
      final rightExact = right.normalizedName == normalizedInput;
      if (leftExact != rightExact) {
        return leftExact ? -1 : 1;
      }
    }
    final recentComparison = (right.lastUsedAt ?? _epoch).compareTo(
      left.lastUsedAt ?? _epoch,
    );
    if (recentComparison != 0) {
      return recentComparison;
    }
    final countComparison = right.useCount.compareTo(left.useCount);
    if (countComparison != 0) {
      return countComparison;
    }
    return left.name.compareTo(right.name);
  });
  return ranked.take(limit).toList(growable: false);
}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
