import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../shared/models/message_model.dart';
import '../../shared/providers/message_provider.dart';
import '../../shared/widgets/message_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim Group Inbox  (read-only)
// ─────────────────────────────────────────────────────────────────────────────

class GroupInboxScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;

  const GroupInboxScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  ConsumerState<GroupInboxScreen> createState() => _GroupInboxScreenState();
}

class _GroupInboxScreenState extends ConsumerState<GroupInboxScreen> {
  // Audio
  final _player = AudioPlayer();
  String? _playingId;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // TTS
  final _tts = FlutterTts();
  String? _ttsPlayingId;
  bool _ttsSpeaking = false;

  // UI
  String _filter = 'all'; // all | urgent | voice | tts
  final _scrollController = ScrollController();
  final Set<String> _newMessageIds = {};
  Timer? _highlightClearTimer;
  int _preLoadUnread = 0; // unread count captured before _load() runs
  bool _initialLoadDone = false; // true once the first load has completed

  final _filters = const [
    ('all', 'inbox_filter_all'),
    ('urgent', 'inbox_filter_urgent'),
    ('voice', 'inbox_filter_voice'),
    ('tts', 'inbox_filter_tts'),
  ];

  @override
  void initState() {
    super.initState();

    // Audio listeners
    _player.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playingId = null;
          _position = Duration.zero;
        });
      }
    });

    // TTS
    _tts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _ttsSpeaking = false;
          _ttsPlayingId = null;
        });
      }
    });
    _tts.setErrorHandler((_) {
      if (mounted) {
        setState(() {
          _ttsSpeaking = false;
          _ttsPlayingId = null;
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  @override
  void dispose() {
    _player.dispose();
    _tts.stop();
    _scrollController.dispose();
    _highlightClearTimer?.cancel();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    // Capture unread count BEFORE clearing it so we know which to highlight
    _preLoadUnread = ref.read(messageProvider).unreadCount;
    await ref.read(messageProvider.notifier).loadMessages(widget.groupId);
    await ref.read(messageProvider.notifier).markAllRead(widget.groupId);
    // Scroll + highlight triggered by ref.listen detecting isLoading → false
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (jump) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      } else {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<GroupMessage> get _filtered {
    final all = ref.read(messageProvider).messages;
    return switch (_filter) {
      'urgent' => all.where((m) => m.isUrgent).toList(),
      'voice' => all.where((m) => m.type == 'voice').toList(),
      'tts' => all.where((m) => m.type == 'tts').toList(),
      _ => all,
    };
  }

  // ── Audio ─────────────────────────────────────────────────────────────────

  Future<void> _toggleVoice(GroupMessage msg) async {
    if (_playingId == msg.id) {
      await _player.pause();
      setState(() => _playingId = null);
      return;
    }
    if (_ttsPlayingId != null) {
      await _tts.stop();
      setState(() {
        _ttsSpeaking = false;
        _ttsPlayingId = null;
      });
    }
    setState(() {
      _playingId = msg.id;
      _position = Duration.zero;
    });
    final url = ref
        .read(messageProvider.notifier)
        .buildUploadUrl(msg.mediaUrl!);
    await _player.play(UrlSource(url));
  }

  Future<void> _toggleTts(GroupMessage msg) async {
    final text = msg.originalText ?? msg.content ?? '';
    if (_ttsPlayingId == msg.id && _ttsSpeaking) {
      await _tts.stop();
      setState(() {
        _ttsSpeaking = false;
        _ttsPlayingId = null;
      });
      return;
    }
    if (_playingId != null) {
      await _player.stop();
      setState(() {
        _playingId = null;
        _position = Duration.zero;
      });
    }
    await _tts.stop();
    setState(() {
      _ttsPlayingId = msg.id;
      _ttsSpeaking = true;
    });
    await _tts.speak(text);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final msgState = ref.watch(messageProvider);
    final filtered = _filtered;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Scroll & highlight driven by provider changes
    ref.listen(messageProvider, (prev, next) {
      // ── Initial / pull-to-refresh load finished ──────────────────────────
      if ((prev?.isLoading ?? false) &&
          !next.isLoading &&
          next.messages.isNotEmpty) {
        if (!_initialLoadDone) {
          // Highlight the last N messages that were unread before opening
          final count = _preLoadUnread.clamp(1, next.messages.length);
          final highlightIds = next.messages
              .skip(next.messages.length - count)
              .map((m) => m.id)
              .toSet();
          setState(() {
            _initialLoadDone = true;
            _newMessageIds.addAll(highlightIds);
          });
          _highlightClearTimer?.cancel();
          _highlightClearTimer = Timer(const Duration(seconds: 4), () {
            if (mounted) setState(() => _newMessageIds.clear());
          });
        }
        _scrollToBottom(jump: true);
        return;
      }
      // ── New socket message appended (no loading state) ───────────────────
      if (!next.isLoading &&
          (prev?.messages.length ?? 0) < next.messages.length) {
        final prevIds = prev?.messages.map((m) => m.id).toSet() ?? {};
        final arrivedIds = next.messages
            .where((m) => !prevIds.contains(m.id))
            .map((m) => m.id)
            .toSet();
        if (arrivedIds.isNotEmpty) {
          setState(() => _newMessageIds.addAll(arrivedIds));
          _highlightClearTimer?.cancel();
          _highlightClearTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _newMessageIds.clear());
          });
          _scrollToBottom(); // smooth animate — no flicker
        }
      }
    });

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDark),
            _buildFilterRow(isDark),
            Expanded(
              child: msgState.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : filtered.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _load,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _buildCard(filtered[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 16.w, 8.h),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Symbols.arrow_back,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          SizedBox(width: 4.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.groupName,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 16.sp,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'inbox_title'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _load,
            child: Container(
              width: 36.w,
              height: 36.w,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
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

  // ── Filter chips ──────────────────────────────────────────────────────────

  Widget _buildFilterRow(bool isDark) {
    return Container(
      height: 44.h,
      color: isDark ? AppColors.surfaceDark : Colors.white,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        itemCount: _filters.length,
        separatorBuilder: (_, _) => SizedBox(width: 8.w),
        itemBuilder: (_, i) {
          final (key, label) = _filters[i];
          final selected = _filter == key;
          return GestureDetector(
            onTap: () => setState(() => _filter = key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : (isDark ? Colors.white24 : Colors.black12),
                ),
              ),
              child: Text(
                label.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : (isDark ? Colors.white70 : AppColors.textMutedLight),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.inbox, size: 48.w, color: AppColors.textMutedLight),
          SizedBox(height: 12.h),
          Text(
            'inbox_empty'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 15.sp,
              color: AppColors.textMutedLight,
            ),
          ),
        ],
      ),
    );
  }

  // ── Message card ──────────────────────────────────────────────────────────

  Widget _buildCard(GroupMessage msg) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrgent = msg.isUrgent;
    final isNew = _newMessageIds.contains(msg.id);

    Color cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    Color borderColor = Colors.transparent;
    if (isUrgent) {
      cardBg = isDark ? const Color(0xFF2D1515) : const Color(0xFFFEF2F2);
      borderColor = const Color(0xFFFECACA);
    } else if (isNew) {
      cardBg = isDark ? const Color(0xFF1A2A1A) : const Color(0xFFECFDF5);
      borderColor = AppColors.primary.withOpacity(0.5);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: borderColor, width: isNew ? 1.8 : 1.2),
        boxShadow: [
          BoxShadow(
            color: isNew
                ? AppColors.primary.withOpacity(0.15)
                : Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: isNew ? 14 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(msg, isDark),
            SizedBox(height: 10.h),
            if (msg.type == 'text') _buildTextBody(msg, isDark),
            if (msg.type == 'voice') _buildVoiceBody(msg, isDark),
            if (msg.type == 'tts') _buildTtsBody(msg, isDark),
            if (msg.type == 'meetpoint') _buildMeetpointBody(msg, isDark),
            SizedBox(height: 8.h),
            _buildCardFooter(msg, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildCardHeader(GroupMessage msg, bool isDark) {
    return Row(
      children: [
        // Avatar
        CircleAvatar(
          radius: 18.r,
          backgroundColor: AppColors.primary.withOpacity(0.15),
          child: Text(
            msg.sender?.initial ?? 'M',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 14.sp,
              color: AppColors.primary,
            ),
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                msg.sender?.fullName ?? 'settings_role_moderator'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  fontSize: 13.sp,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
              Row(
                children: [
                  MessageTypeBadge(type: msg.type),
                  if (msg.isUrgent) ...[
                    SizedBox(width: 6.w),
                    const UrgentBadge(),
                  ],
                ],
              ),
            ],
          ),
        ),
        Text(
          _formatTime(msg.createdAt),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 11.sp,
            color: AppColors.textMutedLight,
          ),
        ),
      ],
    );
  }

  Widget _buildTextBody(GroupMessage msg, bool isDark) {
    return Text(
      msg.content ?? '',
      style: TextStyle(
        fontFamily: 'Lexend',
        fontSize: 14.sp,
        height: 1.5,
        color: isDark ? Colors.white70 : AppColors.textDark,
      ),
    );
  }

  Widget _buildVoiceBody(GroupMessage msg, bool isDark) {
    final isPlaying = _playingId == msg.id;
    final progress = (isPlaying && _duration.inMilliseconds > 0)
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return WaveformPlayer(
      messageId: msg.id,
      isPlaying: isPlaying,
      progress: progress.clamp(0.0, 1.0),
      durationSeconds: msg.duration,
      positionSeconds: isPlaying ? _position.inSeconds : null,
      onToggle: () => _toggleVoice(msg),
      isDark: isDark,
    );
  }

  Widget _buildTtsBody(GroupMessage msg, bool isDark) {
    final isSpeaking = _ttsPlayingId == msg.id && _ttsSpeaking;
    final text = msg.originalText ?? msg.content ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Blue TTS label pill
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
          decoration: BoxDecoration(
            color: const Color(0xFFDBEAFE),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.volume_up,
                size: 14.w,
                color: const Color(0xFF1D4ED8),
              ),
              SizedBox(width: 4.w),
              Text(
                'msg_tts_label'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1D4ED8),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          text,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14.sp,
            height: 1.5,
            color: isDark ? Colors.white70 : AppColors.textDark,
          ),
        ),
        SizedBox(height: 10.h),
        GestureDetector(
          onTap: () => _toggleTts(msg),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 9.h),
            decoration: BoxDecoration(
              color: isSpeaking ? Colors.red.shade600 : const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSpeaking ? Symbols.pause : Symbols.play_arrow,
                  size: 16.w,
                  color: Colors.white,
                ),
                SizedBox(width: 6.w),
                Text(
                  isSpeaking ? 'msg_playing'.tr() : 'msg_play_aloud'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 13.sp,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMeetpointBody(GroupMessage msg, bool isDark) {
    final mp = msg.meetpointData;
    final name = mp?['name']?.toString() ?? msg.content ?? 'Meetpoint';
    final lat = (mp?['latitude'] as num?)?.toDouble();
    final lng = (mp?['longitude'] as num?)?.toDouble();

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3B1212) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34.w,
                height: 34.w,
                decoration: const BoxDecoration(
                  color: Color(0xFFDC2626),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Symbols.crisis_alert,
                  color: Colors.white,
                  size: 18.w,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'area_meetpoint'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                        fontSize: 10.sp,
                        color: const Color(0xFFDC2626),
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      name,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 14.sp,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (msg.content != null &&
              msg.content!.isNotEmpty &&
              msg.content != name) ...[
            SizedBox(height: 8.h),
            Text(
              msg.content!,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                height: 1.4,
                color: isDark ? Colors.white70 : AppColors.textDark,
              ),
            ),
          ],
          if (lat != null && lng != null) ...[
            SizedBox(height: 10.h),
            GestureDetector(
              onTap: () {
                final url = Uri.parse(
                  'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
                );
                launchUrl(url, mode: LaunchMode.externalApplication);
              },
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 10.h),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Symbols.navigation,
                      size: 16.w,
                      color: Colors.white,
                      fill: 1,
                    ),
                    SizedBox(width: 6.w),
                    Text(
                      'area_navigate'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                        fontSize: 13.sp,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardFooter(GroupMessage msg, bool isDark) {
    return Text(
      _formatDate(msg.createdAt),
      style: TextStyle(
        fontFamily: 'Lexend',
        fontSize: 11.sp,
        color: AppColors.textMutedLight,
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final a = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $a';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;
    if (diff == 0) return 'inbox_today'.tr();
    if (diff == 1) return 'inbox_yesterday'.tr();
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
