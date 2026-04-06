import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../utils/qibla_math.dart';

class QiblaCompassScreen extends StatefulWidget {
  const QiblaCompassScreen({super.key});

  @override
  State<QiblaCompassScreen> createState() => _QiblaCompassScreenState();
}

class _QiblaCompassScreenState extends State<QiblaCompassScreen> {
  static const double _alignToleranceDeg = 5.0;
  static const double _headingDeadbandDeg = 0.8;
  static const double _minGpsMoveMeters = 20.0;

  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<Position>? _positionSub;

  bool _loading = true;
  String? _error;

  double? _rawHeading;
  double? _smoothedHeading;
  double? _qiblaBearing;
  double? _distanceKm;
  // ignore: unused_field
  Position? _lastGpsPosition;
  double? _lastBearingLat;
  double? _lastBearingLng;
  bool _wasAligned = false;

  DateTime? _lastUiUpdate;
  final Duration _uiThrottle = const Duration(milliseconds: 40);

  @override
  void initState() {
    super.initState();
    _startQiblaTracking();
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _startQiblaTracking() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setError(
          'qibla_error_location'.tr(),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setError('qibla_error_permission'.tr());
        return;
      }

      final initial = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
        ),
      );
      _lastGpsPosition = initial;
      _applyLocation(lat: initial.latitude, lng: initial.longitude);

      _positionSub?.cancel();
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        ),
      ).listen((pos) {
        _lastGpsPosition = pos;
        _applyLocation(lat: pos.latitude, lng: pos.longitude);
      });

      _compassSub?.cancel();
      _compassSub = FlutterCompass.events?.listen((event) {
        final heading = event.heading;
        if (heading == null) return;

        _rawHeading = QiblaMath.normalize360(heading);
        if (_smoothedHeading == null) {
          _smoothedHeading = _rawHeading;
        } else {
          final delta = QiblaMath.shortestDelta(
            _smoothedHeading!,
            _rawHeading!,
          ).abs();
          if (delta < _headingDeadbandDeg) return;
          final alpha = delta > 20
              ? 0.35
              : delta > 8
                  ? 0.22
                  : 0.12;
          _smoothedHeading = QiblaMath.smoothAngle(
            _smoothedHeading!,
            _rawHeading!,
            alpha,
          );
        }

        _handleAlignmentFeedback();
        _loading = false;
        _error = null;
        _throttledRebuild();
      });

      if (_compassSub == null) {
        _setError('qibla_error_sensor'.tr());
      }
    } catch (_) {
      _setError('qibla_error_generic'.tr());
    }
  }

  void _applyLocation({required double lat, required double lng}) {
    if (_lastBearingLat != null && _lastBearingLng != null) {
      final moved = Geolocator.distanceBetween(
        _lastBearingLat!,
        _lastBearingLng!,
        lat,
        lng,
      );
      if (moved < _minGpsMoveMeters) {
        return;
      }
    }

    _qiblaBearing = QiblaMath.bearingToKaaba(lat, lng);
    _distanceKm = QiblaMath.distanceToKaabaKm(lat, lng);
    _lastBearingLat = lat;
    _lastBearingLng = lng;
    _handleAlignmentFeedback();
    _loading = false;
    _error = null;
    _throttledRebuild(force: true);
  }

  /// How far the phone heading is from the Qibla direction.
  double _qiblaDelta() {
    if (_qiblaBearing == null || _smoothedHeading == null) return 999;
    return QiblaMath.shortestDelta(_smoothedHeading!, _qiblaBearing!);
  }

  bool _isAligned() {
    return _qiblaDelta().abs() <= _alignToleranceDeg;
  }

  void _handleAlignmentFeedback() {
    final aligned = _isAligned();
    if (aligned && !_wasAligned) {
      HapticFeedback.lightImpact();
    }
    _wasAligned = aligned;
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  void _throttledRebuild({bool force = false}) {
    if (!mounted) return;
    final now = DateTime.now();
    if (force ||
        _lastUiUpdate == null ||
        now.difference(_lastUiUpdate!) >= _uiThrottle) {
      _lastUiUpdate = now;
      setState(() {});
    }
  }

  double _degToRad(double deg) => deg * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Container(
        color: const Color(0xFF09162D),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFFE67E22)),
        ),
      );
    }

    final hasSensors = _smoothedHeading != null && _qiblaBearing != null;

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

    final heading = _smoothedHeading ?? 0;
    final qibla = _qiblaBearing ?? 0;
    final aligned = _isAligned();

    // The angle from the phone's heading to the Qibla (how much we rotate the
    // Qibla marker from "straight up" on screen).
    // Qibla marker sits outside. When the phone turns, the marker rotates to
    // keep pointing at the real-world Qibla direction.
    final qiblaRelative = QiblaMath.normalize360(qibla - heading);

    // Arrow inside the circle: always points up (phone's heading direction)
    // and lights up when aligned with Qibla
    final arrowColor = aligned
        ? const Color(0xFF2ECC71) // bright green
        : const Color(0xFFE67E22); // orange

    final glowColor = aligned
        ? const Color(0xFF2ECC71).withOpacity(0.4)
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
                      // ── Compass ring (rotates with phone heading) ────
                      // The whole dial rotates inversely to the heading so
                      // N/E/S/W labels stay in their real-world directions.
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

                      // ── Qibla marker (outside circle) ───────────────
                      // Rotates with qiblaRelative so it always points at
                      // the real Qibla direction.
                      Transform.rotate(
                        angle: _degToRad(qiblaRelative),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: EdgeInsets.only(top: 0),
                            child: _QiblaMarker(aligned: aligned),
                          ),
                        ),
                      ),

                      // ── Center arrow (phone heading) ────────────────
                      // Always points straight up (phone heading direction).
                      // Lights up green when aligned with Qibla.
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
                            color: arrowColor.withOpacity(0.5),
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
                        QiblaMath.cardinal(heading),
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
                        value: '${qibla.round()}°',
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
                        icon: aligned
                            ? Symbols.check_circle
                            : Symbols.rotate_right,
                        label: 'qibla_offset'.tr(),
                        value: '${_qiblaDelta().round()}°',
                        isDark: isDark,
                        highlight: aligned,
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
                    .withOpacity(0.5),
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
  final String value;
  final bool isDark;
  final bool highlight;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48.w,
          height: 48.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: highlight
                ? const Color(0xFF2ECC71).withOpacity(0.15)
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
        SizedBox(height: 6.h),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 16.sp,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF09162D),
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 11.sp,
            color: isDark ? Colors.white54 : AppColors.textMutedLight,
          ),
        ),
      ],
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
          ? const Color(0xFF2ECC71).withOpacity(0.5)
          : const Color(0xFFE67E22).withOpacity(0.3);
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

    // Degree numbers at 30° intervals (except cardinals)
    for (var i = 30; i < 360; i += 30) {
      if (i % 90 == 0) continue; // skip cardinals
      if (i % 45 == 0) continue; // skip sub-cardinals

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
