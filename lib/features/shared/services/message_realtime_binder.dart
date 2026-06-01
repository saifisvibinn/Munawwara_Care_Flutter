import '../../../core/services/socket_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../calling/calling_scope.dart';
import '../providers/message_provider.dart';

/// Global socket binding for chat delete events (pilgrim + moderator).
class MessageRealtimeBinder {
  MessageRealtimeBinder._();

  static bool _deleteListenerBound = false;

  /// Ensures [message_deleted] is handled even when a screen did not register.
  static void bindDeleteListener() {
    if (_deleteListenerBound) return;
    _deleteListenerBound = true;
    SocketService.on('message_deleted', _onMessageDeleted);
    AppLogger.i('[MessageRealtimeBinder] message_deleted listener bound');
  }

  static void _onMessageDeleted(dynamic data) {
    final c = CallingScope.riverpod;
    if (c == null) return;
    try {
      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      c.read(messageProvider.notifier).onMessageDeleted(map);
    } catch (e) {
      AppLogger.w('[MessageRealtimeBinder] message_deleted error: $e');
    }
  }
}
