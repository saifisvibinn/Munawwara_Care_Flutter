import 'dart:async';
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/incoming_chat_sfx.dart';
import '../services/speech_service.dart';
import '../theme/app_colors.dart';

class InAppPopup {
  static OverlayEntry? _current;
  static Timer? _autoHide;

  static void show(
    BuildContext context, {
    required String title,
    required String body,
    bool isUrgent = false,
    VoidCallback? onViewChat,
    bool lockUntilDismiss = false,
    String? playType,
    String? playValue,
    String? playTtsAudioUrl,
    String playLocale = 'en',
    Duration? duration,
  }) {
    _dismiss();
    final overlay = Overlay.of(context);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _PopupCard(
        senderName: title,
        body: body,
        isUrgent: isUrgent,
        isMeetpoint: false,
        onViewChat: onViewChat,
        lockUntilDismiss: lockUntilDismiss,
        playType: playType,
        playValue: playValue,
        playTtsAudioUrl: playTtsAudioUrl,
        playLocale: playLocale,
        onDismiss: _dismiss,
      ),
    );

    _current = entry;
    overlay.insert(entry);

    if (!lockUntilDismiss && duration != null) {
      _autoHide = Timer(duration, _dismiss);
    }
  }

  static void showMeetpoint(
    BuildContext context, {
    required String name,
    String? body,
    String? time,
    VoidCallback? onNavigate,
    Duration? duration,
  }) {
    _dismiss();
    final overlay = Overlay.of(context);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _PopupCard(
        senderName: name,
        body: body ?? '',
        time: time,
        isUrgent: true,
        isMeetpoint: true,
        onNavigate: onNavigate,
        onDismiss: _dismiss,
      ),
    );

    _current = entry;
    overlay.insert(entry);

    if (duration != null) {
      _autoHide = Timer(duration, _dismiss);
    }
  }

  static void _dismiss() {
    _autoHide?.cancel();
    _autoHide = null;
    _current?.remove();
    _current = null;
  }
}

class _PopupCard extends StatefulWidget {
  final String senderName;
  final String body;
  final String? time;
  final bool isUrgent;
  final bool isMeetpoint;
  final VoidCallback? onViewChat;
  final VoidCallback? onDismiss;
  final VoidCallback? onNavigate;
  final bool lockUntilDismiss;
  final String? playType;
  final String? playValue;
  final String? playTtsAudioUrl;
  final String playLocale;

  const _PopupCard({
    required this.senderName,
    required this.body,
    required this.isUrgent,
    required this.isMeetpoint,
    this.onViewChat,
    this.onDismiss,
    this.onNavigate,
    this.time,
    this.lockUntilDismiss = false,
    this.playType,
    this.playValue,
    this.playTtsAudioUrl,
    this.playLocale = 'en',
  });

  @override
  State<_PopupCard> createState() => _PopupCardState();
}

class _PopupCardState extends State<_PopupCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  /// True after the first full play (or error) so "Replay audio" enables.
  bool _replayUnlocked = false;

  void _markPlaybackFinished() {
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _replayUnlocked = true;
    });
  }

  /// Waits for [AudioPlayer] URL/device playback to finish (see [_runPlayback]).
  Future<void> _awaitAudioplayersSourceEnd() async {
    try {
      await _player.onPlayerComplete.first.timeout(
        const Duration(minutes: 5),
      );
    } on TimeoutException {
      await _player.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _scaleAnim = Tween<double>(
      begin: 0.85,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: widget.isUrgent ? Curves.elasticOut : Curves.easeOutCubic,
    ));

    _controller.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canPlay) {
        if (mounted) setState(() => _replayUnlocked = true);
        return;
      }
      _runPlayback();
    });
  }

  bool get _canPlay {
    final type = widget.playType;
    final value = widget.playValue;
    if (type == 'voice') {
      return value != null && value.isNotEmpty;
    }
    if (type == 'tts') {
      final hasText = value != null && value.trim().isNotEmpty;
      final hasUrl = widget.playTtsAudioUrl != null &&
          widget.playTtsAudioUrl!.trim().isNotEmpty;
      return hasText || hasUrl;
    }
    return false;
  }

  Future<void> _stopPlayback() async {
    await IncomingChatSfx.stop();
    await SpeechService.stop();
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _replayUnlocked = true;
    });
  }

  Future<void> _onReplayPressed() async {
    if (!_replayUnlocked || _isPlaying) return;
    await _runPlayback();
  }

  Future<void> _runPlayback() async {
    if (!_canPlay || !mounted) return;

    final type = widget.playType;
    final value = widget.playValue;

    try {
      await IncomingChatSfx.stop();
      await SpeechService.stop();
      await _player.stop();

      if (type == 'voice') {
        try {
          await _player.play(UrlSource(value!));
          if (mounted) setState(() => _isPlaying = true);
          await _awaitAudioplayersSourceEnd();
        } catch (_) {
          // UrlSource failed or playback error.
        }
        _markPlaybackFinished();
        return;
      }

      if (type == 'tts') {
        final url = widget.playTtsAudioUrl?.trim();
        final text = value?.trim() ?? '';
        if (text.isEmpty && (url == null || url.isEmpty)) {
          _markPlaybackFinished();
          return;
        }
        if (mounted) setState(() => _isPlaying = true);
        try {
          await SpeechService.playRobust(
            audioUrl: (url != null && url.isNotEmpty) ? url : null,
            backupText: text,
            lang: widget.playLocale,
          );
        } finally {
          _markPlaybackFinished();
        }
      }
    } catch (_) {
      _markPlaybackFinished();
    }
  }

  @override
  void dispose() {
    unawaited(IncomingChatSfx.stop());
    unawaited(SpeechService.stop());
    _player.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned.fill(
      child: Stack(
        children: [
          // Blur + dim — shown instantly so it never lags behind the card
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
              child: Container(
                color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.26),
              ),
            ),
          ),
          // Card — fades + scales in
          Positioned.fill(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Align(
                alignment: Alignment.center,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 28.w),
                  child: ScaleTransition(
                    scale: _scaleAnim,
                    child: _buildCard(context, isDark),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, bool isDark) {
    if (widget.isMeetpoint) {
      return _buildMeetpointCard(context, isDark);
    }
    return _buildMessageCard(context, isDark);
  }

  Widget _buildMessageCard(BuildContext context, bool isDark) {
    final accent = widget.isUrgent
        ? const Color(0xFFDC2626)
        : AppColors.primary;
    final icon = widget.isUrgent ? Symbols.emergency : Symbols.chat;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 1.sw,
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 14.h),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(
            color: widget.isUrgent ? const Color(0xFFDC2626) : const Color(0xFFE5E7EB),
            width: widget.isUrgent ? 3.0 : 1.0,
          ),
          boxShadow: [
            if (widget.isUrgent)
              BoxShadow(
                color: const Color(0xFFDC2626).withValues(alpha: isDark ? 0.35 : 0.2),
                blurRadius: 32,
                spreadRadius: 2,
              ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.14),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42.w,
                  height: 42.w,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: accent, size: 22.w),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.isUrgent
                                  ? 'popup_urgent_message'.tr()
                                  : 'popup_new_message'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w700,
                                fontSize: 17.sp,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF111827),
                              ),
                            ),
                          ),
                          Text(
                            'popup_now'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 10.sp,
                              color: const Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        widget.senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 11.sp,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF202734)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
                ),
              ),
              child: Text(
                widget.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12.sp,
                  height: 1.35,
                  color: isDark ? Colors.white70 : const Color(0xFF1F2937),
                ),
              ),
            ),
            if (_canPlay) ...[
              SizedBox(height: 12.h),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    if (_isPlaying)
                      OutlinedButton.icon(
                        onPressed: _stopPlayback,
                        icon: Icon(
                          Symbols.stop_circle,
                          size: 16.w,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                        label: Text(
                          'msg_stop'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: isDark
                                ? Colors.white24
                                : const Color(0xFFD1D5DB),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(99.r),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: 16.w,
                            vertical: 8.h,
                          ),
                        ),
                      ),
                    Builder(
                      builder: (context) {
                        final canReplay = _replayUnlocked && !_isPlaying;
                        final onFg = canReplay
                            ? (isDark ? Colors.white : AppColors.textDark)
                            : (isDark
                                  ? Colors.white38
                                  : const Color(0xFF9CA3AF));
                        return OutlinedButton.icon(
                          onPressed: canReplay ? _onReplayPressed : null,
                          icon: Icon(Symbols.repeat, size: 16.w, color: onFg),
                          label: Text(
                            'popup_replay_audio'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w600,
                              color: onFg,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: onFg,
                            disabledForegroundColor: isDark
                                ? Colors.white38
                                : const Color(0xFF9CA3AF),
                            side: BorderSide(
                              color: isDark
                                  ? Colors.white24
                                  : const Color(0xFFD1D5DB),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(99.r),
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: 16.w,
                              vertical: 8.h,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 14.h),
            SizedBox(
              width: double.infinity,
              height: 46.h,
              child: ElevatedButton.icon(
                onPressed: () {
                  widget.onDismiss?.call();
                  widget.onViewChat?.call();
                },
                icon: Icon(Symbols.visibility, size: 18.w, color: Colors.white),
                label: Text(
                  'popup_view_chat'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 13.sp,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                ),
              ),
            ),
            SizedBox(height: 6.h),
            TextButton(
              onPressed: widget.onDismiss,
              child: Text(
                'popup_dismiss'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w500,
                  fontSize: 11.sp,
                  color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeetpointCard(BuildContext context, bool isDark) {
    const red = Color(0xFFDC2626);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 1.sw,
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 14.h),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(
            color: const Color(0xFFDC2626),
            width: 3.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44.w,
                  height: 44.w,
                  decoration: BoxDecoration(
                    color: red.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Symbols.campaign, color: red, size: 22.w),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'popup_urgent_meetpoint'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w700,
                                fontSize: 16.sp,
                                color: red,
                              ),
                            ),
                          ),
                          if (widget.time != null)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8.w,
                                vertical: 2.h,
                              ),
                              decoration: BoxDecoration(
                                color: red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6.r),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Symbols.schedule,
                                    size: 12.w,
                                    color: red,
                                  ),
                                  SizedBox(width: 4.w),
                                  Text(
                                    widget.time!,
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11.sp,
                                      color: red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        widget.senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 13.sp,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF111827),
                        ),
                      ),
                      if (widget.body.isNotEmpty) ...[
                        SizedBox(height: 2.h),
                        Text(
                          widget.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12.sp,
                            color: isDark
                                ? Colors.white60
                                : const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 14.h),
            Row(
              children: [
                if (widget.onNavigate != null) ...[
                  Expanded(
                    child: SizedBox(
                      height: 46.h,
                      child: ElevatedButton.icon(
                        onPressed: widget.onNavigate,
                        icon: Icon(
                          Symbols.navigation,
                          size: 18.w,
                          color: Colors.white,
                        ),
                        label: Text(
                          'area_navigate'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            fontSize: 13.sp,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.r),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                ],
                Expanded(
                  child: SizedBox(
                    height: 46.h,
                    child: OutlinedButton(
                      onPressed: widget.onDismiss,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: isDark
                              ? Colors.white24
                              : const Color(0xFFD1D5DB),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                      ),
                      child: Text(
                        'popup_dismiss'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 13.sp,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF1F2937),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
