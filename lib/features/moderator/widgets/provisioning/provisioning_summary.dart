import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../../core/theme/app_colors.dart';
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
            title: 'Total',
            value: summary.totalProvisioned,
            icon: Symbols.group,
            color: AppColors.primary,
            isDark: isDark,
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: _ModernStatCard(
            title: 'Pending',
            value: summary.pendingCount,
            icon: Symbols.pending_actions,
            color: const Color(0xFFF59E0B),
            isDark: isDark,
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: _ModernStatCard(
            title: 'Activated',
            value: summary.activatedCount,
            icon: Symbols.verified,
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
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.05 : 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(6.w),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, size: 18.w, color: color),
          ),
          SizedBox(height: 12.h),
          Text(
            '$value',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 24.sp,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 11.sp,
              fontWeight: FontWeight.w500,
              color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
            ),
          ),
        ],
      ),
    );
  }
}
