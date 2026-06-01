import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/moderator_resolved_sos_store.dart';

final moderatorResolvedSosProvider = AsyncNotifierProvider<
    ModeratorResolvedSosNotifier,
    List<ModeratorResolvedSosRecord>>(ModeratorResolvedSosNotifier.new);

class ModeratorResolvedSosNotifier
    extends AsyncNotifier<List<ModeratorResolvedSosRecord>> {
  @override
  Future<List<ModeratorResolvedSosRecord>> build() =>
      ModeratorResolvedSosStore.loadAll();

  Future<void> refresh() async {
    state = AsyncValue.data(await ModeratorResolvedSosStore.loadAll());
  }

  Future<void> addResolved(ModeratorResolvedSosRecord record) async {
    await ModeratorResolvedSosStore.prepend(record);
    await refresh();
  }

  Future<void> clearAll() async {
    await ModeratorResolvedSosStore.clearAll();
    await refresh();
  }
}
