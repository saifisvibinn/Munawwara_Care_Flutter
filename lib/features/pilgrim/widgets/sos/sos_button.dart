import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SOS Button
// ─────────────────────────────────────────────────────────────────────────────

class SosButton extends StatefulWidget {
  final double size;
  final AnimationController pulseController;
  final AnimationController holdController;
  final bool isHolding;
  final bool isLoading;
  final bool sosActive;
  final int countdown;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  const SosButton({
    super.key,
    this.size = 190,
    required this.pulseController,
    required this.holdController,
    required this.isHolding,
    required this.isLoading,
    required this.sosActive,
    required this.countdown,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnim;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 250),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.90).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOut,
        reverseCurve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onDown() {
    setState(() => _isPressed = true);
    _scaleController.forward();
    HapticFeedback.mediumImpact();
  }

  void _onUp() {
    setState(() => _isPressed = false);
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final double size = widget.size;

    return GestureDetector(
      onLongPressDown: (_) => _onDown(),
      onLongPressStart: (_) {
        HapticFeedback.heavyImpact();
        widget.onHoldStart();
      },
      onLongPressEnd: (_) {
        _onUp();
        widget.onHoldEnd();
      },
      onLongPressCancel: () {
        _onUp();
        widget.onHoldEnd();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_scaleAnim, widget.pulseController]),
        builder: (context, child) {
          final pulseCurve = Curves.easeInOut.transform(widget.pulseController.value);
          // Press scale always wins; pulse breathes underneath when idle
          final double pressScale = _isPressed ? _scaleAnim.value : 1.0;
          final double pulseScale = _isPressed ? 1.0 : (1.0 + (pulseCurve * 0.045));
          return Transform.scale(scale: pressScale * pulseScale, child: child);
        },
        child: SizedBox(
          width: (size + 16).w,
          height: (size + 16).w,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── Main Button Surface & Glow ──
              AnimatedBuilder(
                animation: widget.pulseController,
                builder: (context, child) {
                  final pulseValue = widget.pulseController.value;
                  final double glowRadius = 28.0 + (pulseValue * 18.0);
                  final double spreadRadius = 6.0 + (pulseValue * 8.0);
                  final double glowAlpha = widget.sosActive ? 0.35 : (0.45 + (pulseValue * 0.15));

                  return Container(
                    width: size.w,
                    height: size.w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.sosActive
                          ? const Color(0xFFD32F2F)
                          : const Color(0xFFE02020),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE02020).withValues(alpha: glowAlpha),
                          blurRadius: glowRadius.w,
                          spreadRadius: spreadRadius.w,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 10.w,
                          offset: Offset(0, 4.w),
                        ),
                      ],
                    ),
                    child: child,
                  );
                },
                child: widget.isLoading
                    ? Center(
                        child: SizedBox(
                          width: (size * 0.21).clamp(24.0, 40.0).w,
                          height: (size * 0.21).clamp(24.0, 40.0).w,
                          child: const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 4,
                          ),
                        ),
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: widget.isHolding
                            ? SosHoldingContent(
                                key: const ValueKey('holding'),
                                countdown: widget.countdown,
                                size: size,
                              )
                            : SosIdleContent(
                                key: const ValueKey('idle'),
                                sosActive: widget.sosActive,
                                size: size,
                              ),
                      ),
              ),

              // ── Holding Progress Ring (only when actually holding) ──
              if (widget.isHolding)
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: widget.holdController,
                    builder: (_, _) {
                      final ringStroke = (size * 0.042).clamp(4.0, 8.0);
                      final rotationAngle = widget.holdController.value * 2.0 * 3.14159265;
                      return Transform.rotate(
                        angle: rotationAngle,
                        child: SizedBox(
                          width: (size + 10).w,
                          height: (size + 10).w,
                          child: CircularProgressIndicator(
                            value: widget.holdController.value,
                            strokeWidth: ringStroke.w,
                            color: Colors.white,
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SOS Button inner content — holding state
// ─────────────────────────────────────────────────────────────────────────────

class SosHoldingContent extends StatelessWidget {
  final int countdown;
  final double size;
  const SosHoldingContent({super.key, required this.countdown, required this.size});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'sos_keep_holding'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: (size * 0.082).clamp(10.0, 16.0).sp,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          'sos_hold_seconds'.tr(namedArgs: {'n': '$countdown'}),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: (size * 0.071).clamp(9.0, 14.0).sp,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SOS Button inner content — idle / active state
// ─────────────────────────────────────────────────────────────────────────────

class SosIdleContent extends StatelessWidget {
  final bool sosActive;
  final double size;
  const SosIdleContent({super.key, required this.sosActive, required this.size});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'sos_title'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: (size * 0.25).clamp(24.0, 48.0).sp,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: (size * 0.02).clamp(1.0, 4.0),
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          sosActive ? 'sos_active_text'.tr() : 'sos_hold_label'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: (size * 0.08).clamp(8.0, 14.0).sp,
            fontWeight: FontWeight.w900, // Extra bold
            color: Colors.white, // Fully white
            letterSpacing: (size * 0.01).clamp(0.5, 1.5),
          ),
        ),
      ],
    );
  }
}
