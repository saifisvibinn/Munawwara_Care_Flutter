import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Post-SOS help session panel (calm surface; status text + cancel button)
// ─────────────────────────────────────────────────────────────────────────────

class SosHelpSessionPanel extends StatefulWidget {
  final bool isDark;
  final String statusKey;

  /// Name of the moderator who confirmed they're handling this (empty if none).
  final String moderatorName;

  final Future<void> Function() onCancelRequest;
  final Future<void> Function()? onCallBack;
  final bool showCancel;
  final bool showCallBack;
  final bool disableCancel;

  final int cooldownSeconds;

  const SosHelpSessionPanel({
    super.key,
    required this.isDark,
    required this.statusKey,
    required this.onCancelRequest,
    this.onCallBack,
    this.showCancel = true,
    this.showCallBack = false,
    this.disableCancel = false,
    this.moderatorName = '',
    this.cooldownSeconds = 0,
  });

  @override
  State<SosHelpSessionPanel> createState() => _SosHelpSessionPanelState();
}

class _SosHelpSessionPanelState extends State<SosHelpSessionPanel> {
  bool _isCallBackConnecting = false;
  Timer? _connectingDotsTimer;
  int _connectingDotPhase = 0;

  bool get _isCallBackDisabled =>
      widget.onCallBack == null ||
      widget.cooldownSeconds > 0 ||
      _isCallBackConnecting;

  String get _connectingLabelBase =>
      'call_connecting'.tr().replaceAll(RegExp(r'\.+\s*$'), '').trim();

  String get _connectingButtonLabel {
    if (_connectingDotPhase == 0) {
      return _connectingLabelBase;
    }
    final dots = List<String>.generate(
      _connectingDotPhase,
      (_) => '.',
    ).join(' ');
    return '$_connectingLabelBase $dots';
  }

  void _startConnectingDotsAnimation() {
    _connectingDotsTimer?.cancel();
    _connectingDotPhase = 0;
    _connectingDotsTimer = Timer.periodic(
      const Duration(milliseconds: 450),
      (_) {
        if (!mounted) return;
        setState(() {
          _connectingDotPhase = (_connectingDotPhase + 1) % 4;
        });
      },
    );
  }

  void _stopConnectingDotsAnimation() {
    _connectingDotsTimer?.cancel();
    _connectingDotsTimer = null;
    _connectingDotPhase = 0;
  }

  Future<void> _handleCallBackTap() async {
    if (_isCallBackDisabled) return;
    setState(() => _isCallBackConnecting = true);
    _startConnectingDotsAnimation();
    try {
      await widget.onCallBack!();
    } finally {
      _stopConnectingDotsAnimation();
      if (mounted) {
        setState(() => _isCallBackConnecting = false);
      }
    }
  }

  @override
  void dispose() {
    _stopConnectingDotsAnimation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = 'call_support_display_name'.tr();
    final surface = widget.isDark ? AppColors.surfaceDark : Colors.white;
    final border = AppColors.primary.withValues(alpha: 0.22);
    final titleColor = widget.isDark ? Colors.white : AppColors.textDark;
    final muted = widget.isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;

    final isResponding = widget.statusKey == 'sos_status_responding';

    final String statusText;
    if (isResponding) {
      statusText = 'sos_status_responding'.tr();
    } else {
      statusText = widget.statusKey.tr();
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 400.w),
      child: Container(
        padding: EdgeInsets.fromLTRB(22.w, 24.h, 22.w, 20.h),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(22.r),
          border: Border.all(
            color: isResponding ? Colors.green.withValues(alpha: 0.35) : border,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: widget.isDark ? 0.25 : 0.06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── State icon ────────────────────────────────────────────────────
            Icon(
              isResponding
                  ? Icons.directions_run_rounded
                  : Icons.mark_email_read_outlined,
              color: isResponding ? Colors.green : AppColors.primary,
              size: 40.w,
            ),
            SizedBox(height: 14.h),
            Text(
              'sos_help_title'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 18.sp,
                fontWeight: FontWeight.w800,
                color: titleColor,
                height: 1.25,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'sos_help_subtitle'.tr(namedArgs: {'name': brand}),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: muted,
                height: 1.45,
              ),
            ),
            SizedBox(height: 16.h),

            // ── Visual indicator (no loading animation) ───────────────────────
            Container(
              width: 64.w,
              height: 64.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isResponding ? Colors.green : AppColors.primary)
                    .withValues(alpha: 0.12),
              ),
              child: Icon(
                isResponding
                    ? Icons.check_rounded
                    : Icons.support_agent_rounded,
                color: isResponding ? Colors.green : AppColors.primary,
                size: 36.w,
              ),
            ),

            SizedBox(height: 14.h),

            // ── Status text ───────────────────────────────────────────────────
            Text(
              statusText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: isResponding ? Colors.green : AppColors.primary,
                height: 1.35,
              ),
            ),
            SizedBox(height: 22.h),

            if (widget.showCallBack) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isCallBackDisabled ? null : _handleCallBackTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: (_isCallBackConnecting ||
                            widget.cooldownSeconds > 0)
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.5),
                    disabledForegroundColor: Colors.white.withValues(
                      alpha: 0.85,
                    ),
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                  child: Text(
                    _isCallBackConnecting
                        ? _connectingButtonLabel
                        : widget.cooldownSeconds > 0
                            ? '${'sos_call_back'.tr()} '
                                '(${widget.cooldownSeconds})'
                            : 'sos_call_back'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ] else if (widget.showCancel) ...[
              // ── Cancel button ───────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: (isResponding || widget.disableCancel)
                      ? null
                      : () => widget.onCancelRequest(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: (isResponding || widget.disableCancel)
                        ? Colors.grey.shade400
                        : muted,
                    side: BorderSide(
                      color: (isResponding || widget.disableCancel)
                          ? Colors.grey.shade300
                          : widget.isDark
                          ? AppColors.dividerDark
                          : AppColors.dividerLight,
                    ),
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                  child: Text(
                    'sos_cancel_request'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
