import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/call_history_api.dart';

/// Badge count for unread incoming missed calls (server-driven).
final missedCallsUnreadProvider =
    NotifierProvider<MissedCallsUnreadNotifier, int>(
  MissedCallsUnreadNotifier.new,
);

class MissedCallsUnreadNotifier extends Notifier<int> {
  @override
  int build() => 0;

  Future<void> refresh() async {
    state = await CallHistoryApi.fetchUnreadMissedCount();
  }
}
