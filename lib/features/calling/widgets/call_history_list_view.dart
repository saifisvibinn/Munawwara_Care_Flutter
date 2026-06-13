import 'dart:async';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/caller_gender_cache.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_logger.dart';
import '../../auth/providers/auth_provider.dart';
import '../../moderator/providers/moderator_provider.dart';
import '../../shared/widgets/group_chat_theme.dart';
import '../../shared/widgets/pilgrim_gender_avatar.dart';
import '../data/call_history_api.dart';
import '../providers/missed_calls_unread_provider.dart';

class CallHistoryListView extends ConsumerStatefulWidget {
  const CallHistoryListView({
    super.key,
    this.missedOnly = false,
    this.highlightUnreadMissed = false,
  });

  final bool missedOnly;
  final bool highlightUnreadMissed;

  @override
  ConsumerState<CallHistoryListView> createState() => _CallHistoryListViewState();
}

class _CallHistoryListViewState extends ConsumerState<CallHistoryListView> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  bool _hadUnreadMissedHighlight = false;
  Map<String, String> _cachedPeerPictures = {};
  Map<String, String> _cachedPeerGenders = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_hadUnreadMissedHighlight) {
      unawaited(_markUnreadMissedSeen());
    }
    super.dispose();
  }

  Future<void> _markUnreadMissedSeen() async {
    try {
      await CallHistoryApi.markMissedCallsRead();
      await ref.read(missedCallsUnreadProvider.notifier).refresh();
    } catch (e) {
      AppLogger.w('[CallHistoryListView] mark-read on dispose: $e');
    }
  }

  bool _isUnreadMissedInbound(Map<String, dynamic> row, String myId) {
    if (myId.isEmpty) return false;
    final callerId = _idOf(row['caller_id']);
    if (callerId == myId) return false;
    if (row['status']?.toString() != 'missed') return false;
    return row['is_read'] != true;
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await CallHistoryApi.fetchCallHistory();
      final rows = widget.missedOnly
          ? all.where((c) => c['status']?.toString() == 'missed').toList()
          : all;
      if (!mounted) return;
      final myId = ref.read(authProvider).userId ?? '';
      final hasUnreadHighlight = widget.highlightUnreadMissed &&
          rows.any((row) => _isUnreadMissedInbound(row, myId));
      final peerPictures = <String, String>{};
      final peerGenders = <String, String>{};
      final role = ref.read(authProvider).role;
      final isModerator = role == 'moderator' || role == 'admin';
      if (isModerator) {
        final peerIds = <String>{};
        for (final row in rows) {
          final callerId = _idOf(row['caller_id']);
          final outgoing = callerId == myId;
          final other = outgoing ? row['receiver_id'] : row['caller_id'];
          final peerId = _idOf(other);
          if (peerId.isNotEmpty) peerIds.add(peerId);
        }
        for (final peerId in peerIds) {
          final cachedPic =
              await CallerGenderCache.resolveProfilePicture(peerId);
          if (cachedPic != null && cachedPic.isNotEmpty) {
            peerPictures[peerId] = cachedPic;
          }
          final cachedGender = await CallerGenderCache.resolve(peerId);
          if (cachedGender != null && cachedGender.isNotEmpty) {
            peerGenders[peerId] = cachedGender;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _hadUnreadMissedHighlight = hasUnreadHighlight;
        _cachedPeerPictures = peerPictures;
        _cachedPeerGenders = peerGenders;
      });
      final shouldMarkUnreadSeen = hasUnreadHighlight ||
          (widget.missedOnly &&
              rows.isNotEmpty &&
              !widget.highlightUnreadMissed);
      if (shouldMarkUnreadSeen) {
        try {
          await CallHistoryApi.markMissedCallsRead();
          if (!mounted) return;
          await ref.read(missedCallsUnreadProvider.notifier).refresh();
        } catch (e) {
          AppLogger.w('[CallHistoryListView] mark-read: $e');
        }
      }
    } on DioException catch (e) {
      AppLogger.e('[CallHistoryListView] load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiService.parseError(e);
      });
    } catch (e) {
      AppLogger.e('[CallHistoryListView] load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'call_history_load_error'.tr();
      });
    }
  }

  static String _idOf(dynamic ref) {
    if (ref is Map) {
      return (ref['_id'] ?? ref['id'] ?? '').toString();
    }
    return ref?.toString() ?? '';
  }

  static String _nameOf(dynamic ref) {
    if (ref is Map) {
      final n = ref['full_name']?.toString();
      if (n != null && n.isNotEmpty) return n;
    }
    return 'Unknown';
  }

  static String? _profilePictureOf(dynamic ref) {
    if (ref is! Map) return null;
    final pic = ref['profile_picture']?.toString() ??
        ref['profilePicture']?.toString();
    final trimmed = pic?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _genderOf(dynamic ref) {
    if (ref is! Map) return null;
    final g = ref['gender']?.toString().trim() ?? '';
    return g.isEmpty ? null : g;
  }

  bool _peerShowsAsSupport({
    required String? myRole,
    required Map<String, dynamic> row,
    required bool outgoing,
  }) {
    if (myRole?.toLowerCase() != 'pilgrim') return false;
    final callerRaw = row['caller_id'];
    final receiverRaw = row['receiver_id'];
    final callerIsMod = callerRaw is Map &&
        callerRaw['user_type']?.toString().toLowerCase() == 'moderator';
    final receiverIsMod = receiverRaw is Map &&
        receiverRaw['user_type']?.toString().toLowerCase() == 'moderator';
    if (!outgoing && callerIsMod) return true;
    if (outgoing && receiverIsMod) return true;
    return false;
  }

  String? _resolvePeerProfilePicture({
    required dynamic otherRef,
    required String peerId,
    required List<ModeratorGroup> groups,
  }) {
    final fromApi = _profilePictureOf(otherRef);
    if (fromApi != null && fromApi.isNotEmpty) return fromApi;
    for (final group in groups) {
      for (final pilgrim in group.pilgrims) {
        if (pilgrim.id != peerId) continue;
        final pic = pilgrim.profilePicture?.trim();
        if (pic != null && pic.isNotEmpty) return pic;
      }
    }
    return _cachedPeerPictures[peerId];
  }

  String? _resolvePeerGender({
    required dynamic otherRef,
    required String peerId,
    required List<ModeratorGroup> groups,
  }) {
    final fromApi = _genderOf(otherRef);
    if (fromApi != null && fromApi.isNotEmpty) return fromApi;
    for (final group in groups) {
      for (final pilgrim in group.pilgrims) {
        if (pilgrim.id != peerId) continue;
        final gender = pilgrim.gender?.trim();
        if (gender != null && gender.isNotEmpty) return gender;
      }
    }
    return _cachedPeerGenders[peerId];
  }

  Widget _buildLeadingAvatar({
    required bool isDark,
    required String? myRole,
    required Map<String, dynamic> row,
    required bool outgoing,
    required dynamic otherRef,
    required String peerId,
    required List<ModeratorGroup> groups,
  }) {
    if (_peerShowsAsSupport(
      myRole: myRole,
      row: row,
      outgoing: outgoing,
    )) {
      return SupportBrandAvatar(
        isDark: isDark,
        diameter: 44,
        showShadow: false,
      );
    }
    final imageUrl = _resolvePeerProfilePicture(
      otherRef: otherRef,
      peerId: peerId,
      groups: groups,
    );
    final gender = _resolvePeerGender(
      otherRef: otherRef,
      peerId: peerId,
      groups: groups,
    );
    return PilgrimGenderAvatar(
      gender: gender,
      imageUrl: imageUrl,
      size: 44.w,
    );
  }

  String _peerDisplayName({
    required String? myRole,
    required Map<String, dynamic> row,
    required bool outgoing,
    required dynamic otherRef,
  }) {
    if (_peerShowsAsSupport(
      myRole: myRole,
      row: row,
      outgoing: outgoing,
    )) {
      return 'call_support_display_name'.tr();
    }
    return _nameOf(otherRef);
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'ringing':
        return 'call_history_status_ringing'.tr();
      case 'in-progress':
        return 'call_history_status_in_progress'.tr();
      case 'completed':
        return 'call_history_status_completed'.tr();
      case 'missed':
        return 'call_history_status_missed'.tr();
      case 'declined':
        return 'call_history_status_declined'.tr();
      case 'unreachable':
        return 'call_history_status_unreachable'.tr();
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    
    final auth = ref.watch(authProvider);
    final myId = auth.userId ?? '';
    final myRole = auth.role;
    final isModerator = myRole == 'moderator' || myRole == 'admin';
    final groups = isModerator
        ? ref.watch(moderatorProvider).groups
        : const <ModeratorGroup>[];

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textMuted,
                  fontSize: 15.sp,
                ),
              ),
              SizedBox(height: 16.h),
              FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: Text('call_history_retry'.tr()),
              ),
            ],
          ),
        ),
      );
    }

    if (_rows.isEmpty) {
      return Center(
        child: Text(
          widget.missedOnly ? 'missed_calls_empty'.tr() : 'call_history_empty'.tr(),
          style: TextStyle(
            color: textMuted,
            fontSize: 16.sp,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 100.h),
        itemCount: _rows.length,
        separatorBuilder: (_, _) => SizedBox(height: 8.h),
        itemBuilder: (context, i) {
          final c = _rows[i];
          final callerId = _idOf(c['caller_id']);
          final outgoing = callerId == myId;
          final other = outgoing ? c['receiver_id'] : c['caller_id'];
          final otherName = _peerDisplayName(
            myRole: myRole,
            row: c,
            outgoing: outgoing,
            otherRef: other,
          );
          final status = c['status']?.toString() ?? '';
          final created = c['createdAt']?.toString() ?? c['created_at']?.toString();
          DateTime? dt;
          if (created != null && created.isNotEmpty) {
            try {
              dt = DateTime.parse(created).toLocal();
            } catch (_) {}
          }
          final timeStr = dt != null ? DateFormat.yMMMd().add_jm().format(dt) : '';
          final isUnreadMissed = widget.highlightUnreadMissed &&
              _isUnreadMissedInbound(c, myId);
          final peerId = _idOf(other);

          return Material(
            color: isUnreadMissed
                ? AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.1)
                : (isDark ? AppColors.surfaceDark : Colors.white),
            borderRadius: BorderRadius.circular(14.r),
            elevation: 0,
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              leading: _buildLeadingAvatar(
                isDark: isDark,
                myRole: myRole,
                row: c,
                outgoing: outgoing,
                otherRef: other,
                peerId: peerId,
                groups: groups,
              ),
              title: Text(
                otherName,
                style: TextStyle(
                  fontWeight:
                      isUnreadMissed ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 14.sp,
                  color: textPrimary,
                ),
              ),
              subtitle: Padding(
                padding: EdgeInsets.only(top: 4.h),
                child: Text(
                  '${outgoing ? 'call_history_outgoing'.tr() : 'call_history_incoming'.tr()} · ${_statusLabel(status)}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: textMuted,
                  ),
                ),
              ),
              trailing: Text(
                timeStr,
                style: TextStyle(
                  fontSize: 10.sp,
                  color: textMuted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
