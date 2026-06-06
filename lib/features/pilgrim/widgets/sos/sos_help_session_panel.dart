import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/standard_snackbar.dart';
import '../../screens/live_translate_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Redesigned pulsing SOS button (active/sent state)
// ─────────────────────────────────────────────────────────────────────────────

class RedesignedSosSentButton extends StatelessWidget {
  final AnimationController pulseController;
  final bool isResponding;
  final bool isResolved;
  final double size;

  const RedesignedSosSentButton({
    super.key,
    required this.pulseController,
    required this.isResponding,
    this.isResolved = false,
    this.size = 136,
  });

  @override
  Widget build(BuildContext context) {
    final color = (isResponding || isResolved) ? Colors.green.shade600 : const Color(0xFFF97316);

    return AnimatedBuilder(
      animation: pulseController,
      builder: (context, child) {
        final value = pulseController.value;
        return SizedBox(
          width: (size * 1.8).w,
          height: (size * 1.8).w,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer radar wave
              Opacity(
                opacity: (1.0 - value) * 0.16,
                child: Transform.scale(
                  scale: 1.0 + (value * 0.75),
                  child: Container(
                    width: size.w,
                    height: size.w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
              // Inner radar wave
              Opacity(
                opacity: (1.0 - value) * 0.32,
                child: Transform.scale(
                  scale: 1.0 + (value * 0.38),
                  child: Container(
                    width: size.w,
                    height: size.w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ),
              // Main central button surface
              Container(
                width: size.w,
                height: size.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(
                    color: Colors.white,
                    width: 3.5.w,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 26.w,
                      spreadRadius: 4.w,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: EdgeInsets.all(4.w),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.w),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: (size * 0.16).w,
                      ),
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      isResolved
                          ? 'sos_btn_resolved'.tr()
                          : isResponding
                              ? 'sos_btn_active'.tr()
                              : 'sos_btn_sent'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: (size * 0.11).sp,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

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

  final AnimationController pulseController;
  final VoidCallback? onWeatherTap;
  final VoidCallback? onHotspotsTap;

  const SosHelpSessionPanel({
    super.key,
    required this.isDark,
    required this.statusKey,
    required this.onCancelRequest,
    required this.pulseController,
    this.onWeatherTap,
    this.onHotspotsTap,
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

  Widget _buildMiniServiceButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final isDark = widget.isDark;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFFFF7ED); // Soft peach tint
    final tintColor = isDark
        ? AppColors.primary
        : const Color(0xFFF97316); // Premium orange

    return Opacity(
      opacity: onTap == null ? 0.5 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 50.w,
              height: 50.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bg,
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFFFE5D0),
                  width: 1.2,
                ),
              ),
              child: Icon(
                icon,
                color: tintColor,
                size: 22.w,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 10.sp,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = 'call_support_display_name'.tr();
    final titleColor = widget.isDark ? Colors.white : const Color(0xFF0F3E1F); // Premium Green
    final muted = widget.isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;

    final isResolved = widget.statusKey == 'sos_status_resolved_friendly';
    final isResponding = widget.statusKey == 'sos_status_responding' ||
        widget.statusKey == 'sos_status_being_handled';

    final String titleText;
    if (isResolved) {
      final translated = 'sos_resolved_title'.tr();
      titleText = translated == 'sos_resolved_title' ? 'Help request resolved' : translated;
    } else {
      titleText = 'sos_help_title'.tr();
    }

    final String fullDesc;
    if (isResolved) {
      final translated = 'sos_status_resolved_friendly'.tr();
      fullDesc = translated == 'sos_status_resolved_friendly'
          ? "you're request was resolved, thank you for using munawwara care care"
          : translated;
    } else {
      final String statusText;
      if (isResponding) {
        statusText = 'sos_status_responding'.tr();
      } else {
        statusText = widget.statusKey.tr();
      }
      fullDesc = '${'sos_help_subtitle'.tr(namedArgs: {'name': brand})} $statusText';
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 420.w),
      child: Container(
        padding: EdgeInsets.fromLTRB(22.w, 12.h, 22.w, 18.h),
        decoration: BoxDecoration(
          color: Colors.transparent, // Flush integration
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Large Pulsing active SOS Sent Button ────────────────────────
            RedesignedSosSentButton(
              pulseController: widget.pulseController,
              isResponding: isResponding,
              isResolved: isResolved,
            ),
            SizedBox(height: 24.h),

            // ── Premium Green Heading ───────────────────────────────────────
            Text(
              titleText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 22.sp,
                fontWeight: FontWeight.w800,
                color: titleColor,
                letterSpacing: -0.2,
                height: 1.2,
              ),
            ),
            SizedBox(height: 10.h),

            // ── Reassuring Centered Description ─────────────────────────────
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              child: Text(
                fullDesc,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13.5.sp,
                  fontWeight: FontWeight.w500,
                  color: muted,
                  height: 1.45,
                ),
              ),
            ),
            SizedBox(height: 28.h),

            if (widget.showCallBack) ...[
              // ── Call back capsule button ────────────────────────────────────
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
                      borderRadius: BorderRadius.circular(28.r), // Premium capsule
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
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ] else if (widget.showCancel) ...[
              // ── Cancel capsule button ───────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (isResponding || widget.disableCancel)
                      ? null
                      : () => widget.onCancelRequest(),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFF1F5F9), // Light premium grey
                    foregroundColor: (isResponding || widget.disableCancel)
                        ? Colors.grey.shade400
                        : widget.isDark
                            ? Colors.white
                            : const Color(0xFF334155), // Slate-700
                    disabledBackgroundColor: widget.isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF8FAFC),
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28.r), // Premium capsule
                    ),
                  ),
                  child: Text(
                    'sos_cancel_request'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ],

            // ── Other Services Mini-bar ─────────────────────────────────────
            SizedBox(height: 32.h),
            Divider(
              color: widget.isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE2E8F0),
              thickness: 1.0,
            ),
            SizedBox(height: 12.h),
            Text(
              'muslim_featured_categories'.tr().toUpperCase(), // "Featured" or "Other Services"
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 10.5.sp,
                fontWeight: FontWeight.w800,
                color: widget.isDark ? Colors.white60 : const Color(0xFF94A3B8),
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 14.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMiniServiceButton(
                  icon: Icons.wb_sunny_rounded,
                  label: 'label_weather'.tr(),
                  onTap: widget.onWeatherTap,
                ),
                _buildMiniServiceButton(
                  icon: Icons.explore_rounded,
                  label: 'label_explore'.tr(),
                  onTap: widget.onHotspotsTap,
                ),
                _buildMiniServiceButton(
                  icon: Icons.translate_rounded,
                  label: 'label_translate'.tr(),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LiveTranslateScreen(),
                      ),
                    );
                  },
                ),
                _buildMiniServiceButton(
                  icon: Icons.people_alt_rounded,
                  label: 'label_reassure'.tr(),
                  onTap: () {
                    StandardSnackBar.showInfo(
                      context,
                      'coming_soon'.tr(),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
