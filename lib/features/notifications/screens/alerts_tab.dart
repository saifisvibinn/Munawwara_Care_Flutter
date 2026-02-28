import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../models/notification_model.dart';
import '../providers/notification_provider.dart';
import '../../moderator/providers/moderator_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../moderator/widgets/pilgrim_profile_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Alerts Tab — shown when the user taps "Alerts" in the bottom nav
// ─────────────────────────────────────────────────────────────────────────────

class AlertsTab extends ConsumerStatefulWidget {
  const AlertsTab({super.key});

  @override
  ConsumerState<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends ConsumerState<AlertsTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationProvider.notifier).fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'alerts_title'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 24.sp,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        'alerts_subtitle'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13.sp,
                          color: AppColors.textMutedLight,
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.notifications.any((n) => n.read))
                  TextButton(
                    onPressed: () =>
                        ref.read(notificationProvider.notifier).clearRead(),
                    child: Text(
                      'alerts_clear_read'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          SizedBox(height: 12.h),

          // ── Content ─────────────────────────────────────────────────────
          Expanded(
            child: state.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : state.error != null
                ? _ErrorView(
                    error: state.error!,
                    onRetry: () =>
                        ref.read(notificationProvider.notifier).fetch(),
                  )
                : state.notifications.isEmpty
                ? const _EmptyView()
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () =>
                        ref.read(notificationProvider.notifier).fetch(),
                    child: ListView.separated(
                      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 100.h),
                      itemCount: state.notifications.length,
                      separatorBuilder: (_, _) => SizedBox(height: 8.h),
                      itemBuilder: (ctx, i) {
                        final n = state.notifications[i];
                        return _NotificationTile(
                          notification: n,
                          isDark: isDark,
                          onDelete: () => ref
                              .read(notificationProvider.notifier)
                              .delete(n.id),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification tile — swipe right to dismiss
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationTile extends ConsumerWidget {
  final AppNotification notification;
  final bool isDark;
  final VoidCallback onDelete;

  const _NotificationTile({
    required this.notification,
    required this.isDark,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notification;
    final bg = isDark ? const Color(0xFF1A2C24) : Colors.white;

    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20.w),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Icon(Symbols.delete, color: Colors.white, size: 22.w),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16.r),
          border: n.read
              ? null
              : Border(left: BorderSide(color: n.iconColor, width: 3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(14.w),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon chip
              Container(
                width: 38.w,
                height: 38.w,
                decoration: BoxDecoration(
                  color: n.iconColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(n.icon, size: 18.w, color: n.iconColor),
              ),
              SizedBox(width: 12.w),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: n.read
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                              fontSize: 13.sp,
                              color: isDark ? Colors.white : AppColors.textDark,
                            ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          _formatDate(n.createdAt),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 10.sp,
                            color: AppColors.textMutedLight,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 3.h),
                    Text(
                      n.message,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12.sp,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : AppColors.textMutedLight,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 6.h),
                    // Type badge
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8.w,
                        vertical: 2.h,
                      ),
                      decoration: BoxDecoration(
                        color: n.iconColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: Text(
                        n.typeLabel.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 9.sp,
                          fontWeight: FontWeight.w700,
                          color: n.iconColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    // Navigate button for area/meetpoint notifications
                    if ((n.type == 'suggested_area' || n.type == 'meetpoint') &&
                        n.data?['location'] != null) ...[
                      SizedBox(height: 8.h),
                      GestureDetector(
                        onTap: () {
                          final loc =
                              n.data!['location'] as Map<String, dynamic>;
                          final lat = (loc['lat'] as num).toDouble();
                          final lng = (loc['lng'] as num).toDouble();
                          final url = Uri.parse(
                            'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
                          );
                          launchUrl(url, mode: LaunchMode.externalApplication);
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12.w,
                            vertical: 7.h,
                          ),
                          decoration: BoxDecoration(
                            color: n.iconColor,
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Symbols.navigation,
                                size: 14.w,
                                color: Colors.white,
                                fill: 1,
                              ),
                              SizedBox(width: 4.w),
                              Text(
                                'area_navigate'.tr(),
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.sp,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    // View Profile button for SOS alerts
                    if (n.type == 'sos_alert' &&
                        n.data?['pilgrim_id'] != null) ...[
                      SizedBox(height: 8.h),
                      GestureDetector(
                        onTap: () {
                          final pId = n.data!['pilgrim_id'] as String;
                          final gId = n.data!['group_id'] as String?;

                          final modState = ref.read(moderatorProvider);
                          PilgrimInGroup? pilgrim;
                          for (final g in modState.groups) {
                            try {
                              pilgrim = g.pilgrims.firstWhere(
                                (p) => p.id == pId,
                              );
                              break;
                            } catch (_) {}
                          }
                          if (pilgrim != null && gId != null) {
                            final uid = ref.read(authProvider).userId ?? '';
                            showPilgrimProfileSheet(context, pilgrim, gId, uid);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Pilgrim not found in your groups',
                                  style: const TextStyle(fontFamily: 'Lexend'),
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12.w,
                            vertical: 7.h,
                          ),
                          decoration: BoxDecoration(
                            color: n.iconColor,
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Symbols.person,
                                size: 14.w,
                                color: Colors.white,
                                fill: 1,
                              ),
                              SizedBox(width: 4.w),
                              Text(
                                'View Profile',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.sp,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Unread dot
              if (!n.read) ...[
                SizedBox(width: 6.w),
                Container(
                  width: 8.w,
                  height: 8.w,
                  decoration: BoxDecoration(
                    color: n.iconColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'alerts_just_now'.tr();
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(date);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / Error states
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.notifications_off,
            size: 56.w,
            color: AppColors.textMutedLight,
          ),
          SizedBox(height: 12.h),
          Text(
            'alerts_empty'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textMutedLight,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            "alerts_all_caught_up".tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              color: AppColors.textMutedLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.error_outline, size: 48.w, color: Colors.red.shade400),
          SizedBox(height: 12.h),
          Text(
            error,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              color: AppColors.textMutedLight,
            ),
          ),
          SizedBox(height: 16.h),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Symbols.refresh),
            label: Text('alerts_retry'.tr()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
