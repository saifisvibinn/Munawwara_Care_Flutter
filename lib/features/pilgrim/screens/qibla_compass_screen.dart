import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
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
  static const double _alignToleranceDeg = 3.0;
  static const double _headingDeadbandDeg = 0.8;
  static const double _minGpsMoveMeters = 20.0;

  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<Position>? _positionSub;

  bool _loading = true;
  String? _error;

  double? _rawHeading;
  double? _smoothedHeading;
  double? _qiblaBearing;
  double? _smoothedRelativeAngle;
  double? _distanceKm;
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
          'Location services are disabled. Enable GPS to use Qibla compass.',
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setError('Location permission is required to use Qibla compass.');
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
      _positionSub =
          Geolocator.getPositionStream(
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
        _updateRelativeAngle();
        _handleAlignmentFeedback();

        _loading = false;
        _error = null;
        _throttledRebuild();
      });

      if (_compassSub == null) {
        _setError('Compass sensor is unavailable on this device.');
      }
    } catch (_) {
      _setError('Unable to initialize Qibla compass.');
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
    _updateRelativeAngle(force: true);
    _handleAlignmentFeedback();
    _loading = false;
    _error = null;
    _throttledRebuild(force: true);
  }

  void _updateRelativeAngle({bool force = false}) {
    if (_qiblaBearing == null || _smoothedHeading == null) return;
    final target = QiblaMath.normalize360(_qiblaBearing! - _smoothedHeading!);
    _smoothedRelativeAngle = (_smoothedRelativeAngle == null || force)
        ? target
        : QiblaMath.smoothAngle(_smoothedRelativeAngle!, target, 0.24);
  }

  bool _isAligned(double relativeAngle) {
    final delta = QiblaMath.shortestDelta(0, relativeAngle).abs();
    return delta <= _alignToleranceDeg;
  }

  void _handleAlignmentFeedback() {
    if (_smoothedRelativeAngle == null) return;
    final aligned = _isAligned(_smoothedRelativeAngle!);
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final hasSensors =
        _smoothedHeading != null &&
        _qiblaBearing != null &&
        _smoothedRelativeAngle != null;

    if (!hasSensors && _error != null) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.explore_off,
                  size: 42.w,
                  color: AppColors.textMutedLight,
                ),
                SizedBox(height: 12.h),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14.sp,
                    color: isDark ? Colors.white70 : AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final heading = _smoothedHeading ?? 0;
    final relativeDirection = _smoothedRelativeAngle ?? 0;
    final aligned = _isAligned(relativeDirection);
    final arrowColor = aligned
        ? const Color(0xFF3C9D4A)
        : const Color(0xFFC89E4B);

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 24.h),
        children: [
          Center(
            child: Text(
              'Qibla Compass',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 30.sp,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Center(
            child: SizedBox(
              width: 340.w,
              height: 340.w,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Compass dial stays fixed on screen.
                  CustomPaint(
                    size: Size(340.w, 340.w),
                    painter: _CompassDialPainter(),
                  ),

                  // Kaaba marker rotates around edge according to relative angle.
                  Transform.rotate(
                    angle: _degToRad(relativeDirection),
                    child: Transform.translate(
                      offset: Offset(0, -130.h),
                      child: Container(
                        width: 36.w,
                        height: 36.w,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFB8964A),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          Symbols.mosque,
                          size: 20.w,
                          color: const Color(0xFF1B1E4D),
                        ),
                      ),
                    ),
                  ),

                  // Center marker only (kept minimal to reduce clutter)
                  Container(
                    width: 48.w,
                    height: 48.w,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFB8964A),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Symbols.adjust,
                      size: 24.w,
                      color: const Color(0xFF1B1E4D),
                    ),
                  ),

                  // Fixed phone-heading arrow (does not rotate with dial).
                  Transform.translate(
                    offset: Offset(0, -130.h),
                    child: Icon(
                      Symbols.navigation,
                      size: 52.w,
                      color: arrowColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 12.h),
          Center(
            child: Text(
              '${relativeDirection.round()}° ${QiblaMath.cardinal(relativeDirection)}',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 22.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1B1E4D),
              ),
            ),
          ),
          SizedBox(height: 18.h),
          if (_distanceKm != null)
            Center(
              child: Text(
                'Distance to Kaaba: ${_distanceKm!.toStringAsFixed(0)} km',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1B1E4D),
                ),
              ),
            ),
          SizedBox(height: 8.h),
          Center(
            child: Text(
              'Heading: ${heading.round()}°',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 12.sp,
                color: AppColors.textMutedLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _degToRad(double deg) => deg * math.pi / 180;
}

class _CompassDialPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..shader = const LinearGradient(
        colors: [Color(0xFFF1D986), Color(0xFFC89E4B)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFD3C08D);

    canvas.drawCircle(center, radius - 8, outer);
    canvas.drawCircle(center, radius - 24, inner);
    canvas.drawCircle(center, radius - 78, inner);

    final tick = Paint()
      ..color = const Color(0xFFD9CBA5)
      ..strokeWidth = 2;

    for (var i = 0; i < 96; i++) {
      final angle = (2 * math.pi / 96) * i;
      final isMajor = i % 12 == 0;
      final start = radius - 34;
      final end = isMajor ? radius - 14 : radius - 22;
      final p1 = Offset(
        center.dx + start * math.cos(angle),
        center.dy + start * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + end * math.cos(angle),
        center.dy + end * math.sin(angle),
      );
      canvas.drawLine(p1, p2, tick);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
