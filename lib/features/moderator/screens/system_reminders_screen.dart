import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../core/widgets/custom_dialog.dart';
import '../../../core/widgets/standard_snackbar.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dropdown_theme.dart';
import '../providers/moderator_provider.dart';
import '../providers/reminder_provider.dart';
import '../widgets/reminder_card.dart';
import 'dart:async';

class SystemRemindersScreen extends ConsumerStatefulWidget {
  const SystemRemindersScreen({super.key});

  @override
  ConsumerState<SystemRemindersScreen> createState() =>
      _SystemRemindersScreenState();
}

class _SystemRemindersScreenState extends ConsumerState<SystemRemindersScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncPilgrimAudienceWithGroups(ref.read(moderatorProvider).groups);
      ref.read(reminderProvider.notifier).load();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.read(reminderProvider.notifier).load();
    });
  }

  int _targetAudienceIndex = 0; // 0 = System Wide, 1 = Specific Groups, 2 = Specific Pilgrim
  int _historyFilterIndex = 0; // 0 = All, 1 = System, 2 = Groups, 3 = Pilgrim
  final Set<String> _selectedGroupIds = {};
  String? _selectedGroupIdForPilgrim;
  String? _selectedPilgrimId;

  final _messageController = TextEditingController();
  DateTime? _selectedDate;
  DateTime get _startDate => _selectedDate ?? DateTime.now();
  TimeOfDay? _selectedTime;
  TimeOfDay get _startTime => _selectedTime ?? TimeOfDay.now();
  int _repeatCount = 1;
  int? _selectedIntervalMin; // null = custom
  bool _isCustomInterval = false;
  /// Dart weekdays 1=Mon … 7=Sun — same time on each selected day (server UTC anchor).
  final Set<int> _weeklyDays = {};
  
  List<Map<String, dynamic>> get _intervalOptions => [
        {'labelKey': 'reminder_interval_chip_1m', 'value': 1},
        {'labelKey': 'reminder_interval_chip_5m', 'value': 5},
        {'labelKey': 'reminder_interval_chip_30m', 'value': 30},
        {'labelKey': 'reminder_interval_chip_1h', 'value': 60},
        {'labelKey': 'reminder_interval_chip_6h', 'value': 360},
        {'labelKey': 'reminder_interval_chip_12h', 'value': 720},
        {'labelKey': 'reminder_interval_chip_1d', 'value': 1440},
      ];

  bool _isCreating = false;

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageController.dispose();

    super.dispose();
  }

  void _onSelectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _selectedDate = picked);
  }

  void _onSelectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null && mounted) setState(() => _selectedTime = picked);
  }

  /// Keeps pilgrim-audience dropdown state aligned with [moderatorProvider] after refresh.
  void _syncPilgrimAudienceWithGroups(List<ModeratorGroup> allGroups) {
    String? gid = _selectedGroupIdForPilgrim;
    if (gid != null && !allGroups.any((g) => g.id == gid)) {
      gid = null;
    }
    ModeratorGroup? group;
    if (gid != null) {
      for (final g in allGroups) {
        if (g.id == gid) {
          group = g;
          break;
        }
      }
    }
    String? pid = _selectedPilgrimId;
    if (pid != null &&
        (group == null || !group.pilgrims.any((p) => p.id == pid))) {
      pid = null;
    }
    if (gid != _selectedGroupIdForPilgrim || pid != _selectedPilgrimId) {
      if (!mounted) return;
      setState(() {
        _selectedGroupIdForPilgrim = gid;
        _selectedPilgrimId = pid;
      });
    }
  }

  Future<void> _createReminders() async {
    final msg = _messageController.text.trim();
    if (msg.isEmpty) {
      StandardSnackBar.showError(context, 'reminder_enter_message'.tr());
      return;
    }

    final state = ref.read(moderatorProvider);
    final allGroups = state.groups;

    // Determine target groups and type
    List<String> targetGroups = [];
    String targetType = 'group';

    if (_targetAudienceIndex == 0) {
      targetGroups = allGroups.map((g) => g.id).toList();
      targetType = 'system';
    } else if (_targetAudienceIndex == 1) {
      targetGroups = _selectedGroupIds.toList();
      targetType = 'group';
    } else {
      if (_selectedGroupIdForPilgrim == null || _selectedPilgrimId == null) {
        StandardSnackBar.showWarning(context, 'reminder_select_group_and_pilgrim'.tr());
        return;
      }
      targetGroups = [_selectedGroupIdForPilgrim!];
      targetType = 'pilgrim';
    }

    if (targetGroups.isEmpty) {
      StandardSnackBar.showWarning(context, 'reminder_no_groups_selected'.tr());
      return;
    }

    setState(() => _isCreating = true);

    final sched = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _startTime.hour,
      _startTime.minute,
    );

    int intervalMin = _isCustomInterval ? 15 : (_selectedIntervalMin ?? 15);
    int count = _repeatCount;

    final weeklyList =
        _weeklyDays.isEmpty ? null : (List<int>.from(_weeklyDays)..sort());

    final success = await ref
        .read(reminderProvider.notifier)
        .create(
          groupIds: targetGroups,
          targetType: targetType,
          pilgrimId: _targetAudienceIndex == 2 ? _selectedPilgrimId : null,
          text: msg,
          scheduledAt: sched,
          repeatCount: count,
          repeatIntervalMin: intervalMin,
          weeklyDays: weeklyList,
        );

    if (!mounted) return;

    setState(() => _isCreating = false);

    if (success) {
      StandardSnackBar.showSuccess(context, 'reminder_create_success'.tr());
      _messageController.clear();
      _selectedGroupIds.clear();
      setState(() {
        _targetAudienceIndex = 0;
        _repeatCount = 1;
        _selectedIntervalMin = null;
        _isCustomInterval = false;
        _selectedGroupIdForPilgrim = null;
        _selectedPilgrimId = null;
        _weeklyDays.clear();
      });
    } else {
      StandardSnackBar.showError(context, 'reminder_create_partial_fail'.tr());
    }
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(moderatorProvider);
    ref.listen<ModeratorState>(moderatorProvider, (previous, next) {
      if (!mounted) return;
      _syncPilgrimAudienceWithGroups(next.groups);
    });
    final allGroups = state.groups;
    final remState = ref.watch(reminderProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 100.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'reminder_schedule_page_title'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w800,
                fontSize: 28.sp,
                color: isDark ? Colors.white : const Color(0xFF1A1A4E),
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'reminder_schedule_page_subtitle'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                color: AppColors.textMutedLight,
              ),
            ),
            SizedBox(height: 24.h),

            // TARGET AUDIENCE
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'reminder_target_audience'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 12.sp,
                      color: AppColors.textMutedLight,
                      letterSpacing: 1.1,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Container(
                    width: double.infinity,
                    height: 50.h,
                    padding: EdgeInsets.all(4.w),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2A3C) : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final segmentWidth = constraints.maxWidth / 3;
                        final isRtl = Directionality.of(context).name == 'rtl';
                        final visualIndex = isRtl
                            ? (2 - _targetAudienceIndex)
                            : _targetAudienceIndex;
                        return Stack(
                          children: [
                            // Animated Indicator
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.fastOutSlowIn,
                              left: visualIndex * segmentWidth,
                              width: segmentWidth,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.surfaceDark : Colors.white,
                                  borderRadius: BorderRadius.circular(12.r),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: isDark ? 0.25 : 0.08,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Buttons
                            Row(
                              children: [
                                _buildSegment(0, 'reminder_audience_system_wide', isDark),
                                _buildSegment(1, 'reminder_audience_groups_tab', isDark),
                                _buildSegment(2, 'reminder_audience_pilgrim_tab', isDark),
                              ],
                            ),
                          ],
                        );
                      }
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16.h),

            // SPECIFIC GROUPS SELECTOR
            if (_targetAudienceIndex == 1) ...[
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: isDark
                        ? AppColors.backgroundDark
                        : const Color(0xFFEEEEF8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.2 : 0.05,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'reminder_select_recipient_groups'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 14.sp,
                        color: isDark ? Colors.white : const Color(0xFF1A1A4E),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    ...allGroups.map((g) {
                      final isSelected = _selectedGroupIds.contains(g.id);
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedGroupIds.remove(g.id);
                            } else {
                              _selectedGroupIds.add(g.id);
                            }
                          });
                        },
                        child: Container(
                          margin: EdgeInsets.only(bottom: 8.h),
                          padding: EdgeInsets.symmetric(
                            horizontal: 16.w,
                            vertical: 12.h,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF2A2A3C)
                                : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Symbols.groups,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF8A6A30),
                                size: 20.w,
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Text(
                                  g.groupName,
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14.sp,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1A1A4E),
                                  ),
                                ),
                              ),
                              Icon(
                                isSelected
                                    ? Symbols.check_circle
                                    : Symbols.radio_button_unchecked,
                                color: isSelected
                                    ? const Color(0xFFC05621)
                                    : AppColors.textMutedLight,
                                size: 20.w,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    SizedBox(height: 8.h),
                    Center(
                      child: TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(
                          Symbols.add_circle,
                          color: Color(0xFF9A3412),
                          size: 18,
                        ),
                        label: Text(
                          'reminder_browse_more_groups'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF9A3412),
                            fontSize: 13.sp,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16.h),
            ],

            // SPECIFIC PILGRIM SELECTOR
            if (_targetAudienceIndex == 2) ...[
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: isDark
                        ? AppColors.backgroundDark
                        : const Color(0xFFEEEEF8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.2 : 0.05,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'reminder_select_pilgrim_section'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 14.sp,
                        color: isDark ? Colors.white : const Color(0xFF1A1A4E),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('system_reminder_specific_group'),
                      value: _selectedGroupIdForPilgrim != null &&
                              allGroups.any((g) => g.id == _selectedGroupIdForPilgrim)
                          ? _selectedGroupIdForPilgrim
                          : null,
                      decoration: AppDropdownTheme.formFieldDecoration(
                        isDark: isDark,
                        labelText: 'reminder_select_group_dropdown'.tr(),
                        nested: true,
                      ),
                      icon: AppDropdownTheme.menuTrailingIcon(),
                      dropdownColor: AppDropdownTheme.menuBackground(isDark),
                      borderRadius: AppDropdownTheme.menuBorderRadius(),
                      elevation: AppDropdownTheme.menuElevation(),
                      menuMaxHeight: AppDropdownTheme.menuMaxHeight(),
                      isExpanded: true,
                      style: AppDropdownTheme.valueStyle(isDark, fontSize: 14),
                      items: allGroups
                          .map(
                            (g) => DropdownMenuItem(
                              value: g.id,
                              child: Text(
                                g.groupName,
                                style: AppDropdownTheme.menuItemStyle(isDark),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedGroupIdForPilgrim = val;
                          _selectedPilgrimId = null; // reset pilgrim when group changes
                        });
                      },
                    ),
                    SizedBox(height: 12.h),
                    if (_selectedGroupIdForPilgrim != null) ...[
                      Builder(
                        builder: (ctx) {
                          ModeratorGroup? group;
                          for (final g in allGroups) {
                            if (g.id == _selectedGroupIdForPilgrim) {
                              group = g;
                              break;
                            }
                          }
                          if (group == null) {
                            return Text(
                              'reminder_select_group_dropdown'.tr(),
                              style: TextStyle(color: Colors.red, fontSize: 12.sp),
                            );
                          }
                          final pilgrims = group.pilgrims;
                          if (pilgrims.isEmpty) {
                            return Text('reminder_no_pilgrims'.tr(), style: TextStyle(color: Colors.red, fontSize: 12.sp));
                          }
                          final validPilgrimId =
                              _selectedPilgrimId != null &&
                                      pilgrims.any((p) => p.id == _selectedPilgrimId)
                                  ? _selectedPilgrimId
                                  : null;
                          return DropdownButtonFormField<String>(
                            key: ValueKey(
                              'system_reminder_specific_pilgrim_$_selectedGroupIdForPilgrim',
                            ),
                            value: validPilgrimId,
                            decoration: AppDropdownTheme.formFieldDecoration(
                              isDark: isDark,
                              labelText: 'reminder_select_pilgrim'.tr(),
                              nested: true,
                            ),
                            icon: AppDropdownTheme.menuTrailingIcon(),
                            dropdownColor:
                                AppDropdownTheme.menuBackground(isDark),
                            borderRadius: AppDropdownTheme.menuBorderRadius(),
                            elevation: AppDropdownTheme.menuElevation(),
                            menuMaxHeight: AppDropdownTheme.menuMaxHeight(),
                            isExpanded: true,
                            style:
                                AppDropdownTheme.valueStyle(isDark, fontSize: 14),
                            items: pilgrims
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p.id,
                                    child: Text(
                                      p.fullName,
                                      style: AppDropdownTheme.menuItemStyle(
                                        isDark,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedPilgrimId = val;
                              });
                            },
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 16.h),
            ],

            // REMINDER MESSAGE
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(
                  color: isDark
                      ? AppColors.backgroundDark
                      : const Color(0xFFEEEEF8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'reminder_text_label'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 14.sp,
                      color: isDark ? Colors.white : const Color(0xFF1A1A4E),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Container(
                    height: 120.h,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2A2A3C)
                          : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: TextField(
                      controller: _messageController,
                      maxLines: null,
                      minLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      cursorColor: AppColors.primary,
                      selectionControls: MaterialTextSelectionControls(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 14.sp,
                        color: isDark ? Colors.white : const Color(0xFF1A1A4E),
                      ),
                      decoration: InputDecoration(
                        hintText: 'reminder_text_hint'.tr(),
                        hintStyle: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 14.sp,
                          color: AppColors.textMutedLight,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.all(16.w),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16.h),

            // SCHEDULING OPTIONS
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(
                  color: isDark
                      ? AppColors.backgroundDark
                      : const Color(0xFFEEEEF8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'reminder_scheduling_section'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 14.sp,
                      color: isDark ? Colors.white : const Color(0xFF1A1A4E),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'reminder_label_start_date'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w600,
                                fontSize: 10.sp,
                                color: AppColors.textMutedLight,
                                letterSpacing: 1.1,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            GestureDetector(
                              onTap: _onSelectDate,
                              child: Container(
                                height: 48.h,
                                padding: EdgeInsets.symmetric(horizontal: 12.w),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF2A2A3C)
                                      : const Color(0xFFE5E7EB),
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Symbols.calendar_today,
                                      size: 18.w,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF1A1A4E),
                                    ),
                                    SizedBox(width: 8.w),
                                    Expanded(
                                      child: Text(
                                        DateFormat(
                                          'MMM dd, yyyy',
                                        ).format(_startDate),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 14.sp,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF1A1A4E),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'reminder_label_start_time'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w600,
                                fontSize: 10.sp,
                                color: AppColors.textMutedLight,
                                letterSpacing: 1.1,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            GestureDetector(
                              onTap: _onSelectTime,
                              child: Container(
                                height: 48.h,
                                padding: EdgeInsets.symmetric(horizontal: 12.w),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF2A2A3C)
                                      : const Color(0xFFE5E7EB),
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Symbols.schedule,
                                      size: 18.w,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF1A1A4E),
                                    ),
                                    SizedBox(width: 8.w),
                                    Expanded(
                                      child: Text(
                                        _startTime.format(context),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 14.sp,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF1A1A4E),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20.h),
                  Text(
                    'reminder_weekdays_section'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 14.sp,
                      color: isDark ? Colors.white : const Color(0xFF1A1A4E),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'reminder_weekdays_hint'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 11.sp,
                      color: AppColors.textMutedLight,
                    ),
                  ),
                  SizedBox(height: 10.h),
                  Wrap(
                    spacing: 6.w,
                    runSpacing: 6.h,
                    children: List.generate(7, (i) {
                      final d = i + 1;
                      final selected = _weeklyDays.contains(d);
                      return FilterChip(
                        label: Text(
                          'reminder_weekday_short_$d'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 11.sp,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected
                                ? Colors.white
                                : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                        selected: selected,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _weeklyDays.add(d);
                            } else {
                              _weeklyDays.remove(d);
                            }
                          });
                        },
                        selectedColor: const Color(0xFFF97316),
                        backgroundColor: isDark
                            ? const Color(0xFF2A2A3C)
                            : const Color(0xFFE5E7EB),
                        checkmarkColor: Colors.white,
                        showCheckmark: false,
                        padding: EdgeInsets.symmetric(horizontal: 4.w),
                      );
                    }),
                  ),
                  SizedBox(height: 20.h),
// REPEAT SETTINGS
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'reminder_repeat_count'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 14.sp,
                          color: isDark ? Colors.white : const Color(0xFF1A1A4E),
                        ),
                      ),
                       Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              if (_repeatCount > 1) {
                                setState(() {
                                  _repeatCount--;
                                  // Reset interval when going back to 1
                                  if (_repeatCount == 1) {
                                    _selectedIntervalMin = null;
                                    _isCustomInterval = false;
                                  }
                                });
                              }
                            },
                            icon: Icon(
                              Icons.remove_circle_outline,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          Text(
                            '$_repeatCount',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w700,
                              fontSize: 16.sp,
                              color: isDark ? Colors.white : const Color(0xFF1A1A4E),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              if (_repeatCount >= 104) return;
                              setState(() {
                                _repeatCount++;
                                if (_weeklyDays.isEmpty &&
                                    _repeatCount == 2 &&
                                    _selectedIntervalMin == null &&
                                    !_isCustomInterval) {
                                  _selectedIntervalMin = 15;
                                }
                              });
                            },
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: Color(0xFFF97316),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Interval only when repeating by delay (not weekly multi-day)
                  if (_repeatCount > 1 && _weeklyDays.isEmpty) ...[
                    SizedBox(height: 20.h),
                    Text(
                      'reminder_interval_short'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 14.sp,
                        color: isDark ? Colors.white : const Color(0xFF1A1A4E),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: _intervalOptions.map((opt) {
                        final isSelected = _selectedIntervalMin == opt['value'];
                        return ChoiceChip(
                          label: Text(
                            (opt['labelKey'] as String).tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w500,
                              fontSize: 12.sp,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: const Color(0xFFF97316),
                          backgroundColor: isDark
                              ? const Color(0xFF2A2A3C)
                              : const Color(0xFFE5E7EB),
                          onSelected: (val) {
                            if (val) {
                              setState(() {
                                _selectedIntervalMin = opt['value'];
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 32.h),

            // CREATE BUTTON
            SizedBox(
              width: double.infinity,
              height: 56.h,
              child: ElevatedButton.icon(
                onPressed: _isCreating ? null : _createReminders,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF97316),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28.r),
                  ),
                  elevation: 2,
                ),
                icon: _isCreating
                    ? SizedBox(
                        width: 20.w,
                        height: 20.w,
                        child: const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Symbols.add_alert, size: 24),
                label: Text(
                  _isCreating ? 'reminder_creating'.tr() : 'reminder_create_btn'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 16.sp,
                  ),
                ),
              ),
            ),
            
            SizedBox(height: 48.h),
            
            Text(
              'reminder_history_section'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 20.sp,
                color: isDark ? Colors.white : const Color(0xFF1A1A4E),
              ),
            ),
            SizedBox(height: 16.h),
            
            // HISTORY FILTER
            Container(
              height: 38.h,
              margin: EdgeInsets.only(bottom: 16.h),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip(0, 'reminder_hist_all', isDark),
                  _buildFilterChip(1, 'reminder_hist_system', isDark),
                  _buildFilterChip(2, 'reminder_hist_groups', isDark),
                  _buildFilterChip(3, 'reminder_hist_pilgrim', isDark),
                ],
              ),
            ),
            
            remState.isLoading && remState.reminders.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Builder(
                    builder: (context) {
                      final filtered = remState.reminders.where((r) {
                        if (_historyFilterIndex == 0) return true;
                        if (_historyFilterIndex == 1) return r.targetType == 'system';
                        if (_historyFilterIndex == 2) {
                          return r.targetType == 'group' ||
                              r.targetType == 'all_groups';
                        }
                        if (_historyFilterIndex == 3) return r.targetType == 'pilgrim';
                        return true;
                      }).toList();

                      if (filtered.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 32.h),
                            child: Text(
                              'reminder_empty_history_filter'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                color: AppColors.textMutedLight,
                                fontSize: 14.sp,
                              ),
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final reminder = filtered[i];
                          return Dismissible(
                            key: ValueKey(reminder.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: EdgeInsets.only(right: 20.w),
                              margin: EdgeInsets.only(bottom: 12.h),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(14.r),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Symbols.delete,
                                    color: Colors.white,
                                    size: 24.sp,
                                  ),
                                  SizedBox(height: 4.h),
                                  Text(
                                    'reminder_delete_confirm'.tr(),
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      color: Colors.white,
                                      fontSize: 11.sp,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            confirmDismiss: (_) async {
                              return StandardDialog.show<bool>(
                                context: context,
                                title: 'reminder_delete_title',
                                content: 'reminder_delete_body',
                                confirmText: 'reminder_delete_confirm',
                                cancelText: 'reminder_no',
                                isDestructive: true,
                              );
                            },
                            onDismissed: (_) =>
                                ref.read(reminderProvider.notifier).delete(reminder.id),
                            child: ReminderCard(
                              reminder: reminder,
                              onCancel: () async {
                                final confirmed = await StandardDialog.show<bool>(
                                  context: context,
                                  title: 'reminder_cancel_title',
                                  content: 'reminder_cancel_body',
                                  confirmText: 'reminder_cancel_confirm',
                                  cancelText: 'reminder_no',
                                  isDestructive: true,
                                );
                                if (confirmed == true && mounted) {
                                  await ref.read(reminderProvider.notifier).cancel(reminder.id);
                                }
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }



  Widget _buildFilterChip(int index, String labelKey, bool isDark) {
    final isSelected = _historyFilterIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _historyFilterIndex = index),
      child: Container(
        margin: EdgeInsets.only(right: 8.w),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF97316)
              : (isDark ? const Color(0xFF2A2A3C) : const Color(0xFFF3F4F6)),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF97316)
                : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
          ),
        ),
        child: Center(
          child: Text(
            labelKey.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12.sp,
              color: isSelected ? Colors.white : AppColors.textMutedLight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegment(int index, String labelKey, bool isDark) {
    final isSelected = _targetAudienceIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _targetAudienceIndex = index),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13.sp,
              color: isSelected
                  ? (isDark ? Colors.white : const Color(0xFF1A1A4E))
                  : AppColors.textMutedLight,
            ),
            child: Text(labelKey.tr()),
          ),
        ),
      ),
    );
  }
}

