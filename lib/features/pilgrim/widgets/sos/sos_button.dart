import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SOS Button
// ─────────────────────────────────────────────────────────────────────────────

class SosButton extends StatefulWidget {
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

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onDown() {
    _scaleController.forward();
    HapticFeedback.mediumImpact();
  }

  void _onUp() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    const double size = 190;
    const double ringStroke = 8;

    Widget disc = GestureDetector(
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
        animation: _scaleAnim,
        builder: (_, child) =>
            Transform.scale(scale: _scaleAnim.value, child: child),
        child: SizedBox(
          width: size.w,
          height: size.w,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── Layered Animated Glows ────────────────────────────────────
              AnimatedBuilder(
                animation: widget.pulseController,
                builder: (_, _) {
                  final p = widget.pulseController.value;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer faint glow
                      Transform.scale(
                        scale: 1.0 + (0.6 * p),
                        child: Container(
                          width: (size - 10).w,
                          height: (size - 10).w,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red.withValues(alpha: 0.15 * (1 - p)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.2 * (1 - p)),
                                blurRadius: 25 * p,
                                spreadRadius: 10 * p,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Inner pulse
                      Transform.scale(
                        scale: 1.0 + (0.3 * p),
                        child: Container(
                          width: (size - 20).w,
                          height: (size - 20).w,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red.withValues(alpha: 0.25 * (1 - p)),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              // ── Holding Progress Ring ─────────────────────────────────────
              if (widget.isHolding)
                AnimatedBuilder(
                  animation: widget.holdController,
                  builder: (_, _) => SizedBox(
                    width: size.w,
                    height: size.w,
                    child: CircularProgressIndicator(
                      value: widget.holdController.value,
                      strokeWidth: ringStroke.w,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                ),

              // ── Main Button Surface ───────────────────────────────────────
              Container(
                width: (size - 24).w,
                height: (size - 24).w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: widget.sosActive
                        ? [Colors.red.shade400, Colors.red.shade700]
                        : [const Color(0xFFFF4B4B), const Color(0xFFC41E3A)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(
                        alpha: widget.sosActive ? 0.3 : 0.5,
                      ),
                      blurRadius: 24,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.2),
                      blurRadius: 0,
                      spreadRadius: -4,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: widget.isLoading
                    ? Center(
                        child: SizedBox(
                          width: 40.w,
                          height: 40.w,
                          child: const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 4,
                          ),
                        ),
                      )
                    : widget.isHolding
                        ? SosHoldingContent(countdown: widget.countdown)
                        : SosIdleContent(sosActive: widget.sosActive),
              ),
            ],
          ),
        ),
      ),
    );

    return disc;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SOS Button inner content — holding state
// ─────────────────────────────────────────────────────────────────────────────

class SosHoldingContent extends StatelessWidget {
  final int countdown;
  const SosHoldingContent({super.key, required this.countdown});

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
            fontSize: 15.sp,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'sos_hold_seconds'.tr(namedArgs: {'n': '$countdown'}),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 13.sp,
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
  const SosIdleContent({super.key, required this.sosActive});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'sos_title'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 48.sp,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 4,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          sosActive ? 'sos_active_text'.tr() : 'sos_hold_label'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14.sp,
            fontWeight: FontWeight.w800,
            color: Colors.white.withValues(alpha: 0.8),
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}
