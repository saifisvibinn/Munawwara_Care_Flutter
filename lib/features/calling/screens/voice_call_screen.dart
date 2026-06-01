import 'dart:async';
import 'dart:ui' show FilterQuality, FontFeature, ImageFilter;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/services/callkit_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/support_dialogs.dart';
import '../../shared/widgets/pilgrim_gender_avatar.dart';
import '../providers/call_provider.dart';
import '../widgets/call_peer_display.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VoiceCallScreen — in-app voice call UI (outgoing / connected / ended)
// Uses AppColors + theme brightness to match Munawwara Care elsewhere.
// ─────────────────────────────────────────────────────────────────────────────

class VoiceCallScreen extends ConsumerStatefulWidget {
  static bool isActive = false;

  final List<Map<String, String>>? autoRouteMods;
  final VoidCallback? onAllBusy;

  /// Seeds the header before [callProvider] finishes async setup (UI only).
  final String? initialPeerName;

  /// Seeds pilgrim avatar before [CallState.remotePeerGender] is set.
  final String? initialPeerGender;

  const VoiceCallScreen({
    super.key,
    this.autoRouteMods,
    this.onAllBusy,
    this.initialPeerName,
    this.initialPeerGender,
  });

  @override
  ConsumerState<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends ConsumerState<VoiceCallScreen> {
  late List<Map<String, String>> _queue;
  String? _cachedName;
  String? _cachedGender;
  Timer? _autoPopTimer;
  bool _showRatingOnPop = false;

  @override
  void initState() {
    super.initState();
    VoiceCallScreen.isActive = true;
    _queue = List.from(widget.autoRouteMods ?? []);
    _seedDisplayCache();
  }

  void _seedDisplayCache() {
    if (!isUnresolvedCallPeerName(widget.initialPeerName)) {
      _cachedName = widget.initialPeerName!.trim();
    }
    final initialGender = widget.initialPeerGender?.trim();
    if (initialGender != null && initialGender.isNotEmpty) {
      _cachedGender = initialGender;
    }
    final call = ref.read(callProvider);
    final resolved = resolveCallPeerDisplayName(
      call: call,
      cachedName: _cachedName,
    );
    if (resolved.isNotEmpty) {
      _cachedName = resolved;
    }
    final gender = call.remotePeerGender?.trim();
    if (gender != null && gender.isNotEmpty) {
      _cachedGender = gender;
    }
  }

  void _syncDisplayCache(CallState call) {
    final resolved = resolveCallPeerDisplayName(
      call: call,
      cachedName: _cachedName,
    );
    if (resolved.isNotEmpty) {
      _cachedName = resolved;
    }
    final gender = call.remotePeerGender?.trim();
    if (gender != null && gender.isNotEmpty) {
      _cachedGender = gender;
    }
  }

  @override
  void dispose() {
    _autoPopTimer?.cancel();
    VoiceCallScreen.isActive = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = _CallPalette(isDark);

    _syncDisplayCache(call);

    ref.listen(callProvider, (prev, next) {
      if (next.status == CallStatus.ended &&
          prev?.status == CallStatus.connected) {
        _showRatingOnPop = true;
      }

      if (next.status == CallStatus.ended &&
          prev?.status != CallStatus.ended &&
          mounted) {
        final autoRouteReasons = [
          'declined',
          'busy',
          'error',
          'missed',
          'timeout',
        ];
        final isAutoRouteReason = autoRouteReasons.contains(next.endReason);

        if (isAutoRouteReason && _queue.isNotEmpty) {
          _autoPopTimer?.cancel();
          _autoPopTimer = Timer(const Duration(seconds: 1), () {
            if (!mounted) return;
            final nextMod = _queue.removeAt(0);
            // Do not cache moderator personal name — pilgrim UI uses support label
            // from [callProvider]; caching here would override it on the next frame.
            final nextName = nextMod['name']?.trim();
            final nextGender = nextMod['gender']?.trim();
            setState(() {
              _cachedName = isUnresolvedCallPeerName(nextName) ? null : nextName;
              _cachedGender =
                  (nextGender != null && nextGender.isNotEmpty)
                      ? nextGender
                      : null;
            });
            ref
                .read(callProvider.notifier)
                .startCall(
                  remoteUserId: nextMod['id']!,
                  remoteUserName: nextMod['name'] ?? '',
                  remotePeerGender: nextMod['gender'],
                );
          });
        } else {
          _autoPopTimer?.cancel();
          _autoPopTimer = Timer(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.of(context).maybePop();
              if (isAutoRouteReason && widget.onAllBusy != null) {
                widget.onAllBusy!();
              }
              if (_showRatingOnPop) {
                SupportDialogs.showRating(context, isContextual: true);
              }
            }
          });
        }
      }
      if (next.status == CallStatus.idle &&
          prev?.status != CallStatus.ended &&
          mounted) {
        Navigator.of(context).maybePop();
        if (_showRatingOnPop) {
          SupportDialogs.showRating(context, isContextual: true);
        }
      }
    });

    final displayName = resolveCallPeerDisplayName(
      call: call,
      cachedName: _cachedName,
    );
    final showPeerName = displayName.isNotEmpty;
    final initials = showPeerName ? callPeerInitials(displayName) : '';

    final canPop = call.status == CallStatus.ended || call.status == CallStatus.idle;

    return PopScope(
      canPop: canPop,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: c.backgroundGradient),
          child: Stack(
            children: [
              Positioned(
                top: -80.h,
                right: -40.w,
                child: _BlurOrb(
                  color: AppColors.primary.withValues(
                    alpha: isDark ? 0.12 : 0.18,
                  ),
                  size: 220,
                ),
              ),
              Positioned(
                bottom: 40.h,
                left: -60.w,
                child: _BlurOrb(
                  color: AppColors.accentGold.withValues(
                    alpha: isDark ? 0.06 : 0.1,
                  ),
                  size: 180,
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20.w,
                        vertical: 10.h,
                      ),
                      child: Center(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14.w,
                            vertical: 8.h,
                          ),
                          decoration: BoxDecoration(
                            color: c.chipFill,
                            borderRadius: BorderRadius.circular(20.r),
                            border: Border.all(color: c.chipBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Symbols.wifi_calling_3,
                                size: 17.sp,
                                color: AppColors.primary,
                              ),
                              SizedBox(width: 8.w),
                              Text(
                                'call_internet'.tr(),
                                style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 12.sp,
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Expanded(
                      child: Column(
                        children: [
                          const Spacer(flex: 2),
                          if (call.displayPeerAsSupportBranding)
                            _SupportBrandingAvatar(palette: c)
                          else if (call.isGroupRingingOut)
                            _AvatarRing(initials: initials, palette: c)
                          else
                            _PilgrimPeerAvatar(
                              gender: _cachedGender ?? call.remotePeerGender,
                              palette: c,
                            ),
                          SizedBox(height: 22.h),
                          Opacity(
                            opacity: showPeerName ? 1 : 0,
                            child: Text(
                              showPeerName ? displayName : ' ',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24.sp,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Lexend',
                                color: c.textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          SizedBox(height: 10.h),
                          _StatusChip(
                            call: call,
                            palette: c,
                            endedMessage: call.status == CallStatus.ended
                                ? _endReasonLabel(call.endReason)
                                : null,
                          ),
                          const Spacer(flex: 3),
                          if (call.status == CallStatus.calling ||
                              call.status == CallStatus.ringing ||
                              call.status == CallStatus.connecting ||
                              call.status == CallStatus.connected) ...[
                            Container(
                              margin: EdgeInsets.symmetric(horizontal: 28.w),
                              padding: EdgeInsets.symmetric(
                                vertical: 18.h,
                                horizontal: 12.w,
                              ),
                              decoration: BoxDecoration(
                                color: c.panelFill,
                                borderRadius: BorderRadius.circular(22.r),
                                border: Border.all(color: c.panelBorder),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _ControlTile(
                                    icon: call.isMuted
                                        ? Symbols.mic_off
                                        : Symbols.mic,
                                    label: call.isMuted
                                        ? 'call_unmute'.tr()
                                        : 'call_mute'.tr(),
                                    active: call.isMuted,
                                    palette: c,
                                    onTap: () => ref
                                        .read(callProvider.notifier)
                                        .toggleMute(),
                                  ),
                                  _ControlTile(
                                    icon: call.isSpeakerOn
                                        ? Symbols.volume_up
                                        : Symbols.hearing,
                                    label: call.isSpeakerOn
                                        ? 'call_speaker'.tr()
                                        : 'call_earpiece'.tr(),
                                    active: call.isSpeakerOn,
                                    palette: c,
                                    onTap: () => ref
                                        .read(callProvider.notifier)
                                        .toggleSpeaker(),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 28.h),
                          ],
                          if (call.status != CallStatus.ended) ...[
                            GestureDetector(
                              onTap: () {
                                _queue.clear();
                                final notifier = ref.read(callProvider.notifier);
                                if (call.status == CallStatus.calling) {
                                  notifier.cancelOutgoingRing();
                                } else if (call.status == CallStatus.ringing) {
                                  notifier.declineCall();
                                } else {
                                  notifier.endCall();
                                }
                              },
                              child: Container(
                                width: 76.w,
                                height: 76.w,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.error,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.error.withValues(
                                        alpha: 0.35,
                                      ),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Symbols.call_end,
                                  color: Colors.white,
                                  size: 34.sp,
                                  fill: 1,
                                ),
                              ),
                            ),
                          ],
                          SizedBox(height: 48.h),
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
    );
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

class _CallPalette {
  _CallPalette(bool isDark)
    : textPrimary = isDark ? AppColors.textLight : AppColors.textDark,
      textSecondary = isDark
          ? AppColors.textMutedLight
          : AppColors.textMutedDark,
      textMuted = isDark
          ? AppColors.textMutedLight.withValues(alpha: 0.75)
          : AppColors.textMutedDark,
      chipFill = isDark
          ? AppColors.surfaceDark.withValues(alpha: 0.85)
          : Colors.white.withValues(alpha: 0.92),
      chipBorder = isDark ? AppColors.dividerDark : AppColors.dividerLight,
      panelFill = isDark ? AppColors.surfaceDark : Colors.white,
      panelBorder = isDark ? AppColors.dividerDark : AppColors.dividerLight,
      avatarRing = isDark ? AppColors.dividerDark : AppColors.dividerLight,
      backgroundGradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                AppColors.backgroundDark,
                Color.lerp(
                  AppColors.backgroundDark,
                  const Color(0xFF151D2E),
                  0.5,
                )!,
              ]
            : [AppColors.backgroundLight, const Color(0xFFE4E7F5)],
      );

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color chipFill;
  final Color chipBorder;
  final Color panelFill;
  final Color panelBorder;
  final Color avatarRing;
  final LinearGradient backgroundGradient;
}

class _BlurOrb extends StatelessWidget {
  const _BlurOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

class _PilgrimPeerAvatar extends StatelessWidget {
  const _PilgrimPeerAvatar({required this.gender, required this.palette});

  final String? gender;
  final _CallPalette palette;

  @override
  Widget build(BuildContext context) {
    final inner = 124.w - 8.w;
    return Container(
      width: 124.w,
      height: 124.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.avatarRing, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 28,
            spreadRadius: 0,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: EdgeInsets.all(4.w),
      child: PilgrimGenderAvatar(gender: gender, size: inner),
    );
  }
}

class _SupportBrandingAvatar extends StatelessWidget {
  const _SupportBrandingAvatar({required this.palette});

  final _CallPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 124.w,
      height: 124.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.avatarRing, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 28,
            spreadRadius: 0,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: EdgeInsets.all(4.w),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: ClipOval(
          child: Padding(
            padding: EdgeInsets.all(18.w),
            child: Image.asset(
              kCallKitSupportAvatarAsset,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarRing extends StatelessWidget {
  const _AvatarRing({required this.initials, required this.palette});

  final String initials;
  final _CallPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 124.w,
      height: 124.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.avatarRing, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 28,
            spreadRadius: 0,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: EdgeInsets.all(4.w),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Text(
            initials.isEmpty ? '?' : initials,
            style: TextStyle(
              fontSize: 36.sp,
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.call,
    required this.palette,
    this.endedMessage,
  });

  final CallState call;
  final _CallPalette palette;

  /// When the call has just ended, show this in the same slot as the timer
  /// so the Munawwara logo block does not jump vertically.
  final String? endedMessage;

  @override
  Widget build(BuildContext context) {
    if (call.status == CallStatus.ended) {
      final text = endedMessage ?? '';
      if (text.isEmpty) {
        return SizedBox(height: 44.h);
      }
      return Container(
        constraints: BoxConstraints(minHeight: 44.h),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: palette.chipFill,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: palette.chipBorder),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.sp,
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            color: palette.textSecondary,
            height: 1.3,
          ),
        ),
      );
    }

    final label = switch (call.status) {
      CallStatus.calling => 'call_calling'.tr(),
      CallStatus.connecting => 'call_connecting'.tr(),
      CallStatus.connected => call.formattedDuration,
      _ => '',
    };
    if (label.isEmpty) return const SizedBox.shrink();

    final isLive = call.status == CallStatus.connected;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: isLive
            ? AppColors.primary.withValues(alpha: 0.14)
            : palette.chipFill,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isLive
              ? AppColors.primary.withValues(alpha: 0.45)
              : palette.chipBorder,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: isLive ? 18.sp : 13.sp,
          fontFamily: 'Lexend',
          fontWeight: FontWeight.w600,
          color: isLive ? AppColors.primary : palette.textSecondary,
          letterSpacing: isLive ? 1.2 : 0.2,
          fontFeatures: isLive ? const [FontFeature.tabularFigures()] : null,
        ),
      ),
    );
  }
}

class _ControlTile extends StatelessWidget {
  const _ControlTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final _CallPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56.w,
                height: 56.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? AppColors.primary.withValues(alpha: 0.2)
                      : palette.chipFill,
                  border: Border.all(
                    color: active
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : palette.chipBorder,
                  ),
                ),
                child: Icon(
                  icon,
                  fill: 1,
                  color: active ? AppColors.primary : palette.textPrimary,
                  size: 26.sp,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                label,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 11.sp,
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
