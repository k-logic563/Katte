class KatteGroup {
  const KatteGroup({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.inviteCode,
  });

  final String id;
  final String name;
  final String createdBy;
  final String inviteCode;
}

enum GroupMemberRole { owner, member }

class GroupMember {
  const GroupMember({
    required this.userId,
    required this.displayName,
    required this.photoUrl,
    required this.role,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final GroupMemberRole role;
}
