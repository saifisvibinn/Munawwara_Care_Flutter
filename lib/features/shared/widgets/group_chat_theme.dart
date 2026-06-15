import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/services/callkit_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass.dart';

/// Munawwara Care logo for in-app surfaces (RGBA; not [kCallKitSupportAvatarAsset]).
class SupportBrandAvatar extends StatelessWidget {
  const SupportBrandAvatar({
    super.key,
    required this.isDark,
    this.diameter = 42,
    this.iconPadding,
    this.showShadow = true,
  });

  final bool isDark;
  final double diameter;
  final double? iconPadding;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final pad = iconPadding ?? diameter * 0.17;
    return Container(
      width: diameter.w,
      height: diameter.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark
            ? AppColors.primary.withValues(alpha: 0.14)
            : Colors.white,
        border: Border.all(
          color: AppColors.primary.withValues(alpha: isDark ? 0.32 : 0.25),
        ),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: Padding(
          padding: EdgeInsets.all(pad.w),
          child: Image.asset(
            kSupportBrandAvatarAsset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}

/// Shared layout tokens for pilgrim group inbox and moderator group messages.
abstract final class GroupChatTheme {
  static const Color urgentAccentBar = Color(0xFFDC2626);

  static Color scaffoldBackground(bool isDark) =>
      AppGlassTheme.dashboardBackgroundColor(isDark);

  static Color cardBackground(
    bool isDark, {
    required bool urgent,
    required bool highlightNew,
  }) {
    if (urgent) {
      return isDark ? const Color(0xFF2A1C1C) : const Color(0xFFFFF5F5);
    }
    if (highlightNew) {
      return isDark
          ? AppColors.primary.withValues(alpha: 0.08)
          : AppColors.primary.withValues(alpha: 0.06);
    }
    return isDark ? AppColors.surfaceDark : Colors.white;
  }

  static Color cardBorderColor(
    bool isDark, {
    required bool urgent,
    required bool highlightNew,
  }) {
    if (isDark) {
      return Colors.white.withValues(alpha: 0.08);
    }
    return const Color(0xFFE5E5EA);
  }

  static double cardBorderWidth({
    required bool urgent,
    required bool highlightNew,
  }) => 0.5;

  static Color listGapColor(bool isDark) =>
      isDark ? AppColors.backgroundDark : const Color(0xFFF2F2F7);

  /// Matches the pilgrim inbox filter row background (moderator uses as spacer below header).
  static Color filterStripBackground(bool isDark) =>
      isDark ? AppColors.surfaceDark : const Color(0xFFF8FAFC);
}

/// Solid message row shell — independent cards with spacing.
class GroupBroadcastMessageCard extends StatelessWidget {
  const GroupBroadcastMessageCard({
    super.key,
    required this.isDark,
    required this.isUrgent,
    required this.isNew,
    required this.child,
    this.dismissKey,
    this.onLongPress,
    this.onConfirmDelete,
    this.onDismissed,
    this.animate = false,
  });

  final bool isDark;
  final bool isUrgent;
  final bool isNew;
  final Widget child;
  final Key? dismissKey;
  final VoidCallback? onLongPress;
  final Future<bool> Function()? onConfirmDelete;
  final VoidCallback? onDismissed;
  final bool animate;

  Widget _buildShell(BuildContext context) {
    final cardBg = GroupChatTheme.cardBackground(
      isDark,
      urgent: isUrgent,
      highlightNew: isNew && !isUrgent,
    );
    final divider = isDark ? AppColors.dividerDark : const Color(0xFFE5E5EA);
    final radius = 10.r;

    final shell = Container(
      margin: EdgeInsets.fromLTRB(20.w, 0, 20.w, 10.h),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: divider, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isUrgent)
                Container(width: 3.w, color: GroupChatTheme.urgentAccentBar),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isUrgent ? 12.w : 14.w,
                    14.h,
                    14.w,
                    14.h,
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (animate) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        child: shell,
      );
    }
    return shell;
  }

  @override
  Widget build(BuildContext context) {
    Widget card = GestureDetector(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: _buildShell(context),
    );

    if (onConfirmDelete != null && onDismissed != null) {
      card = Dismissible(
        key: dismissKey ?? const ValueKey('broadcast_card'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: EdgeInsets.only(right: 20.w),
          margin: EdgeInsets.fromLTRB(20.w, 0, 20.w, 10.h),
          decoration: BoxDecoration(
            color: GroupChatTheme.urgentAccentBar,
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Symbols.delete, color: Colors.white, size: 22.sp),
              SizedBox(height: 4.h),
              Text(
                'msg_delete_confirm'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  color: Colors.white,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        confirmDismiss: (_) => onConfirmDelete!(),
        onDismissed: (_) => onDismissed!(),
        child: card,
      );
    }

    return card;
  }
}

/// Shared metadata footer for moderator broadcast cards.
class GroupBroadcastMetaRow extends StatelessWidget {
  const GroupBroadcastMetaRow({
    super.key,
    required this.senderLabel,
    required this.timestamp,
    required this.isDark,
  });

  final String senderLabel;
  final String timestamp;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            senderLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              color: muted,
            ),
          ),
        ),
        SizedBox(width: 8.w),
        Text(
          timestamp,
          style: TextStyle(fontFamily: 'Lexend', fontSize: 12.sp, color: muted),
        ),
      ],
    );
  }
}

/// Compact group-scope chip for moderator broadcast cards.
class GroupScopeChip extends StatelessWidget {
  const GroupScopeChip({super.key, required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.white70 : AppColors.textMutedDark;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.groups, size: 13.w, color: fg),
          SizedBox(width: 4.w),
          Text(
            'msg_mod_group_scope'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared “play aloud” / TTS control — bordered secondary action (system blue).
class TtsPlayAloudButton extends StatelessWidget {
  final bool isSpeaking;
  final bool isLoading;
  final VoidCallback onPressed;
  final String idleLabel;
  final String playingLabel;
  final bool compact;

  const TtsPlayAloudButton({
    super.key,
    required this.isSpeaking,
    required this.onPressed,
    required this.idleLabel,
    required this.playingLabel,
    this.isLoading = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isSpeaking ? Colors.white : AppColors.info;
    final bg = isSpeaking
        ? AppColors.info
        : (isDark
              ? AppColors.info.withValues(alpha: 0.12)
              : AppColors.info.withValues(alpha: 0.08));
    final borderColor = isSpeaking
        ? AppColors.info
        : AppColors.info.withValues(alpha: isDark ? 0.35 : 0.45);

    Widget leadingIcon;
    String label;

    if (isLoading) {
      leadingIcon = SizedBox(
        width: 18.w,
        height: 18.w,
        child: const CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.info,
        ),
      );
      label = idleLabel;
    } else if (isSpeaking) {
      leadingIcon = Icon(Symbols.stop, size: compact ? 18.w : 20.w);
      label = playingLabel;
    } else {
      leadingIcon = Icon(Symbols.volume_up, size: compact ? 18.w : 20.w);
      label = idleLabel;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(12.r),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: compact ? 40.h : 44.h),
          child: Ink(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 14.w : 16.w,
              vertical: compact ? 8.h : 10.h,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(color: fg, size: compact ? 18.w : 20.w),
                  child: leadingIcon,
                ),
                SizedBox(width: 8.w),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: compact ? 13.sp : 14.sp,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Large title block at the top of the broadcast scroll area (iOS style).
class GroupBroadcastPageHeader extends StatelessWidget {
  const GroupBroadcastPageHeader({
    super.key,
    required this.isDark,
    required this.title,
    this.subtitle,
  });

  final bool isDark;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;

    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w800,
              fontSize: 28.sp,
              letterSpacing: -0.5,
              height: 1.15,
              color: textPrimary,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            SizedBox(height: 4.h),
            Text(
              subtitle!,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
                color: textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Floating nav chrome — back affordance + optional centered context pill.
class GroupBroadcastNavBar extends StatelessWidget {
  const GroupBroadcastNavBar({
    super.key,
    required this.isDark,
    required this.title,
    this.subtitle,
    this.onBack,
    this.showBrandAvatar = false,
  });

  final bool isDark;
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final bool showBrandAvatar;

  /// Height of the floating nav row (safe area + bar).
  static double overlayHeight(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top + 10.h + 42.w + 6.h;

  static double scrollTopPadding(BuildContext context, {double extra = 0}) =>
      overlayHeight(context) + extra;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;
    final navHeight = overlayHeight(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: navHeight,
          child: AppScrollGlassEdge(
            height: navHeight,
            edge: AppScrollGlassEdgeSide.top,
            isDark: isDark,
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 6.h),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (onBack != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppGlassIconButton(
                      isDark: isDark,
                      icon: Symbols.arrow_back,
                      onTap: onBack!,
                      size: 42.w,
                    ),
                  ),
                if (showBrandAvatar)
                  AppGlassSurface(
                    isDark: isDark,
                    borderRadius: BorderRadius.circular(14.r),
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 8.h,
                    ),
                    glassTheme: AppGlassTheme.groupBroadcastNavPillOf(isDark),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SupportBrandAvatar(
                          isDark: isDark,
                          diameter: 28,
                          iconPadding: 4,
                          showShadow: false,
                        ),
                        SizedBox(width: 8.w),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 180.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.sp,
                                  color: textPrimary,
                                  decoration: TextDecoration.none,
                                  decorationColor: Colors.transparent,
                                ),
                              ),
                              if (subtitle != null && subtitle!.isNotEmpty)
                                Text(
                                  subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 11.sp,
                                    color: textMuted,
                                    decoration: TextDecoration.none,
                                    decorationColor: Colors.transparent,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
