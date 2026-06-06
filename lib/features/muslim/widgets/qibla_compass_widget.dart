import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../constants/muslim_colors.dart';
import '../utils/muslim_localization.dart';
import '../models/muslim_models.dart';

class QiblaCompassWidget extends StatefulWidget {
  const QiblaCompassWidget({super.key, required this.qibla});

  final QiblaData qibla;

  @override
  State<QiblaCompassWidget> createState() => _QiblaCompassWidgetState();
}

class _QiblaCompassWidgetState extends State<QiblaCompassWidget> {
  static const _alignToleranceDeg = 5.0;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  Timer? _sensorTimeout;
  double? _heading;
  bool _sensorUnavailable = false;
  bool _wasAligned = false;

  final List<double> _latestAccel = [0.0, 0.0, 0.0];
  final List<double> _latestMag = [0.0, 0.0, 0.0];
  bool _hasAccel = false;
  bool _hasMag = false;
  static const double _alpha = 0.15; // Tunable low-pass filter constant

  @override
  void initState() {
    super.initState();
    _startCompass();
  }

  void _startCompass() {
    _accelSub = accelerometerEventStream().listen(
      (event) {
        if (!mounted) return;
        if (!_hasAccel) {
          _latestAccel[0] = event.x;
          _latestAccel[1] = event.y;
          _latestAccel[2] = event.z;
          _hasAccel = true;
        } else {
          _latestAccel[0] = _latestAccel[0] + _alpha * (event.x - _latestAccel[0]);
          _latestAccel[1] = _latestAccel[1] + _alpha * (event.y - _latestAccel[1]);
          _latestAccel[2] = _latestAccel[2] + _alpha * (event.z - _latestAccel[2]);
        }
        _calculateTiltCompensatedHeading();
      },
      onError: (error) {
        setState(() => _sensorUnavailable = true);
      },
    );

    _magSub = magnetometerEventStream().listen(
      (event) {
        if (!mounted) return;
        if (!_hasMag) {
          _latestMag[0] = event.x;
          _latestMag[1] = event.y;
          _latestMag[2] = event.z;
          _hasMag = true;
        } else {
          _latestMag[0] = _latestMag[0] + _alpha * (event.x - _latestMag[0]);
          _latestMag[1] = _latestMag[1] + _alpha * (event.y - _latestMag[1]);
          _latestMag[2] = _latestMag[2] + _alpha * (event.z - _latestMag[2]);
        }
        _calculateTiltCompensatedHeading();
      },
      onError: (error) {
        setState(() => _sensorUnavailable = true);
      },
    );

    _sensorTimeout = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      if (_heading == null) {
        setState(() => _sensorUnavailable = true);
      }
    });
  }

  void _calculateTiltCompensatedHeading() {
    if (!_hasAccel || !_hasMag) return;

    final ax = _latestAccel[0];
    final ay = _latestAccel[1];
    final az = _latestAccel[2];

    final mx = _latestMag[0];
    final my = _latestMag[1];
    final mz = _latestMag[2];

    // Compute pitch and roll in radians
    final roll = math.atan2(ay, az);
    final pitch = math.atan2(-ax, math.sqrt(ay * ay + az * az));

    final sinRoll = math.sin(roll);
    final cosRoll = math.cos(roll);
    final sinPitch = math.sin(pitch);
    final cosPitch = math.cos(pitch);

    // Tilt-compensated horizontal magnetometer components
    final xh = mx * cosPitch + my * sinRoll * sinPitch + mz * cosRoll * sinPitch;
    final yh = my * cosRoll - mz * sinRoll;

    // Heading in degrees (clockwise from North: 0 = North, 90 = East, etc.)
    double headingDeg = math.atan2(-xh, yh) * 180 / math.pi;
    headingDeg = (headingDeg + 360) % 360;

    final aligned = _isAligned(headingDeg);
    if (aligned && !_wasAligned) {
      HapticFeedback.lightImpact();
    }
    _wasAligned = aligned;

    setState(() {
      _heading = headingDeg;
      _sensorUnavailable = false;
    });
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _magSub?.cancel();
    _sensorTimeout?.cancel();
    super.dispose();
  }

  double get _qiblaBearing => widget.qibla.qiblaDirection;

  bool _isAligned(double heading) {
    if (widget.qibla.message != null) return false;
    final delta = (heading - _qiblaBearing + 180) % 360 - 180;
    return delta.abs() <= _alignToleranceDeg;
  }

  double _degToRad(double deg) => deg * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    final heading = _heading;
    final atKaaba = widget.qibla.message != null;
    final hasLiveCompass = heading != null && !atKaaba;
    final effectiveHeading = heading ?? 0.0;
    final aligned = hasLiveCompass && _isAligned(effectiveHeading);

    final arrowColor =
        aligned ? MuslimColors.primaryContainer : MuslimColors.secondaryContainer;
    final glowColor = aligned
        ? MuslimColors.primaryContainer.withValues(alpha: 0.35)
        : Colors.transparent;

    final compassSize = 220.w;

    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: MuslimColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: aligned
              ? MuslimColors.primaryContainer
              : MuslimColors.outlineVariant.withValues(alpha: 0.35),
          width: aligned ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            'muslim_qibla_direction'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: MuslimColors.primary,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            _subtitle(heading: heading, aligned: aligned, atKaaba: atKaaba),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: aligned
                  ? MuslimColors.primaryContainer
                  : MuslimColors.secondaryContainer,
            ),
          ),
          SizedBox(height: 16.h),
          SizedBox(
            width: compassSize,
            height: compassSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Rotating dial and nested rotating marker are locked together
                // under a single heading rotation transform.
                Transform.rotate(
                  angle: _degToRad(-effectiveHeading),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Compass ring — N/E/S/W labels.
                      CustomPaint(
                        size: Size(compassSize, compassSize),
                        painter: _CompassDialPainter(
                          aligned: aligned,
                          cardinalLabels: localizedQiblaCardinals(),
                        ),
                      ),

                      // Qibla marker — physically locked to the dial at its absolute geographic bearing!
                      Transform.rotate(
                        angle: _degToRad(_qiblaBearing),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: _QiblaMarker(aligned: aligned),
                        ),
                      ),
                    ],
                  ),
                ),

                // Centre arrow — fixed, points where the phone is facing (straight ahead).
                Container(
                  width: 48.w,
                  height: 48.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MuslimColors.surface,
                    boxShadow: [
                      BoxShadow(
                        color: glowColor,
                        blurRadius: aligned ? 22 : 0,
                        spreadRadius: aligned ? 6 : 0,
                      ),
                    ],
                    border: Border.all(
                      color: arrowColor.withValues(alpha: 0.55),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.navigation_rounded,
                    size: 26.w,
                    color: arrowColor,
                  ),
                ),
              ],
            ),
          ),
          if (!hasLiveCompass && !atKaaba) ...[
            SizedBox(height: 12.h),
            Text(
              _statusText(heading: heading, aligned: aligned, atKaaba: atKaaba),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 12.sp,
                height: 1.45,
                color: MuslimColors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _subtitle({
    required double? heading,
    required bool aligned,
    required bool atKaaba,
  }) {
    if (atKaaba) return widget.qibla.message!;
    if (_sensorUnavailable || heading == null) {
      return 'qibla_error_sensor'.tr();
    }
    return aligned ? 'qibla_facing'.tr() : 'qibla_rotate'.tr();
  }

  String _statusText({
    required double? heading,
    required bool aligned,
    required bool atKaaba,
  }) {
    if (atKaaba) return widget.qibla.message!;
    if (_sensorUnavailable || heading == null) {
      return 'qibla_error_sensor'.tr();
    }
    if (aligned) return 'qibla_facing'.tr();
    return 'qibla_rotate'.tr();
  }
}

class _QiblaMarker extends StatelessWidget {
  const _QiblaMarker({required this.aligned});

  final bool aligned;

  @override
  Widget build(BuildContext context) {
    final color = aligned
        ? MuslimColors.primaryContainer
        : MuslimColors.secondaryContainer;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36.w,
          height: 36.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(
            Symbols.mosque,
            size: 20.w,
            color: Colors.white,
          ),
        ),
        CustomPaint(
          size: Size(12.w, 7.h),
          painter: _TrianglePainter(color: color),
        ),
      ],
    );
  }
}

class _CompassDialPainter extends CustomPainter {
  _CompassDialPainter({
    required this.aligned,
    required this.cardinalLabels,
  });

  final bool aligned;
  final List<String> cardinalLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final outerRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = aligned
          ? MuslimColors.primaryContainer.withValues(alpha: 0.45)
          : MuslimColors.secondaryContainer.withValues(alpha: 0.28);
    canvas.drawCircle(center, radius - 18, outerRing);

    final innerRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = MuslimColors.outlineVariant.withValues(alpha: 0.55);
    canvas.drawCircle(center, radius - 38, innerRing);

    final majorTick = Paint()
      ..color = MuslimColors.secondaryContainer
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final minorTick = Paint()
      ..color = MuslimColors.outlineVariant.withValues(alpha: 0.75)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 360; i += 5) {
      final angle = _degToRad(i.toDouble() - 90);
      final isMajor = i % 90 == 0;
      final isMinor = i % 45 == 0 && !isMajor;
      final isMedium = i % 15 == 0 && !isMajor && !isMinor;

      final tickStart = isMajor
          ? radius - 34
          : isMinor
              ? radius - 31
              : isMedium
                  ? radius - 28
                  : radius - 25;
      final tickEnd = radius - 18;

      final p1 = Offset(
        center.dx + tickStart * math.cos(angle),
        center.dy + tickStart * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + tickEnd * math.cos(angle),
        center.dy + tickEnd * math.sin(angle),
      );

      canvas.drawLine(p1, p2, isMajor || isMinor ? majorTick : minorTick);

      if (isMajor) {
        final index = i ~/ 90;
        final label = index < cardinalLabels.length
            ? cardinalLabels[index]
            : '';
        final isNorth = index == 0;
        final textPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: isNorth ? 13 : 11,
              fontWeight: FontWeight.w800,
              color: isNorth
                  ? MuslimColors.secondaryContainer
                  : MuslimColors.onSurfaceVariant,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final labelRadius = radius - 42;
        textPainter.paint(
          canvas,
          Offset(
            center.dx + labelRadius * math.cos(angle) - textPainter.width / 2,
            center.dy + labelRadius * math.sin(angle) - textPainter.height / 2,
          ),
        );
      }
    }
  }

  double _degToRad(double deg) => deg * math.pi / 180;

  @override
  bool shouldRepaint(covariant _CompassDialPainter old) =>
      old.aligned != aligned || old.cardinalLabels != cardinalLabels;
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter({required this.color});

  final Color color;

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
