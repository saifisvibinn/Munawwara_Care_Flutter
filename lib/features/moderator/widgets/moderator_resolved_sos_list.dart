import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/moderator_resolved_sos_provider.dart';
import '../services/moderator_resolved_sos_store.dart';

/// List of moderator-resolved SOS incidents (newest first).
class ModeratorResolvedSosList extends ConsumerWidget {
  final bool isDark;

  const ModeratorResolvedSosList({super.key, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(moderatorResolvedSosProvider);
    final list = async.value ?? [];

    if (async.isLoading && list.isEmpty) {
      final h = MediaQuery.sizeOf(context).height;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          SizedBox(height: h * 0.28),
          const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ],
      );
    }

    if (list.isEmpty) {
      final h = MediaQuery.sizeOf(context).height;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          SizedBox(height: h * 0.28),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Text(
              'moderator_resolved_sos_empty'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : AppColors.textMutedDark,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
      itemCount: list.length,
      separatorBuilder: (_, _) => SizedBox(height: 10.h),
      itemBuilder: (ctx, i) {
        return _ResolvedSosTile(record: list[i], isDark: isDark);
      },
    );
  }
}

class _ResolvedSosTile extends StatelessWidget {
  final ModeratorResolvedSosRecord record;
  final bool isDark;

  const _ResolvedSosTile({required this.record, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final border = isDark ? AppColors.dividerDark : AppColors.dividerLight;
    final titleColor = isDark ? Colors.white : AppColors.textDark;
    final muted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final when = DateTime.fromMillisecondsSinceEpoch(record.resolvedAtMs);
    final whenLabel = DateFormat.yMMMd().add_jm().format(when);

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Symbols.check_circle,
              color: AppColors.success,
              size: 20.w,
              fill: 1,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.pilgrimName.isEmpty ? '—' : record.pilgrimName,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 14.sp,
                    color: titleColor,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'moderator_resolved_sos_card_group'.tr(
                    namedArgs: {
                      'group': record.groupName.isEmpty ? '—' : record.groupName,
                    },
                  ),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    color: muted,
                    height: 1.35,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  'moderator_resolved_sos_card_time'.tr(
                    namedArgs: {'when': whenLabel},
                  ),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
