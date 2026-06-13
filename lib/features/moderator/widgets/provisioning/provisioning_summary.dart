import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass/app_glass.dart';
import '../../models/provisioning_models.dart';

class ProvisioningSummaryCards extends StatelessWidget {
  final ProvisioningSummary summary;
  final bool isDark;

  const ProvisioningSummaryCards({
    super.key,
    required this.summary,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModernStatCard(
            title: 'provisioning_total'.tr().toUpperCase(),
            value: summary.totalProvisioned,
            icon: Symbols.groups,
            color: AppColors.primary,
            isDark: isDark,
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: _ModernStatCard(
            title: 'status_pending'.tr().toUpperCase(),
            value: summary.pendingCount,
            icon: Symbols.schedule,
            color: const Color(0xFFEAB308),
            isDark: isDark,
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: _ModernStatCard(
            title: 'group_status_activated'.tr().toUpperCase(),
            value: summary.activatedCount,
            icon: Symbols.verified_user,
            color: const Color(0xFF10B981),
            isDark: isDark,
          ),
        ),
      ],
    );
  }
}

class _ModernStatCard extends StatelessWidget {
  final String title;
  final int value;
  final IconData icon;
  final Color color;
  final bool isDark;

  const _ModernStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      isDark: isDark,
      padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
              ),
              Icon(icon, size: 22.sp, color: color.withValues(alpha: 0.9)),
            ],
          ),
          SizedBox(height: 6.h),
          Text(
            title,
            style: TextStyle(
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
            ),
          ),
        ],
      ),
    );
  }
}
