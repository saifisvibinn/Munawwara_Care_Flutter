import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../models/reminder_model.dart';
import '../providers/moderator_provider.dart';
import '../providers/reminder_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Reminders Screen
// Launched from the pilgrim detail bottom sheet in GroupManagementScreen.
// Shows all reminders for the group (optionally pre-filtered to one pilgrim).
// ─────────────────────────────────────────────────────────────────────────────

class RemindersScreen extends ConsumerStatefulWidget {
  final String groupId;
  final List<PilgrimInGroup> pilgrims;
  // When opened from a specific pilgrim card, these are pre-filled
  final String? defaultPilgrimId;
  final String? defaultPilgrimName;

  const RemindersScreen({
    super.key,
    required this.groupId,
    this.pilgrims = const [],
    this.defaultPilgrimId,
    this.defaultPilgrimName,
  });

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(reminderProvider.notifier).load(widget.groupId);
    });
    // Refresh every 30 s so status/fires_sent stay up-to-date
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.read(reminderProvider.notifier).load(widget.groupId);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ── Create reminder sheet ───────────────────────────────────────────────

  void _openCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateReminderSheet(
        groupId: widget.groupId,
        pilgrims: widget.pilgrims,
        defaultPilgrimId: widget.defaultPilgrimId,
        defaultPilgrimName: widget.defaultPilgrimName,
      ),
    );
  }

  // ── Cancel confirmation ─────────────────────────────────────────────────

  Future<void> _confirmCancel(ReminderModel r) async {
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
      await ref.read(reminderProvider.notifier).cancel(r.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = ref.watch(reminderProvider);

    // Filter to this pilgrim if opened from a pilgrim card
    final reminders = widget.defaultPilgrimId != null
        ? rs.reminders
              .where(
                (r) =>
                    r.targetType == 'pilgrim' &&
                    r.pilgrimId == widget.defaultPilgrimId,
              )
              .toList()
        : rs.reminders;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          widget.defaultPilgrimName != null
              ? 'reminder_screen_title_for'.tr(
                  namedArgs: {'name': widget.defaultPilgrimName!},
                )
              : 'reminder_screen_title'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 16.sp,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Symbols.refresh),
            tooltip: 'reminder_refresh'.tr(),
            onPressed: () =>
                ref.read(reminderProvider.notifier).load(widget.groupId),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateSheet,
        backgroundColor: AppColors.primary,
        icon: const Icon(Symbols.add_alarm, color: Colors.white),
        label: Text(
          'reminder_new'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: 13.sp,
          ),
        ),
      ),
      body: rs.isLoading && reminders.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : reminders.isEmpty
          ? const _EmptyState()
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(reminderProvider.notifier).load(widget.groupId),
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 100.h),
                itemCount: reminders.length,
                itemBuilder: (_, i) {
                  final reminder = reminders[i];
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
                    child: _ReminderCard(
                      reminder: reminder,
                      onCancel: () => _confirmCancel(reminder),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reminder Card
// ─────────────────────────────────────────────────────────────────────────────

class _ReminderCard extends StatelessWidget {
  final ReminderModel reminder;
  final VoidCallback onCancel;

  const _ReminderCard({required this.reminder, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _statusColor(reminder.status);
    final timeStr = DateFormat(
      'dd MMM yyyy  HH:mm',
    ).format(reminder.scheduledAt.toLocal());

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border(left: BorderSide(color: statusColor, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status badge + time
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  'reminder_status_${reminder.status}'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Symbols.schedule, size: 14.sp, color: Colors.grey),
              SizedBox(width: 4.w),
              Text(
                timeStr,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 11.sp,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),

          // Reminder text
          Text(
            reminder.text,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textLight : AppColors.textDark,
            ),
          ),
          SizedBox(height: 8.h),

          // Target + repeat info
          Row(
            children: [
              Icon(
                reminder.targetType == 'pilgrim'
                    ? Symbols.person
                    : Symbols.group,
                size: 14.sp,
                color: AppColors.primary,
              ),
              SizedBox(width: 4.w),
              Text(
                reminder.targetType == 'pilgrim'
                    ? (reminder.pilgrimName ?? 'reminder_target_pilgrim'.tr())
                    : 'reminder_target_group'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12.sp,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(width: 16.w),
              Icon(Symbols.repeat, size: 14.sp, color: Colors.grey),
              SizedBox(width: 4.w),
              Text(
                'reminder_fires_sent'.tr(
                      namedArgs: {
                        'sent': '${reminder.firesSent}',
                        'total': '${reminder.repeatCount}',
                      },
                    ) +
                    (reminder.repeatCount > 1
                        ? '  ·  ${'reminder_interval_every'.tr(namedArgs: {'interval': _formatInterval(reminder.repeatIntervalMin)})}'
                        : ''),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12.sp,
                  color: Colors.grey,
                ),
              ),
            ],
          ),

          // Cancel button (only for active reminders)
          if (reminder.isActive) ...[
            SizedBox(height: 10.h),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: Icon(
                  Symbols.cancel,
                  size: 16.sp,
                  color: Colors.redAccent,
                ),
                label: Text(
                  'area_cancel'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    color: Colors.redAccent,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.w,
                    vertical: 4.h,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.blueAccent;
      case 'active':
        return AppColors.primary;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _formatInterval(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.add_alarm, size: 64.sp, color: Colors.grey.shade400),
          SizedBox(height: 16.h),
          Text(
            'reminder_empty_title'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'reminder_empty_sub'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Reminder Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _CreateReminderSheet extends ConsumerStatefulWidget {
  final String groupId;
  final List<PilgrimInGroup> pilgrims;
  final String? defaultPilgrimId;
  final String? defaultPilgrimName;

  const _CreateReminderSheet({
    required this.groupId,
    this.pilgrims = const [],
    this.defaultPilgrimId,
    this.defaultPilgrimName,
  });

  @override
  ConsumerState<_CreateReminderSheet> createState() =>
      _CreateReminderSheetState();
}

class _CreateReminderSheetState extends ConsumerState<_CreateReminderSheet> {
  final _textController = TextEditingController();
  final _customIntervalController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  DateTime? _scheduledAt;
  int _repeatCount = 1;
  int? _selectedIntervalMin; // null = custom
  bool _isCustomInterval = false;
  bool _isSaving = false;
  String? _selectedPilgrimId;
  String? _selectedPilgrimName;

  // If opened from a pilgrim card, target is always 'pilgrim'.
  // Otherwise moderator can choose.
  late String _targetType;

  static const _intervalPresets = [
    (label: '5 min', value: 5),
    (label: '15 min', value: 15),
    (label: '30 min', value: 30),
    (label: '1 hr', value: 60),
    (label: '2 hr', value: 120),
  ];

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    _targetType = widget.defaultPilgrimId != null ? 'pilgrim' : 'group';
    _selectedIntervalMin = 15;
  }

  @override
  void dispose() {
    _textController.dispose();
    _customIntervalController.dispose();
    super.dispose();
  }

  // ── Date + time picker ──────────────────────────────────────────────────

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(minutes: 5)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            brightness: Theme.of(ctx).brightness,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))),
    );
    if (time == null || !mounted) return;

    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  // ── Save ────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_scheduledAt == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('reminder_date_required'.tr())));
      return;
    }
    if (_scheduledAt!.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('reminder_date_future'.tr())));
      return;
    }

    final intervalMin = _isCustomInterval
        ? int.tryParse(_customIntervalController.text.trim()) ?? 15
        : (_selectedIntervalMin ?? 15);

    setState(() => _isSaving = true);
    final ok = await ref
        .read(reminderProvider.notifier)
        .create(
          groupId: widget.groupId,
          targetType: _targetType,
          pilgrimId: _targetType == 'pilgrim'
              ? (widget.defaultPilgrimId ?? _selectedPilgrimId)
              : null,
          text: _textController.text.trim(),
          scheduledAt: _scheduledAt!,
          repeatCount: _repeatCount,
          repeatIntervalMin: intervalMin,
        );
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('reminder_create_failed'.tr())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 32.h),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40.w,
                    height: 4.h,
                    margin: EdgeInsets.only(bottom: 16.h),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                  ),
                ),

                Text(
                  'reminder_new'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 18.sp,
                    color: isDark ? AppColors.textLight : AppColors.textDark,
                  ),
                ),
                SizedBox(height: 20.h),

                // ── Target (only shown when NOT launched from a specific pilgrim) ──
                if (widget.defaultPilgrimId == null) ...[
                  _Label('reminder_send_to'.tr()),
                  SizedBox(height: 8.h),
                  Row(
                    children: [
                      _TargetChip(
                        label: 'reminder_target_pilgrim'.tr(),
                        icon: Symbols.person,
                        selected: _targetType == 'pilgrim',
                        onTap: () => setState(() => _targetType = 'pilgrim'),
                      ),
                      SizedBox(width: 10.w),
                      _TargetChip(
                        label: 'reminder_target_group'.tr(),
                        icon: Symbols.group,
                        selected: _targetType == 'group',
                        onTap: () => setState(() => _targetType = 'group'),
                      ),
                    ],
                  ),
                  if (_targetType == 'pilgrim' &&
                      widget.pilgrims.isNotEmpty) ...[
                    SizedBox(height: 8.h),
                    DropdownButtonFormField<String>(
                      value: _selectedPilgrimId,
                      decoration: _inputDecoration(
                        'reminder_select_pilgrim'.tr(),
                      ),
                      isExpanded: true,
                      items: widget.pilgrims
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(
                                p.fullName,
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 14.sp,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (id) {
                        setState(() {
                          _selectedPilgrimId = id;
                          _selectedPilgrimName = widget.pilgrims
                              .firstWhere((p) => p.id == id)
                              .fullName;
                        });
                      },
                      validator: (_) {
                        if (_targetType == 'pilgrim' &&
                            widget.defaultPilgrimId == null &&
                            _selectedPilgrimId == null) {
                          return 'reminder_pilgrim_required'.tr();
                        }
                        return null;
                      },
                    ),
                  ] else if (_targetType == 'pilgrim' &&
                      widget.pilgrims.isEmpty) ...[
                    SizedBox(height: 8.h),
                    Container(
                      padding: EdgeInsets.all(10.w),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        'reminder_no_pilgrims'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.sp,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: 16.h),
                ] else ...[
                  // Show who the reminder is for
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 8.h,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Symbols.person,
                          color: AppColors.primary,
                          size: 18.sp,
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          widget.defaultPilgrimName ?? 'reminder_pilgrim'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            fontSize: 14.sp,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16.h),
                ],

                // ── Reminder text ────────────────────────────────────────────
                _Label('reminder_text_label'.tr()),
                SizedBox(height: 8.h),
                TextFormField(
                  controller: _textController,
                  maxLines: 3,
                  maxLength: 500,
                  style: TextStyle(fontFamily: 'Lexend', fontSize: 14.sp),
                  decoration: _inputDecoration('reminder_text_hint'.tr()),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'reminder_text_error'.tr()
                      : null,
                ),
                SizedBox(height: 16.h),

                // ── Scheduled time ───────────────────────────────────────────
                _Label('reminder_when_label'.tr()),
                SizedBox(height: 8.h),
                GestureDetector(
                  onTap: _pickDateTime,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14.w,
                      vertical: 14.h,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _scheduledAt != null
                            ? AppColors.primary
                            : Colors.grey.shade400,
                      ),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Symbols.calendar_month,
                          color: _scheduledAt != null
                              ? AppColors.primary
                              : Colors.grey,
                          size: 20.sp,
                        ),
                        SizedBox(width: 10.w),
                        Text(
                          _scheduledAt != null
                              ? DateFormat(
                                  'dd MMM yyyy  HH:mm',
                                ).format(_scheduledAt!)
                              : 'reminder_pick_datetime'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14.sp,
                            color: _scheduledAt != null
                                ? (isDark
                                      ? AppColors.textLight
                                      : AppColors.textDark)
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16.h),

                // ── Repeat count ─────────────────────────────────────────────
                _Label('reminder_repeat_label'.tr()),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Symbols.remove_circle_outline),
                      color: AppColors.primary,
                      onPressed: _repeatCount > 1
                          ? () => setState(() => _repeatCount--)
                          : null,
                    ),
                    SizedBox(width: 4.w),
                    Container(
                      width: 48.w,
                      alignment: Alignment.center,
                      child: Text(
                        '$_repeatCount',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 20.sp,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    SizedBox(width: 4.w),
                    IconButton(
                      icon: const Icon(Symbols.add_circle_outline),
                      color: AppColors.primary,
                      onPressed: _repeatCount < 20
                          ? () => setState(() => _repeatCount++)
                          : null,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      _repeatCount == 1
                          ? 'reminder_once'.tr()
                          : 'reminder_times'.tr(
                              namedArgs: {'count': '$_repeatCount'},
                            ),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13.sp,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16.h),

                // ── Interval (shown only when repeat > 1) ───────────────────
                if (_repeatCount > 1) ...[
                  _Label('reminder_interval_label'.tr()),
                  SizedBox(height: 8.h),
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 8.h,
                    children: [
                      ..._intervalPresets.map(
                        (p) => _IntervalChip(
                          label: p.label,
                          selected:
                              !_isCustomInterval &&
                              _selectedIntervalMin == p.value,
                          onTap: () => setState(() {
                            _isCustomInterval = false;
                            _selectedIntervalMin = p.value;
                          }),
                        ),
                      ),
                      _IntervalChip(
                        label: 'reminder_interval_other'.tr(),
                        selected: _isCustomInterval,
                        onTap: () => setState(() {
                          _isCustomInterval = true;
                          _selectedIntervalMin = null;
                        }),
                      ),
                    ],
                  ),
                  if (_isCustomInterval) ...[
                    SizedBox(height: 10.h),
                    TextFormField(
                      controller: _customIntervalController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: TextStyle(fontFamily: 'Lexend', fontSize: 14.sp),
                      decoration: _inputDecoration(
                        'reminder_interval_hint'.tr(),
                      ),
                      validator: (v) {
                        if (!_isCustomInterval) return null;
                        final n = int.tryParse(v?.trim() ?? '');
                        if (n == null || n < 1)
                          return 'reminder_interval_error'.tr();
                        return null;
                      },
                    ),
                  ],
                  SizedBox(height: 16.h),
                ],

                // ── Save button ──────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 50.h,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            'reminder_set_btn'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w600,
                              fontSize: 15.sp,
                              color: Colors.white,
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

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      fontFamily: 'Lexend',
      fontSize: 13.sp,
      color: Colors.grey,
    ),
    filled: true,
    fillColor: isDark
        ? Colors.white.withOpacity(0.05)
        : Colors.grey.withOpacity(0.07),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10.r),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10.r),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10.r),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10.r),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
    ),
    contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Lexend',
        fontWeight: FontWeight.w600,
        fontSize: 13.sp,
        color: isDark ? AppColors.textLight : AppColors.textDark,
      ),
    );
  }
}

class _TargetChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TargetChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16.sp,
              color: selected ? Colors.white : AppColors.primary,
            ),
            SizedBox(width: 6.w),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntervalChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _IntervalChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 7.h),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.primary,
          ),
        ),
      ),
    );
  }
}
