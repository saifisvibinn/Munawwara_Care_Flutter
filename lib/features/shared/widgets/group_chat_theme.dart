import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/services/callkit_service.dart';
import '../../../core/theme/app_colors.dart';

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
  static const Color urgentRed = Color(0xFFDC2626);

  static Color scaffoldBackground(bool isDark) =>
      isDark ? AppColors.backgroundDark : const Color(0xFFF1F5F6);

  static Color cardBackground(bool isDark, {required bool urgent, required bool highlightNew}) {
    if (urgent) {
      return isDark ? const Color(0xFF221A1A) : const Color(0xFFFFFBFB);
    }
    if (highlightNew) {
      return isDark ? const Color(0xFF1A2A1A) : const Color(0xFFECFDF5);
    }
    return isDark ? AppColors.surfaceDark : Colors.white;
  }

  static Color cardBorderColor(bool isDark, {required bool urgent, required bool highlightNew}) {
    if (urgent) return urgentRed;
    if (highlightNew) return AppColors.primary.withValues(alpha: 0.5);
    return isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE8EEF2);
  }

  static double cardBorderWidth({required bool urgent, required bool highlightNew}) {
    if (urgent) return 1.5;
    if (highlightNew) return 1.2;
    return 1.0;
  }

  /// Matches the pilgrim inbox filter row background (moderator uses as spacer below header).
  static Color filterStripBackground(bool isDark) =>
      isDark ? AppColors.surfaceDark : const Color(0xFFF8FAFC);
}

/// Shared “play aloud” / TTS control (info blue) for pilgrim inbox and moderator group chat.
class TtsPlayAloudButton extends StatelessWidget {
  final bool isSpeaking;
  final bool isLoading;
  final VoidCallback onPressed;
  final String idleLabel;
  final String playingLabel;
  /// Tighter padding and type for moderator cards / short TTS lines.
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
    Widget leadingIcon;
    String label;

    if (isLoading) {
      leadingIcon = SizedBox(
        width: 18.w,
        height: 18.w,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.info,
        ),
      );
      label = idleLabel; // keep label stable during load
    } else if (isSpeaking) {
      leadingIcon = Icon(Symbols.stop, size: compact ? 18.w : 20.w);
      label = playingLabel;
    } else {
      leadingIcon = Icon(Symbols.volume_up, size: compact ? 18.w : 20.w);
      label = idleLabel;
    }

    final vPad = compact ? 8.h : 12.h;
    final hPad = compact ? 14.w : 18.w;
    final fontSize = compact ? 13.sp : 14.sp;

    return FilledButton.tonalIcon(
      // Disable taps while buffering to prevent double-trigger
      onPressed: isLoading ? null : onPressed,
      icon: leadingIcon,
      label: Text(
        label,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontWeight: FontWeight.w600,
          fontSize: fontSize,
        ),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: isSpeaking
            ? AppColors.info
            : AppColors.info.withValues(alpha: 0.14),
        foregroundColor: isSpeaking ? Colors.white : AppColors.info,
        disabledBackgroundColor: AppColors.info.withValues(alpha: 0.10),
        disabledForegroundColor: AppColors.info.withValues(alpha: 0.60),
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
        elevation: 0,
      ),
    );
  }
}

/// Header row shared by group inbox (pilgrim) and group messages (moderator).
class GroupChatHeader extends StatelessWidget {
  final bool isDark;
  final String title;
  final String subtitle;
  final VoidCallback onRefresh;
  final VoidCallback? onBack;
  final bool showBrandAvatar;

  const GroupChatHeader({
    super.key,
    required this.isDark,
    required this.title,
    required this.subtitle,
    required this.onRefresh,
    this.onBack,
    this.showBrandAvatar = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = isDark ? Colors.white : AppColors.textDark;
    final subtitleColor = isDark ? Colors.white60 : AppColors.textMutedLight;
    final topInset = MediaQuery.paddingOf(context).top;

    return Container(
      padding: EdgeInsets.fromLTRB(4.w, 6.h + topInset, 12.w, 6.h),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            IconButton(
              icon: Icon(
                Symbols.arrow_back,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
              onPressed: onBack,
            ),
            SizedBox(width: 4.w),
          ],
          if (showBrandAvatar) ...[
            SupportBrandAvatar(isDark: isDark),
            SizedBox(width: 10.w),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 16.sp,
                    color: titleColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11.sp,
                    color: subtitleColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRefresh,
            child: Container(
              width: 36.w,
              height: 36.w,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                Symbols.refresh,
                size: 18.w,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
