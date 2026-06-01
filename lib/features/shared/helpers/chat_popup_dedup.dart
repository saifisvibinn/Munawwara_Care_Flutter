import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences keys used by [ChatNotificationHelper]. Extracted here so
/// [MessageNotifier] can seed IDs after REST/cache loads without importing UI.
abstract final class ChatPopupDedup {
  static const lastPopupMsKey = 'chat_last_in_app_popup_ms_v1';
  static const notifiedIdsKey = 'chat_notified_message_ids_v1';
  static const maxNotifiedIds = 150;

  /// Seeds the notified-id ring buffer with message ids already in history,
  /// so socket replays after hot restart do not trigger popup/SFX again.
  static Future<void> mergeKnownMessageIds(Iterable<String> rawIds) async {
    final prefs = await SharedPreferences.getInstance();
    var list = prefs.getStringList(notifiedIdsKey) ?? [];
    for (final id in rawIds) {
      final s = id.trim();
      if (s.isEmpty || list.contains(s)) continue;
      list = [...list, s];
      if (list.length > maxNotifiedIds) {
        list = list.sublist(list.length - maxNotifiedIds);
      }
    }
    await prefs.setStringList(notifiedIdsKey, list);
  }
}
