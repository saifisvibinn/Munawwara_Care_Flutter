import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/standard_snackbar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Recent Translation Model
// ─────────────────────────────────────────────────────────────────────────────

class RecentTranslation {
  final String text;
  final String translation;
  final String fromLang;
  final String toLang;

  const RecentTranslation({
    required this.text,
    required this.translation,
    required this.fromLang,
    required this.toLang,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Translate Screen (Full-page UI matching your mockup precisely)
// ─────────────────────────────────────────────────────────────────────────────

class LiveTranslateScreen extends StatefulWidget {
  final Future<String> Function(String text, String from, String to)? onTranslateApi;

  const LiveTranslateScreen({super.key, this.onTranslateApi});

  @override
  State<LiveTranslateScreen> createState() => _LiveTranslateScreenState();
}

class _LiveTranslateScreenState extends State<LiveTranslateScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  late AnimationController _micPulseController;

  // Language state
  String _fromLang = "lang_english";
  String _toLang = "lang_arabic";
  bool _initialized = false;

  // Translate interactive state
  bool _isListening = false;
  bool _isLoading = false;
  String _inputText = "";
  String _translationText = "";

  // Simulation step counter
  int _speechSimulationStep = 0;

  // Recent list
  final List<RecentTranslation> _recents = [
    const RecentTranslation(
      text: "As-salamu alaykum",
      translation: "وعليكم السلام",
      fromLang: "lang_english",
      toLang: "lang_arabic",
    ),
    const RecentTranslation(
      text: "Thank you very much",
      translation: "شكرًا جزيلًا لك",
      fromLang: "lang_english",
      toLang: "lang_arabic",
    ),
  ];

  @override
  void initState() {
    super.initState();
    _micPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _inputText = 'translate_mock_clinic_input'.tr();
      _translationText = 'translate_mock_clinic_output'.tr();
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _micPulseController.dispose();
    super.dispose();
  }

  // ── Swap Languages ─────────────────────────────────────────────────────────
  void _swapLanguages() {
    setState(() {
      final tmp = _fromLang;
      _fromLang = _toLang;
      _toLang = tmp;

      // Swap contents if valid
      final tmpText = _inputText;
      _inputText = _translationText;
      _translationText = tmpText;
    });
    HapticFeedback.lightImpact();
  }

  // ── TTS Sound Playback ─────────────────────────────────────────────────────
  void _playTtsAudio() {
    StandardSnackBar.showInfo(context, 'translate_playing_audio'.tr());
    HapticFeedback.selectionClick();
  }

  // ── Copy text to Clipboard ─────────────────────────────────────────────────
  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _inputText));
    StandardSnackBar.showSuccess(context, 'translate_copied'.tr());
  }

  // ── Trigger API / Simulated Translate ──────────────────────────────────────
  Future<void> _handleTranslation(String text) async {
    if (text.trim().isEmpty) return;
    _inputController.clear();
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _inputText = text;
    });

    try {
      if (widget.onTranslateApi != null) {
        // Real API Callback
        final result = await widget.onTranslateApi!(text, _fromLang, _toLang);
        if (mounted) {
          setState(() {
            _translationText = result;
          });
        }
      } else {
        // Simulated Translation Engine
        await Future<void>.delayed(const Duration(milliseconds: 1000));
        
        final String mockResult;
        final cleanText = text.trim().toLowerCase();
        
        if (cleanText.contains("hotel")) {
          mockResult = "أين يقع الفندق؟";
        } else if (cleanText.contains("bus")) {
          mockResult = "أين تقع محطة الحافلات؟";
        } else if (cleanText.contains("water")) {
          mockResult = "أريد بعض الماء من فضلك.";
        } else if (cleanText.contains("thank")) {
          mockResult = "شكرًا جزيلًا";
        } else if (cleanText.contains("doctor") || cleanText.contains("medical")) {
          mockResult = "أنا بحاجة إلى طبيب.";
        } else {
          mockResult = "[Simulated Translation to Arabic]";
        }

        if (mounted) {
          setState(() {
            _translationText = mockResult;
            _recents.insert(
              0,
              RecentTranslation(
                text: text,
                translation: mockResult,
                fromLang: _fromLang,
                toLang: _toLang,
              ),
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        StandardSnackBar.showError(context, 'translate_error'.tr(args: [e.toString()]));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ── Speech-to-Text Listening Simulator ─────────────────────────────────────
  void _toggleListening() {
    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  void _startListening() {
    HapticFeedback.heavyImpact();
    _micPulseController.repeat();
    setState(() {
      _isListening = true;
      _inputText = 'translate_listening'.tr();
      _translationText = "";
    });

    // Simulated speech generation pipeline
    Timer(const Duration(milliseconds: 1500), () {
      if (!mounted || !_isListening) return;
      setState(() {
        _inputText = 'translate_detecting'.tr();
      });
    });

    Timer(const Duration(milliseconds: 3200), () {
      if (!mounted || !_isListening) return;
      
      final String simulatedPhrase;
      final String simulatedTranslation;

      if (_speechSimulationStep == 0) {
        simulatedPhrase = 'translate_mock_excuse_me'.tr();
        simulatedTranslation = 'translate_mock_excuse_me'.tr();
        _speechSimulationStep = 1;
      } else {
        simulatedPhrase = 'translate_mock_pharmacy'.tr();
        simulatedTranslation = 'translate_mock_pharmacy'.tr();
        _speechSimulationStep = 0;
      }

      setState(() {
        _inputText = '"$simulatedPhrase"';
        _translationText = simulatedTranslation;
        _recents.insert(
          0,
          RecentTranslation(
            text: simulatedPhrase,
            translation: simulatedTranslation,
            fromLang: _fromLang,
            toLang: _toLang,
          ),
        );
      });
      _stopListening();
      HapticFeedback.mediumImpact();
    });
  }

  void _stopListening() {
    _micPulseController.stop();
    _micPulseController.value = 0.0;
    setState(() {
      _isListening = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : const Color(0xFFF7F9FB);
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final textDarkColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final outlineColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : const Color(0xFFFFEDD5); // Tailwind border-orange-100

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: const Color(0xFFC2410C), // Deep orange-700
            size: 20.w,
          ),
        ),
        title: Text(
          'live_translate'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 18.sp,
            fontWeight: FontWeight.w800,
            color: const Color(0xFFC2410C),
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Language Selector Card ──────────────────────────────────────
              Container(
                padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 12.h),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(24.r),
                  border: Border.all(color: outlineColor, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // From Lang
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'translate_from'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF94A3B8),
                              letterSpacing: 0.5,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            _fromLang.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w700,
                              color: textDarkColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Swap Button
                    GestureDetector(
                      onTap: _swapLanguages,
                      child: Container(
                        padding: EdgeInsets.all(10.w),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFEEF2F6), // Indigo tint
                        ),
                        child: Icon(
                          Symbols.swap_horiz,
                          color: const Color(0xFFEA580C),
                          size: 20.w,
                        ),
                      ),
                    ),

                    // To Lang
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'translate_to'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF94A3B8),
                              letterSpacing: 0.5,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            _toLang.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w700,
                              color: textDarkColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16.h),

              // ── Listening Input Card ──────────────────────────────────────
              Container(
                padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 18.h),
                constraints: BoxConstraints(minHeight: 110.h),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(24.r),
                  border: Border.all(color: outlineColor, width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: _isListening
                                ? const Color(0xFFFEE2E2) // Red tint
                                : const Color(0xFFE0E7FF), // Indigo tint
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Text(
                            _isListening ? 'translate_listening'.tr() : 'translate_input_text'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 9.sp,
                              fontWeight: FontWeight.w800,
                              color: _isListening ? Colors.red.shade700 : const Color(0xFF4F46E5),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _copyToClipboard,
                          icon: Icon(
                            Icons.copy_rounded,
                            size: 18.w,
                            color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      _inputText,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 16.sp,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                        color: textDarkColor,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16.h),

              // ── Translation Display Card ──────────────────────────────────
              Container(
                padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 18.h),
                constraints: BoxConstraints(minHeight: 110.h),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(24.r),
                  border: Border.all(color: outlineColor, width: 1.2),
                ),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 3))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'translate_translation'.tr(),
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFFEA580C),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              IconButton(
                                onPressed: _translationText.isEmpty ? null : _playTtsAudio,
                                icon: Icon(
                                  Icons.volume_up_rounded,
                                  size: 20.w,
                                  color: const Color(0xFFEA580C),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            _translationText,
                            textAlign: _toLang == "lang_arabic" ? TextAlign.right : TextAlign.left,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 20.sp,
                              fontWeight: FontWeight.w800,
                              color: textDarkColor,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
              ),
              SizedBox(height: 16.h),

              // ── Input Type Field Bar ────────────────────────────────────────
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        onSubmitted: _handleTranslation,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13.5.sp,
                          color: textDarkColor,
                        ),
                        decoration: InputDecoration(
                          hintText: 'translate_hint'.tr(),
                          hintStyle: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13.5.sp,
                            color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _handleTranslation(_inputController.text),
                      icon: Icon(
                        Icons.send_rounded,
                        color: const Color(0xFFEA580C),
                        size: 18.w,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24.h),

              // ── Recent Section Header ──────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'translate_recent'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: Text(
                      'translate_view_all'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 10.5.sp,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFEA580C),
                      ),
                    ),
                  ),
                ],
              ),

              // ── Recents List ────────────────────────────────────────────────
              ..._recents.map((item) => Container(
                    margin: EdgeInsets.only(bottom: 10.h),
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFE2E8F0),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 13.5.sp,
                                  fontWeight: FontWeight.w700,
                                  color: textDarkColor,
                                ),
                              ),
                              SizedBox(height: 3.h),
                              Text(
                                '${item.fromLang.tr()} to ${item.toLang.tr()}',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 10.sp,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _inputText = item.text;
                              _translationText = item.translation;
                            });
                          },
                          icon: Icon(
                            Symbols.history,
                            size: 20.w,
                            color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  )),

              SizedBox(height: 24.h),

              // ── Centered Speech Tap-to-Speak Control ────────────────────────
              Column(
                children: [
                  AnimatedBuilder(
                    animation: _micPulseController,
                    builder: (context, child) {
                      final val = _micPulseController.value;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_isListening) ...[
                            // Mic outer pulsing wave
                            Opacity(
                              opacity: (1.0 - val) * 0.16,
                              child: Transform.scale(
                                scale: 1.0 + (val * 0.8),
                                child: Container(
                                  width: 76.w,
                                  height: 76.w,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFFEA580C),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          GestureDetector(
                            onTap: _toggleListening,
                            child: Container(
                              width: 76.w,
                              height: 76.w,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF9A3412), // Brownish Orange
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF9A3412).withValues(alpha: 0.35),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                                color: Colors.white,
                                size: 30.w,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  SizedBox(height: 10.h),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFFFF7ED), // Soft orange tint
                      borderRadius: BorderRadius.circular(20.r),
                    ),
                    child: Text(
                      _isListening ? 'translate_tap_to_stop'.tr() : 'translate_tap_to_speak'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFC2410C),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18.h),
            ],
          ),
        ),
      ),
    );
  }
}
