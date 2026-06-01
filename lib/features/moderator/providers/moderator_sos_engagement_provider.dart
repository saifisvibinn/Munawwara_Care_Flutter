import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/moderator_sos_engagement_store.dart';

final moderatorSosEngagementProvider = AsyncNotifierProvider<
    ModeratorSosEngagementNotifier,
    List<ModeratorSosEngagementRecord>>(
  ModeratorSosEngagementNotifier.new,
);

class ModeratorSosEngagementNotifier
    extends AsyncNotifier<List<ModeratorSosEngagementRecord>> {
  @override
  Future<List<ModeratorSosEngagementRecord>> build() =>
      ModeratorSosEngagementStore.loadAll();

  Future<void> refresh() async {
    state = AsyncValue.data(await ModeratorSosEngagementStore.loadAll());
  }
}
