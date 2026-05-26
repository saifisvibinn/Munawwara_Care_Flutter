// ─────────────────────────────────────────────────────────────────────────────
// GroupMessage  &  MessageSender  –  shared message data models
// ─────────────────────────────────────────────────────────────────────────────

import '../../../core/utils/app_logger.dart';

/// Normalizes Mongo/API/socket id fields to a plain hex string.
String mongoIdString(dynamic raw) {
  if (raw == null) return '';
  if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  if (raw is Map) {
    final o = raw[r'$oid'] ?? raw['oid'];
    if (o != null) return o.toString().trim();
  }
  return raw.toString().trim();
}

/// API / Mongo dates are UTC ISO strings; convert to device local for labels.
DateTime _parseCreatedAt(dynamic raw) {
  if (raw == null) return DateTime.now();
  if (raw is Map) {
    final d = raw[r'$date'];
    if (d != null) {
      if (d is int) {
        return DateTime.fromMillisecondsSinceEpoch(d, isUtc: true).toLocal();
      }
      final fromExt = DateTime.tryParse(d.toString());
      if (fromExt != null) return fromExt.toLocal();
    }
  }
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true).toLocal();
  }
  final parsed = DateTime.tryParse(raw.toString());
  if (parsed != null) return parsed.toLocal();
  return DateTime.now();
}

/// Quoted message preview stored with the new message (same group).
class MessageReplySnapshot {
  final String messageId;
  final String senderName;
  final String previewText;
  final String messageType;

  const MessageReplySnapshot({
    required this.messageId,
    required this.senderName,
    required this.previewText,
    required this.messageType,
  });

  factory MessageReplySnapshot.fromJson(Map<String, dynamic> j) {
    final mid = j['message_id'];
    return MessageReplySnapshot(
      messageId: mid == null ? '' : mongoIdString(mid),
      senderName: j['sender_name']?.toString() ?? '',
      previewText: j['preview_text']?.toString() ?? '',
      messageType: j['message_type']?.toString() ?? 'text',
    );
  }
}

class MessageSender {
  final String id;
  final String fullName;
  final String? role;

  const MessageSender({required this.id, required this.fullName, this.role});

  factory MessageSender.fromJson(Map<String, dynamic> j) {
    try {
      return MessageSender(
        id: j['_id']?.toString() ?? '',
        fullName: j['full_name']?.toString() ?? 'Unknown',
        role: j['role']?.toString(),
      );
    } catch (e) {
      AppLogger.w('[MessageSender] Error parsing fromJson: $e');
      return const MessageSender(id: '', fullName: 'Unknown');
    }
  }

  String get initial => fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
}

class GroupMessage {
  final String id;
  final String? clientMessageId;
  final String sendStatus; // 'sending' | 'sent' | 'failed'
  final String groupId;
  final String? recipientId; // null → broadcast to whole group
  final MessageSender? sender;
  final String senderModel; // 'User' | 'Pilgrim'
  final String type; // 'text' | 'voice' | 'tts' | 'meetpoint'
  final String? content;
  final String? mediaUrl; // GCS HTTPS URL or legacy uploads filename
  final String? audioUrl; // GCS URL for TTS messages
  final String? originalText; // TTS source text
  final bool isUrgent;
  final int duration; // seconds (voice)
  final Map<String, dynamic>?
  meetpointData; // { area_id, name, latitude, longitude }
  final DateTime createdAt;
  final MessageReplySnapshot? replySnapshot;

  const GroupMessage({
    required this.id,
    this.clientMessageId,
    this.sendStatus = 'sent',
    required this.groupId,
    this.recipientId,
    this.sender,
    required this.senderModel,
    required this.type,
    this.content,
    this.mediaUrl,
    this.audioUrl,
    this.originalText,
    required this.isUrgent,
    required this.duration,
    this.meetpointData,
    required this.createdAt,
    this.replySnapshot,
  });

  bool get isFromModerator => senderModel == 'User';
  bool get isBroadcast => recipientId == null;

  GroupMessage copyWith({
    String? id,
    String? clientMessageId,
    String? sendStatus,
    String? groupId,
    String? recipientId,
    MessageSender? sender,
    String? senderModel,
    String? type,
    String? content,
    String? mediaUrl,
    String? audioUrl,
    String? originalText,
    bool? isUrgent,
    int? duration,
    Map<String, dynamic>? meetpointData,
    DateTime? createdAt,
    MessageReplySnapshot? replySnapshot,
  }) =>
      GroupMessage(
        id: id ?? this.id,
        clientMessageId: clientMessageId ?? this.clientMessageId,
        sendStatus: sendStatus ?? this.sendStatus,
        groupId: groupId ?? this.groupId,
        recipientId: recipientId ?? this.recipientId,
        sender: sender ?? this.sender,
        senderModel: senderModel ?? this.senderModel,
        type: type ?? this.type,
        content: content ?? this.content,
        mediaUrl: mediaUrl ?? this.mediaUrl,
        audioUrl: audioUrl ?? this.audioUrl,
        originalText: originalText ?? this.originalText,
        isUrgent: isUrgent ?? this.isUrgent,
        duration: duration ?? this.duration,
        meetpointData: meetpointData ?? this.meetpointData,
        createdAt: createdAt ?? this.createdAt,
        replySnapshot: replySnapshot ?? this.replySnapshot,
      );

  factory GroupMessage.fromJson(Map<String, dynamic> j) {
    try {
      final senderRaw = j['sender_id'];
      MessageSender? sender;
      if (senderRaw is Map) {
        sender = MessageSender.fromJson(Map<String, dynamic>.from(senderRaw));
      }

      final mpRaw = j['meetpoint_data'];
      Map<String, dynamic>? meetpointData;
      if (mpRaw is Map) {
        meetpointData = Map<String, dynamic>.from(mpRaw);
      }

      MessageReplySnapshot? replySnapshot;
      final snapRaw = j['reply_snapshot'];
      if (snapRaw is Map) {
        final snap = MessageReplySnapshot.fromJson(
          Map<String, dynamic>.from(snapRaw),
        );
        if (snap.previewText.trim().isNotEmpty ||
            snap.senderName.trim().isNotEmpty) {
          replySnapshot = snap;
        }
      }

      return GroupMessage(
        id: mongoIdString(j['_id'] ?? j['id']),
        clientMessageId: j['client_message_id']?.toString() ?? j['clientMessageId']?.toString(),
        sendStatus: j['send_status']?.toString() ?? j['sendStatus']?.toString() ?? 'sent',
        groupId: mongoIdString(j['group_id']),
        recipientId: mongoIdString(j['recipient_id']).isEmpty
            ? null
            : mongoIdString(j['recipient_id']),
        sender: sender,
        senderModel: j['sender_model']?.toString() ?? 'User',
        type: j['type']?.toString() ?? 'text',
        content: j['content']?.toString(),
        mediaUrl: j['media_url']?.toString(),
        audioUrl: j['audio_url']?.toString(),
        originalText: j['original_text']?.toString(),
        isUrgent: j['is_urgent'] == true ||
            j['is_urgent'] == 1 ||
            j['is_urgent']?.toString() == 'true',
        duration: (j['duration'] as num?)?.toInt() ?? 0,
        meetpointData: meetpointData,
        createdAt: _parseCreatedAt(j['created_at']),
        replySnapshot: replySnapshot,
      );
    } catch (e) {
      AppLogger.w('[GroupMessage] Error parsing fromJson: $e');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'client_message_id': clientMessageId,
        'send_status': sendStatus,
        'group_id': groupId,
        'recipient_id': recipientId,
        'sender_model': senderModel,
        'type': type,
        'content': content,
        'media_url': mediaUrl,
        'audio_url': audioUrl,
        'original_text': originalText,
        'is_urgent': isUrgent,
        'duration': duration,
        'meetpoint_data': meetpointData,
        'created_at': createdAt.toUtc().toIso8601String(),
        'reply_snapshot': replySnapshot == null
            ? null
            : {
                'message_id': replySnapshot!.messageId,
                'sender_name': replySnapshot!.senderName,
                'preview_text': replySnapshot!.previewText,
                'message_type': replySnapshot!.messageType,
              },
        'sender_id': sender == null
            ? null
            : {
                '_id': sender!.id,
                'full_name': sender!.fullName,
                'role': sender!.role,
              },
      };
}

/// Text suitable for the system clipboard (voice → empty).
String messagePlainTextForCopy(GroupMessage msg) {
  switch (msg.type) {
    case 'text':
      return msg.content ?? '';
    case 'tts':
      return msg.originalText ?? msg.content ?? '';
    case 'voice':
      return '';
    case 'meetpoint':
      final n = msg.meetpointData?['name']?.toString();
      if (n != null && n.isNotEmpty) return n;
      return msg.content ?? '';
    default:
      return msg.content ?? '';
  }
}
