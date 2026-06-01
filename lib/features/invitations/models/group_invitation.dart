/// Pending group invitation returned by `GET /invitations`.
class GroupInvitation {
  final String id;
  final String inviteeEmail;
  final String status;
  final DateTime? createdAt;
  final String groupId;
  final String groupName;
  final String inviterName;

  const GroupInvitation({
    required this.id,
    required this.inviteeEmail,
    required this.status,
    this.createdAt,
    required this.groupId,
    required this.groupName,
    required this.inviterName,
  });

  factory GroupInvitation.fromJson(Map<String, dynamic> json) {
    final groupRaw = json['group_id'];
    String groupId = '';
    String groupName = '';
    if (groupRaw is Map<String, dynamic>) {
      groupId = groupRaw['_id']?.toString() ?? '';
      groupName = groupRaw['group_name']?.toString() ?? '';
    } else {
      groupId = groupRaw?.toString() ?? '';
    }

    final inviterRaw = json['inviter_id'];
    String inviterName = '';
    if (inviterRaw is Map<String, dynamic>) {
      inviterName = inviterRaw['full_name']?.toString() ?? '';
    }

    return GroupInvitation(
      id: json['_id']?.toString() ?? '',
      inviteeEmail: json['invitee_email']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      groupId: groupId,
      groupName: groupName,
      inviterName: inviterName,
    );
  }
}
