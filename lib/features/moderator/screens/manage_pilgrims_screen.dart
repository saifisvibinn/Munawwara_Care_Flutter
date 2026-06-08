import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dropdown_theme.dart';
import '../providers/manage_pilgrims_provider.dart';
import '../providers/moderator_provider.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../../core/widgets/custom_dialog.dart';
import '../widgets/pilgrim_profile_sheet.dart';
import '../../auth/providers/auth_provider.dart';
import '../../shared/widgets/pilgrim_gender_avatar.dart';
import '../../pilgrim/models/insurance_company.dart';

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
  String _filter = 'all'; // all | assigned | unassigned
  String _unassignedSubFilter = 'all'; // all | manual | deleted
  String _search = '';
  final Set<String> _selectedPilgrimIds = {};
  bool _bulkSelectionMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  List<_GroupOption> _groupsFromModerator() {
    return ref
        .read(moderatorProvider)
        .groups
        .map((g) => _GroupOption(id: g.id, name: g.groupName))
        .where((g) => g.id.isNotEmpty)
        .toList();
  }

  Future<void> _refresh() async {
    await ref.read(managePilgrimsProvider.notifier).refresh();
    if (!mounted) return;
    setState(() {
      final all = ref.read(managePilgrimsProvider).pilgrims;
      _selectedPilgrimIds.removeWhere((id) => !all.any((p) => p.id == id));
      _bulkSelectionMode = false;
    });
  }

  List<ManagedPilgrimItem> _filtered(List<ManagedPilgrimItem> all) {
    return all.where((p) {
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

  void _showNoAssignableGroupsDialog(String titleKey) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : Colors.white;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
        contentPadding: EdgeInsets.fromLTRB(24.w, 28.h, 24.w, 20.h),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.group_off,
              size: 48.w,
              color: AppColors.primary.withValues(alpha: 0.9),
            ),
            SizedBox(height: 16.h),
            Text(
              titleKey.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 18.sp,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              'assign_to_group_no_available'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                height: 1.45,
                color: isDark ? Colors.white70 : AppColors.textMutedLight,
              ),
            ),
            SizedBox(height: 24.h),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                ),
                child: Text(
                  'dialog_ok'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 15.sp,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _enterBulkSelection(ManagedPilgrimItem pilgrim) {
    setState(() {
      _bulkSelectionMode = true;
      _selectedPilgrimIds.add(pilgrim.id);
    });
  }

  void _exitBulkSelection() {
    setState(() {
      _bulkSelectionMode = false;
      _selectedPilgrimIds.clear();
    });
  }

  void _togglePilgrimSelection(String id) {
    setState(() {
      if (_selectedPilgrimIds.contains(id)) {
        _selectedPilgrimIds.remove(id);
      } else {
        _selectedPilgrimIds.add(id);
      }
    });
  }

  Future<void> _assignToGroup(
      ManagedPilgrimItem pilgrim, _GroupOption group) async {
    final (ok, err) = await ref
        .read(moderatorProvider.notifier)
        .addPilgrimToGroup(group.id, userId: pilgrim.id);
    if (!mounted) return;
    if (ok) {
      StandardSnackBar.showSuccess(
        context,
        'group_move_success_msg'.tr(
          namedArgs: {'name': pilgrim.fullName, 'groupName': group.name},
        ),
      );
      await _refresh();
    } else {
      StandardSnackBar.showError(context, err ?? 'error_generic'.tr());
    }
  }

  Future<void> _removeFromGroup(ManagedPilgrimItem pilgrim) async {
    final gid = pilgrim.currentGroupId;
    if (gid == null) return;
    final (ok, err) = await ref
        .read(moderatorProvider.notifier)
        .removePilgrimFromGroup(gid, pilgrim.id);
    if (!mounted) return;
    if (ok) {
      StandardSnackBar.showWarning(
        context,
        'group_remove_success_msg'.tr(namedArgs: {'name': pilgrim.fullName}),
      );
      await _refresh();
    } else {
      StandardSnackBar.showError(context, err ?? 'error_generic'.tr());
    }
  }

  void _showActions(ManagedPilgrimItem pilgrim, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActionsSheet(
        pilgrim: pilgrim,
        groups: _groupsFromModerator(),
        isDark: isDark,
        onAssign: () {
          Navigator.pop(context);
          _showAssignGroupDialog(pilgrim);
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
        onDeleteCompletely: () {
          Navigator.pop(context);
          _confirmDeletePilgrim(pilgrim);
        },
      ),
    );
  }

  Future<void> _confirmDeletePilgrim(ManagedPilgrimItem pilgrim) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bodyColor =
        isDark ? Colors.white70 : AppColors.textMutedLight;

    final confirmed = await StandardDialog.show<bool>(
      context: context,
      title: 'group_delete_pilgrim_title',
      confirmText: 'group_delete',
      cancelText: 'area_cancel',
      isDestructive: true,
      contentWidget: Text(
        'group_delete_pilgrim_body'.tr(args: [pilgrim.fullName]),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 14.sp,
          color: bodyColor,
          height: 1.5,
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final (ok, err) = await ref
        .read(moderatorProvider.notifier)
        .deleteManagedPilgrim(pilgrim.id);
    if (!mounted) return;
    if (ok) {
      StandardSnackBar.showSuccess(
        context,
        'provisioning_pilgrim_removed'.tr(),
      );
      await _refresh();
    } else {
      StandardSnackBar.showError(
        context,
        err ?? 'edit_profile_error_generic'.tr(),
      );
    }
  }

  void _showAssignGroupDialog(ManagedPilgrimItem pilgrim) {
    final available = _groupsFromModerator()
        .where((g) => g.id != pilgrim.currentGroupId)
        .toList();
    
    if (available.isEmpty) {
      _showNoAssignableGroupsDialog('assign_to_group_title');
      return;
    }

    String searchQuery = '';
    
    StandardDialog.show(
      context: context,
      title: 'assign_to_group_title',
      showActions: false, // Custom actions for better control
      contentWidget: SizedBox(
        width: double.maxFinite,
        child: StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtered = available.where((g) => 
              g.name.toLowerCase().contains(searchQuery.toLowerCase())
            ).toList();

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (available.length > 5) ...[
                  TextField(
                    onChanged: (v) => setDialogState(() => searchQuery = v),
                    style: TextStyle(fontFamily: 'Lexend', fontSize: 14.sp),
                    decoration: InputDecoration(
                      hintText: 'manage_search_groups_hint'.tr(),
                      prefixIcon: Icon(Symbols.search, size: 20.w),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
                    ),
                  ),
                  SizedBox(height: 16.h),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 400.h),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => Divider(height: 1.h, indent: 48.w),
                    itemBuilder: (ctx, i) {
                      final g = filtered[i];
                      return ListTile(
                        onTap: () {
                          Navigator.pop(ctx, true);
                          _assignToGroup(pilgrim, g);
                        },
                        contentPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                        leading: Container(
                          padding: EdgeInsets.all(8.w),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Symbols.group, size: 20.w, color: AppColors.primary),
                        ),
                        title: Text(
                          g.name,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            fontSize: 14.sp,
                          ),
                        ),
                        trailing: Icon(Symbols.chevron_right, size: 18.w, color: AppColors.textMutedLight),
                      );
                    },
                  ),
                ),
                if (filtered.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 20.h),
                    child: Text('manage_no_matching_groups'.tr(), 
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Lexend', color: AppColors.textMutedLight)),
                  ),
                SizedBox(height: 24.h),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.r),
                      side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
                    ),
                  ),
                  child: Text(
                    'cancel'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMutedLight,
                      fontSize: 14.sp,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _bulkMoveToGroup(
    List<ManagedPilgrimItem> pilgrims,
    _GroupOption group,
  ) async {
    const batch = 4;
    var ok = 0;
    final errors = <String>[];
    final notifier = ref.read(moderatorProvider.notifier);
    for (var i = 0; i < pilgrims.length; i += batch) {
      final end =
          i + batch > pilgrims.length ? pilgrims.length : i + batch;
      final slice = pilgrims.sublist(i, end);
      await Future.wait(
        slice.map((p) async {
          final (success, err) =
              await notifier.addPilgrimToGroup(group.id, userId: p.id);
          if (success) {
            ok++;
          } else {
            errors.add('${p.fullName}: ${err ?? 'error_generic'.tr()}');
          }
        }),
      );
    }
    if (!mounted) return;
    if (errors.isEmpty) {
      StandardSnackBar.showSuccess(
        context,
        'manage_bulk_move_success'.tr(
          namedArgs: {
            'moved': '$ok',
            'total': '${pilgrims.length}',
            'groupName': group.name,
          },
        ),
      );
      setState(() {
        _selectedPilgrimIds.clear();
        _bulkSelectionMode = false;
      });
      await _refresh();
    } else if (ok > 0) {
      StandardSnackBar.showWarning(
        context,
        'manage_bulk_move_partial'.tr(
          namedArgs: {
            'moved': '$ok',
            'total': '${pilgrims.length}',
          },
        ),
      );
      setState(() {
        _selectedPilgrimIds.clear();
        _bulkSelectionMode = false;
      });
      await _refresh();
    } else {
      StandardSnackBar.showError(
        context,
        errors.isNotEmpty ? errors.first : 'edit_profile_error_generic'.tr(),
      );
    }
  }

  bool _allSelectedInSameGroup(
    List<ManagedPilgrimItem> pilgrims,
    String groupId,
  ) =>
      pilgrims.isNotEmpty &&
      pilgrims.every((p) => p.currentGroupId == groupId);

  void _showBulkMoveGroupDialog() {
    final all = ref.read(managePilgrimsProvider).pilgrims;
    final selected =
        all.where((p) => _selectedPilgrimIds.contains(p.id)).toList();
    if (selected.isEmpty) return;

    final available = _groupsFromModerator()
        .where((g) => !_allSelectedInSameGroup(selected, g.id))
        .toList();

    if (available.isEmpty) {
      _showNoAssignableGroupsDialog('manage_bulk_move_title');
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    String searchQuery = '';

    StandardDialog.show(
      context: context,
      title: 'manage_bulk_move_title',
      showActions: false,
      contentWidget: SizedBox(
        width: double.maxFinite,
        child: StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filteredList = available
                .where(
                  (g) => g.name.toLowerCase().contains(
                        searchQuery.toLowerCase(),
                      ),
                )
                .toList();

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'manage_bulk_move_subtitle'.tr(
                    namedArgs: {'count': '${selected.length}'},
                  ),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13.sp,
                    color: isDark
                        ? AppColors.textMutedLight
                        : AppColors.textMutedDark,
                  ),
                ),
                SizedBox(height: 12.h),
                if (available.length > 5) ...[
                  TextField(
                    onChanged: (v) => setDialogState(() => searchQuery = v),
                    style: TextStyle(fontFamily: 'Lexend', fontSize: 14.sp),
                    decoration: InputDecoration(
                      hintText: 'manage_search_groups_hint'.tr(),
                      prefixIcon: Icon(Symbols.search, size: 20.w),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12.w,
                        vertical: 8.h,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                  ),
                  SizedBox(height: 16.h),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 400.h),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: filteredList.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1.h, indent: 48.w),
                    itemBuilder: (ctx, i) {
                      final g = filteredList[i];
                      return ListTile(
                        onTap: () {
                          Navigator.pop(ctx, true);
                          _bulkMoveToGroup(selected, g);
                        },
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 4.h,
                        ),
                        leading: Container(
                          padding: EdgeInsets.all(8.w),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Symbols.group,
                            size: 20.w,
                            color: AppColors.primary,
                          ),
                        ),
                        title: Text(
                          g.name,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            fontSize: 14.sp,
                          ),
                        ),
                        trailing: Icon(
                          Symbols.chevron_right,
                          size: 18.w,
                          color: AppColors.textMutedLight,
                        ),
                      );
                    },
                  ),
                ),
                if (filteredList.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 20.h),
                    child: Text(
                      'manage_no_matching_groups'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: AppColors.textMutedLight,
                      ),
                    ),
                  ),
                SizedBox(height: 24.h),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.r),
                      side: BorderSide(
                        color: Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  child: Text(
                    'cancel'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMutedLight,
                      fontSize: 14.sp,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showEditProfileDialog(ManagedPilgrimItem pilgrim) {
    StandardDialog.show(
      context: context,
      barrierDismissible: false,
      showActions: false,
      title: 'manage_edit_logistics_title',
      contentWidget: _EditLogisticsContent(
        pilgrim: pilgrim,
        onSaved: _refresh,
      ),
    );
  }

  void _showProfileSheet(ManagedPilgrimItem pilgrim, bool isDark) {
    final currentUserId = ref.read(authProvider).userId ?? '';
    final gId = pilgrim.currentGroupId ?? 'limbo';
    showPilgrimProfileSheet(context, pilgrim.toPilgrimInGroup(), gId, currentUserId);
  }

  @override
  Widget build(BuildContext context) {
    final manageState = ref.watch(managePilgrimsProvider);
    final all = manageState.pilgrims;
    final isLoading = manageState.isLoading;
    final error = manageState.error;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final filtered = _filtered(all);

    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'manage_pilgrims_title'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w800,
                        fontSize: 28.sp,
                        color: textPrimary,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'manage_pilgrims_subtitle'.tr(),
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
                        cursorColor: AppColors.primary,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                          color: textPrimary,
                        ),
                        decoration: InputDecoration(
                          filled: false,
                          isDense: true,
                          hintText: 'manage_pilgrims_search_hint'.tr(),
                          hintStyle: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500,
                            color: textMuted.withValues(alpha: 0.92),
                          ),
                          prefixIcon: Icon(
                            Symbols.search,
                            color: textMuted,
                            size: 20.sp,
                          ),
                          prefixIconConstraints: BoxConstraints(
                            minWidth: 48.w,
                            minHeight: 40.h,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.fromLTRB(
                            0,
                            12.h,
                            16.w,
                            12.h,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),

                    // Filter chips
                    Row(
                      children: [
                        _FilterChip(
                          label: 'manage_filter_all'.tr(args: ['${all.length}']),
                          selected: _filter == 'all',
                          onTap: () => setState(() => _filter = 'all'),
                          isDark: isDark,
                        ),
                        SizedBox(width: 8.w),
                        _FilterChip(
                          label:
                              'manage_filter_unassigned'.tr(args: ['${all.where((p) => !p.isAssigned).length}']),
                          selected: _filter == 'unassigned',
                          onTap: () =>
                              setState(() => _filter = 'unassigned'),
                          isDark: isDark,
                          accentColor: const Color(0xFFFF8400),
                        ),
                        SizedBox(width: 8.w),
                        _FilterChip(
                          label:
                              'manage_filter_assigned'.tr(args: ['${all.where((p) => p.isAssigned).length}']),
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
                              'manage_type'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w600,
                                color: textMuted,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            _FilterChip(
                              label: 'manage_filter_all_unassigned'.tr(),
                              selected: _unassignedSubFilter == 'all',
                              onTap: () => setState(() => _unassignedSubFilter = 'all'),
                              isDark: isDark,
                              accentColor: const Color(0xFFFF8400),
                              isSmall: true,
                            ),
                            SizedBox(width: 6.w),
                            _FilterChip(
                              label: 'manage_filter_manual'.tr(),
                              selected: _unassignedSubFilter == 'manual',
                              onTap: () => setState(() => _unassignedSubFilter = 'manual'),
                              isDark: isDark,
                              accentColor: const Color(0xFFFF8400),
                              isSmall: true,
                            ),
                            SizedBox(width: 6.w),
                            _FilterChip(
                              label: 'manage_filter_from_deleted_groups'.tr(),
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
                    if (!isLoading &&
                        error == null &&
                        filtered.isNotEmpty &&
                        _bulkSelectionMode) ...[
                      SizedBox(height: 12.h),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 10.h,
                        ),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: isDark
                                ? AppColors.dividerDark
                                : AppColors.dividerLight,
                          ),
                        ),
                        child: Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'manage_bulk_n_selected'.tr(
                                namedArgs: {
                                  'count': '${_selectedPilgrimIds.length}',
                                },
                              ),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                for (final p in filtered) {
                                  _selectedPilgrimIds.add(p.id);
                                }
                              }),
                              child: Text(
                                'manage_bulk_select_all_visible'.tr(),
                                style: const TextStyle(
                                  fontFamily: 'Lexend',
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _selectedPilgrimIds.isEmpty
                                  ? null
                                  : () => setState(
                                        () => _selectedPilgrimIds.clear(),
                                      ),
                              child: Text(
                                'manage_bulk_clear_selection'.tr(),
                                style: const TextStyle(
                                  fontFamily: 'Lexend',
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _exitBulkSelection,
                              child: Text(
                                'manage_bulk_done'.tr(),
                                style: const TextStyle(
                                  fontFamily: 'Lexend',
                                ),
                              ),
                            ),
                            if (_selectedPilgrimIds.isNotEmpty)
                              FilledButton.tonalIcon(
                                onPressed: _showBulkMoveGroupDialog,
                                icon: Icon(
                                  Symbols.drive_file_move,
                                  size: 18.w,
                                ),
                                label: Text(
                                  'manage_bulk_move_to_group'.tr(),
                                  style: const TextStyle(
                                    fontFamily: 'Lexend',
                                  ),
                                ),
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
            if (isLoading && all.isEmpty)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (error != null && all.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Symbols.error_circle_rounded,
                          color: Colors.red.shade400, size: 48.w),
                      SizedBox(height: 12.h),
                      Text(error,
                          style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 14.sp,
                              color: textMuted)),
                      SizedBox(height: 12.h),
                      TextButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Symbols.refresh),
                        label: Text('alerts_retry'.tr()),
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
                            ? 'manage_no_pilgrims_match_search'.tr()
                            : 'manage_no_pilgrims_found'.tr(),
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
                      selectionMode: _bulkSelectionMode,
                      isSelected: _selectedPilgrimIds.contains(filtered[i].id),
                      onLongPressEnterSelection: () =>
                          _enterBulkSelection(filtered[i]),
                      onToggleFromRow: () =>
                          _togglePilgrimSelection(filtered[i].id),
                      onSelectionChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          if (v) {
                            _selectedPilgrimIds.add(filtered[i].id);
                          } else {
                            _selectedPilgrimIds.remove(filtered[i].id);
                          }
                        });
                      },
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
  final ManagedPilgrimItem pilgrim;
  final bool isDark;
  final VoidCallback onAction;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onLongPressEnterSelection;
  final VoidCallback onToggleFromRow;
  final ValueChanged<bool?> onSelectionChanged;

  const _PilgrimCard({
    required this.pilgrim,
    required this.isDark,
    required this.onAction,
    required this.selectionMode,
    required this.isSelected,
    required this.onLongPressEnterSelection,
    required this.onToggleFromRow,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    final borderColor = isSelected
        ? AppColors.primary.withValues(alpha: 0.85)
        : (selectionMode
            ? (isDark
                ? AppColors.dividerDark
                : AppColors.dividerLight)
            : (pilgrim.isAssigned
                ? Colors.transparent
                : const Color(0xFFFF8400).withValues(alpha: 0.4)));

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: borderColor,
          width: isSelected ? 2 : 1,
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
            if (selectionMode) ...[
              Checkbox(
                value: isSelected,
                onChanged: onSelectionChanged,
                activeColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              SizedBox(width: 4.w),
            ],
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: onLongPressEnterSelection,
                onTap: selectionMode ? onToggleFromRow : null,
                child: Row(
                  children: [
                    ClipOval(
                      child: PilgrimGenderAvatar(
                        gender: pilgrim.gender,
                        size: 44.w,
                        imageUrl: pilgrim.profilePicture,
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
                              color: textMuted,
                            ),
                          ),
                          SizedBox(height: 6.h),
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
                        Flexible(
                          child: Text(
                            pilgrim.isAssigned
                                ? pilgrim.currentGroupName!
                                : (pilgrim.limboReason == 'group_deleted'
                                    ? 'manage_deleted_group'.tr(args: [pilgrim.limboGroupName ?? '?'])
                                    : 'manage_unassigned'.tr()),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w600,
                              fontSize: 11.sp,
                              color: pilgrim.isAssigned
                                  ? Colors.green.shade700
                                  : const Color(0xFFFF8400),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pilgrim.hotelName != null) ...[
                    SizedBox(height: 6.h),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Symbols.apartment, size: 12.w, color: textMuted),
                        SizedBox(width: 4.w),
                        Text(
                          '${pilgrim.hotelName}${pilgrim.roomNumber != null ? ' (${ 'group_room_number'.tr() }: ${pilgrim.roomNumber})' : ''}',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 10.sp,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
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

// ── Actions Sheet ────────────────────────────────────────────────────────────

class _ActionsSheet extends StatelessWidget {
  final ManagedPilgrimItem pilgrim;
  final List<_GroupOption> groups;
  final bool isDark;
  final VoidCallback onAssign;
  final VoidCallback onRemove;
  final VoidCallback onEdit;
  final VoidCallback onViewProfile;
  final VoidCallback onDeleteCompletely;

  const _ActionsSheet({
    required this.pilgrim,
    required this.groups,
    required this.isDark,
    required this.onAssign,
    required this.onRemove,
    required this.onEdit,
    required this.onViewProfile,
    required this.onDeleteCompletely,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.surfaceDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;


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
                ClipOval(
                  child: PilgrimGenderAvatar(
                    gender: pilgrim.gender,
                    size: 40.w,
                    imageUrl: pilgrim.profilePicture,
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
            label: 'manage_view_full_profile'.tr(),
            isDark: isDark,
            onTap: onViewProfile,
          ),
          _ActionTile(
            icon: Symbols.edit_square,
            label: 'manage_edit_logistics'.tr(),
            isDark: isDark,
            onTap: onEdit,
          ),

          if (!pilgrim.isAssigned)
            _ActionTile(
              icon: Symbols.group_add,
              label: 'assign_to_group_title'.tr(),
              isDark: isDark,
              onTap: onAssign,
            )
          else
            _ActionTile(
              icon: Symbols.group_remove,
              label: 'manage_remove_from_group'.tr(),
              isDark: isDark,
              color: Colors.red.shade600,
              onTap: onRemove,
            ),
          const Divider(),
          _ActionTile(
            icon: Symbols.delete_forever,
            label: 'manage_delete_pilgrim_account'.tr(),
            isDark: isDark,
            color: Colors.red.shade700,
            onTap: onDeleteCompletely,
          ),
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
  final int capacity;
  final int currentOccupancy;
  const _RoomOption({
    required this.id,
    required this.roomNumber,
    this.floor,
    required this.capacity,
    this.currentOccupancy = 0,
  });
}

class _EditLogisticsContent extends ConsumerStatefulWidget {
  final ManagedPilgrimItem pilgrim;
  final VoidCallback onSaved;
  const _EditLogisticsContent({required this.pilgrim, required this.onSaved});

  @override
  ConsumerState<_EditLogisticsContent> createState() => _EditLogisticsContentState();
}

class _EditLogisticsContentState extends ConsumerState<_EditLogisticsContent> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  List<_HotelOption> _hotels = [];
  List<InsuranceCompany> _insurances = [];

  final _morafeqNameCtrl = TextEditingController();
  final _morafeqPhoneCtrl = TextEditingController();
  final _morafeqEmailCtrl = TextEditingController();
  final _tasheraNumberCtrl = TextEditingController();

  String? _selectedHotelId;
  String? _selectedRoomId;
  String? _selectedInsuranceCompanyId;

  @override
  void initState() {
    super.initState();
    _morafeqNameCtrl.text = widget.pilgrim.morafeqName ?? '';
    _morafeqPhoneCtrl.text = widget.pilgrim.morafeqPhone ?? '';
    _morafeqEmailCtrl.text = widget.pilgrim.morafeqEmail ?? '';
    _tasheraNumberCtrl.text = widget.pilgrim.tasheraNumber ?? '';
    _selectedInsuranceCompanyId = widget.pilgrim.insuranceCompany?.id;
    if (widget.pilgrim.currentGroupId != null) {
      _loadResources();
    }
  }

  @override
  void dispose() {
    _morafeqNameCtrl.dispose();
    _morafeqPhoneCtrl.dispose();
    _morafeqEmailCtrl.dispose();
    _tasheraNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadResources() async {
    setState(() => _isLoading = true);
    try {
      final resp = await ApiService.dio.get(
        '/groups/${widget.pilgrim.currentGroupId}/resource-options',
        queryParameters: {'exclude_pilgrim_id': widget.pilgrim.id},
      );
      final raw = resp.data;
      final payload = raw is Map<String, dynamic> 
          ? (raw['data'] as Map<String, dynamic>? ?? raw) 
          : <String, dynamic>{};

      final hotelsRaw = (payload['hotels'] as List<dynamic>? ?? []);
      final insurancesRaw = (payload['insurances'] as List<dynamic>? ?? []);

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
              capacity: (rMap['capacity'] as num?)?.toInt() ?? 1,
              currentOccupancy: (rMap['current_occupancy'] as num?)?.toInt() ?? 0,
            );
          }).toList(),
        );
      }).toList();

      _insurances = insurancesRaw.map((i) {
        return InsuranceCompany.fromJson(Map<String, dynamic>.from(i as Map));
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

      _syncSelectionsWithOptions();
    } catch (e) {
      // ignore
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _syncSelectionsWithOptions() {
    if (_selectedInsuranceCompanyId != null &&
        !_insurances.any((i) => i.id == _selectedInsuranceCompanyId)) {
      _selectedInsuranceCompanyId = null;
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    final hotel = _hotels.where((h) => h.id == _selectedHotelId).firstOrNull;
    final room = hotel?.rooms.where((r) => r.id == _selectedRoomId).firstOrNull;

    final updates = {
      'hotel_name': hotel?.name,
      'room_number': room?.roomNumber,
      'morafeq_name': _morafeqNameCtrl.text.trim().isEmpty ? null : _morafeqNameCtrl.text.trim(),
      'morafeq_phone': _morafeqPhoneCtrl.text.trim().isEmpty ? null : _morafeqPhoneCtrl.text.trim(),
      'morafeq_email': _morafeqEmailCtrl.text.trim().isEmpty ? null : _morafeqEmailCtrl.text.trim(),
      'tashera_number': _tasheraNumberCtrl.text.trim().isEmpty ? null : _tasheraNumberCtrl.text.trim(),
      'insurance_company_id': _selectedInsuranceCompanyId,
    };

    final (success, err) = await ref.read(moderatorProvider.notifier).updatePilgrimDetails(widget.pilgrim.id, updates);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      widget.onSaved();
      StandardDialog.hide(context);
      StandardSnackBar.showSuccess(context, 'manage_logistics_updated'.tr());
    } else {
      StandardSnackBar.showError(context, err ?? 'edit_profile_error_generic'.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hotel = _hotels.where((h) => h.id == _selectedHotelId).firstOrNull;
    final rooms = hotel?.rooms ?? [];

    if (_isLoading && _hotels.isEmpty) {
      return SizedBox(height: 100.h, child: const Center(child: CircularProgressIndicator()));
    }

    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedHotelId,
                    isExpanded: true,
                    decoration: AppDropdownTheme.formFieldDecoration(
                      isDark: isDark,
                      labelText: 'group_hotel_name'.tr(),
                      prefixIcon: Icon(Symbols.apartment),
                    ),
                    icon: AppDropdownTheme.menuTrailingIcon(),
                    dropdownColor: AppDropdownTheme.menuBackground(isDark),
                    borderRadius: AppDropdownTheme.menuBorderRadius(),
                    elevation: AppDropdownTheme.menuElevation(),
                    menuMaxHeight: AppDropdownTheme.menuMaxHeight(),
                    style: AppDropdownTheme.valueStyle(isDark),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(
                          'group_no_hotel'.tr(),
                          style: AppDropdownTheme.menuItemStyle(isDark),
                        ),
                      ),
                      ..._hotels.map(
                        (h) => DropdownMenuItem(
                          value: h.id,
                          child: Text(
                            h.name,
                            overflow: TextOverflow.ellipsis,
                            style: AppDropdownTheme.menuItemStyle(isDark),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      _selectedHotelId = v;
                      _selectedRoomId = null;
                    }),
                  ),
                  SizedBox(height: 12.h),
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedRoomId,
                    isExpanded: true,
                    disabledHint: Text('manage_select_hotel_first'.tr()),
                    decoration: AppDropdownTheme.formFieldDecoration(
                      isDark: isDark,
                      labelText: 'group_room_number'.tr(),
                      prefixIcon: Icon(Symbols.meeting_room),
                    ),
                    icon: AppDropdownTheme.menuTrailingIcon(),
                    dropdownColor: AppDropdownTheme.menuBackground(isDark),
                    borderRadius: AppDropdownTheme.menuBorderRadius(),
                    elevation: AppDropdownTheme.menuElevation(),
                    menuMaxHeight: AppDropdownTheme.menuMaxHeight(),
                    style: AppDropdownTheme.valueStyle(isDark),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(
                          'group_no_room'.tr(),
                          style: AppDropdownTheme.menuItemStyle(isDark),
                        ),
                      ),
                      ...rooms.map((r) {
                        final current = r.currentOccupancy;
                        final isFull = current >= r.capacity;
                        final base = AppDropdownTheme.menuItemStyle(isDark);
                        return DropdownMenuItem(
                          value: r.id,
                          child: Text(
                            '${r.roomNumber}${r.floor != null ? ' (F${r.floor})' : ''} - $current/${r.capacity}${isFull ? ' (${ 'manage_full'.tr() })' : ''}',
                            style: isFull
                                ? base.copyWith(color: Colors.green.shade400)
                                : base,
                          ),
                        );
                      }),
                    ],
                    onChanged: _selectedHotelId == null
                        ? null
                        : (v) => setState(() => _selectedRoomId = v),
                  ),
                  SizedBox(height: 12.h),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.h),
                      child: Text(
                        'morafeq_companion_info'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.bold,
                          fontSize: 13.sp,
                          color: isDark ? Colors.white70 : AppColors.textMutedDark,
                        ),
                      ),
                    ),
                  ),
                  TextFormField(
                    controller: _morafeqNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: AppDropdownTheme.formFieldDecoration(
                      isDark: isDark,
                      labelText: 'morafeq_name'.tr(),
                      prefixIcon: const Icon(Symbols.person),
                    ),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                    validator: (v) {
                      final phone = _morafeqPhoneCtrl.text.trim();
                      if (phone.isNotEmpty && (v == null || v.trim().isEmpty)) {
                        return 'provisioning_required'.tr();
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 12.h),
                  TextFormField(
                    controller: _morafeqPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: AppDropdownTheme.formFieldDecoration(
                      isDark: isDark,
                      labelText: 'morafeq_phone'.tr(),
                      prefixIcon: const Icon(Symbols.phone),
                    ),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                    validator: (v) {
                      final name = _morafeqNameCtrl.text.trim();
                      if (name.isNotEmpty && (v == null || v.trim().isEmpty)) {
                        return 'provisioning_required'.tr();
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 12.h),
                  TextFormField(
                    controller: _morafeqEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: AppDropdownTheme.formFieldDecoration(
                      isDark: isDark,
                      labelText: '${'morafeq_email'.tr()} (${'provisioning_optional_logistics'.tr()})',
                      prefixIcon: const Icon(Symbols.mail),
                    ),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                    validator: (v) {
                      if (v != null && v.trim().isNotEmpty) {
                        final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                        if (!emailRegex.hasMatch(v.trim())) {
                          return 'provisioning_invalid'.tr();
                        }
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 12.h),
                  TextFormField(
                    controller: _tasheraNumberCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: AppDropdownTheme.formFieldDecoration(
                      isDark: isDark,
                      labelText: 'Tashera Number',
                      prefixIcon: Icon(Symbols.tag),
                    ),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedInsuranceCompanyId,
                    isExpanded: true,
                    decoration: AppDropdownTheme.formFieldDecoration(
                      isDark: isDark,
                      labelText: 'Insurance Company',
                      prefixIcon: Icon(Symbols.health_and_safety),
                    ),
                    icon: AppDropdownTheme.menuTrailingIcon(),
                    dropdownColor: AppDropdownTheme.menuBackground(isDark),
                    borderRadius: AppDropdownTheme.menuBorderRadius(),
                    elevation: AppDropdownTheme.menuElevation(),
                    menuMaxHeight: AppDropdownTheme.menuMaxHeight(),
                    style: AppDropdownTheme.valueStyle(isDark, fontSize: 13),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'No Insurance',
                          style: AppDropdownTheme.menuItemStyle(isDark, fontSize: 13),
                        ),
                      ),
                      ..._insurances.map(
                        (i) => DropdownMenuItem<String?>(
                          value: i.id,
                          child: Text(
                            i.name,
                            style: AppDropdownTheme.menuItemStyle(isDark, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedInsuranceCompanyId = v),
                  ),
                  SizedBox(height: 24.h),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => StandardDialog.hide(context),
                          style: TextButton.styleFrom(),
                          child: Text(
                            'cancel'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white60 : AppColors.textMutedLight,
                              fontSize: 14.sp,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _save,
                          style: ElevatedButton.styleFrom(),
                          child: _isLoading
                              ? SizedBox(width: 20.w, height: 20.w, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(
                                  'settings_save'.tr(),
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.sp,
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
