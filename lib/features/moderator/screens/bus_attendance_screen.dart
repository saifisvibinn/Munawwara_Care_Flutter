import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gal/gal.dart';

import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_dialog.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../shared/widgets/pilgrim_gender_avatar.dart';
import '../providers/bus_attendance_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Bus / Trip Attendance Screen — Moderator-facing
// ─────────────────────────────────────────────────────────────────────────────

class BusAttendanceScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;
  final String? pastSessionId;

  const BusAttendanceScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    this.pastSessionId,
  });

  @override
  ConsumerState<BusAttendanceScreen> createState() =>
      _BusAttendanceScreenState();
}

class _BusAttendanceScreenState extends ConsumerState<BusAttendanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _busController;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  bool _showAllHistory = false;

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _busController = TextEditingController(text: 'Trip - $today');

    if (widget.pastSessionId == null) {
      // Listen for real-time boarding updates
      SocketService.on('bus_boarding_update', _onBoardingUpdate);
    }

    // Load active/created session or past session details
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    if (widget.pastSessionId == null) {
      SocketService.off('bus_boarding_update');
    }
    _elapsedTimer?.cancel();
    _tabController.dispose();
    _busController.dispose();
    ref.read(busAttendanceProvider.notifier).reset();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (widget.pastSessionId != null) {
      await ref
          .read(busAttendanceProvider.notifier)
          .fetchSessionDetails(widget.groupId, widget.pastSessionId!);
      if (!mounted) return;

      final session = ref.read(busAttendanceProvider).session;
      if (session != null && session.startedAt != null && session.completedAt != null) {
        setState(() {
          _elapsed = session.completedAt!.difference(session.startedAt!);
        });
      }
    } else {
      await _checkOrStartSession();
      if (!mounted) return;
      await ref
          .read(busAttendanceProvider.notifier)
          .fetchHistory(widget.groupId);
    }
  }

  // ── Session management ──────────────────────────────────────────────────

  Future<void> _checkOrStartSession() async {
    // First try to fetch existing status
    await ref.read(busAttendanceProvider.notifier).fetchStatus(widget.groupId);
    if (!mounted) return;

    final st = ref.read(busAttendanceProvider);
    if (st.hasActiveSession) {
      // Resume existing session — if we don't have QR data, re-start to get it
      if (st.qrImageBase64 == null || st.qrImageBase64!.isEmpty) {
        await ref.read(busAttendanceProvider.notifier).startSession(widget.groupId);
      }
      _startElapsedTimer();
    }
  }

  void _startElapsedTimer() {
    final session = ref.read(busAttendanceProvider).session;
    if (session == null || session.startedAt == null) return;
    _updateElapsed(session.startedAt!);
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final currentSession = ref.read(busAttendanceProvider).session;
      if (currentSession == null || currentSession.startedAt == null) {
        _elapsedTimer?.cancel();
        return;
      }
      _updateElapsed(currentSession.startedAt!);
    });
  }

  void _updateElapsed(DateTime startedAt) {
    final now = DateTime.now();
    final diff = now.difference(startedAt);
    if (diff != _elapsed) {
      setState(() => _elapsed = diff.isNegative ? Duration.zero : diff);
    }
  }

  void _onBoardingUpdate(dynamic data) {
    if (!mounted || data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    ref
        .read(busAttendanceProvider.notifier)
        .handleBoardingUpdate(map, widget.groupId);

    // Subtle haptic feedback when a pilgrim boards
    final isBoarded = map['boarded'] != false;
    if (isBoarded) {
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _endSession() async {
    final confirmed = await StandardDialog.show<bool>(
      context: context,
      title: 'attendance_end_confirm_title',
      content: 'attendance_end_confirm_body',
      confirmText: 'attendance_end_session',
      cancelText: 'area_cancel',
      isDestructive: true,
    );
    if (confirmed == true && mounted) {
      final ok = await ref
          .read(busAttendanceProvider.notifier)
          .completeSession(widget.groupId);
      if (ok && mounted) {
        StandardSnackBar.showSuccess(
          context,
          'attendance_session_ended'.tr(),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _cancelCreatedSession(BusAttendanceState st) async {
    final confirmed = await StandardDialog.show<bool>(
      context: context,
      title: 'attendance_cancel_trip_title',
      content: 'attendance_cancel_trip_body',
      confirmText: 'attendance_cancel_trip_btn',
      cancelText: 'attendance_keep_trip_btn',
      isDestructive: true,
    );
    if (confirmed == true && st.session != null && mounted) {
      final ok = await ref
          .read(busAttendanceProvider.notifier)
          .completeSession(widget.groupId);
      if (ok && mounted) {
        StandardSnackBar.showSuccess(
          context,
          'attendance_cancelled_success'.tr(),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref
                .read(busAttendanceProvider.notifier)
                .fetchHistory(widget.groupId);
          }
        });
      }
    }
  }

  Widget _buildPrintableQrCard({
    required String qrData,
    required String attendanceCode,
    required String busName,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/static/inapp_icon.png',
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Image.asset(
                    'assets/static/logo.jpeg',
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.directions_bus,
                      size: 48,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MUNAWWARA CARE',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      color: Color(0xFF1E293B),
                      decoration: TextDecoration.none,
                    ),
                  ),
                  Text(
                    'Trip Boarding & Gathering',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: Color(0xFF64748B),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 48),

          Text(
            busName.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: Color(0xFF334155),
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 24),

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFE2E8F0),
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 320,
              gapless: true,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
            ),
          ),
          const SizedBox(height: 40),

          Text(
            'attendance_scan_to_record'.tr(),
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: Color(0xFF64748B),
              letterSpacing: 1.5,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFFEDD5),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Text(
                  'attendance_code_label'.tr(),
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                    color: Color(0xFFC2410C),
                    letterSpacing: 1,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  attendanceCode,
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w800,
                    fontSize: 28,
                    letterSpacing: 6,
                    color: Color(0xFFEA580C),
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareQrCode(BusAttendanceState st) async {
    if (st.session == null || st.attendanceCode == null) return;
    try {
      final screenshotController = ScreenshotController();
      final qrData = 'mcare://bus-attendance?session_id=${st.session!.id}';

      final bytes = await screenshotController.captureFromWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: ui.TextDirection.ltr,
            child: Material(
              child: _buildPrintableQrCard(
                qrData: qrData,
                attendanceCode: st.attendanceCode!,
                busName: st.session?.busIdentifier ?? 'Trip',
              ),
            ),
          ),
        ),
        delay: const Duration(milliseconds: 100),
      );

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/munawwara_care_qr.png').create();
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Munawwara Care Boarding: ${st.session?.busIdentifier ?? 'Trip'}',
      );
    } catch (e) {
      if (mounted) {
        StandardSnackBar.showError(
          context,
          'attendance_share_qr_failed'.tr(args: [e.toString()]),
        );
      }
    }
  }

  Future<void> _downloadQrCode(BusAttendanceState st) async {
    if (st.session == null || st.attendanceCode == null) return;
    try {
      final screenshotController = ScreenshotController();
      final qrData = 'mcare://bus-attendance?session_id=${st.session!.id}';

      final bytes = await screenshotController.captureFromWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: ui.TextDirection.ltr,
            child: Material(
              child: _buildPrintableQrCard(
                qrData: qrData,
                attendanceCode: st.attendanceCode!,
                busName: st.session?.busIdentifier ?? 'Trip',
              ),
            ),
          ),
        ),
        delay: const Duration(milliseconds: 100),
      );

      final tempDir = await getTemporaryDirectory();
      final fileName = '${st.session?.busIdentifier ?? 'trip'}_qr'.replaceAll(RegExp(r'[^\w\-_]'), '_');
      final file = File('${tempDir.path}/$fileName.png');
      await file.writeAsBytes(bytes);

      // Save to gallery
      await Gal.putImage(file.path);

      if (mounted) {
        StandardSnackBar.showSuccess(
          context,
          'attendance_qr_saved_gallery'.tr(),
        );
      }
    } catch (e) {
      if (mounted) {
        StandardSnackBar.showError(
          context,
          'attendance_save_qr_failed'.tr(args: [e.toString()]),
        );
      }
    }
  }

  Future<void> _manualToggle(String pilgrimId, bool board) async {
    final session = ref.read(busAttendanceProvider).session;
    if (session == null) return;
    final ok = await ref.read(busAttendanceProvider.notifier).manualToggle(
          groupId: widget.groupId,
          sessionId: session.id,
          pilgrimId: pilgrimId,
          boarded: board,
        );
    if (!ok && mounted) {
      StandardSnackBar.showError(context, 'attendance_update_error'.tr());
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(busAttendanceProvider);

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: _buildAppBar(st),
      body: widget.pastSessionId != null
          ? (st.isLoading && st.session == null
              ? _buildLoading()
              : _buildActiveSession(st))
          : (!st.hasFetched || st.isStarting
              ? _buildLoading()
              : (!st.hasAnySession
                  ? _buildNoSession(st)
                  : _buildActiveSession(st))),
    );
  }

  PreferredSizeWidget _buildAppBar(BusAttendanceState st) {
    final isCreated = st.hasCreatedSession;
    final isPast = widget.pastSessionId != null;

    return AppBar(
      title: Text(
        isPast ? (st.session?.busIdentifier ?? 'attendance_trip_details'.tr()) : 'attendance_title'.tr(),
        style: TextStyle(
          fontFamily: 'Lexend',
          fontWeight: FontWeight.w700,
          fontSize: 16.sp,
        ),
      ),
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: isDark ? Colors.white : AppColors.textDark,
      leadingWidth: (isCreated && !isPast) ? 80.w : 56.w,
      leading: (isCreated && !isPast)
          ? Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 16.w),
                child: TextButton(
                  onPressed: () => _cancelCreatedSession(st),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'cancel'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 13.sp,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ),
            )
          : IconButton(
              icon: const Icon(Symbols.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
      actions: [
        if (st.hasActiveSession && !isPast)
          TextButton(
            onPressed: _endSession,
            child: Text(
              'attendance_end_session'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 12.sp,
                color: AppColors.error,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36.w,
            height: 36.w,
            child: const CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.primary,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'attendance_start_session'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : AppColors.textMutedDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSession(BusAttendanceState st) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80.w,
              height: 80.w,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Symbols.fact_check,
                size: 40.w,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'attendance_no_active_session'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 16.sp,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'attendance_start_desc'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                color: isDark ? Colors.white54 : AppColors.textMutedDark,
              ),
            ),
            SizedBox(height: 28.h),

            // Trip / Bus Name Input field on main screen
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'attendance_bus_label'.tr().toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white54 : AppColors.textMutedDark,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            SizedBox(height: 8.h),
            TextField(
              controller: _busController,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFF7F8FC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16.w,
                  vertical: 14.h,
                ),
              ),
            ),
            SizedBox(height: 24.h),

            SizedBox(
              width: double.infinity,
              height: 52.h,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final ok = await ref
                      .read(busAttendanceProvider.notifier)
                      .createSession(widget.groupId, busIdentifier: _busController.text);
                  if (!ok && mounted) {
                    final err = ref.read(busAttendanceProvider).error;
                    StandardSnackBar.showError(context, err ?? 'Unknown error');
                  }
                },
                icon: Icon(Symbols.qr_code, size: 22.w, color: Colors.white),
                label: Text(
                  'attendance_create_session'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 14.sp,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  elevation: 0,
                ),
              ),
            ),

            // History section starts here
            if (st.history.isNotEmpty) ...[
              SizedBox(height: 36.h),
              const Divider(),
              SizedBox(height: 20.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Symbols.history,
                        size: 20.w,
                        color: isDark ? Colors.white70 : AppColors.textMutedDark,
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        'attendance_trip_history'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 15.sp,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                  if (st.history.length > 3)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showAllHistory = !_showAllHistory;
                        });
                      },
                      child: Text(
                        _showAllHistory ? 'attendance_show_less'.tr() : 'attendance_show_more'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 12.sp,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 12.h),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _showAllHistory
                    ? st.history.length
                    : (st.history.length > 3 ? 3 : st.history.length),
                itemBuilder: (context, index) {
                  final session = st.history[index];
                  final formattedDate = session.startedAt != null
                      ? DateFormat('MMM dd, yyyy · HH:mm').format(session.startedAt!.toLocal())
                      : (session.completedAt != null
                          ? DateFormat('MMM dd, yyyy · HH:mm').format(session.completedAt!.toLocal())
                          : 'attendance_unknown_date'.tr());

                  final boardedCount = session.boardedPilgrims.length;
                  final totalPilgrims = session.totalPilgrims;

                  return Container(
                    margin: EdgeInsets.only(bottom: 12.h),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.surfaceDark
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14.r),
                      border: Border.all(
                        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                        width: 0.5,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                      leading: Container(
                        width: 40.w,
                        height: 40.w,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Symbols.directions_bus,
                          size: 20.w,
                          color: AppColors.primary,
                        ),
                      ),
                      title: Text(
                        session.busIdentifier,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 13.sp,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 4.h),
                          Text(
                            formattedDate,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 11.sp,
                              color: isDark ? Colors.white54 : AppColors.textMutedDark,
                            ),
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            '${'attendance_present'.tr()}: $boardedCount / $totalPilgrims',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      trailing: Icon(
                        Symbols.arrow_forward_ios,
                        size: 14.w,
                        color: isDark ? Colors.white30 : AppColors.textMutedLight,
                      ),
                      onTap: () {
                        // Open the read-only details screen
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BusAttendanceScreen(
                              groupId: widget.groupId,
                              groupName: widget.groupName,
                              pastSessionId: session.id,
                            ),
                          ),
                        ).then((_) {
                          // Re-fetch history to ensure up-to-date lists if they go back
                          if (mounted) {
                            ref
                                .read(busAttendanceProvider.notifier)
                                .fetchHistory(widget.groupId);
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Active Session Layout ─────────────────────────────────────────────────

  Widget _buildActiveSession(BusAttendanceState st) {
    final isActive = st.hasActiveSession;
    final isPast = widget.pastSessionId != null;

    return Column(
      children: [
        // Header: bus name + elapsed time
        _buildSessionHeader(st),

        // QR + Code section (ONLY if NOT past session)
        if (!isPast) _buildQrSection(st),

        if (!isActive && !isPast) ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 24.h),
            child: SizedBox(
              width: double.infinity,
              height: 52.h,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final ok = await ref
                      .read(busAttendanceProvider.notifier)
                      .startSession(widget.groupId, busIdentifier: st.session?.busIdentifier);
                  if (ok && mounted) {
                    _startElapsedTimer();
                  } else if (!ok && mounted) {
                    final err = ref.read(busAttendanceProvider).error;
                    StandardSnackBar.showError(context, err ?? 'Unknown error');
                  }
                },
                icon: Icon(Symbols.play_arrow, size: 22.w),
                label: Text(
                  'attendance_start_session'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 14.sp,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],

        if (isActive || isPast) ...[
          // Counter bar
          _buildCounterBar(st),

          // Tabs: Present / Missing
          _buildTabBar(st),
          Expanded(child: _buildTabContent(st)),
        ],
      ],
    );
  }

  Widget _buildSessionHeader(BusAttendanceState st) {
    final hh = _elapsed.inHours.toString().padLeft(2, '0');
    final mm = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');

    final isActive = st.hasActiveSession;
    final isPast = widget.pastSessionId != null;
    final statusColor = isPast
        ? Colors.grey
        : (isActive ? AppColors.success : Colors.amber);
    final statusText = isPast
        ? 'attendance_status_completed'.tr()
        : (isActive ? 'attendance_session_active'.tr() : 'attendance_session_created'.tr());

    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(
              Symbols.directions_bus,
              size: 20.w,
              color: AppColors.primary,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  st.session?.busIdentifier ?? widget.groupName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 13.sp,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
                SizedBox(height: 2.h),
                Row(
                  children: [
                    Container(
                      width: 6.w,
                      height: 6.w,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFF7F8FC),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.timer,
                  size: 14.w,
                  color: isDark ? Colors.white60 : AppColors.textMutedDark,
                ),
                SizedBox(width: 4.w),
                Text(
                  (isActive || isPast) ? '$hh:$mm:$ss' : '--:--:--',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 12.sp,
                    color: isDark ? Colors.white : AppColors.textDark,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrSection(BusAttendanceState st) {
    final hasQr = st.qrImageBase64 != null && st.qrImageBase64!.isNotEmpty;

    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          // QR image
          Container(
            width: 160.w,
            height: 160.w,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            padding: EdgeInsets.all(8.w),
            child: hasQr
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8.r),
                    child: Image.memory(
                      base64Decode(st.qrImageBase64!),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => Icon(
                        Symbols.qr_code_2,
                        size: 80.w,
                        color: AppColors.textMutedLight,
                      ),
                    ),
                  )
                : Center(
                    child: SizedBox(
                      width: 28.w,
                      height: 28.w,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
          ),

          SizedBox(height: 12.h),

          // "Scan QR to check in" label
          Text(
            'attendance_scan_qr'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 11.sp,
              color: isDark ? Colors.white54 : AppColors.textMutedDark,
            ),
          ),

          if (hasQr) ...[
            SizedBox(height: 14.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _downloadQrCode(st),
                  icon: Icon(Symbols.download, size: 18.w, color: AppColors.primary),
                  label: Text(
                    'attendance_download_qr'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 12.sp,
                      color: AppColors.primary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.primary, width: 1.2),
                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                ElevatedButton.icon(
                  onPressed: () => _shareQrCode(st),
                  icon: Icon(Symbols.share, size: 18.w, color: Colors.white),
                  label: Text(
                    'attendance_share_qr_btn'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 12.sp,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ],

          SizedBox(height: 16.h),

          // Attendance code chip
          if (st.attendanceCode != null)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: st.attendanceCode!));
                HapticFeedback.selectionClick();
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${'attendance_code'.tr()}:  ',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white70 : AppColors.textMutedDark,
                      ),
                    ),
                    Text(
                      st.attendanceCode!,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Icon(
                      Symbols.content_copy,
                      size: 16.w,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCounterBar(BusAttendanceState st) {
    final boarded = st.boarded.length;
    final total = st.totalPilgrims;
    final pct = total > 0 ? boarded / total : 0.0;
    final allPresent = total > 0 && boarded == total;

    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: allPresent
            ? AppColors.success.withValues(alpha: 0.08)
            : (isDark ? AppColors.surfaceDark : Colors.white),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: allPresent
              ? AppColors.success.withValues(alpha: 0.3)
              : (isDark ? AppColors.dividerDark : AppColors.dividerLight),
          width: allPresent ? 1.5 : 0.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    allPresent ? Symbols.check_circle : Symbols.groups,
                    size: 18.w,
                    color: allPresent
                        ? AppColors.success
                        : (isDark ? Colors.white70 : AppColors.textDark),
                  ),
                  SizedBox(width: 6.w),
                  Text(
                    allPresent
                        ? 'attendance_all_present'.tr()
                        : 'attendance_of_total'.tr(namedArgs: {
                            'count': '$boarded',
                            'total': '$total',
                          }),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 13.sp,
                      color: allPresent
                          ? AppColors.success
                          : (isDark ? Colors.white : AppColors.textDark),
                    ),
                  ),
                ],
              ),
              Text(
                '${(pct * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w800,
                  fontSize: 14.sp,
                  color: allPresent
                      ? AppColors.success
                      : AppColors.primary,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: pct),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (_, val, _) => LinearProgressIndicator(
                value: val,
                minHeight: 6.h,
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFE8E8F0),
                valueColor: AlwaysStoppedAnimation(
                  allPresent ? AppColors.success : AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(BusAttendanceState st) {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF0F0F8),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorPadding: EdgeInsets.all(3.w),
        labelColor: isDark ? Colors.white : AppColors.textDark,
        unselectedLabelColor:
            isDark ? Colors.white54 : AppColors.textMutedDark,
        labelStyle: TextStyle(
          fontFamily: 'Lexend',
          fontWeight: FontWeight.w700,
          fontSize: 12.sp,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'Lexend',
          fontWeight: FontWeight.w500,
          fontSize: 12.sp,
        ),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Symbols.check_circle, size: 16.w),
                SizedBox(width: 6.w),
                Text('${'attendance_present'.tr()} (${st.boarded.length})'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Symbols.person_off, size: 16.w),
                SizedBox(width: 6.w),
                Text('${'attendance_missing'.tr()} (${st.missing.length})'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(BusAttendanceState st) {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildBoardedList(st),
        _buildMissingList(st),
      ],
    );
  }

  // ── Boarded (Present) List ────────────────────────────────────────────────

  Widget _buildBoardedList(BusAttendanceState st) {
    if (st.boarded.isEmpty) {
      return _buildEmptyTab(
        icon: Symbols.how_to_reg,
        text: 'attendance_missing'.tr(),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
      itemCount: st.boarded.length,
      itemBuilder: (_, i) {
        final p = st.boarded[i];
        final time = DateFormat('HH:mm').format(p.boardedAt.toLocal());
        return _PilgrimTile(
          isDark: isDark,
          name: p.fullName,
          initials: p.initials,
          gender: p.gender,
          profilePicture: p.profilePicture,
          subtitle: '${'attendance_checked_in'.tr()} · $time',
          subtitleColor: AppColors.success,
          trailing: widget.pastSessionId != null
              ? null
              : IconButton(
                  icon: Icon(
                    Symbols.person_remove,
                    size: 20.w,
                    color: AppColors.error.withValues(alpha: 0.7),
                  ),
                  tooltip: 'attendance_manual_checkout'.tr(),
                  onPressed: () => _manualToggle(p.id, false),
                ),
          leadingIcon: Symbols.check_circle,
          leadingIconColor: AppColors.success,
        );
      },
    );
  }

  // ── Missing List ──────────────────────────────────────────────────────────

  Widget _buildMissingList(BusAttendanceState st) {
    if (st.missing.isEmpty) {
      return _buildEmptyTab(
        icon: Symbols.celebration,
        text: 'attendance_all_present'.tr(),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
      itemCount: st.missing.length,
      itemBuilder: (_, i) {
        final p = st.missing[i];
        final battery = p.batteryPercent != null ? '${p.batteryPercent}%' : '';
        final hotel = p.hotelName ?? '';
        final room = p.roomNumber != null ? 'R${p.roomNumber}' : '';
        final parts = [hotel, room, battery]
            .where((s) => s.isNotEmpty)
            .join(' · ');

        return _PilgrimTile(
          isDark: isDark,
          name: p.fullName,
          initials: p.initials,
          gender: p.gender,
          profilePicture: p.profilePicture,
          subtitle: parts.isEmpty ? null : parts,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (p.phoneNumber != null)
                IconButton(
                  icon: Icon(
                    Symbols.call,
                    size: 20.w,
                    color: AppColors.primary,
                  ),
                  onPressed: () async {
                    final uri = Uri(scheme: 'tel', path: p.phoneNumber);
                    if (await canLaunchUrl(uri)) launchUrl(uri);
                  },
                ),
              if (widget.pastSessionId == null)
                IconButton(
                  icon: Icon(
                    Symbols.person_add,
                    size: 20.w,
                    color: AppColors.success,
                  ),
                  tooltip: 'attendance_manual_checkin'.tr(),
                  onPressed: () => _manualToggle(p.id, true),
                ),
            ],
          ),
          leadingIcon: Symbols.radio_button_unchecked,
          leadingIconColor: isDark ? Colors.white30 : AppColors.textMutedLight,
        );
      },
    );
  }

  Widget _buildEmptyTab({required IconData icon, required String text}) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48.w,
              color: isDark ? Colors.white24 : AppColors.textMutedLight,
            ),
            SizedBox(height: 12.h),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white38 : AppColors.textMutedDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable Pilgrim Tile
// ─────────────────────────────────────────────────────────────────────────────

class _PilgrimTile extends StatelessWidget {
  final bool isDark;
  final String name;
  final String initials;
  final String? gender;
  final String? profilePicture;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? trailing;
  final IconData leadingIcon;
  final Color leadingIconColor;

  const _PilgrimTile({
    required this.isDark,
    required this.name,
    required this.initials,
    this.gender,
    this.profilePicture,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
    required this.leadingIcon,
    required this.leadingIconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Avatar with status dot overlay
          SizedBox(
            width: 38.w,
            height: 38.w,
            child: Stack(
              children: [
                PilgrimGenderAvatar(
                  gender: gender,
                  size: 38.w,
                  imageUrl: profilePicture,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 14.w,
                    height: 14.w,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      leadingIcon,
                      size: 12.w,
                      color: leadingIconColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 13.sp,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: 2.h),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 10.sp,
                      color: subtitleColor ??
                          (isDark ? Colors.white54 : AppColors.textMutedDark),
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
