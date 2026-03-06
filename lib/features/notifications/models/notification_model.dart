import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Notification Model
// ─────────────────────────────────────────────────────────────────────────────

class AppNotification {
  final String id;
  final String type;
  final String title;
  final String message;
  final bool read;
  final DateTime createdAt;
  final Map<String, dynamic>? data;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.read,
    required this.createdAt,
    this.data,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['_id'] as String,
      type: json['type'] as String? ?? 'general',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      read: json['read'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      data: json['data'] as Map<String, dynamic>?,
    );
  }

  AppNotification copyWith({bool? read}) => AppNotification(
    id: id,
    type: type,
    title: title,
    message: message,
    read: read ?? this.read,
    createdAt: createdAt,
    data: data,
  );

  // ── Icon & color based on notification type ──────────────────────────────

  IconData get icon {
    switch (type) {
      case 'sos_alert':
        return Symbols.sos;
      case 'moderator_removed':
        return Symbols.person_remove;
      case 'moderator_left':
        return Symbols.logout;
      case 'moderator_request_approved':
        return Symbols.verified;
      case 'moderator_request_rejected':
        return Symbols.cancel;
      case 'invitation_accepted':
        return Symbols.check_circle;
      case 'invitation_declined':
        return Symbols.do_not_disturb_on;
      case 'group_invitation':
        return Symbols.mail;
      case 'suggested_area':
        return Symbols.pin_drop;
      case 'meetpoint':
        return Symbols.crisis_alert;
      case 'missed_call':
        return Symbols.phone_missed;
      case 'reminder':
        return Symbols.add_alarm;
      default:
        return Symbols.notifications;
    }
  }

  Color get iconColor {
    switch (type) {
      case 'sos_alert':
        return const Color(0xFFEF4444);
      case 'moderator_removed':
      case 'moderator_request_rejected':
      case 'invitation_declined':
        return const Color(0xFFEF4444);
      case 'moderator_request_approved':
      case 'invitation_accepted':
        return AppColors.primary;
      case 'moderator_left':
        return const Color(0xFF94A3B8);
      case 'group_invitation':
        return const Color(0xFF3B82F6);
      case 'suggested_area':
        return AppColors.primary;
      case 'meetpoint':
        return const Color(0xFFEF4444);
      case 'missed_call':
        return const Color(0xFFEF4444);
      case 'reminder':
        return const Color(0xFFF97316); // AppColors.primary (orange)
      default:
        return const Color(0xFF64748B);
    }
  }

  String get typeLabel {
    switch (type) {
      case 'sos_alert':
        return 'SOS Alert';
      case 'moderator_removed':
        return 'Removed';
      case 'moderator_left':
        return 'Left Group';
      case 'moderator_request_approved':
        return 'Approved';
      case 'moderator_request_rejected':
        return 'Rejected';
      case 'invitation_accepted':
        return 'Accepted';
      case 'invitation_declined':
        return 'Declined';
      case 'group_invitation':
        return 'Invitation';
      case 'suggested_area':
        return 'Suggested Area';
      case 'meetpoint':
        return 'Meetpoint';
      case 'missed_call':
        return 'Missed Call';
      case 'reminder':
        return 'Reminder';
      default:
        return 'Notification';
    }
  }

  bool get isTappable => type == 'sos_alert';
}
