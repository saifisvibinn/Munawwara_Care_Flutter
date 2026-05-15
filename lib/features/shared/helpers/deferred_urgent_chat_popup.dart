/// Holds an urgent chat payload from [SocketService] until the app is
/// [AppLifecycleState.resumed].
///
/// When [new_message] arrives in the background, FCM may show the system
/// notification while the socket handler skips [ChatNotificationHelper] because
/// [WidgetsBinding.instance.lifecycleState] is not resumed. Flushing this
/// queue on resume restores the in-app urgent UX when the user returns.
class DeferredUrgentChatPopup {
  static Map<String, dynamic>? _pending;

  static bool _mapIsUrgent(Map<String, dynamic> map) {
    final u = map['is_urgent'];
    return u == true || u == 1 || u?.toString() == 'true';
  }

  /// Stores [map] if urgent (latest wins).
  static void offerIfUrgent(Map<String, dynamic> map) {
    if (!_mapIsUrgent(map)) return;
    _pending = Map<String, dynamic>.from(map);
  }

  static Map<String, dynamic>? takePending() {
    final p = _pending;
    _pending = null;
    return p;
  }
}
