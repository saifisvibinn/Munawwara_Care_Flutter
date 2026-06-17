import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/tts_cloud_api.dart';
import '../../../core/services/speech_service.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../shared/helpers/message_visibility.dart';
import '../../shared/models/message_model.dart';
import '../../shared/helpers/chat_popup_dedup.dart';
import '../../shared/providers/message_provider.dart';
import '../../shared/widgets/group_chat_theme.dart';
import '../../shared/widgets/message_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim Group Inbox  (read-only)
// ─────────────────────────────────────────────────────────────────────────────

class GroupInboxScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;

  /// Increment this notifier to trigger a scroll-to-bottom (e.g. on tab switch).
  final ValueNotifier<int>? scrollNotifier;

  const GroupInboxScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    this.scrollNotifier,
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
  final _sfxPlayer = AudioPlayer();

  // TTS
  String? _ttsPlayingId;
  bool _ttsSpeaking = false;
  bool _ttsLoading = false;

  // UI
  String _filter = 'all'; // all | private
  final _scrollController = ScrollController();
  final Set<String> _newMessageIds = {};
  Timer? _highlightClearTimer;
  int _preLoadUnread = 0; // unread count captured before _load() runs
  bool _initialLoadDone = false; // true once the first load has completed
  /// After [loadMessages] leaves loading, socket-style SFX/tab pulse may run.
  bool _receiveSfxArmed = false;

  bool _hasUnreadAll = false;
  bool _hasUnreadPrivate = false;
  bool _pulseAll = false;
  bool _pulsePrivate = false;
  Timer? _pulseAllTimer;
  Timer? _pulsePrivateTimer;

  // Translation — keyed by message id (manual or auto).
  final Map<String, String> _translations = {};
  final Set<String> _translating = {}; // ids currently fetching
  /// Moderator messages translated automatically to [context.locale].
  final Set<String> _autoTranslatedMessageIds = {};
  /// When true, show source text but keep [_translations] for toggling back.
  final Set<String> _showOriginalInstead = {};
  /// Skips duplicate API work per message id (until locale changes).
  final Set<String> _autoTranslateAttempted = {};
  String? _autoTranslateLocale;
  late final MessageNotifier _messageNotifier;

  @override
  void initState() {
    super.initState();
    _messageNotifier = ref.read(messageProvider.notifier);

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messageNotifier.setActiveGroup(widget.groupId);
      unawaited(_load());
    });
    widget.scrollNotifier?.addListener(_onExternalScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lang = context.locale.languageCode;
    if (_autoTranslateLocale != null && _autoTranslateLocale != lang) {
      setState(() {
        _translations.clear();
        _autoTranslatedMessageIds.clear();
        _showOriginalInstead.clear();
        _autoTranslateAttempted.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _queueAutoTranslate(ref.read(messageProvider).messages);
      });
    }
    _autoTranslateLocale = lang;
  }

  void _onExternalScroll() {
    _openChatTab();
  }

  Future<void> _openChatTab() async {
    if (!mounted) return;
    _preLoadUnread = ref.read(messageProvider).unreadCount;
    await ref.read(messageProvider.notifier).markAllRead(widget.groupId);
    _scrollToBottom(jump: true);
    await ref.read(messageProvider.notifier).loadMessages(widget.groupId);
    _queueAutoTranslateForCurrentMessages();
  }

  Future<void> _refreshMessages() async {
    _preLoadUnread = ref.read(messageProvider).unreadCount;
    await ref.read(messageProvider.notifier).loadMessages(
          widget.groupId,
          force: true,
        );
    await ref.read(messageProvider.notifier).markAllRead(widget.groupId);
    _queueAutoTranslateForCurrentMessages();
  }

  @override
  void dispose() {
    widget.scrollNotifier?.removeListener(_onExternalScroll);
    if (widget.scrollNotifier == null) {
      final notifier = _messageNotifier;
      Future.microtask(() => notifier.setActiveGroup(null));
    }
    _player.dispose();
    _sfxPlayer.dispose();
    SpeechService.stop();
    _scrollController.dispose();
    _highlightClearTimer?.cancel();
    _pulseAllTimer?.cancel();
    _pulsePrivateTimer?.cancel();
    super.dispose();
  }

  void _triggerTabPulse(String tab) {
    const pulseWindow = Duration(seconds: 6);
    if (tab == 'private') {
      _hasUnreadPrivate = true;
      _pulsePrivate = true;
      _pulsePrivateTimer?.cancel();
      _pulsePrivateTimer = Timer(pulseWindow, () {
        if (!mounted) return;
        setState(() => _pulsePrivate = false);
      });
    } else {
      _hasUnreadAll = true;
      _pulseAll = true;
      _pulseAllTimer?.cancel();
      _pulseAllTimer = Timer(pulseWindow, () {
        if (!mounted) return;
        setState(() => _pulseAll = false);
      });
    }
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    _preLoadUnread = ref.read(messageProvider).unreadCount;
    await ref.read(messageProvider.notifier).loadMessages(widget.groupId);
    await ref.read(messageProvider.notifier).markAllRead(widget.groupId);
    _queueAutoTranslateForCurrentMessages();
    // Scroll + highlight triggered by ref.listen detecting isLoading → false
  }

  void _queueAutoTranslateForCurrentMessages() {
    if (!mounted) return;
    _queueAutoTranslate(ref.read(messageProvider).messages);
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
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<GroupMessage> _filterMessages(List<GroupMessage> all) {
    final myId = ref.read(authProvider).userId ?? '';
    return switch (_filter) {
      'private' => all
          .where((m) => m.recipientId != null)
          .where((m) => isMessageVisibleToUser(m, myId))
          .toList(),
      _ => all.where((m) => isMessageVisibleToUser(m, myId)).toList(),
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
      await SpeechService.stop();
      setState(() {
        _ttsSpeaking = false;
        _ttsPlayingId = null;
        _ttsLoading = false;
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
    final ttsLang = context.locale.languageCode;
    final originalText = msg.originalText ?? msg.content ?? '';
    final showingTranslated = _translations.containsKey(msg.id) &&
        !_showOriginalInstead.contains(msg.id);
    final text = showingTranslated && _translations[msg.id] != null
        ? _translations[msg.id]!
        : originalText;
    final isCurrentlySpeaking = _ttsPlayingId == msg.id && (_ttsSpeaking || _ttsLoading);
    
    if (isCurrentlySpeaking) {
      await SpeechService.stop();
      if (mounted) {
        setState(() {
          _ttsSpeaking = false;
          _ttsPlayingId = null;
          _ttsLoading = false;
        });
      }
      return;
    }
    
    if (_playingId != null) {
      await _player.stop();
      if (mounted) {
        setState(() {
          _playingId = null;
          _position = Duration.zero;
        });
      }
    }

    await SpeechService.stop();
    if (mounted) {
      setState(() {
        _ttsPlayingId = msg.id;
        _ttsLoading = true;
      });
    }

    try {
      // Stored [audio_url] matches server default (e.g. EN). When the bubble
      // shows a translation, fetch Cloud TTS for that exact string + locale.
      String? audioUrl =
          ref.read(messageProvider.notifier).resolveMediaUrl(msg.audioUrl);
      if (showingTranslated && (_translations[msg.id]?.trim().isNotEmpty ?? false)) {
        audioUrl = await TtsCloudApi.fetchAudioUrl(
          text: text,
          lang: ttsLang,
        );
      }
      await SpeechService.playRobust(
        audioUrl: audioUrl,
        backupText: text,
        lang: ttsLang,
      );
    } finally {
      if (mounted && _ttsPlayingId == msg.id) {
        setState(() {
          _ttsLoading = false;
          _ttsSpeaking = false;
          _ttsPlayingId = null;
        });
      }
    }
  }

  Future<void> _playReceiveSfx(GroupMessage msg) async {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final notified =
          prefs.getStringList(ChatPopupDedup.notifiedIdsKey) ?? [];
      if (notified.contains(msg.id)) {
        return;
      }
    } catch (_) {}
    try {
      if (msg.isUrgent) {
        // Avoid “double alarm” when urgent TTS is also handled by notifications.
        if (msg.type == 'tts') return;
        await _sfxPlayer.play(AssetSource('static/urgent_tts.wav'));
      } else {
        await _sfxPlayer.play(AssetSource('static/in_app.mp3'));
      }
    } catch (_) {
      // ignore – SFX should never break chat UX
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final msgState = ref.watch(messageProvider);
    final filtered = _filterMessages(msgState.messages);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showLoading = filtered.isEmpty &&
        (msgState.isLoading || !_initialLoadDone);

    // Scroll & highlight driven by provider changes
    ref.listen(messageProvider, (prev, next) {
      final loadFinished =
          (prev?.isLoading ?? false) && !next.isLoading;
      if (loadFinished) {
        _receiveSfxArmed = true;
      }

      // ── Initial / pull-to-refresh load finished ──────────────────────────
      if (loadFinished && next.messages.isNotEmpty) {
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _queueAutoTranslate(next.messages);
        });
        return;
      }

      if (loadFinished && next.messages.isEmpty && !_initialLoadDone) {
        if (mounted) {
          setState(() => _initialLoadDone = true);
        }
      }

      // ── New socket message appended (no loading state) ───────────────────
      if (!_receiveSfxArmed || prev == null) return;
      if (prev.isLoading || next.isLoading) return;
      if (prev.messages.length >= next.messages.length) return;

      final prevIds = prev.messages.map((m) => m.id).toSet();
      final arrived = next.messages.where((m) => !prevIds.contains(m.id));
      final arrivedIds = arrived.map((m) => m.id).toSet();
      if (arrivedIds.isEmpty) return;

      setState(() => _newMessageIds.addAll(arrivedIds));
      _highlightClearTimer?.cancel();
      _highlightClearTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _newMessageIds.clear());
      });
      _scrollToBottom(); // smooth animate — no flicker
      for (final m in arrived) {
        unawaited(_playReceiveSfx(m));
      }
      for (final m in arrived) {
        final targetTab = (m.recipientId != null) ? 'private' : 'all';
        if (_filter != targetTab) {
          setState(() => _triggerTabPulse(targetTab));
        }
      }
      _queueAutoTranslate(arrived.toList());
    });

    return Scaffold(
      backgroundColor: GroupChatTheme.scaffoldBackground(isDark),
      body: _buildBody(isDark, showLoading, filtered),
    );
  }

  Widget _buildBody(
    bool isDark,
    bool showLoading,
    List<GroupMessage> filtered,
  ) {
    final bottomInset = widget.scrollNotifier == null
        ? MediaQuery.paddingOf(context).bottom
        : 0.0;

    return Column(
      children: [
        GroupChatHeader(
          isDark: isDark,
          title: 'call_support_display_name'.tr(),
          subtitle: 'inbox_title'.tr(),
          onRefresh: _refreshMessages,
          onBack: () => Navigator.of(context).maybePop(),
          showBrandAvatar: true,
        ),
        _buildFilterRow(isDark),
        Expanded(
          child: showLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                  ),
                )
              : filtered.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _refreshMessages,
                  child: ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: EdgeInsets.fromLTRB(
                      16.w,
                      8.h,
                      16.w,
                      24.h + bottomInset,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final msg = filtered[filtered.length - 1 - i];
                      return _buildCard(msg);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ── Filter chips ──────────────────────────────────────────────────────────

  Widget _buildFilterRow(bool isDark) {
    final bg = GroupChatTheme.filterStripBackground(isDark);
    final surface = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white;
    final border = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0);

    Widget buildBox({
      required String key,
      required String labelKey,
      required bool selected,
      required bool hasDot,
      required bool isPulsing,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            scale: isPulsing ? 1.03 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(vertical: 10.h),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : surface,
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: selected ? AppColors.primary : border),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    labelKey.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? Colors.white
                          : (isDark ? Colors.white70 : AppColors.textDark),
                    ),
                  ),
                  if (hasDot)
                    Positioned(
                      right: 10.w,
                      top: 8.h,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: selected ? 0.0 : 1.0,
                        child: Container(
                          width: 8.w,
                          height: 8.w,
                          decoration: const BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      color: bg,
      padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 10.h),
      child: Row(
        children: [
          buildBox(
            key: 'all',
            labelKey: 'inbox_filter_all',
            selected: _filter == 'all',
            hasDot: _hasUnreadAll,
            isPulsing: _pulseAll,
            onTap: () {
              setState(() {
                _filter = 'all';
                _hasUnreadAll = false;
                _pulseAll = false;
              });
              _pulseAllTimer?.cancel();
              _pulseAllTimer = null;
            },
          ),
          SizedBox(width: 10.w),
          buildBox(
            key: 'private',
            labelKey: 'inbox_filter_only_you',
            selected: _filter == 'private',
            hasDot: _hasUnreadPrivate,
            isPulsing: _pulsePrivate,
            onTap: () {
              setState(() {
                _filter = 'private';
                _hasUnreadPrivate = false;
                _pulsePrivate = false;
              });
              _pulsePrivateTimer?.cancel();
              _pulsePrivateTimer = null;
            },
          ),
        ],
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

    final cardBg = GroupChatTheme.cardBackground(
      isDark,
      urgent: isUrgent,
      highlightNew: isNew && !isUrgent,
    );
    final borderColor = GroupChatTheme.cardBorderColor(
      isDark,
      urgent: isUrgent,
      highlightNew: isNew && !isUrgent,
    );
    final borderWidth = GroupChatTheme.cardBorderWidth(
      urgent: isUrgent,
      highlightNew: isNew && !isUrgent,
    );

    return GestureDetector(
      onLongPress: () => _openInboxCopySheet(msg, isDark),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        margin: EdgeInsets.only(bottom: 10.h),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: borderColor,
            width: borderWidth,
          ),
          boxShadow: [
            BoxShadow(
              color: isNew
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: isDark ? 0.18 : 0.035),
              blurRadius: isNew ? 12 : 10,
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
                  child: const PrivateIndicator(isForPilgrim: true),
                ),
              _buildCardHeader(msg, isDark),
              SizedBox(height: 12.h),
              if (msg.replySnapshot != null)
                MessageReplyQuote(
                  snapshot: msg.replySnapshot!,
                  isDark: isDark,
                ),
              if (msg.type == 'text') _buildTextBody(msg, isDark),
            if (msg.type == 'voice') _buildVoiceBody(msg, isDark),
            if (msg.type == 'tts') _buildTtsBody(msg, isDark),
            if (msg.type == 'meetpoint') _buildMeetpointBody(msg, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openInboxCopySheet(GroupMessage msg, bool isDark) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: Icon(Symbols.content_copy, size: 22.w),
          title: Text(
            'msg_copy'.tr(),
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
          onTap: () {
            final plain = messagePlainTextForCopy(msg);
            Navigator.pop(ctx);
            if (plain.trim().isEmpty) {
              StandardSnackBar.showInfo(context, 'msg_copy_empty'.tr());
              return;
            }
            Clipboard.setData(ClipboardData(text: plain));
            StandardSnackBar.showInfo(context, 'msg_copied'.tr());
          },
        ),
      ),
    );
  }

  /// Staff: small Munawwara Care logo + name (trust cue per card), then chips.
  Widget _buildCardHeader(GroupMessage msg, bool isDark) {
    final fromSupport = msg.isFromModerator;
    final metaStyle = TextStyle(
      fontFamily: 'Lexend',
      fontSize: 11.sp,
      fontWeight: FontWeight.w500,
      color: isDark ? Colors.white54 : AppColors.textMutedLight,
    );

    final chips = Wrap(
      spacing: 6.w,
      runSpacing: 6.h,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _inboxTypeChip(msg, isDark),
        if (msg.isUrgent) _urgentChipCompact(isDark),
      ],
    );

    if (fromSupport) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _staffBrandRow(isDark)),
              SizedBox(width: 8.w),
              Text(
                _formatDateTime(msg.createdAt),
                style: metaStyle,
                textAlign: TextAlign.right,
              ),
            ],
          ),
          SizedBox(height: 8.h),
          chips,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16.r,
          backgroundColor: AppColors.primary.withValues(alpha: 0.14),
          child: Text(
            msg.sender?.initial ?? '?',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 13.sp,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 6.h),
              chips,
            ],
          ),
        ),
        SizedBox(width: 8.w),
        Text(
          _formatDateTime(msg.createdAt),
          style: metaStyle,
          textAlign: TextAlign.right,
        ),
      ],
    );
  }

  /// Compact sender identity for moderator/staff — matches voice-call branding.
  Widget _staffBrandRow(bool isDark) {
    return Row(
      children: [
        SupportBrandAvatar(
          isDark: isDark,
          diameter: 30,
          iconPadding: 5,
          showShadow: false,
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            'call_support_display_name'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w600,
              fontSize: 13.sp,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _inboxTypeChip(GroupMessage msg, bool isDark) {
    final muted = isDark ? Colors.white70 : AppColors.textMutedLight;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : AppColors.primary.withValues(alpha: 0.07);
    final (icon, label) = switch (msg.type) {
      'voice' => (Symbols.graphic_eq, 'inbox_filter_voice'.tr()),
      'tts' => (Symbols.record_voice_over, 'inbox_filter_tts'.tr()),
      _ => (Symbols.chat_bubble, 'inbox_type_text'.tr()),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14.w, color: muted),
          SizedBox(width: 5.w),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _urgentChipCompact(bool isDark) {
    final c = const Color(0xFFDC2626);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: c, width: 1.25),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.priority_high, size: 14.w, color: c),
          SizedBox(width: 3.w),
          Text(
            'inbox_filter_urgent'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 10.sp,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextBody(GroupMessage msg, bool isDark) {
    final original = msg.content ?? '';
    final showingTranslated = _translations.containsKey(msg.id) &&
        !_showOriginalInstead.contains(msg.id);
    final displayText =
        showingTranslated ? _translations[msg.id]! : original;
    final bodyColor =
        isDark ? Colors.white.withValues(alpha: 0.88) : AppColors.textDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_autoTranslatedMessageIds.contains(msg.id) && showingTranslated)
          _buildAutoTranslatedBadge(isDark),
        Text(
          displayText,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 15.sp,
            fontWeight: FontWeight.w400,
            height: 1.45,
            color: bodyColor,
          ),
        ),
        SizedBox(height: 10.h),
        _buildTranslateButton(msg, original, dense: true),
      ],
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
    final isLoading = _ttsPlayingId == msg.id && _ttsLoading;
    final originalText = msg.originalText ?? msg.content ?? '';
    final showingTranslated = _translations.containsKey(msg.id) &&
        !_showOriginalInstead.contains(msg.id);
    final displayText = showingTranslated
        ? _translations[msg.id]!
        : originalText;
    final bodyColor =
        isDark ? Colors.white.withValues(alpha: 0.88) : AppColors.textDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_autoTranslatedMessageIds.contains(msg.id) && showingTranslated)
          _buildAutoTranslatedBadge(isDark),
        Text(
          displayText,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 15.sp,
            fontWeight: FontWeight.w400,
            height: 1.45,
            color: bodyColor,
          ),
        ),
        SizedBox(height: 12.h),
        _buildTranslateButton(msg, originalText, dense: true),
        SizedBox(height: 10.h),
        TtsPlayAloudButton(
          isSpeaking: isSpeaking,
          isLoading: isLoading,
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
        timeStr != null ? DateTime.tryParse(timeStr)?.toLocal() : null;

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

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatDateTime(DateTime dt) {
    return '${_formatDate(dt)} · ${_formatTime(dt)}';
  }

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

  // Try a lightweight, heuristic language detection for common scripts.
  // Returns a language code like 'ar' or 'en', or 'unknown' if undetermined.
  String _detectLikelyLanguage(String text) {
    if (text.trim().isEmpty) return 'unknown';
    final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(text);
    if (hasArabic) return 'ar';
    final hasLatin = RegExp(r'[A-Za-z]').hasMatch(text);
    if (hasLatin) return 'en';
    return 'unknown';
  }

  static const Map<String, String> _langNames = {
    'en': 'English',
    'ar': 'Arabic',
    'ur': 'Urdu',
    'fr': 'French',
    'id': 'Indonesian',
    'tr': 'Turkish',
  };

  // ── On-demand translation ─────────────────────────────────────────────────

  Widget _buildTranslateButton(
    GroupMessage msg,
    String originalText, {
    bool dense = false,
  }) {
    final hasCached = _translations.containsKey(msg.id);
    final showingTranslated =
        hasCached && !_showOriginalInstead.contains(msg.id);
    final isLoading = _translating.contains(msg.id);

    if (isLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: dense ? 11.w : 12.w,
            height: dense ? 11.w : 12.w,
            child: const CircularProgressIndicator(strokeWidth: 1.5),
          ),
          SizedBox(width: 6.w),
          Text(
            'inbox_translating'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: dense ? 10.sp : 11.sp,
              color: AppColors.textMutedLight,
            ),
          ),
        ],
      );
    }

    final label = hasCached
        ? (showingTranslated
            ? 'inbox_show_original'.tr()
            : 'inbox_show_translation'.tr())
        : 'inbox_translate'.tr();

    return InkWell(
      onTap: () {
        if (hasCached) {
          setState(() {
            if (_showOriginalInstead.contains(msg.id)) {
              _showOriginalInstead.remove(msg.id);
            } else {
              _showOriginalInstead.add(msg.id);
            }
          });
          return;
        }
        unawaited(_translateMessage(msg, originalText));
      },
      borderRadius: BorderRadius.circular(6.r),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: dense ? 2.h : 4.h,
          horizontal: 2.w,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.translate_rounded,
              size: dense ? 15.w : 16.w,
              color: AppColors.primary.withValues(alpha: 0.9),
            ),
            SizedBox(width: 5.w),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: dense ? 11.sp : 12.sp,
                color: AppColors.primary.withValues(alpha: 0.95),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoTranslatedBadge(bool isDark) {
    final muted = isDark ? Colors.white54 : AppColors.textMutedLight;
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        children: [
          Icon(
            Icons.g_translate_rounded,
            size: 11.w,
            color: AppColors.primary.withValues(alpha: 0.85),
          ),
          SizedBox(width: 4.w),
          Expanded(
            child: Text(
              'inbox_auto_translated_badge'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 9.5.sp,
                fontWeight: FontWeight.w500,
                height: 1.2,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _queueAutoTranslate(List<GroupMessage> messages) {
    if (messages.isEmpty) return;
    unawaited(_runAutoTranslateQueue(messages));
  }

  Future<void> _runAutoTranslateQueue(List<GroupMessage> messages) async {
    final targets = messages.where((m) {
      if (!m.isFromModerator) return false;
      if (m.type != 'text' && m.type != 'tts') return false;
      if (_translations.containsKey(m.id)) return false;
      if (_autoTranslateAttempted.contains(m.id)) return false;
      return true;
    }).toList();
    for (final m in targets) {
      if (!mounted) return;
      await _autoTranslateMessageFromModerator(m);
      await Future<void>.delayed(const Duration(milliseconds: 70));
    }
  }

  Future<void> _autoTranslateMessageFromModerator(GroupMessage msg) async {
    if (!mounted) return;
    if (!msg.isFromModerator) return;
    if (msg.type != 'text' && msg.type != 'tts') return;
    if (_autoTranslateAttempted.contains(msg.id)) return;

    final original = msg.type == 'tts'
        ? (msg.originalText ?? msg.content ?? '')
        : (msg.content ?? '');
    if (original.trim().isEmpty) {
      _autoTranslateAttempted.add(msg.id);
      return;
    }

    final targetLang = context.locale.languageCode;
    final detected = _detectLikelyLanguage(original);
    if (detected != 'unknown' && detected == targetLang) {
      _autoTranslateAttempted.add(msg.id);
      return;
    }

    if (_translating.contains(msg.id)) return;
    _autoTranslateAttempted.add(msg.id);
    if (mounted) setState(() => _translating.add(msg.id));
    try {
      final response = await ApiService.dio.post(
        '/auth/translate',
        data: {'text': original, 'targetLang': targetLang},
      );
      final translated = response.data?['translatedText'] as String?;
      if (!mounted) return;
      if (translated == null) {
        _autoTranslateAttempted.remove(msg.id);
        return;
      }
      if (translated.trim() == original.trim()) return;
      setState(() {
        _translations[msg.id] = translated;
        _autoTranslatedMessageIds.add(msg.id);
        _showOriginalInstead.remove(msg.id);
      });
    } catch (_) {
      _autoTranslateAttempted.remove(msg.id);
    } finally {
      if (mounted) setState(() => _translating.remove(msg.id));
    }
  }

  Future<void> _translateMessage(GroupMessage msg, String originalText) async {
    if (_translating.contains(msg.id)) return;

    final targetLang = context.locale.languageCode;
    final detected = _detectLikelyLanguage(originalText);
    if (detected != 'unknown' && detected == targetLang) {
      final name = _langNames[targetLang] ?? targetLang;
      StandardSnackBar.showInfo(
        context,
        'msg_already_in_lang'.tr(args: [name]),
      );
      return;
    }

    if (mounted) setState(() => _translating.add(msg.id));
    try {
      final response = await ApiService.dio.post(
        '/auth/translate',
        data: {'text': originalText, 'targetLang': targetLang},
      );
      final translated = response.data?['translatedText'] as String?;
      if (mounted && translated != null && translated.trim().isNotEmpty) {
        setState(() {
          _translations[msg.id] = translated;
          _showOriginalInstead.remove(msg.id);
        });
      }
    } catch (_) {
      // User still sees original text
    } finally {
      if (mounted) setState(() => _translating.remove(msg.id));
    }
  }
}
