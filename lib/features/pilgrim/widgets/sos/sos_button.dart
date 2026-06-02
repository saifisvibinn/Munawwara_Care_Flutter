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
    final double size = widget.size;
    final double ringStroke = (size * 0.042).clamp(4.0, 8.0);

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

              // ── Main Button Surface (solid red, thin white ring — design mock) ──
              Container(
                width: size.w,
                height: size.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.sosActive
                      ? const Color(0xFFD32F2F)
                      : const Color(0xFFE02020),
                  border: Border.all(
                    color: Colors.white,
                    width: 2.5.w,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE02020).withValues(
                        alpha: widget.sosActive ? 0.32 : 0.42,
                      ),
                      blurRadius: 28,
                      spreadRadius: 6,
                    ),
                    BoxShadow(
                      color: const Color(0xFFE02020).withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
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
                    : widget.isHolding
                        ? SosHoldingContent(countdown: widget.countdown, size: size)
                        : SosIdleContent(sosActive: widget.sosActive, size: size),
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
