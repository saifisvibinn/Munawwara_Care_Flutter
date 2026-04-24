import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_colors.dart';

// ── Data Models ──────────────────────────────────────────────────────────────

class _PilgrimItem {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String? nationalId;
  final int? age;
  final String language;
  final String ethnicity;
  final bool isOnline;
  final String? currentGroupId;
  final String? currentGroupName;

  const _PilgrimItem({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    this.nationalId,
    this.age,
    required this.language,
    required this.ethnicity,
    required this.isOnline,
    this.currentGroupId,
    this.currentGroupName,
  });

  factory _PilgrimItem.fromMap(Map<String, dynamic> m) {
    final g = m['current_group'] as Map<String, dynamic>?;
    return _PilgrimItem(
      id: m['_id']?.toString() ?? '',
      fullName: m['full_name']?.toString() ?? '',
      phoneNumber: m['phone_number']?.toString() ?? '',
      nationalId: m['national_id']?.toString(),
      age: m['age'] as int?,
      language: m['language']?.toString() ?? 'en',
      ethnicity: m['ethnicity']?.toString() ?? 'Other',
      isOnline: m['is_online'] == true,
      currentGroupId: g?['group_id']?.toString(),
      currentGroupName: g?['group_name']?.toString(),
    );
  }

  bool get isAssigned => currentGroupId != null;
}

class _GroupOption {
  final String id;
  final String name;
  const _GroupOption({required this.id, required this.name});
}

// ── Screen ───────────────────────────────────────────────────────────────────

class ManagePilgrimsScreen extends ConsumerStatefulWidget {
  const ManagePilgrimsScreen({super.key});

  @override
  ConsumerState<ManagePilgrimsScreen> createState() =>
      _ManagePilgrimsScreenState();
}

class _ManagePilgrimsScreenState extends ConsumerState<ManagePilgrimsScreen> {
  List<_PilgrimItem> _all = [];
  List<_GroupOption> _groups = [];
  bool _isLoading = true;
  String? _error;
  String _filter = 'all'; // all | assigned | unassigned
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.dio.get('/groups/my-pilgrims'),
        ApiService.dio.get('/groups/dashboard'),
      ]);

      final pilgrimsRaw =
          (results[0].data['data'] as List<dynamic>? ?? []);
      final groupsRaw =
          ((results[1].data['data'] ?? results[1].data) as List<dynamic>? ?? []);

      setState(() {
        _all = pilgrimsRaw
            .whereType<Map<String, dynamic>>()
            .map(_PilgrimItem.fromMap)
            .where((p) => p.id.isNotEmpty)
            .toList();
        _groups = groupsRaw
            .whereType<Map>()
            .map((g) => _GroupOption(
                  id: g['_id']?.toString() ?? g['id']?.toString() ?? '',
                  name: g['group_name']?.toString() ?? 'Unnamed Group',
                ))
            .where((g) => g.id.isNotEmpty)
            .toList();
      });
    } on DioException catch (e) {
      setState(() => _error = ApiService.parseError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<_PilgrimItem> get _filtered {
    return _all.where((p) {
      final matchFilter = _filter == 'all' ||
          (_filter == 'assigned' && p.isAssigned) ||
          (_filter == 'unassigned' && !p.isAssigned);
      final q = _search.toLowerCase();
      final matchSearch = q.isEmpty ||
          p.fullName.toLowerCase().contains(q) ||
          p.phoneNumber.contains(q) ||
          (p.nationalId?.contains(q) ?? false);
      return matchFilter && matchSearch;
    }).toList();
  }

  Future<void> _assignToGroup(
      _PilgrimItem pilgrim, _GroupOption group) async {
    try {
      await ApiService.dio.post(
        '/groups/${group.id}/add-pilgrim',
        data: {'identifier': pilgrim.phoneNumber},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '${pilgrim.fullName} moved to ${group.name}',
          style: const TextStyle(fontFamily: 'Lexend'),
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ));
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ApiService.parseError(e),
            style: const TextStyle(fontFamily: 'Lexend')),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _removeFromGroup(_PilgrimItem pilgrim) async {
    final gid = pilgrim.currentGroupId;
    if (gid == null) return;
    try {
      await ApiService.dio.post(
        '/groups/$gid/remove-pilgrim',
        data: {'user_id': pilgrim.id},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '${pilgrim.fullName} removed from group',
          style: const TextStyle(fontFamily: 'Lexend'),
        ),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
      ));
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ApiService.parseError(e),
            style: const TextStyle(fontFamily: 'Lexend')),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _showActions(_PilgrimItem pilgrim, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActionsSheet(
        pilgrim: pilgrim,
        groups: _groups,
        isDark: isDark,
        onAssign: (group) {
          Navigator.pop(context);
          _assignToGroup(pilgrim, group);
        },
        onRemove: () {
          Navigator.pop(context);
          _removeFromGroup(pilgrim);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final filtered = _filtered;

    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manage Pilgrims',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w800,
                        fontSize: 28.sp,
                        color: textPrimary,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Assign, transfer, or remove pilgrims from groups.',
                      style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13.sp,
                          color: textMuted),
                    ),
                    SizedBox(height: 16.h),

                    // Search bar
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(14.r),
                        border: Border.all(
                          color: isDark
                              ? AppColors.dividerDark
                              : AppColors.dividerLight,
                        ),
                      ),
                      child: TextField(
                        onChanged: (v) => setState(() => _search = v),
                        style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14.sp,
                            color: textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Search by name, phone, or ID…',
                          hintStyle: TextStyle(
                              fontFamily: 'Lexend',
                              color: textMuted,
                              fontSize: 13.sp),
                          prefixIcon:
                              Icon(Symbols.search, color: textMuted, size: 20.w),
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 14.h),
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),

                    // Filter chips
                    Row(
                      children: [
                        _FilterChip(
                          label: 'All (${_all.length})',
                          selected: _filter == 'all',
                          onTap: () => setState(() => _filter = 'all'),
                          isDark: isDark,
                        ),
                        SizedBox(width: 8.w),
                        _FilterChip(
                          label:
                              'Unassigned (${_all.where((p) => !p.isAssigned).length})',
                          selected: _filter == 'unassigned',
                          onTap: () =>
                              setState(() => _filter = 'unassigned'),
                          isDark: isDark,
                          accentColor: const Color(0xFFFF8400),
                        ),
                        SizedBox(width: 8.w),
                        _FilterChip(
                          label:
                              'Assigned (${_all.where((p) => p.isAssigned).length})',
                          selected: _filter == 'assigned',
                          onTap: () =>
                              setState(() => _filter = 'assigned'),
                          isDark: isDark,
                          accentColor: Colors.green,
                        ),
                      ],
                    ),
                    SizedBox(height: 16.h),
                  ],
                ),
              ),
            ),

            // Body
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Symbols.error_circle_rounded,
                          color: Colors.red.shade400, size: 48.w),
                      SizedBox(height: 12.h),
                      Text(_error!,
                          style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 14.sp,
                              color: textMuted)),
                      SizedBox(height: 12.h),
                      TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Symbols.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Symbols.group, size: 56.w, color: textMuted),
                      SizedBox(height: 12.h),
                      Text(
                        _search.isNotEmpty
                            ? 'No pilgrims match your search.'
                            : 'No pilgrims found.',
                        style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14.sp,
                            color: textMuted),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 100.h),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _PilgrimCard(
                      pilgrim: filtered[i],
                      isDark: isDark,
                      onAction: () =>
                          _showActions(filtered[i], isDark),
                    ),
                    childCount: filtered.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Pilgrim Card ─────────────────────────────────────────────────────────────

class _PilgrimCard extends StatelessWidget {
  final _PilgrimItem pilgrim;
  final bool isDark;
  final VoidCallback onAction;

  const _PilgrimCard({
    required this.pilgrim,
    required this.isDark,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: pilgrim.isAssigned
              ? Colors.transparent
              : const Color(0xFFFF8400).withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Row(
          children: [
            // Avatar circle
            Container(
              width: 44.w,
              height: 44.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: pilgrim.isAssigned
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : const Color(0xFFFF8400).withValues(alpha: 0.12),
              ),
              child: Center(
                child: Text(
                  pilgrim.fullName.isNotEmpty
                      ? pilgrim.fullName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 18.sp,
                    color: pilgrim.isAssigned
                        ? AppColors.primary
                        : const Color(0xFFFF8400),
                  ),
                ),
              ),
            ),
            SizedBox(width: 12.w),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pilgrim.fullName,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 14.sp,
                      color: textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    pilgrim.phoneNumber,
                    style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12.sp,
                        color: textMuted),
                  ),
                  SizedBox(height: 6.h),
                  // Group badge
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(
                      color: pilgrim.isAssigned
                          ? Colors.green.withValues(alpha: 0.12)
                          : const Color(0xFFFF8400).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          pilgrim.isAssigned
                              ? Symbols.group
                              : Symbols.group_off,
                          size: 12.w,
                          color: pilgrim.isAssigned
                              ? Colors.green.shade600
                              : const Color(0xFFFF8400),
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          pilgrim.isAssigned
                              ? pilgrim.currentGroupName!
                              : 'Unassigned',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            fontSize: 11.sp,
                            color: pilgrim.isAssigned
                                ? Colors.green.shade700
                                : const Color(0xFFFF8400),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Action button
            IconButton(
              onPressed: onAction,
              icon: Icon(
                Symbols.more_vert,
                color: textMuted,
                size: 22.w,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Actions Bottom Sheet ─────────────────────────────────────────────────────

class _ActionsSheet extends StatelessWidget {
  final _PilgrimItem pilgrim;
  final List<_GroupOption> groups;
  final bool isDark;
  final void Function(_GroupOption) onAssign;
  final VoidCallback onRemove;

  const _ActionsSheet({
    required this.pilgrim,
    required this.groups,
    required this.isDark,
    required this.onAssign,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.surfaceDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    // Available groups for assignment (exclude current)
    final available = groups
        .where((g) => g.id != pilgrim.currentGroupId)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 32.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ),
          SizedBox(height: 16.h),

          // Header
          Text(
            pilgrim.fullName,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 18.sp,
              color: textPrimary,
            ),
          ),
          Text(
            pilgrim.isAssigned
                ? 'Currently in: ${pilgrim.currentGroupName}'
                : 'Not assigned to any group',
            style: TextStyle(
                fontFamily: 'Lexend', fontSize: 13.sp, color: textMuted),
          ),
          SizedBox(height: 20.h),

          // Assign / Move to group section
          if (available.isNotEmpty) ...[
            Text(
              pilgrim.isAssigned ? 'Move to another group' : 'Assign to group',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w600,
                fontSize: 13.sp,
                color: textMuted,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 8.h),
            ...available.map((g) => _ActionTile(
                  icon: Symbols.group_add,
                  label: g.name,
                  color: AppColors.primary,
                  onTap: () => onAssign(g),
                  isDark: isDark,
                )),
          ],

          if (available.isNotEmpty && pilgrim.isAssigned)
            Divider(
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
              height: 24.h,
            ),

          // Remove option
          if (pilgrim.isAssigned)
            _ActionTile(
              icon: Symbols.group_remove,
              label: 'Remove from ${pilgrim.currentGroupName}',
              color: Colors.red.shade600,
              onTap: onRemove,
              isDark: isDark,
            ),

          if (!pilgrim.isAssigned && available.isEmpty)
            Center(
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Text(
                  'You have no other groups to assign this pilgrim to.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13.sp,
                      color: textMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isDark;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 4.w),
        child: Row(
          children: [
            Container(
              width: 36.w,
              height: 36.w,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(icon, color: color, size: 18.w),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w500,
                  fontSize: 14.sp,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Symbols.chevron_right, size: 18.w, color: color),
          ],
        ),
      ),
    );
  }
}

// ── Filter Chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;
  final Color? accentColor;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.isDark,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: selected
                ? color
                : (isDark ? AppColors.dividerDark : AppColors.dividerLight),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 12.sp,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? color
                : (isDark ? AppColors.textMutedLight : AppColors.textMutedDark),
          ),
        ),
      ),
    );
  }
}
