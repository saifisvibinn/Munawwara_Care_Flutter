import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/moderator_provider.dart';

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
  final String? limboReason; // manual | group_deleted
  final String? limboGroupName;
  final String? hotelName;
  final String? roomNumber;
  final String? busInfo;
  final String? visaStatus;
  final String? medicalHistory;

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
    this.limboReason,
    this.limboGroupName,
    this.hotelName,
    this.roomNumber,
    this.busInfo,
    this.visaStatus,
    this.medicalHistory,
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
      limboReason: m['limbo_reason']?.toString(),
      limboGroupName: m['limbo_group_name']?.toString(),
      hotelName: m['hotel_name']?.toString(),
      roomNumber: m['room_number']?.toString(),
      busInfo: m['bus_info']?.toString(),
      visaStatus: m['visa']?['status']?.toString(),
      medicalHistory: m['medical_history']?.toString(),
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
  String _unassignedSubFilter = 'all'; // all | manual | deleted
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
      bool matchFilter = false;
      if (_filter == 'all') {
        matchFilter = true;
      } else if (_filter == 'assigned') {
        matchFilter = p.isAssigned;
      } else if (_filter == 'unassigned') {
        if (p.isAssigned) {
          matchFilter = false;
        } else {
          if (_unassignedSubFilter == 'all') {
            matchFilter = true;
          } else if (_unassignedSubFilter == 'manual') {
            matchFilter = p.limboReason == 'manual' || p.limboReason == null;
          } else if (_unassignedSubFilter == 'deleted') {
            matchFilter = p.limboReason == 'group_deleted';
          }
        }
      }

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
        onEdit: () {
          Navigator.pop(context);
          _showEditProfileDialog(pilgrim);
        },
        onViewProfile: () {
          Navigator.pop(context);
          _showProfileSheet(pilgrim, isDark);
        },
      ),
    );
  }

  void _showEditProfileDialog(_PilgrimItem pilgrim) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _EditLogisticsDialog(
        pilgrim: pilgrim,
        onSaved: _load,
      ),
    );
  }

  void _showProfileSheet(_PilgrimItem pilgrim, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PilgrimProfileSheet(pilgrim: pilgrim, isDark: isDark),
    );
  }


  Widget _buildEditField(
      String label, TextEditingController ctrl, IconData icon, bool isDark) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: TextField(
        controller: ctrl,
        style: TextStyle(fontFamily: 'Lexend', fontSize: 14.sp),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontFamily: 'Lexend', fontSize: 12.sp),
          prefixIcon: Icon(icon, size: 20.w),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        ),
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
                    if (_filter == 'unassigned') ...[
                      SizedBox(height: 12.h),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Text(
                              'Type:',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w600,
                                color: textMuted,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            _FilterChip(
                              label: 'All Unassigned',
                              selected: _unassignedSubFilter == 'all',
                              onTap: () => setState(() => _unassignedSubFilter = 'all'),
                              isDark: isDark,
                              accentColor: const Color(0xFFFF8400),
                              isSmall: true,
                            ),
                            SizedBox(width: 6.w),
                            _FilterChip(
                              label: 'Manual',
                              selected: _unassignedSubFilter == 'manual',
                              onTap: () => setState(() => _unassignedSubFilter = 'manual'),
                              isDark: isDark,
                              accentColor: const Color(0xFFFF8400),
                              isSmall: true,
                            ),
                            SizedBox(width: 6.w),
                            _FilterChip(
                              label: 'From Deleted Groups',
                              selected: _unassignedSubFilter == 'deleted',
                              onTap: () => setState(() => _unassignedSubFilter = 'deleted'),
                              isDark: isDark,
                              accentColor: const Color(0xFFFF8400),
                              isSmall: true,
                            ),
                          ],
                        ),
                      ),
                    ],
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
                              : (pilgrim.limboReason == 'group_deleted'
                                  ? 'Deleted Group: ${pilgrim.limboGroupName ?? '?'}'
                                  : 'Unassigned'),
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
                  if (pilgrim.hotelName != null || pilgrim.busInfo != null || pilgrim.visaStatus != null) ...[
                    SizedBox(height: 6.h),
                    Wrap(
                      spacing: 12.w,
                      runSpacing: 4.h,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (pilgrim.hotelName != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Symbols.apartment, size: 12.w, color: textMuted),
                              SizedBox(width: 4.w),
                              Text(
                                '${pilgrim.hotelName}${pilgrim.roomNumber != null ? ' (Room: ${pilgrim.roomNumber})' : ''}',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 10.sp,
                                  color: textMuted,
                                ),
                              ),
                            ],
                          ),
                        if (pilgrim.busInfo != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Symbols.directions_bus, size: 12.w, color: textMuted),
                              SizedBox(width: 4.w),
                              Text(
                                pilgrim.busInfo!,
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 10.sp,
                                  color: textMuted,
                                ),
                              ),
                            ],
                          ),
                        if (pilgrim.visaStatus != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Symbols.verified_user,
                                size: 12.w,
                                color: _getVisaColor(pilgrim.visaStatus),
                              ),
                              SizedBox(width: 4.w),
                              Text(
                                pilgrim.visaStatus!.toUpperCase(),
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.w700,
                                  color: _getVisaColor(pilgrim.visaStatus),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
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

  Color _getVisaColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'issued':
        return Colors.green.shade600;
      case 'pending':
        return Colors.orange.shade600;
      case 'rejected':
      case 'expired':
        return Colors.red.shade600;
      default:
        return Colors.grey.shade600;
    }
  }
}

// ── Actions Sheet ────────────────────────────────────────────────────────────

class _ActionsSheet extends StatelessWidget {
  final _PilgrimItem pilgrim;
  final List<_GroupOption> groups;
  final bool isDark;
  final Function(_GroupOption) onAssign;
  final VoidCallback onRemove;
  final VoidCallback onEdit;
  final VoidCallback onViewProfile;

  const _ActionsSheet({
    required this.pilgrim,
    required this.groups,
    required this.isDark,
    required this.onAssign,
    required this.onRemove,
    required this.onEdit,
    required this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.surfaceDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    final available = groups.where((g) => g.id != pilgrim.currentGroupId).toList();

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      padding: EdgeInsets.symmetric(vertical: 20.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Text(
                    pilgrim.fullName.isNotEmpty ? pilgrim.fullName[0] : '?',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pilgrim.fullName,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 16.sp,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        pilgrim.phoneNumber,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.sp,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20.h),
          const Divider(),

          _ActionTile(
            icon: Symbols.person,
            label: 'View Full Profile',
            isDark: isDark,
            onTap: onViewProfile,
          ),
          _ActionTile(
            icon: Symbols.edit_square,
            label: 'Edit Logistics (Hotel, Visa, etc.)',
            isDark: isDark,
            onTap: onEdit,
          ),

          if (pilgrim.isAssigned)
            _ActionTile(
              icon: Symbols.group_remove,
              label: 'Remove from Group',
              isDark: isDark,
              color: Colors.red.shade600,
              onTap: onRemove,
            )
          else ...[
            if (available.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 8.h),
                child: Row(
                  children: [
                    Icon(Symbols.group_add, size: 18.w, color: AppColors.primary),
                    SizedBox(width: 8.w),
                    Text(
                      'Assign to Group',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 13.sp,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 100.h,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  itemCount: available.length,
                  itemBuilder: (context, index) {
                    final g = available[index];
                    return GestureDetector(
                      onTap: () => onAssign(g),
                      child: Container(
                        width: 120.w,
                        margin: EdgeInsets.only(right: 10.w),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.backgroundDark : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            g.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ] else
              Padding(
                padding: EdgeInsets.all(20.w),
                child: Text(
                  'No other groups available for assignment.',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    color: textMuted,
                  ),
                ),
              ),
          ],
          SizedBox(height: 20.h),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final Color? color;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? (isDark ? AppColors.textLight : AppColors.textDark);

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: activeColor, size: 22.w),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontWeight: FontWeight.w500,
          fontSize: 14.sp,
          color: activeColor,
        ),
      ),
    );
  }
}

// ── Edit Logistics Dialog ───────────────────────────────────────────────────

class _HotelOption {
  final String id;
  final String name;
  final List<_RoomOption> rooms;
  const _HotelOption({required this.id, required this.name, required this.rooms});
}

class _RoomOption {
  final String id;
  final String roomNumber;
  final String? floor;
  const _RoomOption({required this.id, required this.roomNumber, this.floor});
}

class _BusOption {
  final String id;
  final String busNumber;
  final String destination;
  const _BusOption({required this.id, required this.busNumber, required this.destination});
}

class _EditLogisticsDialog extends ConsumerStatefulWidget {
  final _PilgrimItem pilgrim;
  final VoidCallback onSaved;
  const _EditLogisticsDialog({required this.pilgrim, required this.onSaved});

  @override
  ConsumerState<_EditLogisticsDialog> createState() => _EditLogisticsDialogState();
}

class _EditLogisticsDialogState extends ConsumerState<_EditLogisticsDialog> {
  bool _isLoading = false;
  List<_HotelOption> _hotels = [];
  List<_BusOption> _buses = [];

  String? _selectedHotelId;
  String? _selectedRoomId;
  String? _selectedBusId;
  String _selectedVisaStatus = 'unknown';

  @override
  void initState() {
    super.initState();
    _selectedVisaStatus = widget.pilgrim.visaStatus ?? 'unknown';
    if (widget.pilgrim.currentGroupId != null) {
      _loadResources();
    }
  }

  Future<void> _loadResources() async {
    setState(() => _isLoading = true);
    try {
      final resp = await ApiService.dio.get('/groups/${widget.pilgrim.currentGroupId}/resource-options');
      final data = resp.data['data'] as Map<String, dynamic>;

      final hotelsRaw = (data['hotels'] as List<dynamic>? ?? []);
      final busesRaw = (data['buses'] as List<dynamic>? ?? []);

      _hotels = hotelsRaw.map((h) {
        final map = h as Map<String, dynamic>;
        final roomsRaw = (map['rooms'] as List<dynamic>? ?? []);
        return _HotelOption(
          id: map['_id']?.toString() ?? '',
          name: map['name']?.toString() ?? 'Hotel',
          rooms: roomsRaw.map((r) {
            final rMap = r as Map<String, dynamic>;
            return _RoomOption(
              id: rMap['_id']?.toString() ?? '',
              roomNumber: rMap['room_number']?.toString() ?? '-',
              floor: rMap['floor']?.toString(),
            );
          }).toList(),
        );
      }).toList();

      _buses = busesRaw.map((b) {
        final map = b as Map<String, dynamic>;
        return _BusOption(
          id: map['_id']?.toString() ?? '',
          busNumber: map['bus_number']?.toString() ?? '-',
          destination: map['destination']?.toString() ?? '',
        );
      }).toList();

      // Match current values if they exist in options
      for (final h in _hotels) {
        if (h.name == widget.pilgrim.hotelName) {
          _selectedHotelId = h.id;
          for (final r in h.rooms) {
            if (r.roomNumber == widget.pilgrim.roomNumber) {
              _selectedRoomId = r.id;
              break;
            }
          }
          break;
        }
      }

      for (final b in _buses) {
        final info = '${b.busNumber} - ${b.destination}';
        if (info == widget.pilgrim.busInfo || b.busNumber == widget.pilgrim.busInfo) {
          _selectedBusId = b.id;
          break;
        }
      }
    } catch (e) {
      // ignore
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    final hotel = _hotels.where((h) => h.id == _selectedHotelId).firstOrNull;
    final room = hotel?.rooms.where((r) => r.id == _selectedRoomId).firstOrNull;
    final bus = _buses.where((b) => b.id == _selectedBusId).firstOrNull;

    final updates = {
      'hotel_name': hotel?.name,
      'room_number': room?.roomNumber,
      'bus_info': bus == null ? null : '${bus.busNumber} - ${bus.destination}',
      'visa': {
        'status': _selectedVisaStatus,
      }
    };

    final (success, err) = await ref.read(moderatorProvider.notifier).updatePilgrimDetails(widget.pilgrim.id, updates);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      widget.onSaved();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Logistics updated', style: const TextStyle(fontFamily: 'Lexend')),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err ?? 'Update failed', style: const TextStyle(fontFamily: 'Lexend')),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedHotel = _hotels.where((h) => h.id == _selectedHotelId).firstOrNull;
    final rooms = selectedHotel?.rooms ?? [];

    return AlertDialog(
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      title: Text('Edit Logistics',
          style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 18.sp,
              color: isDark ? Colors.white : AppColors.textDark)),
      content: _isLoading && _hotels.isEmpty
          ? SizedBox(height: 100.h, child: const Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String?>(
                    value: _selectedHotelId,
                    dropdownColor: isDark ? AppColors.surfaceDark : Colors.white,
                    decoration: _inputDecoration(isDark, 'Hotel', Symbols.apartment),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('No Hotel')),
                      ..._hotels.map((h) => DropdownMenuItem(value: h.id, child: Text(h.name, overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) => setState(() {
                      _selectedHotelId = v;
                      _selectedRoomId = null;
                    }),
                  ),
                  SizedBox(height: 12.h),
                  DropdownButtonFormField<String?>(
                    value: _selectedRoomId,
                    disabledHint: const Text('Select Hotel first'),
                    dropdownColor: isDark ? AppColors.surfaceDark : Colors.white,
                    decoration: _inputDecoration(isDark, 'Room', Symbols.meeting_room),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('No Room')),
                      ...rooms.map((r) => DropdownMenuItem(
                          value: r.id, child: Text(r.floor == null ? r.roomNumber : '${r.roomNumber} (F${r.floor})'))),
                    ],
                    onChanged: _selectedHotelId == null ? null : (v) => setState(() => _selectedRoomId = v),
                  ),
                  SizedBox(height: 12.h),
                  DropdownButtonFormField<String?>(
                    value: _selectedBusId,
                    dropdownColor: isDark ? AppColors.surfaceDark : Colors.white,
                    decoration: _inputDecoration(isDark, 'Bus', Symbols.directions_bus),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('No Bus')),
                      ..._buses.map((b) => DropdownMenuItem(
                          value: b.id, child: Text('${b.busNumber} - ${b.destination}', overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) => setState(() => _selectedBusId = v),
                  ),
                  SizedBox(height: 12.h),
                  DropdownButtonFormField<String>(
                    value: _selectedVisaStatus,
                    dropdownColor: isDark ? AppColors.surfaceDark : Colors.white,
                    decoration: _inputDecoration(isDark, 'Visa Status', Symbols.verified_user),
                    items: ['pending', 'issued', 'rejected', 'expired', 'unknown']
                        .map((s) => DropdownMenuItem(
                            value: s, child: Text(s.toUpperCase(), style: TextStyle(fontFamily: 'Lexend', fontSize: 13.sp))))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedVisaStatus = v!),
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(fontFamily: 'Lexend')),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
          child: _isLoading
              ? SizedBox(width: 20.w, height: 20.w, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text('Save', style: TextStyle(fontFamily: 'Lexend')),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(bool isDark, String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontFamily: 'Lexend', fontSize: 12.sp, color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark),
      prefixIcon: Icon(icon, size: 20.w, color: AppColors.primary),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
    );
  }
}

// ── Pilgrim Profile Sheet ───────────────────────────────────────────────────

class _PilgrimProfileSheet extends StatelessWidget {
  final _PilgrimItem pilgrim;
  final bool isDark;

  const _PilgrimProfileSheet({required this.pilgrim, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.backgroundDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: EdgeInsets.only(top: 12.h),
            width: 40.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),

          // Header
          Padding(
            padding: EdgeInsets.all(20.w),
            child: Row(
              children: [
                Text(
                  'Pilgrim Profile',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Symbols.close, color: textMuted),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              children: [
                // Top Info Card
                Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : AppColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(
                      color: isDark ? AppColors.dividerDark : AppColors.primary.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 64.w,
                        height: 64.w,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            pilgrim.fullName.isNotEmpty ? pilgrim.fullName[0].toUpperCase() : '?',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 16.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pilgrim.fullName,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 18.sp,
                                fontWeight: FontWeight.bold,
                                color: textPrimary,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Row(
                              children: [
                                Icon(Symbols.phone, size: 14.w, color: textMuted),
                                SizedBox(width: 4.w),
                                Text(
                                  pilgrim.phoneNumber,
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 13.sp,
                                    color: textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 24.h),

                // Logistics Section
                _ProfileSectionTitle(title: 'Travel & Accommodation', isDark: isDark),
                _InfoRow(
                  icon: Symbols.apartment,
                  label: 'Hotel',
                  value: pilgrim.hotelName ?? 'Not Assigned',
                  isDark: isDark,
                ),
                _InfoRow(
                  icon: Symbols.meeting_room,
                  label: 'Room Number',
                  value: pilgrim.roomNumber ?? 'Not Assigned',
                  isDark: isDark,
                ),
                _InfoRow(
                  icon: Symbols.directions_bus,
                  label: 'Bus Info',
                  value: pilgrim.busInfo ?? 'Not Assigned',
                  isDark: isDark,
                ),

                SizedBox(height: 24.h),

                // Visa Section
                _ProfileSectionTitle(title: 'Visa Information', isDark: isDark),
                _InfoRow(
                  icon: Symbols.verified_user,
                  label: 'Visa Status',
                  value: pilgrim.visaStatus?.toUpperCase() ?? 'UNKNOWN',
                  valueColor: _getVisaColor(pilgrim.visaStatus),
                  isDark: isDark,
                ),

                SizedBox(height: 24.h),

                // Medical History
                _ProfileSectionTitle(title: 'Medical History', isDark: isDark),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    (pilgrim.medicalHistory == null || pilgrim.medicalHistory!.isEmpty)
                        ? 'No medical history provided.'
                        : pilgrim.medicalHistory!,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),

                SizedBox(height: 24.h),

                // Personal Details
                _ProfileSectionTitle(title: 'Personal Details', isDark: isDark),
                _InfoRow(
                  icon: Symbols.badge,
                  label: 'National ID',
                  value: pilgrim.nationalId ?? 'Not Provided',
                  isDark: isDark,
                ),
                _InfoRow(
                  icon: Symbols.cake,
                  label: 'Age',
                  value: pilgrim.age != null ? '${pilgrim.age} years' : 'Not Provided',
                  isDark: isDark,
                ),
                _InfoRow(
                  icon: Symbols.language,
                  label: 'Language',
                  value: pilgrim.language.toUpperCase(),
                  isDark: isDark,
                ),
                _InfoRow(
                  icon: Symbols.public,
                  label: 'Ethnicity',
                  value: pilgrim.ethnicity,
                  isDark: isDark,
                ),

                SizedBox(height: 40.h),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getVisaColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'issued':
        return Colors.green.shade600;
      case 'pending':
        return Colors.orange.shade600;
      case 'rejected':
      case 'expired':
        return Colors.red.shade600;
      default:
        return Colors.grey.shade600;
    }
  }
}

class _ProfileSectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;

  const _ProfileSectionTitle({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 11.sp,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: isDark ? AppColors.primary : AppColors.primary.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(icon, size: 18.w, color: AppColors.primary),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11.sp,
                    color: textMuted,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? textPrimary,
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



// ── Filter Chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;
  final Color? accentColor;
  final bool isSmall;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.isDark,
    this.accentColor,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSmall ? 8.w : 12.w,
          vertical: isSmall ? 4.h : 7.h,
        ),
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
            fontSize: isSmall ? 10.sp : 12.sp,
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
