import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
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
      ref.read(reminderProvider.notifier).load();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.read(reminderProvider.notifier).load();
    });
  }

  int _targetAudienceIndex = 0; // 0 = System Wide, 1 = Specific Groups
  final Set<String> _selectedGroupIds = {};

  final _messageController = TextEditingController();
  DateTime _startDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  int _repeatCount = 1;
  int? _selectedIntervalMin; // null = custom
  bool _isCustomInterval = false;
  
  final List<Map<String, dynamic>> _intervalOptions = [
    {'label': '1 m', 'value': 1},
    {'label': '5 m', 'value': 5},
    {'label': '30 m', 'value': 30},
    {'label': '1 hr', 'value': 60},
    {'label': '6 hr', 'value': 360},
    {'label': '12 hr', 'value': 720},
    {'label': '1 d', 'value': 1440},
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
    if (picked != null) setState(() => _startDate = picked);
  }

  void _onSelectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _createReminders() async {
    final msg = _messageController.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a reminder message')),
      );
      return;
    }

    final state = ref.read(moderatorProvider);
    final allGroups = state.groups;
    final remState = ref.watch(reminderProvider);

    // Determine target groups
    List<String> targetGroups = [];
    if (_targetAudienceIndex == 0) {
      targetGroups = allGroups.map((g) => g.id).toList();
    } else {
      targetGroups = _selectedGroupIds.toList();
    }

    if (targetGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No groups selected to send reminder to')),
      );
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

    bool success = true;
    for (String groupId in targetGroups) {
      final ok = await ref
          .read(reminderProvider.notifier)
          .create(
            groupId: groupId,
            targetType: 'group',
            text: msg,
            scheduledAt: sched,
            repeatCount: count,
            repeatIntervalMin: intervalMin,
          );
      if (!ok) success = false;
    }

    setState(() => _isCreating = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminders created successfully!')),
      );
      _messageController.clear();
      _selectedGroupIds.clear();
      setState(() {
        _targetAudienceIndex = 0;
        _repeatCount = 1;
        _selectedIntervalMin = null;
        _isCustomInterval = false;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Some reminders failed to create')),
      );
    }
  }

  Widget _intervalChip(int min, String label) {
    final sel = !_isCustomInterval && _selectedIntervalMin == min;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
          fontSize: 12.sp,
          color: sel ? Colors.white : AppColors.primary,
        ),
      ),
      selected: sel,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.primary.withOpacity(0.1),
      side: BorderSide.none,
      onSelected: (v) {
        if (v) {
          setState(() {
            _isCustomInterval = false;
            _selectedIntervalMin = min;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(moderatorProvider);
    final allGroups = state.groups;
    final remState = ref.watch(reminderProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 100.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reminders',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w800,
                fontSize: 28.sp,
                color: isDark ? Colors.white : const Color(0xFF1A1A4E),
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Schedule group reminders for coordinated care activities.',
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
                    'TARGET AUDIENCE',
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
                    height: 48.h,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2A2A3C)
                          : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(24.r),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _targetAudienceIndex = 0),
                            child: Container(
                              margin: EdgeInsets.all(4.w),
                              decoration: BoxDecoration(
                                color: _targetAudienceIndex == 0
                                    ? (isDark
                                          ? AppColors.surfaceDark
                                          : Colors.white)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20.r),
                                boxShadow: _targetAudienceIndex == 0
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.05,
                                          ),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'System Wide',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.sp,
                                  color: _targetAudienceIndex == 0
                                      ? (isDark
                                            ? Colors.white
                                            : const Color(0xFF3B1010))
                                      : AppColors.textMutedLight,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _targetAudienceIndex = 1),
                            child: Container(
                              margin: EdgeInsets.all(4.w),
                              decoration: BoxDecoration(
                                color: _targetAudienceIndex == 1
                                    ? (isDark
                                          ? AppColors.surfaceDark
                                          : Colors.white)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20.r),
                                boxShadow: _targetAudienceIndex == 1
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.05,
                                          ),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Specific Groups',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.sp,
                                  color: _targetAudienceIndex == 1
                                      ? (isDark
                                            ? Colors.white
                                            : const Color(0xFF3B1010))
                                      : AppColors.textMutedLight,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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
                      'Select Recipient Groups',
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
                          'Browse more groups',
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
                    'Reminder Message',
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
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 14.sp,
                        color: isDark ? Colors.white : const Color(0xFF1A1A4E),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter care reminder details here...',
                        hintStyle: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 14.sp,
                          color: AppColors.textMutedLight,
                        ),
                        border: InputBorder.none,
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
                    'Scheduling Options',
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
                              'START DATE',
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
                              'START TIME',
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
// REPEAT SETTINGS
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Repeat Count',
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
                                setState(() => _repeatCount--);
                              }
                            },
                            icon: Icon(
                              Icons.remove_circle_outline,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          Text(
                            '',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w700,
                              fontSize: 16.sp,
                              color: isDark ? Colors.white : const Color(0xFF1A1A4E),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() => _repeatCount++);
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
                  SizedBox(height: 20.h),
                  Text(
                    'Interval',
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
                          opt['label'],
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
                  _isCreating ? 'Creating...' : 'Create Reminder',
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
              'History',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 20.sp,
                color: isDark ? Colors.white : const Color(0xFF1A1A4E),
              ),
            ),
            SizedBox(height: 16.h),
            
            remState.isLoading && remState.reminders.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : remState.reminders.isEmpty
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 32.h),
                          child: Text(
                            'No reminders created yet.',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              color: AppColors.textMutedLight,
                              fontSize: 14.sp,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: remState.reminders.length,
                        itemBuilder: (_, i) {
                          final reminder = remState.reminders[i];
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
                              return showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(
                                    'reminder_delete_title'.tr(),
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 16.sp,
                                    ),
                                  ),
                                  content: Text(
                                    'reminder_delete_body'.tr(),
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 14.sp,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: Text(
                                        'reminder_no'.tr(),
                                        style: const TextStyle(fontFamily: 'Lexend'),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: Text(
                                        'reminder_delete_confirm'.tr(),
                                        style: const TextStyle(
                                          fontFamily: 'Lexend',
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            onDismissed: (_) =>
                                ref.read(reminderProvider.notifier).delete(reminder.id),
                            child: ReminderCard(
                              reminder: reminder,
                              onCancel: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(
                                      'reminder_cancel_title'.tr(),
                                      style: TextStyle(fontFamily: 'Lexend', fontSize: 16.sp),
                                    ),
                                    content: Text(
                                      'reminder_cancel_body'.tr(),
                                      style: TextStyle(fontFamily: 'Lexend', fontSize: 14.sp),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: Text(
                                          'reminder_no'.tr(),
                                          style: const TextStyle(fontFamily: 'Lexend'),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: Text(
                                          'reminder_cancel_confirm'.tr(),
                                          style: const TextStyle(
                                            fontFamily: 'Lexend',
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && mounted) {
                                  await ref.read(reminderProvider.notifier).cancel(reminder.id);
                                }
                              },
                            ),
                          );
                        },
                      ),
          ],
        ),
      ),
    );
  }
}

