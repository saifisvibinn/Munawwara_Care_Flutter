import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../models/message_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Waveform player  (voice message playback bar)
// ─────────────────────────────────────────────────────────────────────────────

class WaveformPlayer extends StatelessWidget {
  final String messageId;
  final bool isPlaying;
  final double progress; // 0.0 – 1.0
  final int durationSeconds;
  final int? positionSeconds;
  final VoidCallback onToggle;
  final bool isDark;
  /// When set, overrides the default icon circle fill (pilgrim voice accent).
  final Color? playCircleColor;
  /// When set, overrides [AppColors.primary] for the play/pause icon.
  final Color? playIconColor;

  const WaveformPlayer({
    super.key,
    required this.messageId,
    required this.isPlaying,
    required this.progress,
    required this.durationSeconds,
    required this.positionSeconds,
    required this.onToggle,
    required this.isDark,
    this.playCircleColor,
    this.playIconColor,
  });

  List<double> _bars() {
    final seed = messageId.isNotEmpty
        ? messageId.codeUnitAt(messageId.length - 1)
        : 10;
    return List.generate(22, (i) => 6 + ((seed * (i + 3)) % 22).toDouble());
  }

  String _formatSecs(int secs) {
    final m = secs ~/ 60;
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final bars = _bars();
    final displaySecs = isPlaying && positionSeconds != null
        ? positionSeconds!
        : durationSeconds;
    final circleFill = playCircleColor ??
        (isDark ? AppColors.iconBgDark : AppColors.iconBgLight);
    final iconTint = playIconColor ?? AppColors.primary;

    return Row(
      children: [
        GestureDetector(
          onTap: onToggle,
          child: Container(
            width: 40.w,
            height: 40.w,
            decoration: BoxDecoration(
              color: circleFill,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPlaying ? Symbols.pause : Symbols.play_arrow,
              size: 20.w,
              color: iconTint,
            ),
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: bars.asMap().entries.map((entry) {
                  final barIdx = entry.key / bars.length;
                  final filled = isPlaying && barIdx < progress;
                  return Container(
                    width: 3.w,
                    height: entry.value.h,
                    margin: EdgeInsets.only(right: 2.w),
                    decoration: BoxDecoration(
                      color: filled
                          ? iconTint
                          : (isDark ? Colors.white24 : Colors.black12),
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  );
                }).toList(),
              ),
              SizedBox(height: 4.h),
              Text(
                _formatSecs(displaySecs),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMutedLight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Urgent message badge
// ─────────────────────────────────────────────────────────────────────────────

class UrgentBadge extends StatelessWidget {
  const UrgentBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.warning, size: 10.w, color: Colors.white),
          SizedBox(width: 3.w),
          Text(
            'URGENT',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 9.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private message indicator
// ─────────────────────────────────────────────────────────────────────────────

class PrivateIndicator extends StatelessWidget {
  final bool isForPilgrim; // true = "Only you see this", false = "Private"
  final String? recipientName; // optional: "Private for [Name]"
  const PrivateIndicator({
    super.key,
    required this.isForPilgrim,
    this.recipientName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 6.h),
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.lock,
            size: 12.w,
            color: AppColors.primary,
            fill: 1,
          ),
          SizedBox(width: 6.w),
          Text(
            isForPilgrim
                ? 'msg_only_you'.tr()
                : (recipientName != null
                    ? 'msg_private_for'.tr(namedArgs: {'name': recipientName!})
                    : 'msg_private_indicator'.tr()),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reply quote (in message bubble)
// ─────────────────────────────────────────────────────────────────────────────

class MessageReplyQuote extends StatelessWidget {
  final MessageReplySnapshot snapshot;
  final bool isDark;

  const MessageReplyQuote({
    super.key,
    required this.snapshot,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primary.withValues(alpha: 0.65);
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.fromLTRB(10.w, 8.h, 10.w, 8.h),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10.r),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            snapshot.senderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 11.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            snapshot.previewText,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12.sp,
              height: 1.35,
              color: isDark ? Colors.white70 : AppColors.textMutedLight,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reply target strip above composer
// ─────────────────────────────────────────────────────────────────────────────

class MessageReplyComposerStrip extends StatelessWidget {
  final MessageReplySnapshot snapshot;
  final bool isDark;
  final VoidCallback onCancel;

  const MessageReplyComposerStrip({
    super.key,
    required this.snapshot,
    required this.isDark,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.fromLTRB(10.w, 8.h, 6.w, 8.h),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(Symbols.reply, size: 18.w, color: AppColors.primary),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'msg_replying_to'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMutedLight,
                  ),
                ),
                Text(
                  '${snapshot.senderName}: ${snapshot.previewText}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: Icon(
              Symbols.close,
              size: 20.w,
              color: AppColors.textMutedLight,
            ),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(
              minWidth: 32.w,
              minHeight: 32.w,
            ),
          ),
        ],
      ),
    );
  }
}
