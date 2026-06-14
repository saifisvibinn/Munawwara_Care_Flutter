import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/config/app_locales.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass.dart';
import '../../../core/widgets/app_selection_field.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../../core/widgets/custom_dialog.dart';
import '../providers/live_translate_provider.dart';
import '../../../core/services/oem_settings_service.dart';

class LiveTranslateScreen extends ConsumerStatefulWidget {
  const LiveTranslateScreen({super.key});

  @override
  ConsumerState<LiveTranslateScreen> createState() => _LiveTranslateScreenState();
}

class _LiveTranslateScreenState extends ConsumerState<LiveTranslateScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  late AnimationController _micPulseController;
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _micPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    _micPulseController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  String _getName(String code) {
    switch (code) {
      case 'en': return 'english';
      case 'ar': return 'arabic';
      case 'ur': return 'urdu';
      case 'tr': return 'turkish';
      case 'id': return 'indonesian';
      case 'fr': return 'french';
      case 'fa': return 'persian';
      case 'ms': return 'malay';
      default: return 'english';
    }
  }

  List<String> _getLanguagesToTry(String code) {
    switch (code.toLowerCase()) {
      case 'ar': return ['ar-SA', 'ar-EG', 'ar-AE', 'ar', 'ar-XA'];
      case 'ur': return ['ur-PK', 'ur-IN', 'ur'];
      case 'tr': return ['tr-TR', 'tr'];
      case 'id': return ['id-ID', 'id'];
      case 'fr': return ['fr-FR', 'fr-CA', 'fr'];
      case 'fa': return ['fa-IR', 'fa-AF', 'fa'];
      case 'ms': return ['ms-MY', 'ms-SG', 'ms'];
      case 'en': return ['en-US', 'en-GB', 'en'];
      default: return [code];
    }
  }

  bool _isRtlLang(String code) => AppLocales.isRtl(code);

  Future<void> _speak(String text, String langCode) async {
    if (text.isEmpty) return;
    try {
      // Configure TTS audio settings explicitly
      await _flutterTts.awaitSpeakCompletion(true);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setSpeechRate(0.45);
      await _flutterTts.setPitch(1.0);

      // Find the first available locale on the device
      final locales = _getLanguagesToTry(langCode);
      String? selectedLocale;
      for (final locale in locales) {
        final available = await _flutterTts.isLanguageAvailable(locale);
        if (available == 1 || available == true) {
          selectedLocale = locale;
          break;
        }
      }

      if (selectedLocale != null) {
        debugPrint("TTS selected locale: $selectedLocale");
        await _flutterTts.setLanguage(selectedLocale);
        await _flutterTts.speak(text);
        HapticFeedback.selectionClick();
      } else {
        debugPrint("TTS not available on device for: $langCode");
        if (mounted) {
          StandardSnackBar.show(
            context,
            message: "Voice package for ${'lang_${_getName(langCode)}'.tr().toUpperCase()} is not installed on this device. Please enable it in System Settings -> Text-to-Speech.",
            type: SnackBarType.warning,
            actionLabel: "Settings",
            onAction: () async {
              try {
                await OemSettingsService.openTtsSettings();
              } catch (e) {
                debugPrint("Failed to open TTS settings: $e");
              }
            },
          );
        }
      }
    } catch (e) {
      debugPrint("TTS error: $e");
    }
  }

  void _showWifiConfirmationDialog() async {
    final result = await StandardDialog.show<bool>(
      context: context,
      title: "Cellular Data Warning",
      content: "You are currently on cellular data. Downloading translation models (approx. 30MB each) may consume data. Do you want to proceed?",
      confirmText: "Download",
      cancelText: "Cancel",
    );
    
    if (result == true) {
      ref.read(liveTranslateProvider.notifier).startDownload(forceCellular: true);
    } else {
      ref.read(liveTranslateProvider.notifier).cancelWifiConfirmation();
    }
  }

  Widget _buildModelBadge(BuildContext context, String langName, bool isDownloaded, bool isDark) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: isDownloaded
            ? (isDark ? const Color(0xFF1E3A1E) : const Color(0xFFDCFCE7))
            : (isDark ? const Color(0xFF3B2F1A) : const Color(0xFFFEF3C7)),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isDownloaded
              ? (isDark ? Colors.green.shade800 : Colors.green.shade200)
              : (isDark ? Colors.amber.shade800 : Colors.amber.shade200),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDownloaded ? Icons.check_circle_outline_rounded : Icons.download_for_offline_rounded,
            size: 14.w,
            color: isDownloaded
                ? (isDark ? Colors.green.shade200 : Colors.green.shade700)
                : (isDark ? Colors.amber.shade200 : Colors.amber.shade700),
          ),
          SizedBox(width: 6.w),
          Text(
            langName,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w700,
              color: isDownloaded
                  ? (isDark ? Colors.green.shade200 : Colors.green.shade800)
                  : (isDark ? Colors.amber.shade200 : Colors.amber.shade800),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveTranslateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : const Color(0xFFF7F9FB);
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final inputCardBg = isDark ? AppColors.surfaceDark : AppColors.iconBgLight.withValues(alpha: 0.5);
    final textDarkColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final outlineColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : const Color(0xFFFFEDD5); // orange-100

    ref.listen<LiveTranslateState>(liveTranslateProvider, (previous, next) {
      if (next.status == TranslationStatus.listening) {
        _micPulseController.repeat();
      } else {
        _micPulseController.stop();
        _micPulseController.value = 0.0;
      }
      
      if (next.inputText != _inputController.text) {
        _inputController.text = next.inputText;
        _inputController.selection = TextSelection.fromPosition(
          TextPosition(offset: next.inputText.length),
        );
      }

      if (next.requiresWifiConfirmation && !(previous?.requiresWifiConfirmation ?? false)) {
        _showWifiConfirmationDialog();
      }
    });

    final modelsDownloaded = state.isSourceModelDownloaded && state.isTargetModelDownloaded;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: const Color(0xFFC2410C),
            size: 20.w,
          ),
        ),
        title: Text(
          'live_translate'.tr(),
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w800,
            color: const Color(0xFFC2410C),
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: AppScrollFadeOverlay(
          showTop: false,
          backgroundColor: isDark
              ? AppColors.backgroundDark
              : const Color(0xFFFFF7ED),
          child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Language Selector Card ──────────────────────────────────────
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
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
                    Expanded(
                      child: AppSelectionField<String>(
                        value: state.fromLang,
                        isDark: isDark,
                        style: AppSelectionStyle.minimal,
                        label: 'translate_from'.tr(),
                        sheetTitle: 'translate_from'.tr(),
                        options: AppLocales.liveTranslateLanguageCodes
                            .map(
                              (code) => AppSelectionOption(
                                value: code,
                                label: 'lang_${_getName(code)}'.tr(),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            ref
                                .read(liveTranslateProvider.notifier)
                                .setSourceLanguage(val);
                          }
                        },
                      ),
                    ),
                    SizedBox(width: 8.w),
                    GestureDetector(
                      onTap: () {
                        ref.read(liveTranslateProvider.notifier).swapLanguages();
                        HapticFeedback.lightImpact();
                      },
                      child: Container(
                        padding: EdgeInsets.all(10.w),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFEEF2F6),
                        ),
                        child: Icon(
                          Symbols.swap_horiz,
                          color: const Color(0xFFEA580C),
                          size: 20.w,
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: AppSelectionField<String>(
                        value: state.toLang,
                        isDark: isDark,
                        style: AppSelectionStyle.minimal,
                        label: 'translate_to'.tr(),
                        sheetTitle: 'translate_to'.tr(),
                        options: AppLocales.liveTranslateLanguageCodes
                            .map(
                              (code) => AppSelectionOption(
                                value: code,
                                label: 'lang_${_getName(code)}'.tr(),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            ref
                                .read(liveTranslateProvider.notifier)
                                .setTargetLanguage(val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16.h),

              // ── Listening Input Card ──────────────────────────────────────
              GestureDetector(
                onTap: () {
                  _inputFocusNode.requestFocus();
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 18.h),
                  constraints: BoxConstraints(minHeight: 120.h, maxHeight: 200.h),
                  decoration: BoxDecoration(
                    color: inputCardBg,
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
                              color: state.status == TranslationStatus.listening
                                  ? const Color(0xFFFEE2E2)
                                  : const Color(0xFFE0E7FF),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Text(
                              state.status == TranslationStatus.listening ? 'translate_listening'.tr() : 'translate_input_text'.tr(),
                              style: TextStyle(
                                fontSize: 9.sp,
                                fontWeight: FontWeight.w800,
                                color: state.status == TranslationStatus.listening ? Colors.red.shade700 : const Color(0xFF4F46E5),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              if (state.inputText.isNotEmpty || state.translatedText.isNotEmpty)
                                IconButton(
                                  onPressed: () {
                                    ref.read(liveTranslateProvider.notifier).clearText();
                                    _inputController.clear();
                                  },
                                  icon: Icon(
                                    Icons.clear_rounded,
                                    size: 18.w,
                                    color: Colors.red.shade600,
                                  ),
                                ),
                              IconButton(
                                onPressed: () {
                                  if (state.inputText.isNotEmpty) {
                                    Clipboard.setData(ClipboardData(text: state.inputText));
                                    StandardSnackBar.showSuccess(context, 'translate_copied'.tr());
                                  }
                                },
                                icon: Icon(
                                  Icons.copy_rounded,
                                  size: 18.w,
                                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: TextField(
                            controller: _inputController,
                            focusNode: _inputFocusNode,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textDirection: _isRtlLang(state.fromLang)
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            textAlign: _isRtlLang(state.fromLang)
                                ? TextAlign.right
                                : TextAlign.left,
                            onChanged: (text) {
                              ref.read(liveTranslateProvider.notifier).translateText(text);
                            },
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                              color: textDarkColor,
                              height: 1.35,
                            ),
                            decoration: InputDecoration(
                              hintText: "No input text yet".tr(),
                              hintStyle: TextStyle(
                                fontSize: 16.sp,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                              ),
                              filled: false,
                              border: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16.h),

              // ── Translation Display Card ──────────────────────────────────
              Container(
                padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 18.h),
                constraints: BoxConstraints(minHeight: 120.h, maxHeight: 200.h),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(24.r),
                  border: Border.all(color: outlineColor, width: 1.2),
                ),
                child: state.status == TranslationStatus.translating
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
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFFEA580C),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              IconButton(
                                onPressed: state.translatedText.isEmpty
                                    ? null
                                    : () => _speak(state.translatedText, state.toLang),
                                icon: Icon(
                                  Icons.volume_up_rounded,
                                  size: 20.w,
                                  color: state.translatedText.isEmpty
                                      ? Colors.grey
                                      : const Color(0xFFEA580C),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8.h),
                          Expanded(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Align(
                                alignment: _isRtlLang(state.toLang)
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Text(
                                  state.translatedText.isEmpty
                                      ? "No translation yet".tr()
                                      : state.translatedText,
                                  textDirection: _isRtlLang(state.toLang)
                                      ? TextDirection.rtl
                                      : TextDirection.ltr,
                                  style: TextStyle(
                                    fontSize: 20.sp,
                                    fontWeight: FontWeight.w800,
                                    color: state.translatedText.isEmpty
                                        ? (isDark ? Colors.white38 : const Color(0xFF94A3B8))
                                        : textDarkColor,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),

              SizedBox(height: 20.h),

              // ── Error / Info Display Banner ──────────────────────────────────
              if (state.errorMessage != null)
                Padding(
                  padding: EdgeInsets.only(bottom: 16.h),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF451A1A) : Colors.red.shade50.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(color: isDark ? Colors.red.shade900 : Colors.red.shade200, width: 1.2),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Text(
                            state.errorMessage!,
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.red.shade200 : Colors.red.shade800,
                            ),
                          ),
                        ),
                        if (state.errorMessage!.contains("permission"))
                          TextButton(
                            onPressed: () => ref.read(liveTranslateProvider.notifier).openSettings(),
                            child: Text(
                              "Settings".tr(),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // ── Speech unavailable Warning ──────────────────────────────
              if (modelsDownloaded && !state.isSpeechSupportedForLanguage)
                Padding(
                  padding: EdgeInsets.only(bottom: 16.h),
                  child: Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF3B2F1A) : Colors.amber.shade50.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(color: isDark ? Colors.amber.shade900 : Colors.amber.shade200, width: 1.2),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: Colors.amber.shade800),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Text(
                            "Speech input not supported on this device for ${state.fromLang.toUpperCase()}. Please type to translate.",
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Model Downloader Prompt / Speech mic control ───────────────
              if (!modelsDownloaded)
                Container(
                  padding: EdgeInsets.all(18.w),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(24.r),
                    border: Border.all(color: outlineColor, width: 1.2),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.download_for_offline_rounded,
                        color: const Color(0xFFEA580C),
                        size: 40.w,
                      ),
                      SizedBox(height: 12.h),
                      Text(
                        "Download Translation Models".tr(),
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w700,
                          color: textDarkColor,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        "To translate between these languages offline, we need to download the on-device language models (~30MB each).".tr(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: isDark ? Colors.white70 : const Color(0xFF64748B),
                        ),
                      ),
                      SizedBox(height: 14.h),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildModelBadge(context, 'lang_${_getName(state.fromLang)}'.tr(), state.isSourceModelDownloaded, isDark),
                          SizedBox(width: 8.w),
                          Icon(Icons.arrow_forward_rounded, size: 14.w, color: Colors.grey),
                          SizedBox(width: 8.w),
                          _buildModelBadge(context, 'lang_${_getName(state.toLang)}'.tr(), state.isTargetModelDownloaded, isDark),
                        ],
                      ),
                      SizedBox(height: 16.h),
                      state.status == TranslationStatus.downloading
                          ? Column(
                              children: [
                                SizedBox(
                                  width: 160.w,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4.r),
                                    child: LinearProgressIndicator(
                                      value: state.downloadProgress / 100.0,
                                      backgroundColor: isDark ? Colors.white12 : const Color(0xFFF1F5F9),
                                      color: const Color(0xFFEA580C),
                                      minHeight: 6.h,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 10.h),
                                Text(
                                  "${'Downloading models... Please wait'.tr()} (${state.downloadProgress}%)",
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFEA580C),
                                  ),
                                ),
                              ],
                            )
                          : ElevatedButton.icon(
                              onPressed: () {
                                ref.read(liveTranslateProvider.notifier).startDownload();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEA580C),
                                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16.r),
                                ),
                              ),
                              icon: const Icon(Icons.download_rounded, color: Colors.white),
                              label: Text(
                                "Download Now".tr(),
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                    ],
                  ),
                )
              else
                Column(
                  children: [
                    AnimatedBuilder(
                      animation: _micPulseController,
                      builder: (context, child) {
                        final val = _micPulseController.value;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            if (state.status == TranslationStatus.listening) ...[
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
                              onLongPressStart: (_) {
                                ref.read(liveTranslateProvider.notifier).requestMicPermissionAndListen();
                              },
                              onLongPressEnd: (_) {
                                ref.read(liveTranslateProvider.notifier).stopListening();
                              },
                              onLongPressCancel: () {
                                ref.read(liveTranslateProvider.notifier).stopListening();
                              },
                              onTap: () {
                                StandardSnackBar.showInfo(
                                  context,
                                  "Hold and speak, release to translate.",
                                );
                              },
                              child: Container(
                                width: 76.w,
                                height: 76.w,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: state.status == TranslationStatus.listening
                                      ? Colors.red.shade700
                                      : const Color(0xFF9A3412),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF9A3412).withValues(alpha: 0.35),
                                      blurRadius: 18,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  state.status == TranslationStatus.listening
                                      ? Icons.stop_rounded
                                      : Icons.mic_rounded,
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
                            : const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                      child: Text(
                        state.status == TranslationStatus.listening
                            ? 'translate_listening'.tr()
                            : 'translate_tap_to_speak'.tr(),
                        style: TextStyle(
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFC2410C),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              SizedBox(height: 24.h),

              // ── Recents Section ───────────────────────────────────────────
              if (state.recents.isNotEmpty) ...[
                Text(
                  'translate_recent'.tr(),
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 8.h),
                ...state.recents.map((item) => Container(
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
                                    fontSize: 13.5.sp,
                                    fontWeight: FontWeight.w700,
                                    color: textDarkColor,
                                  ),
                                ),
                                SizedBox(height: 3.h),
                                  Text(
                                    "${'lang_${_getName(item.fromLang)}'.tr()} ${'translate_to_connector'.tr()} ${'lang_${_getName(item.toLang)}'.tr()}",
                                    style: TextStyle(
                                    fontSize: 10.sp,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              ref.read(liveTranslateProvider.notifier).loadRecent(item);
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
              ],
              SizedBox(height: 18.h),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
