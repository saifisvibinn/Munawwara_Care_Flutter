import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/pilgrim_provider.dart';

/// Shared CTA for walking navigation to a moderator when the nav beacon is on.
class ModeratorNavigateButton extends StatelessWidget {
  const ModeratorNavigateButton({
    super.key,
    required this.onTap,
    this.compact = false,
    this.moderatorName,
  });

  final VoidCallback onTap;

  /// Inline pill for tight rows (e.g. group details moderator list).
  final bool compact;

  /// When set, labels the button for a specific moderator.
  final String? moderatorName;

  String get _label {
    final name = moderatorName?.trim();
    if (name != null && name.isNotEmpty) {
      return 'nav_to_moderator_named'.tr(namedArgs: {'name': name});
    }
    return compact ? 'nav_go'.tr() : 'nav_to_moderator'.tr();
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.navigation,
                color: Colors.white,
                size: 14.sp,
                fill: 1,
              ),
              SizedBox(width: 4.w),
              Text(
                'nav_go'.tr(),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          elevation: 0,
        ),
        icon: Icon(Symbols.navigation, size: 20.sp, fill: 1),
        label: Text(
          _label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// One full-width navigate button per active moderator beacon.
class ModeratorNavigateBeaconList extends StatelessWidget {
  const ModeratorNavigateBeaconList({
    super.key,
    required this.beacons,
    required this.onNavigate,
  });

  final List<ModeratorBeacon> beacons;
  final void Function(ModeratorBeacon beacon) onNavigate;

  @override
  Widget build(BuildContext context) {
    if (beacons.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < beacons.length; i++) ...[
          if (i > 0) SizedBox(height: 6.h),
          ModeratorNavigateButton(
            moderatorName: beacons[i].name,
            onTap: () => onNavigate(beacons[i]),
          ),
        ],
      ],
    );
  }
}
