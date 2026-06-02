import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/dua_category_icons.dart';
import '../constants/muslim_colors.dart';
import '../models/muslim_models.dart';
import '../providers/muslim_providers.dart';
import '../utils/muslim_localization.dart';
import '../widgets/muslim_widgets.dart';
import 'duaa_category_screen.dart';

class DuaaScreen extends ConsumerWidget {
  const DuaaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(duaI18nReadyProvider);
    final categoriesAsync = ref.watch(duaCategoriesProvider);

    return MuslimScreenScaffold(
      title: 'muslim_duaa'.tr(),
      onRefresh: () async {
        ref.invalidate(duaCategoriesProvider);
        await ref.read(duaCategoriesProvider.future);
      },
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(duaCategoriesProvider),
            child: Text('muslim_retry'.tr()),
          ),
        ),
        data: (categories) {
          final journey = categories
              .where((c) => journeyDuaCategoryIds.contains(c.id))
              .toList()
            ..sort(
              (a, b) => journeyDuaCategoryIds
                  .indexOf(a.id)
                  .compareTo(journeyDuaCategoryIds.indexOf(b.id)),
            );
          final other = categories
              .where((c) => !journeyDuaCategoryIds.contains(c.id))
              .toList();

          return ListView(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
            children: [
              if (journey.isNotEmpty) ...[
                _SectionHeader(title: 'muslim_duaa_journey'.tr()),
                SizedBox(height: 12.h),
                ...journey.map(
                  (cat) => _CategoryTile(
                    category: cat,
                    highlighted: true,
                    onTap: () => _openCategory(context, cat),
                  ),
                ),
                SizedBox(height: 20.h),
              ],
              if (other.isNotEmpty) ...[
                _SectionHeader(title: 'muslim_all_categories'.tr()),
                SizedBox(height: 12.h),
                ...other.map(
                  (cat) => _CategoryTile(
                    category: cat,
                    onTap: () => _openCategory(context, cat),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _openCategory(BuildContext context, DuaCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DuaaCategoryScreen(category: category),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: context.mPrimary.withValues(alpha: 0.85),
          ),
        ),
        SizedBox(height: 6.h),
        Container(
          width: 48.w,
          height: 4.h,
          decoration: BoxDecoration(
            color: context.mSecondaryContainer,
            borderRadius: BorderRadius.circular(2.r),
          ),
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.onTap,
    this.highlighted = false,
  });

  final DuaCategory category;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final icon = duaCategoryIcon(category.id);

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Material(
        color: highlighted
            ? context.mSurfaceContainerLow
            : context.mSurfaceContainerLowest,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14.r),
          child: Container(
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(
                color: context.mPrimary.withValues(alpha: highlighted ? 0.12 : 0.06),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48.w,
                  height: 48.w,
                  decoration: BoxDecoration(
                    color: context.mPrimaryContainer,
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: 24.w,
                    color: context.mOnPrimaryContainer,
                  ),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizedDuaCategoryName(category),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: context.mOnSurface,
                        ),
                      ),
                      if (category.description.isNotEmpty)
                        Text(
                          localizedDuaCategoryDescription(category),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12.sp,
                            color: context.mOnSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: context.mSecondaryContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999.r),
                  ),
                  child: Text(
                    '${category.count}',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: context.mSecondary,
                    ),
                  ),
                ),
                SizedBox(width: 4.w),
                muslimForwardChevron(
                  size: 20.w,
                  color: context.mPrimary.withValues(alpha: 0.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

