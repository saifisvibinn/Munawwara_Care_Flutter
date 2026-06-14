import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/services/caller_gender_cache.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass.dart';
import '../../shared/widgets/pilgrim_gender_avatar.dart';
import '../providers/moderator_provider.dart';
import '../providers/moderator_resolved_sos_provider.dart';
import '../services/moderator_resolved_sos_store.dart';

/// List of moderator-resolved SOS incidents (newest first).
class ModeratorResolvedSosList extends ConsumerWidget {
  final bool isDark;

  const ModeratorResolvedSosList({super.key, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(moderatorResolvedSosProvider);
    final list = async.value ?? [];

    if (async.isLoading && list.isEmpty) {
      final h = MediaQuery.sizeOf(context).height;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          SizedBox(height: h * 0.28),
          const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ],
      );
    }

    if (list.isEmpty) {
      final h = MediaQuery.sizeOf(context).height;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          SizedBox(height: h * 0.28),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Text(
              'moderator_resolved_sos_empty'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : AppColors.textMutedDark,
              ),
            ),
          ),
        ],
      );
    }

    return AppScrollFadeOverlay(
      showTop: false,
      child: ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
      itemCount: list.length,
      separatorBuilder: (_, _) => SizedBox(height: 10.h),
      itemBuilder: (ctx, i) {
        return _ResolvedSosTile(record: list[i], isDark: isDark);
      },
    ),
    );
  }
}

class _ResolvedSosTile extends ConsumerStatefulWidget {
  final ModeratorResolvedSosRecord record;
  final bool isDark;

  const _ResolvedSosTile({required this.record, required this.isDark});

  @override
  ConsumerState<_ResolvedSosTile> createState() => _ResolvedSosTileState();
}

class _ResolvedSosTileState extends ConsumerState<_ResolvedSosTile> {
  String? _cachedProfilePicture;
  String? _cachedGender;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCacheFallbacks());
  }

  @override
  void didUpdateWidget(covariant _ResolvedSosTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.pilgrimId != widget.record.pilgrimId) {
      unawaited(_loadCacheFallbacks());
    }
  }

  Future<void> _loadCacheFallbacks() async {
    final pid = widget.record.pilgrimId.trim();
    if (pid.isEmpty) return;
    final groups = ref.read(moderatorProvider).groups;
    final live = _findPilgrimInGroups(pid, groups);
    final needsPic =
        !_hasValue(widget.record.pilgrimProfilePicture) &&
        !_hasValue(live?.profilePicture);
    final needsGender =
        !_hasValue(widget.record.pilgrimGender) &&
        !_hasValue(live?.gender);
    if (!needsPic && !needsGender) return;
    final pic = needsPic
        ? await CallerGenderCache.resolveProfilePicture(pid)
        : null;
    final gender = needsGender ? await CallerGenderCache.resolve(pid) : null;
    if (!mounted) return;
    setState(() {
      if (needsPic) _cachedProfilePicture = pic;
      if (needsGender) _cachedGender = gender;
    });
  }

  static bool _hasValue(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isNotEmpty;
  }

  static PilgrimInGroup? _findPilgrimInGroups(
    String pilgrimId,
    List<ModeratorGroup> groups,
  ) {
    for (final group in groups) {
      for (final pilgrim in group.pilgrims) {
        if (pilgrim.id == pilgrimId) return pilgrim;
      }
    }
    return null;
  }

  String? _resolveProfilePicture(List<ModeratorGroup> groups) {
    final stored = widget.record.pilgrimProfilePicture?.trim();
    if (_hasValue(stored)) return stored;
    final pid = widget.record.pilgrimId.trim();
    if (pid.isEmpty) return _cachedProfilePicture;
    final pic = _findPilgrimInGroups(pid, groups)?.profilePicture?.trim();
    if (_hasValue(pic)) return pic;
    return _cachedProfilePicture;
  }

  String? _resolveGender(List<ModeratorGroup> groups) {
    final stored = widget.record.pilgrimGender?.trim();
    if (_hasValue(stored)) return stored;
    final pid = widget.record.pilgrimId.trim();
    if (pid.isEmpty) return _cachedGender;
    final gender = _findPilgrimInGroups(pid, groups)?.gender?.trim();
    if (_hasValue(gender)) return gender;
    return _cachedGender;
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final isDark = widget.isDark;
    final groups = ref.watch(moderatorProvider).groups;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final border = isDark ? AppColors.dividerDark : AppColors.dividerLight;
    final titleColor = isDark ? Colors.white : AppColors.textDark;
    final muted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final when = DateTime.fromMillisecondsSinceEpoch(record.resolvedAtMs);
    final whenLabel = DateFormat.yMMMd().add_jm().format(when);
    final avatarSize = 52.w;

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResolvedSosAvatar(
            gender: _resolveGender(groups),
            imageUrl: _resolveProfilePicture(groups),
            size: avatarSize,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.pilgrimName.isEmpty ? '—' : record.pilgrimName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.sp,
                    color: titleColor,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'moderator_resolved_sos_card_group'.tr(
                    namedArgs: {
                      'group': record.groupName.isEmpty ? '—' : record.groupName,
                    },
                  ),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: muted,
                    height: 1.35,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  'moderator_resolved_sos_card_time'.tr(
                    namedArgs: {'when': whenLabel},
                  ),
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pilgrim portrait with resolved check badge for history cards.
class _ResolvedSosAvatar extends StatelessWidget {
  final String? gender;
  final String? imageUrl;
  final double size;

  const _ResolvedSosAvatar({
    required this.gender,
    required this.imageUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final badgeSize = size * 0.36;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.success, width: 2),
              color: AppColors.success.withValues(alpha: 0.08),
            ),
            child: ClipOval(
              child: PilgrimGenderAvatar(
                gender: gender,
                size: size,
                imageUrl: imageUrl,
              ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(
                Symbols.check_circle,
                color: Colors.white,
                size: badgeSize * 0.58,
                fill: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
