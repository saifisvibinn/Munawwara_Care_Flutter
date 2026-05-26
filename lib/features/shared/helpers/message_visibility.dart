import '../models/message_model.dart';

/// Whether a chat payload should be shown to [userId] (socket, popup, cache).
bool isRawMessageVisibleToUser(
  Map<String, dynamic> map,
  String userId, {
  bool isModerator = false,
}) {
  if (userId.isEmpty) return false;
  if (isModerator) return true;

  final recipientId = mongoIdString(map['recipient_id']);
  if (recipientId.isEmpty) return true;

  if (recipientId == userId) return true;

  final senderRaw = map['sender_id'];
  final senderId = senderRaw is Map
      ? mongoIdString(senderRaw['_id'])
      : mongoIdString(senderRaw);
  return senderId == userId;
}

/// Same rules for a parsed [GroupMessage].
bool isMessageVisibleToUser(
  GroupMessage msg,
  String userId, {
  bool isModerator = false,
}) {
  if (userId.isEmpty) return false;
  if (isModerator) return true;
  if (msg.isBroadcast) return true;
  final rid = msg.recipientId ?? '';
  if (rid.isEmpty) return true;
  if (rid == userId) return true;
  return msg.sender?.id == userId;
}
