import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../core/widgets/custom_dialog.dart';
import '../../../core/widgets/standard_snackbar.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dropdown_theme.dart';
import '../../../core/widgets/glass/app_glass.dart';
import '../providers/moderator_provider.dart';
import '../providers/reminder_provider.dart';
import '../widgets/reminder_card.dart';
import 'dart:async';

class SystemRemindersScreen extends ConsumerStatefulWidget {
  const SystemRemindersScreen({super.key, this.isTabActive = true});

  final bool isTabActive;

  @override
  ConsumerState<SystemRemindersScreen> createState() =>
      _SystemRemindersScreenState();
}

class _SystemRemindersScreenState extends ConsumerState<SystemRemindersScreen>
    with SingleTickerProviderStateMixin {
  Timer? _refreshTimer;
  late final TabController _audienceTabController;

  @override
  void initState() {
    super.initState();
    _audienceTabController = TabController(length: 2, vsync: this);
    _audienceTabController.addListener(_onAudienceTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncPilgrimAudienceWithGroups(ref.read(moderatorProvider).groups);
      if (widget.isTabActive) {
        ref.read(reminderProvider.notifier).load();
      }
    });
    _syncRefreshTimer();
  }

  @override
  void didUpdateWidget(covariant SystemRemindersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isTabActive != widget.isTabActive) {
      _syncRefreshTimer();
      if (widget.isTabActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(reminderProvider.notifier).load();
          }
        });
      }
    }
  }

  void _syncRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (!widget.isTabActive) {
      return;
    }
    final interval = kReleaseMode
        ? const Duration(minutes: 2)
        : const Duration(seconds: 30);
    _refreshTimer = Timer.periodic(interval, (_) {
      if (mounted && widget.isTabActive) {
        ref.read(reminderProvider.notifier).load();
      }
    });
  }

  void _onAudienceTabChanged() {
    if (!mounted) return;
    final i = _audienceTabController.index;
    if (i == _targetAudienceIndex) return;
    setState(() => _targetAudienceIndex = i);
  }

  int _targetAudienceIndex = 0; // 0 = Specific Groups, 1 = Specific Pilgrim
  int _historyFilterIndex = 0; // 0 = All, 1 = Groups, 2 = Pilgrim
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
    _audienceTabController.removeListener(_onAudienceTabChanged);
    _audienceTabController.dispose();
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



    // Determine target groups and type
    List<String> targetGroups = [];
    String targetType = 'group';

    if (_targetAudienceIndex == 0) {
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

    final sched = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _startTime.hour,
      _startTime.minute,
    );
    final minSched = DateTime.now().add(const Duration(minutes: 1));
    if (!sched.isAfter(minSched)) {
      StandardSnackBar.showWarning(context, 'reminder_date_future'.tr());
      return;
    }

    setState(() => _isCreating = true);

    int intervalMin = _isCustomInterval ? 15 : (_selectedIntervalMin ?? 15);
    int count = _repeatCount;

    final weeklyList =
        _weeklyDays.isEmpty ? null : (List<int>.from(_weeklyDays)..sort());

    final success = await ref
        .read(reminderProvider.notifier)
        .create(
          groupIds: targetGroups,
          targetType: targetType,
          pilgrimId: _targetAudienceIndex == 1 ? _selectedPilgrimId : null,
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
      if (_audienceTabController.index != 0) {
        _audienceTabController.index = 0;
      }
    } else {
      final err = ref.read(reminderProvider).error;
      StandardSnackBar.showError(
        context,
        err ?? 'reminder_create_partial_fail'.tr(),
      );
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

    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final outline = isDark ? AppColors.dividerDark : AppColors.dividerLight;

    return AppDashboardBackground(
      isDark: isDark,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20.w,
            12.h,
            20.w,
            AppGlassTheme.bottomNavScrollPadding(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Symbols.notifications_active_rounded,
                    color: AppColors.primary,
                    size: 30.sp,
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'reminder_schedule_page_title'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w800,
                            fontSize: 22.sp,
                            height: 1.1,
                            color: textPrimary,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'reminder_schedule_page_subtitle'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12.5.sp,
                            height: 1.35,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20.h),

              AppGlassCard(
                isDark: isDark,
                padding: EdgeInsets.fromLTRB(18.w, 18.h, 18.w, 16.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'reminder_target_audience'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 12.sp,
                        color: textMuted,
                      ),
                    ),
                    SizedBox(height: 6.h),
                    Material(
                      color: Colors.transparent,
                      child: TabBar(
                          controller: _audienceTabController,
                          isScrollable: false,
                          labelPadding: EdgeInsets.symmetric(horizontal: 10.w),
                          dividerHeight: 0,
                          indicatorSize: TabBarIndicatorSize.label,
                          indicatorWeight: 3,
                          indicatorColor: AppColors.primary,
                          labelColor: AppColors.primary,
                          unselectedLabelColor: textMuted,
                          labelStyle: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w800,
                            fontSize: 15.sp,
                          ),
                          unselectedLabelStyle: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            fontSize: 15.sp,
                          ),
                          tabs: [
                            Tab(text: 'reminder_audience_groups_tab'.tr()),
                            Tab(text: 'reminder_audience_pilgrim_tab'.tr()),
                          ],
                        ),
                      ),
                      if (_targetAudienceIndex == 0) ...[
                        Divider(height: 24.h, thickness: 1, color: outline),
                        Text(
                          'reminder_select_recipient_groups'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 13.sp,
                            color: textPrimary,
                          ),
                        ),
                        SizedBox(height: 10.h),
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
                            horizontal: 14.w,
                            vertical: 12.h,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : outline.withValues(alpha: 0.75),
                              width: isSelected ? 1.5 : 1,
                            ),
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.07)
                                : Colors.transparent,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Symbols.groups,
                                color: isSelected
                                    ? AppColors.primary
                                    : textMuted,
                                size: 20.sp,
                               ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Text(
                                  g.groupName,
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14.sp,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                              Icon(
                                isSelected
                                    ? Symbols.check_circle
                                    : Symbols.radio_button_unchecked,
                                color: isSelected
                                    ? AppColors.primary
                                    : textMuted,
                                size: 22.sp,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                      ],
                      if (_targetAudienceIndex == 1) ...[
                        Divider(height: 24.h, thickness: 1, color: outline),
                        Text(
                          'reminder_select_pilgrim_section'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 13.sp,
                            color: textPrimary,
                          ),
                        ),
                        SizedBox(height: 10.h),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('system_reminder_specific_group'),
                      initialValue: _selectedGroupIdForPilgrim != null &&
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
                            initialValue: validPilgrimId,
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
                      Divider(height: 24.h, thickness: 1, color: outline),
                      Row(
                        children: [
                          Icon(
                            Symbols.chat_bubble,
                            color: AppColors.primary,
                            size: 20.sp,
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              'reminder_message_short_title'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w700,
                                fontSize: 13.sp,
                                color: textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      Container(
                        height: 100.h,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1A2230)
                              : AppColors.iconBgLight.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: outline.withValues(alpha: 0.65),
                          ),
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
                            color: textPrimary,
                          ),
                          decoration: InputDecoration(
                            filled: false,
                            hintText: 'reminder_text_hint'.tr(),
                            hintStyle: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w500,
                              color: textMuted.withValues(alpha: 0.9),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(
                                color: AppColors.primary.withValues(alpha: 0.45),
                                width: 1.5,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: EdgeInsets.all(14.w),
                          ),
                        ),
                      ),
                      Divider(height: 24.h, thickness: 1, color: outline),
                      Row(
                        children: [
                          Icon(
                            Symbols.schedule,
                            color: AppColors.primary,
                            size: 20.sp,
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              'reminder_scheduling_section'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w700,
                                fontSize: 13.sp,
                                color: textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),
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
                                fontSize: 11.sp,
                                color: textMuted,
                              ),
                            ),
                            SizedBox(height: 6.h),
                            GestureDetector(
                              onTap: _onSelectDate,
                              child: Container(
                                height: 48.h,
                                padding: EdgeInsets.symmetric(horizontal: 12.w),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1A2230)
                                      : AppColors.iconBgLight.withValues(
                                          alpha: 0.65,
                                        ),
                                  borderRadius: BorderRadius.circular(12.r),
                                  border: Border.all(
                                    color: outline.withValues(alpha: 0.65),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Symbols.calendar_today,
                                      size: 18.sp,
                                      color: AppColors.primary,
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
                                          fontWeight: FontWeight.w600,
                                          color: textPrimary,
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
                                fontSize: 11.sp,
                                color: textMuted,
                              ),
                            ),
                            SizedBox(height: 6.h),
                            GestureDetector(
                              onTap: _onSelectTime,
                              child: Container(
                                height: 48.h,
                                padding: EdgeInsets.symmetric(horizontal: 12.w),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1A2230)
                                      : AppColors.iconBgLight.withValues(
                                          alpha: 0.65,
                                        ),
                                  borderRadius: BorderRadius.circular(12.r),
                                  border: Border.all(
                                    color: outline.withValues(alpha: 0.65),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Symbols.schedule,
                                      size: 18.sp,
                                      color: AppColors.primary,
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
                                          fontWeight: FontWeight.w600,
                                          color: textPrimary,
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
                      fontWeight: FontWeight.w700,
                      fontSize: 13.sp,
                      color: textPrimary,
                    ),
                  ),
                  SizedBox(height: 10.h),
                  _WeekdayPickerStrip(
                    isDark: isDark,
                    textPrimary: textPrimary,
                    outline: outline,
                    selectedDays: _weeklyDays,
                    onDayTapped: (d) {
                      setState(() {
                        if (_weeklyDays.contains(d)) {
                          _weeklyDays.remove(d);
                        } else {
                          _weeklyDays.add(d);
                        }
                      });
                    },
                  ),
                  SizedBox(height: 18.h),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          'reminder_repeat_count'.tr(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            fontSize: 13.sp,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () {
                              if (_repeatCount > 1) {
                                setState(() {
                                  _repeatCount--;
                                  if (_repeatCount == 1) {
                                    _selectedIntervalMin = null;
                                    _isCustomInterval = false;
                                  }
                                });
                              }
                            },
                            icon: Icon(
                              Icons.remove_circle_outline,
                              color: textMuted,
                            ),
                          ),
                          Text(
                            '$_repeatCount',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w800,
                              fontSize: 16.sp,
                              color: textPrimary,
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
                            icon: Icon(
                              Icons.add_circle_outline,
                              color: AppColors.primary,
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
                        fontSize: 13.sp,
                        color: textPrimary,
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
                              color: isSelected ? Colors.white : textPrimary,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: AppColors.primary,
                          backgroundColor: isDark
                              ? const Color(0xFF1A2230)
                              : AppColors.iconBgLight.withValues(alpha: 0.65),
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
            SizedBox(height: 16.h),

            // CREATE BUTTON
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isCreating ? null : _createReminders,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: Size(double.infinity, 52.h),
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.r),
                  ),
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
                    : Icon(Symbols.add_alert, size: 22.sp),
                label: Text(
                  _isCreating ? 'reminder_creating'.tr() : 'reminder_create_btn'.tr(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 15.sp,
                  ),
                ),
              ),
            ),
            
            SizedBox(height: 36.h),
            Row(
              children: [
                Icon(
                  Symbols.history,
                  color: AppColors.primary,
                  size: 24.sp,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    'reminder_history_section'.tr(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w800,
                      fontSize: 20.sp,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 14.h),
            
            // HISTORY FILTER
            Container(
              height: 38.h,
              margin: EdgeInsets.only(bottom: 16.h),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip(0, 'reminder_hist_all', isDark),
                  _buildFilterChip(1, 'reminder_hist_groups', isDark),
                  _buildFilterChip(2, 'reminder_hist_pilgrim', isDark),
                ],
              ),
            ),
            
            remState.isLoading && remState.reminders.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Builder(
                    builder: (context) {
                      final filtered = remState.reminders.where((r) {
                        if (_historyFilterIndex == 0) return true;
                        if (_historyFilterIndex == 1) {
                          return r.targetType == 'group' ||
                              r.targetType == 'all_groups';
                        }
                        if (_historyFilterIndex == 2) return r.targetType == 'pilgrim';
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
                              color: textMuted,
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
    ),
    );
  }

  Widget _buildFilterChip(int index, String labelKey, bool isDark) {
    final isSelected = _historyFilterIndex == index;
    final outline = isDark ? AppColors.dividerDark : AppColors.dividerLight;
    final textMutedChip =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    return GestureDetector(
      onTap: () => setState(() => _historyFilterIndex = index),
      child: Container(
        margin: EdgeInsets.only(right: 8.w),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (isDark
                  ? const Color(0xFF1A2230)
                  : AppColors.iconBgLight.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : (isDark
                    ? outline.withValues(alpha: 0.5)
                    : outline.withValues(alpha: 0.55)),
          ),
        ),
        child: Center(
          child: Text(
            labelKey.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12.sp,
              color: isSelected ? Colors.white : textMutedChip,
            ),
          ),
        ),
      ),
    );
  }

}

/// Single-line weekday toggles (Mon–Sun). Uses [FittedBox] so all seven fit on
/// narrow phones without wrapping.
class _WeekdayPickerStrip extends StatelessWidget {
  final bool isDark;
  final Color textPrimary;
  final Color outline;
  final Set<int> selectedDays;
  final ValueChanged<int> onDayTapped;

  const _WeekdayPickerStrip({
    required this.isDark,
    required this.textPrimary,
    required this.outline,
    required this.selectedDays,
    required this.onDayTapped,
  });

  @override
  Widget build(BuildContext context) {
    final baseBg = isDark
        ? const Color(0xFF1A2230)
        : AppColors.iconBgLight.withValues(alpha: 0.65);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A2230).withValues(alpha: 0.55)
            : AppColors.iconBgLight.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: outline.withValues(alpha: 0.45),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: SizedBox(
              width: c.maxWidth,
              child: Row(
                children: List.generate(7, (i) {
                  final d = i + 1;
                  final selected = selectedDays.contains(d);
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: i == 0 ? 0 : 3.w,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(11.r),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => onDayTapped(d),
                          borderRadius: BorderRadius.circular(11.r),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.center,
                            height: 42.h,
                            decoration: BoxDecoration(
                              color: selected ? AppColors.primary : baseBg,
                              borderRadius: BorderRadius.circular(11.r),
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary
                                    : outline.withValues(alpha: 0.55),
                                width: selected ? 1.5 : 1,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.22),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              'reminder_weekday_short_$d'.tr(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 12.sp,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color:
                                    selected ? Colors.white : textPrimary,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          );
        },
      ),
    );
  }
}

