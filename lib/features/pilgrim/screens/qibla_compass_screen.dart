import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter_compass_v2/flutter_compass_v2.dart';
import 'package:flutter_qiblah/flutter_qiblah.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';

class QiblaCompassScreen extends StatefulWidget {
  const QiblaCompassScreen({
    super.key,
    this.enableAlignmentHaptics = true,
  });

  /// When false, compass still updates but alignment haptics are suppressed
  /// (e.g. another bottom-nav tab is selected in the dashboard [PageView]).
  final bool enableAlignmentHaptics;

  @override
  State<QiblaCompassScreen> createState() => _QiblaCompassScreenState();
}

// ─────────────────────────────────────────────────────────────────────────────
// State — ALL compass logic lives here; UI widgets below are untouched.
// ─────────────────────────────────────────────────────────────────────────────

class _QiblaCompassScreenState extends State<QiblaCompassScreen>
    with TickerProviderStateMixin {
  static const double _alignToleranceDeg = 5.0;

  // ── Calibration ─────────────────────────────────────────────────────────────
  bool _showCalibration = false;
  int _sensorAccuracy = -1; // -1 = unknown, 0 = unreliable, 3 = high
  StreamSubscription<CompassEvent>? _calibrationSub;
  late final AnimationController _figure8Ctrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // ── Main compass ─────────────────────────────────────────────────────────
  StreamSubscription<QiblahDirection>? _qiblaSub;
  StreamSubscription<Position>? _positionSub;
  QiblahDirection? _qiblahDirection;
  double? _distanceKm;
  bool _wasAligned = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _figure8Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _startAccuracyWatch();
    _startQiblaTracking();

    // Fallback: If after 4 seconds we are still loading, forcefully show the UI.
    // This handles cases where both QiblahStream and CompassStream are completely silent (e.g. some emulators).
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _loading) {
        setState(() {
          _loading = false;
        });
      }
    });
  }

  Future<void> _startQiblaTracking() async {
    try {
      final status = await FlutterQiblah.checkLocationStatus();
      if (!status.enabled) {
        _setError('qibla_error_location'.tr());
        return;
      }

      var permission = status.status;
      if (permission == LocationPermission.denied) {
        await FlutterQiblah.requestPermissions();
        final s2 = await FlutterQiblah.checkLocationStatus();
        permission = s2.status;
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _setError('qibla_error_permission'.tr());
        return;
      }

      _qiblaSub = FlutterQiblah.qiblahStream.listen((dir) {
        if (!mounted) return;
        setState(() {
          _qiblahDirection = dir;
          _loading = false;
        });
        _handleAlignmentFeedback();
      });

      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        ),
      ).listen((pos) {
        if (!mounted) return;
        setState(() {
          _distanceKm = Geolocator.distanceBetween(
                pos.latitude,
                pos.longitude,
                21.422487,
                39.826206,
              ) /
              1000.0;
        });
      });

      final initial = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );
      if (mounted) {
        setState(() {
          _distanceKm = Geolocator.distanceBetween(
                initial.latitude,
                initial.longitude,
                21.422487,
                39.826206,
              ) /
              1000.0;
        });
      }
    } catch (e) {
      _setError('qibla_error_generic'.tr());
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  @override
  void didUpdateWidget(covariant QiblaCompassScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enableAlignmentHaptics) {
      _wasAligned = false;
    }
  }

  @override
  void dispose() {
    _figure8Ctrl.dispose();
    _pulseCtrl.dispose();
    _calibrationSub?.cancel();
    _qiblaSub?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  /// Listens to the raw compass accuracy. Shows the calibration UI while
  /// the magnetometer is unreliable (accuracy < 2) and hides it once ready.
  /// Also serves as a fallback driver for the compass heading if flutter_qiblah hangs.
  void _startAccuracyWatch() {
    _calibrationSub = FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      final acc = (event.accuracy?.toInt() ?? 3).clamp(0, 3);
      final needsCal = acc < 2;
      
      setState(() {
        _sensorAccuracy = acc;
        _showCalibration = needsCal;
        
        // If we get a compass event, we can stop loading immediately!
        if (event.heading != null) {
          _loading = false;
          _qiblahDirection = QiblahDirection(
            _qiblahDirection?.qiblah ?? 0.0,
            event.heading!,
            _qiblahDirection?.offset ?? 0.0,
          );
        }
      });

      // Keep the subscription alive to continuously drive the compass,
      // but toggle the calibration animation based on accuracy.
      if (!needsCal) {
        _figure8Ctrl.stop();
      } else if (!_figure8Ctrl.isAnimating) {
        _figure8Ctrl.repeat();
      }
    });
  }

  bool _isAligned() {
    if (_qiblahDirection == null) return false;
    // `offset` = absolute Qibla bearing from North.
    // `direction` = device heading from North.
    // Aligned when the phone is pointed within ±tolerance of the Kaaba.
    final delta = (_qiblahDirection!.direction - _qiblahDirection!.offset + 180) % 360 - 180;
    return delta.abs() <= _alignToleranceDeg;
  }

  void _handleAlignmentFeedback() {
    final aligned = _isAligned();
    if (widget.enableAlignmentHaptics &&
        aligned &&
        !_wasAligned) {
      HapticFeedback.lightImpact();
    }
    _wasAligned = aligned;
  }

  String _cardinal(double deg) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final normalized = deg % 360;
    return dirs[((normalized < 0 ? normalized + 360 : normalized) / 45).round() % 8];
  }

  double _degToRad(double deg) => deg * math.pi / 180;

  String _getAccuracyLabel(int acc) {
    if (acc <= 0) return 'qibla_accuracy_unreliable'.tr();
    if (acc == 1) return 'qibla_accuracy_low'.tr();
    if (acc == 2) return 'qibla_accuracy_medium'.tr();
    return 'qibla_accuracy_high'.tr();
  }

  Color? _getAccuracyColor(int acc) {
    if (acc < 2) return const Color(0xFFE74C3C); // Red for Low/Unreliable
    return null; // Default theme color for Medium/High
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Priority: calibration first, then loading, then error, then compass.
    if (_showCalibration) return _buildCalibrationScreen();

    if (_loading) {
      return Container(
        color: const Color(0xFF09162D),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFFE67E22)),
        ),
      );
    }

    final hasSensors = _qiblahDirection != null;

    if (!hasSensors && _error != null) {
      return Container(
        color: const Color(0xFF09162D),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.explore_off,
                    size: 48.w,
                    color: const Color(0xFFE67E22),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Compass rendering model:
    //   • `direction` = phone heading (0–360, 0 = true North)
    //   • `offset`    = absolute Qibla bearing from North (0–360)
    //   • Dial rotates by -direction so N/E/S/W labels track real-world positions.
    //   • Kaaba marker angle in screen-space = offset - direction (normalized).
    //     When the phone points at the Kaaba (direction == offset), this is 0°
    //     (marker at top = straight ahead), which is when alignment fires.
    //   • Center arrow is always fixed at the top of the stack (points up = where
    //     the phone is facing). User rotates the phone until this arrow is under
    //     the Kaaba marker.
    final heading = _qiblahDirection?.direction ?? 0;
    final qiblaAbsoluteBearing = _qiblahDirection?.offset ?? 0;
    // Positive angle = Kaaba is clockwise from the phone's current facing direction.
    final qiblaScreenAngle = (qiblaAbsoluteBearing - heading + 360) % 360;
    final aligned = _isAligned();

    final arrowColor = aligned
        ? const Color(0xFF2ECC71)
        : const Color(0xFFE67E22);

    final glowColor = aligned
        ? const Color(0xFF2ECC71).withValues(alpha: 0.4)
        : Colors.transparent;

    return Container(
      color: const Color(0xFF09162D),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 0),
              child: Text(
                'qibla_title'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 26.sp,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              aligned ? 'qibla_facing'.tr() : 'qibla_rotate'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: aligned
                    ? const Color(0xFF2ECC71)
                    : const Color(0xFFE67E22),
              ),
            ),

            SizedBox(height: 16.h),

            // ── Compass ────────────────────────────────────────────────
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 340.w,
                  height: 340.w,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Compass ring — rotates inversely to the phone heading
                      // so N/E/S/W stay in their real-world directions.
                      Transform.rotate(
                        angle: _degToRad(-heading),
                        child: CustomPaint(
                          size: Size(340.w, 340.w),
                          painter: _CompassDialPainter(
                            isDark: true,
                            aligned: aligned,
                          ),
                        ),
                      ),

                      // Qibla marker — always points at the Kaaba in
                      // screen-space regardless of phone orientation.
                      Transform.rotate(
                        angle: _degToRad(qiblaScreenAngle),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: EdgeInsets.only(top: 0),
                            child: _QiblaMarker(aligned: aligned),
                          ),
                        ),
                      ),

                      // Centre arrow — always points up (= where the phone
                      // faces). Lights up green when aligned with the Qibla.
                      Container(
                        width: 64.w,
                        height: 64.w,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0E1F3D),
                          boxShadow: [
                            BoxShadow(
                              color: glowColor,
                              blurRadius: aligned ? 28 : 0,
                              spreadRadius: aligned ? 8 : 0,
                            ),
                          ],
                          border: Border.all(
                            color: arrowColor.withValues(alpha: 0.5),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.navigation_rounded,
                          size: 34.w,
                          color: arrowColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Bottom info ────────────────────────────────────────────
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(32.r),
                ),
              ),
              padding: EdgeInsets.fromLTRB(24.w, 28.h, 24.w, 36.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Heading display
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${heading.round()}°',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 48.sp,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : const Color(0xFF09162D),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        _cardinal(heading),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 24.sp,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE67E22),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  // Distance and Qibla bearing
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _InfoChip(
                        icon: Symbols.mosque,
                        label: 'qibla_label'.tr(),
                        value: '${qiblaAbsoluteBearing.round()}°',
                        isDark: isDark,
                      ),
                      if (_distanceKm != null)
                        _InfoChip(
                          icon: Symbols.distance,
                          label: 'qibla_distance'.tr(),
                          value: '${_distanceKm!.round()} km',
                          isDark: isDark,
                        ),
                      _InfoChip(
                        icon: Symbols.compass_calibration,
                        label: 'qibla_accuracy'.tr(),
                        value: _getAccuracyLabel(_sensorAccuracy),
                        valueColor: _getAccuracyColor(_sensorAccuracy),
                        isDark: isDark,
                        highlight: _sensorAccuracy >= 3,
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'qibla_accuracy_hint'.tr(),
                                style: const TextStyle(fontFamily: 'Lexend'),
                              ),
                              backgroundColor: const Color(0xFFE67E22),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Calibration screen ──────────────────────────────────────────────────
  Widget _buildCalibrationScreen() {
    final acc = _sensorAccuracy.clamp(0, 3);
    final accentColor = acc == 0
        ? const Color(0xFFE74C3C)
        : acc == 1
            ? const Color(0xFFE67E22)
            : const Color(0xFF2ECC71);
    final statusLabel = acc == 0
        ? 'Unreliable'
        : acc == 1
            ? 'Low accuracy'
            : 'Calibrating…';

    return Container(
      color: const Color(0xFF09162D),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 0),
              child: Text(
                'qibla_title'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 26.sp,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),

            Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 28.w),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Figure-8 animation
                      AnimatedBuilder(
                        animation: _figure8Ctrl,
                        builder: (_, _) => CustomPaint(
                          size: Size(260.w, 170.h),
                          painter: _Figure8Painter(
                            progress: _figure8Ctrl.value,
                            accentColor: accentColor,
                          ),
                        ),
                      ),

                      SizedBox(height: 36.h),

                      // Accuracy pills
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (i) {
                          final filled = i < acc;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            margin: EdgeInsets.symmetric(horizontal: 4.w),
                            width: filled ? 36.w : 12.w,
                            height: 10.h,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5.r),
                              color: filled
                                  ? accentColor
                                  : Colors.white.withValues(alpha: 0.15),
                            ),
                          );
                        }),
                      ),

                      SizedBox(height: 22.h),

                      Text(
                        'Calibrating Compass',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),

                      SizedBox(height: 10.h),

                      Text(
                        'Move your phone in a slow figure-8 pattern to calibrate the magnetic sensor.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13.sp,
                          color: Colors.white60,
                          height: 1.6,
                        ),
                      ),

                      SizedBox(height: 32.h),

                      // Pulsing status badge
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (_, _) {
                          final pulse = _pulseAnim.value;
                          return Transform.scale(
                            scale: 0.96 + 0.04 * pulse,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 20.w,
                                vertical: 11.h,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24.r),
                                border: Border.all(
                                  color: accentColor.withValues(
                                      alpha: 0.35 + 0.25 * pulse),
                                  width: 1.5,
                                ),
                                color: accentColor.withValues(alpha: 0.08),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Symbols.explore,
                                      color: accentColor, size: 18.w),
                                  SizedBox(width: 8.w),
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.w600,
                                      color: accentColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Figure-8 Calibration Painter
// Draws a lemniscate of Bernoulli path with a travelling glowing dot.
// ─────────────────────────────────────────────────────────────────────────────

class _Figure8Painter extends CustomPainter {
  final double progress; // 0.0 → 1.0
  final Color accentColor;

  const _Figure8Painter({required this.progress, required this.accentColor});

  // Lemniscate parametric position at angle t (radians).
  Offset _lemniscate(double t, Offset center, double a) {
    final denom = 1 + math.pow(math.sin(t), 2);
    return Offset(
      center.dx + a * math.cos(t) / denom,
      center.dy + a * math.sin(t) * math.cos(t) / denom,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final a = size.width * 0.36;

    // Draw faint path
    final pathPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = accentColor.withValues(alpha: 0.18);

    final path = Path();
    for (int i = 0; i <= 360; i++) {
      final t = i * math.pi / 180;
      final pt = _lemniscate(t, center, a);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path, pathPaint);

    // Trailing glow arc (last 20% of path)
    final trailPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [Colors.transparent, accentColor.withValues(alpha: 0.7)],
      ).createShader(Rect.fromCircle(center: center, radius: a));

    final trailPath = Path();
    final trailStart = (progress - 0.20).clamp(0.0, 1.0);
    for (int i = 0; i <= 40; i++) {
      final frac = trailStart + i / 40 * 0.20;
      final t = frac * 2 * math.pi;
      final pt = _lemniscate(t, center, a);
      i == 0 ? trailPath.moveTo(pt.dx, pt.dy) : trailPath.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(trailPath, trailPaint);

    // Moving dot with glow
    final t = progress * 2 * math.pi;
    final dot = _lemniscate(t, center, a);

    final glowPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(dot, 14, glowPaint);

    final dotPaint = Paint()..color = accentColor;
    canvas.drawCircle(dot, 7, dotPaint);

    final dotCorePaint = Paint()..color = Colors.white;
    canvas.drawCircle(dot, 3, dotCorePaint);
  }

  @override
  bool shouldRepaint(covariant _Figure8Painter old) =>
      old.progress != progress || old.accentColor != accentColor;
}

// ─────────────────────────────────────────────────────────────────────────────
// Qibla Marker (Kaaba icon outside the compass)
// ─────────────────────────────────────────────────────────────────────────────

class _QiblaMarker extends StatelessWidget {
  final bool aligned;
  const _QiblaMarker({required this.aligned});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44.w,
          height: 44.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: aligned
                ? const Color(0xFF2ECC71)
                : const Color(0xFFE67E22),
            boxShadow: [
              BoxShadow(
                color: (aligned
                        ? const Color(0xFF2ECC71)
                        : const Color(0xFFE67E22))
                    .withValues(alpha: 0.5),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            Symbols.mosque,
            size: 24.w,
            color: Colors.white,
          ),
        ),
        // Small triangle pointer
        CustomPaint(
          size: Size(14.w, 8.w),
          painter: _TrianglePainter(
            color: aligned
                ? const Color(0xFF2ECC71)
                : const Color(0xFFE67E22),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info chip for the bottom section
// ─────────────────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final Widget? valueWidget = null;
  final Color? valueColor;
  final bool isDark;
  final bool highlight;
  final VoidCallback? onTap;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.value,
    this.valueColor,
    required this.isDark,
    this.highlight = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48.w,
            height: 48.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highlight
                  ? const Color(0xFF2ECC71).withValues(alpha: 0.15)
                  : isDark
                      ? const Color(0xFF1A2640)
                      : const Color(0xFFF0F2F5),
            ),
            child: Icon(
              icon,
              size: 22.w,
              color: highlight
                  ? const Color(0xFF2ECC71)
                  : const Color(0xFFE67E22),
            ),
          ),
          if (valueWidget != null)
            Padding(
              padding: EdgeInsets.only(top: 2.h, bottom: 2.h),
              child: valueWidget!,
            )
          else if (value != null)
            Text(
              value!,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 16.sp,
                fontWeight: FontWeight.w800,
                color: valueColor ?? (isDark ? Colors.white : const Color(0xFF09162D)),
              ),
            ),
          SizedBox(height: valueWidget != null ? 4.h : 2.h),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 11.sp,
              color: isDark ? Colors.white54 : AppColors.textMutedLight,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compass Dial Painter
// ─────────────────────────────────────────────────────────────────────────────

class _CompassDialPainter extends CustomPainter {
  final bool isDark;
  final bool aligned;

  _CompassDialPainter({this.isDark = false, this.aligned = false});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer ring
    final outerRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = aligned
          ? const Color(0xFF2ECC71).withValues(alpha: 0.5)
          : const Color(0xFFE67E22).withValues(alpha: 0.3);
    canvas.drawCircle(center, radius - 28, outerRing);

    // Inner ring
    final innerRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF1A3050);
    canvas.drawCircle(center, radius - 60, innerRing);

    // Tick marks + cardinal letters
    final majorTick = Paint()
      ..color = const Color(0xFFE67E22)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final minorTick = Paint()
      ..color = const Color(0xFF2A4A6B)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final cardinals = ['N', 'E', 'S', 'W'];

    for (var i = 0; i < 360; i += 5) {
      final angle = _degToRad(i.toDouble() - 90); // -90 to start from top
      final isMajor = i % 90 == 0;
      final isMinor = i % 45 == 0 && !isMajor;
      final isMedium = i % 15 == 0 && !isMajor && !isMinor;

      final tickStart = isMajor
          ? radius - 52
          : isMinor
              ? radius - 48
              : isMedium
                  ? radius - 44
                  : radius - 40;
      final tickEnd = radius - 30;

      final p1 = Offset(
        center.dx + tickStart * math.cos(angle),
        center.dy + tickStart * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + tickEnd * math.cos(angle),
        center.dy + tickEnd * math.sin(angle),
      );

      canvas.drawLine(p1, p2, isMajor || isMinor ? majorTick : minorTick);

      // Cardinal labels
      if (isMajor) {
        final idx = i ~/ 90;
        final label = cardinals[idx];
        final textPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: label == 'N' ? 16 : 13,
              fontWeight: FontWeight.w800,
              color: label == 'N'
                  ? const Color(0xFFE67E22)
                  : const Color(0xFF8EAFC5),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final labelRadius = radius - 65;
        final labelOffset = Offset(
          center.dx + labelRadius * math.cos(angle) - textPainter.width / 2,
          center.dy + labelRadius * math.sin(angle) - textPainter.height / 2,
        );
        textPainter.paint(canvas, labelOffset);
      }

      // Sub-cardinal labels
      if (isMinor) {
        final actualLabel = i == 45
            ? 'NE'
            : i == 135
                ? 'SE'
                : i == 225
                    ? 'SW'
                    : 'NW';
        final textPainter = TextPainter(
          text: TextSpan(
            text: actualLabel,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A6A85),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final labelRadius = radius - 62;
        final labelOffset = Offset(
          center.dx + labelRadius * math.cos(angle) - textPainter.width / 2,
          center.dy + labelRadius * math.sin(angle) - textPainter.height / 2,
        );
        textPainter.paint(canvas, labelOffset);
      }
    }

    // Degree numbers at 30° intervals (except cardinals and sub-cardinals)
    for (var i = 30; i < 360; i += 30) {
      if (i % 90 == 0) continue;
      if (i % 45 == 0) continue;

      final angle = _degToRad(i.toDouble() - 90);
      final textPainter = TextPainter(
        text: TextSpan(
          text: '$i°',
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 9,
            fontWeight: FontWeight.w500,
            color: Color(0xFF3A5A75),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelRadius = radius - 62;
      final labelOffset = Offset(
        center.dx + labelRadius * math.cos(angle) - textPainter.width / 2,
        center.dy + labelRadius * math.sin(angle) - textPainter.height / 2,
      );
      textPainter.paint(canvas, labelOffset);
    }
  }

  double _degToRad(double deg) => deg * math.pi / 180;

  @override
  bool shouldRepaint(covariant _CompassDialPainter old) =>
      old.aligned != aligned;
}

// ─────────────────────────────────────────────────────────────────────────────
// Triangle pointer painter
// ─────────────────────────────────────────────────────────────────────────────

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter old) => old.color != color;
}
