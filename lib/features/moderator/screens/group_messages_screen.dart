import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_dialog.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../shared/models/message_model.dart';
import '../../shared/providers/message_provider.dart';
import '../providers/moderator_provider.dart';
import '../../shared/widgets/group_chat_theme.dart';
import '../../shared/widgets/message_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Moderator Group Messages  (send + view + delete)
// ─────────────────────────────────────────────────────────────────────────────

class GroupMessagesScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;
  final String currentUserId;

  const GroupMessagesScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.currentUserId,
  });

  @override
  ConsumerState<GroupMessagesScreen> createState() =>
      _GroupMessagesScreenState();
}

class _GroupMessagesScreenState extends ConsumerState<GroupMessagesScreen> {
  // Scroll
  final _scrollController = ScrollController();

  // Compose state
  String _composeType = 'text'; // 'text' | 'voice' | 'tts'
  bool _isUrgent = false;
  final _textController = TextEditingController();

  // Voice Recording
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordedPath;
  int _recordSeconds = 0;
  Timer? _recordTimer;

  // Audio Playback (for voice messages + preview)
  final _player = AudioPlayer();
  String? _playingId; // message id, or '_preview' for recorded preview
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // TTS Playback (for viewing TTS messages)
  final _tts = FlutterTts();
  String? _ttsPlayingId;
  bool _ttsSpeaking = false;

  @override
  void initState() {
    super.initState();

    // Audio listeners
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playingId = null;
          _position = Duration.zero;
        });
      }
    });

    // TTS listeners
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
      ref.read(messageProvider.notifier).setActiveGroup(widget.groupId);
      ref.read(messageProvider.notifier).markAllRead(widget.groupId);
      ref.read(moderatorProvider.notifier).loadDashboard(silently: true);
      _load().then((_) => _scrollToBottom(jump: true));
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    _recordTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    _tts.stop();
    // Use addPostFrameCallback or delay to prevent state updates during build/dispose
    Future.microtask(() {
      if (ref.exists(messageProvider)) {
        ref.read(messageProvider.notifier).setActiveGroup(null);
      }
    });
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    await ref.read(messageProvider.notifier).loadMessages(widget.groupId);
  }

  void _scrollToBottom({bool jump = false}) {
    // With reverse:true, offset 0 = bottom (newest messages).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.offset <= 0) return; // already at bottom
      if (jump) {
        _scrollController.jumpTo(0);
      } else {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Playback ───────────────────────────────────────────────────────────────

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

  Future<void> _togglePreview() async {
    if (_recordedPath == null) return;
    if (_playingId == '_preview') {
      await _player.stop();
      setState(() {
        _playingId = null;
        _position = Duration.zero;
      });
      return;
    }
    setState(() {
      _playingId = '_preview';
      _position = Duration.zero;
    });
    await _player.play(DeviceFileSource(_recordedPath!));
  }

  // ── Recording ─────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _snack('msg_mic_required'.tr());
      return;
    }
    if (!await _recorder.hasPermission()) return;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _recordSeconds = 0;
      _recordedPath = null;
    });

    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      _recordedPath = path;
    });
  }

  void _discardRecording() {
    if (_recordedPath != null) {
      try {
        File(_recordedPath!).deleteSync();
      } catch (_) {}
    }
    setState(() {
      _recordedPath = null;
      _isRecording = false;
      _recordSeconds = 0;
    });
    if (_playingId == '_preview') {
      _player.stop();
      setState(() {
        _playingId = null;
        _position = Duration.zero;
      });
    }
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    FocusScope.of(context).unfocus();

    final ok = await ref
        .read(messageProvider.notifier)
        .sendTextMessage(
          groupId: widget.groupId,
          content: text,
          isUrgent: _isUrgent,
          isTts: _composeType == 'tts',
        );

    if (ok) {
      setState(() => _isUrgent = false);
      _scrollToBottom();
    } else {
      _snack('msg_send_failed'.tr());
    }
  }

  Future<void> _sendVoice() async {
    if (_recordedPath == null) return;
    if (_playingId == '_preview') {
      await _player.stop();
      setState(() {
        _playingId = null;
        _position = Duration.zero;
      });
    }

    final ok = await ref
        .read(messageProvider.notifier)
        .sendVoiceMessage(
          groupId: widget.groupId,
          filePath: _recordedPath!,
          isUrgent: _isUrgent,
          durationSeconds: _recordSeconds,
        );

    if (ok) {
      setState(() {
        _recordedPath = null;
        _isUrgent = false;
        _recordSeconds = 0;
      });
      _scrollToBottom();
    } else {
      _snack('msg_send_voice_failed'.tr());
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<void> _deleteMessage(GroupMessage msg) async {
    final confirmed = await StandardDialog.show<bool>(
      context: context,
      title: 'msg_delete_title',
      content: 'msg_delete_body',
      confirmText: 'msg_delete_confirm',
      cancelText: 'settings_cancel',
      isDestructive: true,
    );
    if (confirmed != true) return;
    final ok = await ref.read(messageProvider.notifier).deleteMessage(msg.id);
    if (!ok) _snack('msg_delete_failed'.tr());
  }

  void _snack(String text) {
    StandardSnackBar.showInfo(context, text);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final msgState = ref.watch(messageProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Scroll to bottom when new socket messages arrive
    ref.listen(messageProvider, (prev, next) {
      if (!next.isLoading &&
          (prev?.messages.length ?? 0) < next.messages.length) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      backgroundColor: GroupChatTheme.scaffoldBackground(isDark),
      body: SafeArea(
        child: Column(
          children: [
            GroupChatHeader(
              isDark: isDark,
              title: widget.groupName,
              subtitle: 'msg_broadcasts'.tr(),
              onRefresh: _load,
              onBack: () => Navigator.of(context).maybePop(),
              showBrandAvatar: true,
            ),
            Container(
              height: 46.h,
              color: GroupChatTheme.filterStripBackground(isDark),
            ),
            Expanded(
              child: msgState.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : _buildMessageList(msgState.messages, isDark),
            ),
            _buildComposer(isDark, msgState.isSending),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  // ── Message list ───────────────────────────────────────────────────────────

  Widget _buildMessageList(List<GroupMessage> messages, bool isDark) {
    if (messages.isEmpty) {
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

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
        itemCount: messages.length,
        itemBuilder: (_, i) {
          // reverse:true renders index 0 at the bottom;
          // map to newest-first order so newest = bottom.
          final msg = messages[messages.length - 1 - i];
          return _buildCard(msg, isDark);
        },
      ),
    );
  }

  // ── Message card ───────────────────────────────────────────────────────────

  Widget _buildCard(GroupMessage msg, bool isDark) {
    final cardBg = GroupChatTheme.cardBackground(
      isDark,
      urgent: msg.isUrgent,
      highlightNew: false,
    );
    final borderColor = GroupChatTheme.cardBorderColor(
      isDark,
      urgent: msg.isUrgent,
      highlightNew: false,
    );
    final borderWidth = GroupChatTheme.cardBorderWidth(
      urgent: msg.isUrgent,
      highlightNew: false,
    );

    return GestureDetector(
      onLongPress: () => _deleteMessage(msg),
      child: Container(
        margin: EdgeInsets.only(bottom: 10.h),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.035),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 14.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (msg.recipientId != null)
                Padding(
                  padding: EdgeInsets.only(bottom: 8.h),
                  child: Builder(
                    builder: (context) {
                      final modState = ref.watch(moderatorProvider);
                      final pilgrim = modState.currentGroup?.pilgrims.firstWhere(
                        (p) => p.id == msg.recipientId,
                        orElse: () =>
                            PilgrimInGroup(id: '', fullName: 'msg_private_indicator'.tr()),
                      );
                      return PrivateIndicator(
                        isForPilgrim: false,
                        recipientName: pilgrim?.fullName,
                      );
                    },
                  ),
                ),
              // Header row: type badges + delete button
              Row(
                children: [
                  MessageTypeBadge(type: msg.type),
                  SizedBox(width: 6.w),
                  if (msg.isUrgent) const UrgentBadge(),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _deleteMessage(msg),
                    child: Icon(
                      Symbols.delete_outline,
                      size: 18.w,
                      color: Colors.red.shade400,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              // Body
              if (msg.type == 'text') _buildTextBody(msg, isDark),
              if (msg.type == 'voice') _buildVoiceBody(msg, isDark),
              if (msg.type == 'tts') _buildTtsBody(msg, isDark),
              if (msg.type == 'meetpoint') _buildMeetpointBody(msg, isDark),
              SizedBox(height: 8.h),
              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    msg.sender?.fullName ?? 'you'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    _formatDate(msg.createdAt),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 11.sp,
                      color: AppColors.textMutedLight,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextBody(GroupMessage msg, bool isDark) {
    final bodyColor = isDark ? Colors.white.withValues(alpha: 0.88) : AppColors.textDark;
    return Text(
      msg.content ?? '',
      style: TextStyle(
        fontFamily: 'Lexend',
        fontSize: 15.sp,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: bodyColor,
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
      playCircleColor: isDark
          ? AppColors.info.withValues(alpha: 0.22)
          : AppColors.info.withValues(alpha: 0.12),
      playIconColor: AppColors.info,
    );
  }

  Widget _buildTtsBody(GroupMessage msg, bool isDark) {
    final isSpeaking = _ttsPlayingId == msg.id && _ttsSpeaking;
    final text = msg.originalText ?? msg.content ?? '';
    final bodyColor = isDark ? Colors.white.withValues(alpha: 0.88) : AppColors.textDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 15.sp,
            fontWeight: FontWeight.w400,
            height: 1.45,
            color: bodyColor,
          ),
        ),
        SizedBox(height: 12.h),
        TtsPlayAloudButton(
          isSpeaking: isSpeaking,
          onPressed: () => _toggleTts(msg),
          idleLabel: 'msg_play_aloud'.tr(),
          playingLabel: 'msg_playing'.tr(),
        ),
      ],
    );
  }

  Widget _buildMeetpointBody(GroupMessage msg, bool isDark) {
    final mp = msg.meetpointData;
    final name = mp?['name']?.toString() ?? msg.content ?? 'Meetpoint';
    final lat = (mp?['latitude'] as num?)?.toDouble();
    final lng = (mp?['longitude'] as num?)?.toDouble();
    final timeStr = mp?['meetpoint_time']?.toString();
    final DateTime? meetTime =
        timeStr != null ? DateTime.tryParse(timeStr) : null;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D1515) : const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: const Color(0xFFFECDD3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42.w,
                height: 42.w,
                decoration: BoxDecoration(
                  color: const Color(0xFFE11D48),
                  borderRadius: BorderRadius.circular(12.r),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE11D48).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child:
                    Icon(Symbols.crisis_alert, color: Colors.white, size: 22.w),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'area_meetpoint'.tr().toUpperCase(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w800,
                        fontSize: 10.sp,
                        letterSpacing: 0.5,
                        color: const Color(0xFFE11D48),
                      ),
                    ),
                    Text(
                      name,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                        fontSize: 16.sp,
                        color: isDark ? Colors.white : const Color(0xFF9F1239),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (meetTime != null) ...[
            SizedBox(height: 16.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.white70,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                children: [
                  Icon(
                    Symbols.schedule,
                    size: 18.w,
                    color: const Color(0xFFE11D48),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      'msg_meetpoint_at'.tr(args: [
                        DateFormat('hh:mm a').format(meetTime),
                        DateFormat('MMM dd').format(meetTime),
                      ]),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 13.sp,
                        color: isDark ? Colors.white : const Color(0xFF881337),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (msg.content != null &&
              msg.content!.isNotEmpty &&
              msg.content != name) ...[
            SizedBox(height: 12.h),
            Text(
              msg.content!,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                height: 1.5,
                color: isDark ? Colors.white70 : const Color(0xFF4C0519),
              ),
            ),
          ],
          if (lat != null && lng != null) ...[
            SizedBox(height: 16.h),
            ElevatedButton.icon(
              onPressed: () {
                final url = Uri.parse(
                  'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
                );
                launchUrl(url, mode: LaunchMode.externalApplication);
              },
              icon: Icon(Symbols.navigation, size: 18.w, color: Colors.white),
              label: Text(
                'area_navigate'.tr(),
                style: const TextStyle(fontFamily: 'Lexend'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE11D48),
                foregroundColor: Colors.white,
                minimumSize: Size(double.infinity, 44.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                elevation: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Composer ───────────────────────────────────────────────────────────────

  Widget _buildComposer(bool isDark, bool isSending) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 10.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Type selector row + urgent toggle
          Row(
            children: [
              _TypeButton(
                label: 'msg_tab_text'.tr(),
                icon: Symbols.text_fields,
                selected: _composeType == 'text',
                onTap: () => setState(() {
                  _composeType = 'text';
                  _discardRecording();
                }),
              ),
              SizedBox(width: 6.w),
              _TypeButton(
                label: 'msg_tab_voice'.tr(),
                icon: Symbols.mic,
                selected: _composeType == 'voice',
                onTap: () => setState(() => _composeType = 'voice'),
              ),
              SizedBox(width: 6.w),
              _TypeButton(
                label: 'msg_tab_tts'.tr(),
                icon: Symbols.volume_up,
                selected: _composeType == 'tts',
                onTap: () => setState(() {
                  _composeType = 'tts';
                  _discardRecording();
                }),
              ),
              const Spacer(),
              // Urgent toggle
              GestureDetector(
                onTap: () => setState(() => _isUrgent = !_isUrgent),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 6.h,
                  ),
                  decoration: BoxDecoration(
                    color: _isUrgent
                        ? Colors.red.shade600
                        : (isDark
                              ? Colors.white10
                              : Colors.black.withValues(alpha: 0.05)),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Symbols.warning,
                        size: 14.w,
                        color: _isUrgent
                            ? Colors.white
                            : AppColors.textMutedLight,
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        'msg_urgent'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: _isUrgent
                              ? Colors.white
                              : AppColors.textMutedLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          // Input area
          if (_composeType == 'text' || _composeType == 'tts')
            _buildTextInput(isDark, isSending)
          else
            _buildVoiceInput(isDark, isSending),
        ],
      ),
    );
  }

  Widget _buildTextInput(bool isDark, bool isSending) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: TextField(
              controller: _textController,
              maxLines: 4,
              minLines: 1,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
              decoration: InputDecoration(
                hintText: _composeType == 'tts'
                    ? 'msg_hint_tts'.tr()
                    : 'msg_hint_text'.tr(),
                hintStyle: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 14.sp,
                  color: AppColors.textMutedLight,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14.w,
                  vertical: 10.h,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 10.w),
        GestureDetector(
          onTap: isSending ? null : _sendText,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44.w,
            height: 44.w,
            decoration: BoxDecoration(
              color: isSending
                  ? AppColors.textMutedLight
                  : (_isUrgent ? Colors.red.shade600 : AppColors.primary),
              borderRadius: BorderRadius.circular(13.r),
            ),
            child: isSending
                ? Padding(
                    padding: EdgeInsets.all(12.w),
                    child: const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(Symbols.send, size: 20.w, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceInput(bool isDark, bool isSending) {
    // State machine: idle → recording → recorded (preview)
    if (_isRecording) {
      return _buildRecordingState(isDark);
    } else if (_recordedPath != null) {
      return _buildPreviewState(isDark, isSending);
    } else {
      return _buildIdleRecordState(isDark);
    }
  }

  Widget _buildIdleRecordState(bool isDark) {
    return Center(
      child: GestureDetector(
        onTap: _startRecording,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14.r),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.mic, size: 20.w, color: Colors.white),
              SizedBox(width: 8.w),
              Text(
                'msg_tap_record'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  fontSize: 14.sp,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingState(bool isDark) {
    final secs = _recordSeconds;
    final min = secs ~/ 60;
    final sec = (secs % 60).toString().padLeft(2, '0');

    return Row(
      children: [
        // Pulsing red mic
        Container(
          width: 44.w,
          height: 44.w,
          decoration: BoxDecoration(
            color: Colors.red.shade600,
            borderRadius: BorderRadius.circular(13.r),
          ),
          child: Icon(Symbols.mic, size: 20.w, color: Colors.white),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'msg_recording'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  fontSize: 13.sp,
                  color: Colors.red.shade600,
                ),
              ),
              Text(
                '$min:$sec',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12.sp,
                  color: AppColors.textMutedLight,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: _stopRecording,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: Colors.red.shade600,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Symbols.stop, size: 16.w, color: Colors.white),
                SizedBox(width: 6.w),
                Text(
                  'msg_stop'.tr(),
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

  Widget _buildPreviewState(bool isDark, bool isSending) {
    final isPlaying = _playingId == '_preview';
    final progress = (isPlaying && _duration.inMilliseconds > 0)
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Row(
      children: [
        // Waveform preview
        Expanded(
          child: WaveformPlayer(
            messageId: '_preview',
            isPlaying: isPlaying,
            progress: progress.clamp(0.0, 1.0),
            durationSeconds: _recordSeconds,
            positionSeconds: isPlaying ? _position.inSeconds : null,
            onToggle: _togglePreview,
            isDark: isDark,
            playCircleColor: isDark
                ? AppColors.info.withValues(alpha: 0.22)
                : AppColors.info.withValues(alpha: 0.12),
            playIconColor: AppColors.info,
          ),
        ),
        SizedBox(width: 8.w),
        // Discard
        GestureDetector(
          onTap: _discardRecording,
          child: Container(
            width: 40.w,
            height: 40.w,
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(
              Symbols.delete_outline,
              size: 18.w,
              color: Colors.red.shade600,
            ),
          ),
        ),
        SizedBox(width: 8.w),
        // Send
        GestureDetector(
          onTap: isSending ? null : _sendVoice,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44.w,
            height: 44.w,
            decoration: BoxDecoration(
              color: isSending
                  ? AppColors.textMutedLight
                  : (_isUrgent ? Colors.red.shade600 : AppColors.primary),
              borderRadius: BorderRadius.circular(13.r),
            ),
            child: isSending
                ? Padding(
                    padding: EdgeInsets.all(12.w),
                    child: const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(Symbols.send, size: 20.w, color: Colors.white),
          ),
        ),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final a = dt.hour >= 12 ? 'PM' : 'AM';
    final time = '$h:$m $a';
    if (diff == 0) return '${'inbox_today'.tr()}  $time';
    if (diff == 1) return '${'inbox_yesterday'.tr()}  $time';
    return '${dt.day}/${dt.month}/${dt.year}  $time';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Composer type button
// ─────────────────────────────────────────────────────────────────────────────

class _TypeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TypeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 7.h),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : (isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFFE2E8F0)),
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14.w,
              color: selected
                  ? Colors.white
                  : (isDark ? Colors.white70 : AppColors.textMutedLight),
            ),
            SizedBox(width: 4.w),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : (isDark ? Colors.white70 : AppColors.textMutedLight),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
