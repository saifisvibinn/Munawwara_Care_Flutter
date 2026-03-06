import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/call_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VoiceCallScreen
// Handles both outgoing (status=calling) and active (status=connected) phases.
// Auto-pops when the call returns to idle.
// ─────────────────────────────────────────────────────────────────────────────

class VoiceCallScreen extends ConsumerStatefulWidget {
  /// Prevents duplicate instances from being pushed onto the stack.
  static bool isActive = false;

  const VoiceCallScreen({super.key});

  @override
  ConsumerState<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends ConsumerState<VoiceCallScreen> {
  /// Cached caller name so it survives provider state resets.
  String? _cachedName;
  Timer? _autoPopTimer;

  /// Prevents cancelling an outgoing call within the first 3 seconds.
  bool _canCancel = false;
  Timer? _cancelLockTimer;

  @override
  void initState() {
    super.initState();
    VoiceCallScreen.isActive = true;
    // Lock the cancel button for the first 3 s so the call-offer socket
    // message has time to reach the server before a cancel is sent.
    _cancelLockTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _canCancel = true);
    });
  }

  @override
  void dispose() {
    _autoPopTimer?.cancel();
    _cancelLockTimer?.cancel();
    VoiceCallScreen.isActive = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callProvider);

    // Cache the name so it survives when provider resets to idle
    if (call.remoteUserName != null && call.remoteUserName!.isNotEmpty) {
      _cachedName = call.remoteUserName;
    }

    // Auto-pop 2 s after 'ended' so user sees the end reason with correct name
    ref.listen(callProvider, (prev, next) {
      if (next.status == CallStatus.ended &&
          prev?.status != CallStatus.ended &&
          mounted) {
        _autoPopTimer?.cancel();
        _autoPopTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
      // Safety net: also pop on idle
      if (next.status == CallStatus.idle && mounted) {
        Navigator.of(context).maybePop();
      }
    });

    final name = _cachedName ?? call.remoteUserName ?? 'Unknown';
    final initials = name
        .trim()
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ────────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
              child: Row(
                children: [
                  const Spacer(),
                  Text(
                    'call_internet'.tr(),
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13.sp,
                      fontFamily: 'Lexend',
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),

            const Spacer(flex: 2),

            // ── Avatar ─────────────────────────────────────────────────────
            Container(
              width: 110.w,
              height: 110.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.4),
                    blurRadius: 30,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: 38.sp,
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            SizedBox(height: 24.h),

            // ── Name ───────────────────────────────────────────────────────
            Text(
              name,
              style: TextStyle(
                fontSize: 26.sp,
                fontWeight: FontWeight.w700,
                fontFamily: 'Lexend',
                color: Colors.white,
              ),
            ),

            SizedBox(height: 8.h),

            // ── Status / Timer ─────────────────────────────────────────────
            Text(
              _statusLabel(call),
              style: TextStyle(
                fontSize: 14.sp,
                fontFamily: 'Lexend',
                color: call.status == CallStatus.connected
                    ? AppColors.primary
                    : Colors.white54,
              ),
            ),

            const Spacer(flex: 3),

            // ── Side controls (mute + speaker) ─────────────────────────────
            if (call.status == CallStatus.connected) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ControlButton(
                    icon: call.isMuted ? Symbols.mic_off : Symbols.mic,
                    label: call.isMuted ? 'call_unmute'.tr() : 'call_mute'.tr(),
                    active: call.isMuted,
                    onTap: () => ref.read(callProvider.notifier).toggleMute(),
                  ),
                  SizedBox(width: 32.w),
                  _ControlButton(
                    icon: call.isSpeakerOn
                        ? Symbols.volume_up
                        : Symbols.volume_down,
                    label: call.isSpeakerOn
                        ? 'call_speaker'.tr()
                        : 'call_earpiece'.tr(),
                    active: call.isSpeakerOn,
                    onTap: () =>
                        ref.read(callProvider.notifier).toggleSpeaker(),
                  ),
                ],
              ),
              SizedBox(height: 36.h),
            ],

            // ── End call button ────────────────────────────────────────────
            if (call.status != CallStatus.ended) ...[
              // During the first 3 s of an outgoing call the button is locked
              // (greyed-out) so the call-offer reaches the server before a
              // cancel can race against it.
              Builder(
                builder: (context) {
                  final isLocked =
                      call.status == CallStatus.calling && !_canCancel;
                  return GestureDetector(
                    onTap: isLocked
                        ? null
                        : () {
                            if (call.status == CallStatus.calling) {
                              SocketService.emit('call-cancel', {
                                'to': call.remoteUserId,
                              });
                              ref.read(callProvider.notifier).endCall();
                            } else {
                              ref.read(callProvider.notifier).endCall();
                            }
                          },
                    child: AnimatedOpacity(
                      opacity: isLocked ? 0.35 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        width: 70.w,
                        height: 70.w,
                        decoration: const BoxDecoration(
                          color: Color(0xFFDC2626),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Symbols.call_end,
                          color: Colors.white,
                          size: 30.w,
                          fill: 1,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],

            // ── End reason ─────────────────────────────────────────────────
            if (call.status == CallStatus.ended) ...[
              Icon(Symbols.info, color: Colors.white38, size: 32.w),
              SizedBox(height: 8.h),
              Text(
                _endReasonLabel(call.endReason),
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14.sp,
                  fontFamily: 'Lexend',
                ),
              ),
            ],

            SizedBox(height: 60.h),
          ],
        ),
      ),
    );
  }

  String _statusLabel(CallState call) {
    switch (call.status) {
      case CallStatus.calling:
        return 'call_calling'.tr();
      case CallStatus.connected:
        return call.formattedDuration;
      case CallStatus.ended:
        return _endReasonLabel(call.endReason);
      default:
        return '';
    }
  }

  String _endReasonLabel(String? reason) {
    switch (reason) {
      case 'declined':
        return 'call_declined'.tr();
      case 'busy':
        return 'call_busy'.tr();
      case 'cancelled':
        return 'call_cancelled'.tr();
      case 'error':
        return 'call_error'.tr();
      default:
        return 'call_ended'.tr();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widget: mute / speaker buttons
// ─────────────────────────────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60.w,
            height: 60.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? Colors.white.withOpacity(0.25)
                  : Colors.white.withOpacity(0.1),
            ),
            child: Icon(icon, fill: 1, color: Colors.white, size: 26.w),
          ),
          SizedBox(height: 6.h),
          Text(
            label,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11.sp,
              fontFamily: 'Lexend',
            ),
          ),
        ],
      ),
    );
  }
}
