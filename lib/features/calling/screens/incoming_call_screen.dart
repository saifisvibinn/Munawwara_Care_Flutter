import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/call_provider.dart';
import 'voice_call_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// IncomingCallScreen
// Full-screen overlay shown when status == CallStatus.ringing.
// Accept → pushReplacement to VoiceCallScreen.
// Decline / auto-cancel → pop.
// ─────────────────────────────────────────────────────────────────────────────

class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callProvider);

    // If the caller cancels or the call ends before we accept, pop this screen
    ref.listen(callProvider, (_, next) {
      if ((next.status == CallStatus.idle || next.status == CallStatus.ended) &&
          mounted) {
        Navigator.of(context).maybePop();
      }
    });

    final name = call.remoteUserName ?? 'Unknown';
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
            SizedBox(height: 60.h),

            // ── Incoming call label ────────────────────────────────────────
            Text(
              'call_incoming'.tr().toUpperCase(),
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11.sp,
                fontFamily: 'Lexend',
                letterSpacing: 2,
              ),
            ),

            const Spacer(flex: 2),

            // ── Pulsing avatar ─────────────────────────────────────────────
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, child) {
                final glow = 18 + 14 * _pulseController.value;
                return Container(
                  width: 120.w,
                  height: 120.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.45),
                        blurRadius: glow,
                        spreadRadius: glow * 0.4,
                      ),
                    ],
                  ),
                  child: child,
                );
              },
              child: Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: 42.sp,
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            SizedBox(height: 28.h),

            // ── Name ───────────────────────────────────────────────────────
            Text(
              name,
              style: TextStyle(
                fontSize: 30.sp,
                fontWeight: FontWeight.w700,
                fontFamily: 'Lexend',
                color: Colors.white,
              ),
            ),

            SizedBox(height: 8.h),

            Text(
              'call_voice'.tr(),
              style: TextStyle(
                fontSize: 14.sp,
                fontFamily: 'Lexend',
                color: Colors.white54,
              ),
            ),

            const Spacer(flex: 3),

            // ── Speaker toggle while ringing ──────────────────────────────
            GestureDetector(
              onTap: () => ref.read(callProvider.notifier).toggleSpeaker(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60.w,
                    height: 60.w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: call.isSpeakerOn
                          ? Colors.white.withOpacity(0.25)
                          : Colors.white.withOpacity(0.1),
                    ),
                    child: Icon(
                      call.isSpeakerOn
                          ? Symbols.volume_up
                          : Symbols.volume_down,
                      fill: 1,
                      color: Colors.white,
                      size: 26.w,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    call.isSpeakerOn
                        ? 'call_speaker'.tr()
                        : 'call_earpiece'.tr(),
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11.sp,
                      fontFamily: 'Lexend',
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 28.h),

            // ── Accept / Decline buttons ───────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Decline ────────────────────────────────────────────────
                _CallButton(
                  icon: Symbols.call_end,
                  label: 'call_decline'.tr(),
                  color: const Color(0xFFDC2626),
                  onTap: () => ref.read(callProvider.notifier).declineCall(),
                ),

                SizedBox(width: 60.w),

                // ── Accept ──────────────────────────────────────────────────────────────
                _CallButton(
                  icon: Symbols.call,
                  label: 'call_accept'.tr(),
                  color: const Color(0xFF16A34A),
                  onTap: () async {
                    await ref.read(callProvider.notifier).acceptCall();
                    if (mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const VoiceCallScreen(),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),

            SizedBox(height: 70.h),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CallButton: big circular accept / decline button
// ─────────────────────────────────────────────────────────────────────────────

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
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
            width: 70.w,
            height: 70.w,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, fill: 1, color: Colors.white, size: 30.w),
          ),
          SizedBox(height: 8.h),
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13.sp,
              fontFamily: 'Lexend',
            ),
          ),
        ],
      ),
    );
  }
}
