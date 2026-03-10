import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';

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

  const WaveformPlayer({
    super.key,
    required this.messageId,
    required this.isPlaying,
    required this.progress,
    required this.durationSeconds,
    required this.positionSeconds,
    required this.onToggle,
    required this.isDark,
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

    return Row(
      children: [
        GestureDetector(
          onTap: onToggle,
          child: Container(
            width: 40.w,
            height: 40.w,
            decoration: BoxDecoration(
              color: isDark ? AppColors.iconBgDark : AppColors.iconBgLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPlaying ? Symbols.pause : Symbols.play_arrow,
              size: 20.w,
              color: AppColors.primary,
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
                          ? AppColors.primary
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
// Message type badge
// ─────────────────────────────────────────────────────────────────────────────

class MessageTypeBadge extends StatelessWidget {
  final String type;
  const MessageTypeBadge({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      'voice' => ('Voice', const Color(0xFF7C3AED)),
      'tts' => ('TTS', const Color(0xFF2563EB)),
      _ => ('Text', AppColors.textMutedLight),
    };

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 10.sp,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
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
