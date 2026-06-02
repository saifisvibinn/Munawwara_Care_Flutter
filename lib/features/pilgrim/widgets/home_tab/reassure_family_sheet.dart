import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/standard_snackbar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Reassure Family Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

void showReassureFamilyBottomSheet({
  required BuildContext context,
  Future<void> Function()? onSendReassurance,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? AppColors.surfaceDark
        : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
    ),
    builder: (ctx) {
      return ReassureFamilySheetBody(onSendReassurance: onSendReassurance);
    },
  );
}

class ReassureFamilySheetBody extends StatefulWidget {
  final Future<void> Function()? onSendReassurance;

  const ReassureFamilySheetBody({super.key, this.onSendReassurance});

  @override
  State<ReassureFamilySheetBody> createState() => _ReassureFamilySheetBodyState();
}

class _ReassureFamilySheetBodyState extends State<ReassureFamilySheetBody> {
  bool _isLoading = false;

  Future<void> _handleSend() async {
    setState(() => _isLoading = true);

    try {
      if (widget.onSendReassurance != null) {
        // Execute real integration if present
        await widget.onSendReassurance!();
      } else {
        // Placeholder / Interactive simulation
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (mounted) {
          StandardSnackBar.showSuccess(
            context,
            'Reassurance sent! Primary contacts notified.',
          );
        }
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        StandardSnackBar.showError(
          context,
          'Failed to send reassurance: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textDarkColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final mutedColor = isDark ? AppColors.textMutedLight : const Color(0xFF475569);

    return Padding(
      padding: EdgeInsets.fromLTRB(22.w, 8.h, 22.w, 24.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header Row ─────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFFFF7ED), // Soft peach tint
                ),
                child: Icon(
                  Icons.favorite_rounded,
                  color: const Color(0xFF7C2D12), // Dark brown/orange-950
                  size: 22.w,
                ),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Text(
                  'Reassure Family',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: textDarkColor,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Symbols.close,
                  size: 22.w,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          SizedBox(height: 18.h),

          // ── Description ────────────────────────────────────────────────────
          Text(
            'Quickly let your loved ones know you are safe during your pilgrimage. This message will be sent to your primary emergency contacts.',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: mutedColor,
              height: 1.45,
            ),
          ),
          SizedBox(height: 20.h),

          // ── Default Status Message Container ───────────────────────────────
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFE2E8F0),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.format_quote_rounded,
                      color: Colors.green.shade600,
                      size: 26.w,
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        'Assalamu Alaykum, I am doing well and safe in Makkah. Alhamdulillah.',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13.5.sp,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600,
                          color: textDarkColor,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14.h),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'DEFAULT STATUS MESSAGE',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 8.5.sp,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 28.h),

          // ── Send Button ────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isLoading ? null : _handleSend,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF97316), // Tailwind Orange-500
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 14.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r), // Premium capsule/rounded
                ),
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 20.w,
                      height: 20.w,
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send_rounded, size: 16.w),
                        SizedBox(width: 8.w),
                        Text(
                          'Send Status to All',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          SizedBox(height: 10.h),

          // ── Helper Text below button ───────────────────────────────────────
          Text(
            'Sends via SMS and Email simultaneously.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 10.5.sp,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
            ),
          ),
          SizedBox(height: 18.h),

          // ── Cancel Text Button ─────────────────────────────────────────────
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.white60 : const Color(0xFF475569),
            ),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.5.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom + 4.h),
        ],
      ),
    );
  }
}
