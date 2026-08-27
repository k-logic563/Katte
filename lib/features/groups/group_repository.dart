import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/application/auth_service.dart';
import 'models/katte_group.dart';

const fallbackUserDisplayName = 'ユーザー';

abstract interface class GroupRepository {
  Future<void> ensureUser(AuthUser user);

  Stream<List<KatteGroup>> watchUserGroups(AuthUser user);

  Future<KatteGroup> createGroup({
    required AuthUser user,
    required String name,
  });

  Future<KatteGroup> joinGroup({
    required AuthUser user,
    required String inviteCode,
  });

  Stream<List<GroupMember>> watchMembers(String groupId);
}

class GroupNotFoundException implements Exception {}

class AlreadyGroupMemberException implements Exception {}

class InviteCodeGenerationException implements Exception {}

class FirestoreGroupRepository implements GroupRepository {
  FirestoreGroupRepository({FirebaseFirestore? firestore, Random? random})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _random = random ?? Random.secure();

  static const _inviteCharacters = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const _inviteCodeLength = 6;
  static const _inviteGenerationAttempts = 8;

  final FirebaseFirestore _firestore;
  final Random _random;

  @override
  Future<void> ensureUser(AuthUser user) async {
    final reference = _firestore.collection('users').doc(user.uid);
    final snapshot = await reference.get();
    final profile = <String, Object?>{
      'displayName': user.displayName,
      'email': user.email,
      'photoUrl': user.photoUrl,
    };

    if (!snapshot.exists) {
      await reference.set({
        ...profile,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final current = snapshot.data();
    final changed = profile.entries.any(
      (entry) => current?[entry.key] != entry.value,
    );
    if (changed) {
      await reference.update({
        ...profile,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Stream<List<KatteGroup>> watchUserGroups(AuthUser user) {
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('groups')
        .snapshots()
        .asyncMap((snapshot) async {
          final groups = await Future.wait(
            snapshot.docs.map((membership) async {
              final groupId = membership.id;
              final group = await _firestore
                  .collection('groups')
                  .doc(groupId)
                  .get();
              if (!group.exists) {
                return null;
              }
              return _groupFromDocument(group);
            }),
          );
          return groups.whereType<KatteGroup>().toList(growable: false)
            ..sort((first, second) => first.name.compareTo(second.name));
        });
  }

  @override
  Future<KatteGroup> createGroup({
    required AuthUser user,
    required String name,
  }) async {
    for (var attempt = 0; attempt < _inviteGenerationAttempts; attempt++) {
      final groupReference = _firestore.collection('groups').doc();
      final inviteCode = _generateInviteCode();
      final inviteReference = _firestore
          .collection('groupInvites')
          .doc(inviteCode);
      final memberReference = groupReference
          .collection('members')
          .doc(user.uid);
      final userGroupReference = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('groups')
          .doc(groupReference.id);

      try {
        await _firestore.runTransaction((transaction) async {
          final invite = await transaction.get(inviteReference);
          if (invite.exists) {
            throw InviteCodeGenerationException();
          }

          transaction.set(groupReference, {
            'name': name,
            'createdBy': user.uid,
            'inviteCode': inviteCode,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          transaction.set(
            memberReference,
            _memberData(
              user: user,
              role: GroupMemberRole.owner,
              inviteCode: inviteCode,
            ),
          );
          transaction.set(userGroupReference, {
            'groupId': groupReference.id,
            'role': GroupMemberRole.owner.name,
            'joinedAt': FieldValue.serverTimestamp(),
          });
          transaction.set(inviteReference, {
            'groupId': groupReference.id,
            'createdAt': FieldValue.serverTimestamp(),
          });
        });
        return KatteGroup(
          id: groupReference.id,
          name: name,
          createdBy: user.uid,
          inviteCode: inviteCode,
        );
      } on InviteCodeGenerationException {
        continue;
      }
    }
    throw InviteCodeGenerationException();
  }

  @override
  Future<KatteGroup> joinGroup({
    required AuthUser user,
    required String inviteCode,
  }) async {
    final normalizedCode = inviteCode.trim().toUpperCase();
    final inviteReference = _firestore
        .collection('groupInvites')
        .doc(normalizedCode);
    late String groupId;

    await _firestore.runTransaction((transaction) async {
      final invite = await transaction.get(inviteReference);
      if (!invite.exists) {
        throw GroupNotFoundException();
      }
      final inviteData = invite.data();
      final value = inviteData?['groupId'];
      if (value is! String || value.isEmpty) {
        throw GroupNotFoundException();
      }
      groupId = value;

      final userGroupReference = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('groups')
          .doc(groupId);
      final membership = await transaction.get(userGroupReference);
      if (membership.exists) {
        throw AlreadyGroupMemberException();
      }

      final memberReference = _firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(user.uid);
      transaction.set(
        memberReference,
        _memberData(
          user: user,
          role: GroupMemberRole.member,
          inviteCode: normalizedCode,
        ),
      );
      transaction.set(userGroupReference, {
        'groupId': groupId,
        'role': GroupMemberRole.member.name,
        'joinedAt': FieldValue.serverTimestamp(),
      });
    });

    final group = await _firestore.collection('groups').doc(groupId).get();
    if (!group.exists) {
      throw GroupNotFoundException();
    }
    return _groupFromDocument(group);
  }

  @override
  Stream<List<GroupMember>> watchMembers(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .orderBy('joinedAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((document) {
                final data = document.data();
                return GroupMember(
                  userId: document.id,
                  displayName: _stringOrFallback(data['displayName']),
                  photoUrl: data['photoUrl'] as String?,
                  role: data['role'] == 'owner'
                      ? GroupMemberRole.owner
                      : GroupMemberRole.member,
                );
              })
              .toList(growable: false),
        );
  }

  String _generateInviteCode() {
    return List.generate(
      _inviteCodeLength,
      (_) => _inviteCharacters[_random.nextInt(_inviteCharacters.length)],
    ).join();
  }
}

Map<String, Object?> _memberData({
  required AuthUser user,
  required GroupMemberRole role,
  required String inviteCode,
}) {
  return {
    'userId': user.uid,
    'displayName': _displayName(user),
    'photoUrl': user.photoUrl,
    'role': role.name,
    'joinedWithInviteCode': inviteCode,
    'joinedAt': FieldValue.serverTimestamp(),
  };
}

KatteGroup _groupFromDocument(DocumentSnapshot<Map<String, dynamic>> document) {
  final data = document.data();
  if (data == null) {
    throw const FormatException('Group data is missing.');
  }
  return KatteGroup(
    id: document.id,
    name: _requiredString(data, 'name'),
    createdBy: _requiredString(data, 'createdBy'),
    inviteCode: _requiredString(data, 'inviteCode'),
  );
}

String _requiredString(Map<String, dynamic> data, String field) {
  final value = data[field];
  if (value is! String || value.isEmpty) {
    throw FormatException('$field is invalid.');
  }
  return value;
}

String _displayName(AuthUser user) {
  final displayName = user.displayName?.trim();
  return displayName == null || displayName.isEmpty
      ? fallbackUserDisplayName
      : displayName;
}

String _stringOrFallback(Object? value) {
  return value is String && value.trim().isNotEmpty
      ? value
      : fallbackUserDisplayName;
}
