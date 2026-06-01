import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models/muslim_models.dart';
import '../providers/muslim_providers.dart';
import '../utils/muslim_localization.dart';
import '../widgets/dua_card.dart';
import '../widgets/muslim_widgets.dart';

class DuaaCategoryScreen extends ConsumerWidget {
  const DuaaCategoryScreen({super.key, required this.category});

  final DuaCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(duaI18nReadyProvider);
    final duasAsync = ref.watch(duaCategoryItemsProvider(category.id));

    return MuslimScreenScaffold(
      title: localizedDuaCategoryName(category),
      onRefresh: () async {
        ref.invalidate(duaCategoryItemsProvider(category.id));
        await ref.read(duaCategoryItemsProvider(category.id).future);
      },
      body: duasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () =>
                ref.invalidate(duaCategoryItemsProvider(category.id)),
            child: Text('muslim_retry'.tr()),
          ),
        ),
        data: (duas) => ListView.separated(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
          itemCount: duas.length,
          separatorBuilder: (_, _) => SizedBox(height: 16.h),
          itemBuilder: (_, index) => DuaCard(dua: duas[index]),
        ),
      ),
    );
  }
}
