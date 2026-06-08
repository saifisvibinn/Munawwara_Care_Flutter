import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';

enum TranslationStatus {
  idle,
  downloading,
  listening,
  translating,
  done,
  error,
}

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

class LiveTranslateState {
  final TranslationStatus status;
  final String fromLang; // 'ar', 'en', 'ur', 'tr', 'id', 'fr'
  final String toLang;   // 'ar', 'en', 'ur', 'tr', 'id', 'fr'
  final String inputText;
  final String translatedText;
  final String? errorMessage;
  final bool isSourceModelDownloaded;
  final bool isTargetModelDownloaded;
  final bool requiresWifiConfirmation;
  final bool isSpeechAvailable;
  final bool isSpeechSupportedForLanguage;
  final List<RecentTranslation> recents;
  final int downloadProgress;

  const LiveTranslateState({
    required this.status,
    required this.fromLang,
    required this.toLang,
    required this.inputText,
    required this.translatedText,
    this.errorMessage,
    required this.isSourceModelDownloaded,
    required this.isTargetModelDownloaded,
    required this.requiresWifiConfirmation,
    required this.isSpeechAvailable,
    required this.isSpeechSupportedForLanguage,
    required this.recents,
    required this.downloadProgress,
  });

  LiveTranslateState copyWith({
    TranslationStatus? status,
    String? fromLang,
    String? toLang,
    String? inputText,
    String? translatedText,
    String? errorMessage,
    bool? isSourceModelDownloaded,
    bool? isTargetModelDownloaded,
    bool? requiresWifiConfirmation,
    bool? isSpeechAvailable,
    bool? isSpeechSupportedForLanguage,
    List<RecentTranslation>? recents,
    int? downloadProgress,
  }) {
    return LiveTranslateState(
      status: status ?? this.status,
      fromLang: fromLang ?? this.fromLang,
      toLang: toLang ?? this.toLang,
      inputText: inputText ?? this.inputText,
      translatedText: translatedText ?? this.translatedText,
      errorMessage: errorMessage ?? this.errorMessage,
      isSourceModelDownloaded: isSourceModelDownloaded ?? this.isSourceModelDownloaded,
      isTargetModelDownloaded: isTargetModelDownloaded ?? this.isTargetModelDownloaded,
      requiresWifiConfirmation: requiresWifiConfirmation ?? this.requiresWifiConfirmation,
      isSpeechAvailable: isSpeechAvailable ?? this.isSpeechAvailable,
      isSpeechSupportedForLanguage: isSpeechSupportedForLanguage ?? this.isSpeechSupportedForLanguage,
      recents: recents ?? this.recents,
      downloadProgress: downloadProgress ?? this.downloadProgress,
    );
  }
}

TranslateLanguage _mapCodeToTranslateLanguage(String code) {
  switch (code) {
    case 'ar':
      return TranslateLanguage.arabic;
    case 'en':
      return TranslateLanguage.english;
    case 'ur':
      return TranslateLanguage.urdu;
    case 'tr':
      return TranslateLanguage.turkish;
    case 'id':
      return TranslateLanguage.indonesian;
    case 'fr':
      return TranslateLanguage.french;
    case 'fa':
      return TranslateLanguage.persian;
    case 'ms':
      return TranslateLanguage.malay;
    default:
      return TranslateLanguage.english;
  }
}

class LiveTranslateNotifier extends Notifier<LiveTranslateState> {
  final OnDeviceTranslatorModelManager _modelManager = OnDeviceTranslatorModelManager();
  final SpeechToText _speech = SpeechToText();
  List<LocaleName> _speechLocales = [];
  bool _speechInitialized = false;

  @override
  LiveTranslateState build() {
    Future.microtask(() => _initAndCheckStatus());
    
    return const LiveTranslateState(
      status: TranslationStatus.idle,
      fromLang: 'en',
      toLang: 'ar',
      inputText: '',
      translatedText: '',
      isSourceModelDownloaded: false,
      isTargetModelDownloaded: false,
      requiresWifiConfirmation: false,
      isSpeechAvailable: false,
      isSpeechSupportedForLanguage: true,
      recents: [
        RecentTranslation(
          text: "Where is the nearest medical clinic?",
          translation: "أين تقع أقرب عيادة طبية؟",
          fromLang: "en",
          toLang: "ar",
        ),
        RecentTranslation(
          text: "Thank you very much",
          translation: "شكرًا جزيلًا لك",
          fromLang: "en",
          toLang: "ar",
        ),
      ],
      downloadProgress: 0,
    );
  }

  Future<void> _initAndCheckStatus() async {
    await checkModelStatus();
    await _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        options: [SpeechToText.androidNoBluetooth],
        onError: (err) {
          debugPrint("Speech recognition error: ${err.errorMsg}");
        },
        onStatus: (status) {
          debugPrint("Speech recognition status update: $status");
        },
      );
      if (available) {
        _speechInitialized = true;
        _speechLocales = await _speech.locales();
        final supported = _checkSpeechSupportForLanguage(state.fromLang, _speechLocales);
        state = state.copyWith(
          isSpeechAvailable: true,
          isSpeechSupportedForLanguage: supported,
        );
      } else {
        state = state.copyWith(
          isSpeechAvailable: false,
          isSpeechSupportedForLanguage: false,
        );
      }
    } catch (e) {
      debugPrint("Error initializing speech: $e");
      state = state.copyWith(
        isSpeechAvailable: false,
        isSpeechSupportedForLanguage: false,
      );
    }
  }

  Future<void> checkModelStatus() async {
    try {
      final sourceLang = _mapCodeToTranslateLanguage(state.fromLang);
      final targetLang = _mapCodeToTranslateLanguage(state.toLang);
      final sourceDownloaded = await _modelManager.isModelDownloaded(sourceLang.bcpCode);
      final targetDownloaded = await _modelManager.isModelDownloaded(targetLang.bcpCode);
      state = state.copyWith(
        isSourceModelDownloaded: sourceDownloaded,
        isTargetModelDownloaded: targetDownloaded,
      );
    } catch (e) {
      state = state.copyWith(
        status: TranslationStatus.error,
        errorMessage: "Error checking models: $e",
      );
    }
  }

  bool _checkSpeechSupportForLanguage(String code, List<LocaleName> availableLocales) {
    return availableLocales.any((locale) =>
        locale.localeId.toLowerCase().startsWith(code.toLowerCase()));
  }

  String _mapCodeToSpeechLocale(String code, List<LocaleName> availableLocales) {
    for (final locale in availableLocales) {
      if (locale.localeId.toLowerCase() == code.toLowerCase()) {
        return locale.localeId;
      }
    }
    for (final locale in availableLocales) {
      if (locale.localeId.toLowerCase().startsWith('${code.toLowerCase()}_') ||
          locale.localeId.toLowerCase().startsWith('${code.toLowerCase()}-')) {
        return locale.localeId;
      }
    }
    return code;
  }

  Future<void> swapLanguages() async {
    final oldFrom = state.fromLang;
    final oldTo = state.toLang;
    final oldInput = state.inputText;
    final oldTranslated = state.translatedText;

    state = state.copyWith(
      fromLang: oldTo,
      toLang: oldFrom,
      inputText: oldTranslated,
      translatedText: oldInput,
      errorMessage: null,
    );

    await checkModelStatus();
    if (_speechInitialized) {
      final supported = _checkSpeechSupportForLanguage(state.fromLang, _speechLocales);
      state = state.copyWith(isSpeechSupportedForLanguage: supported);
    }
  }

  Future<void> setSourceLanguage(String code) async {
    state = state.copyWith(
      fromLang: code,
      inputText: '',
      translatedText: '',
      errorMessage: null,
    );
    await checkModelStatus();
    if (_speechInitialized) {
      final supported = _checkSpeechSupportForLanguage(state.fromLang, _speechLocales);
      state = state.copyWith(isSpeechSupportedForLanguage: supported);
    }
  }

  Future<void> setTargetLanguage(String code) async {
    state = state.copyWith(
      toLang: code,
      inputText: '',
      translatedText: '',
      errorMessage: null,
    );
    await checkModelStatus();
  }

  Future<void> startDownload({bool forceCellular = false}) async {
    state = state.copyWith(
      status: TranslationStatus.downloading,
      requiresWifiConfirmation: false,
      errorMessage: null,
      downloadProgress: 0,
    );

    Timer? progressTimer;
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        state = state.copyWith(
          status: TranslationStatus.error,
          errorMessage: "No internet connection. Internet is required to download translation models.",
        );
        return;
      }

      final isOnMobileData = connectivityResult.contains(ConnectivityResult.mobile);
      if (isOnMobileData && !forceCellular) {
        state = state.copyWith(
          status: TranslationStatus.idle,
          requiresWifiConfirmation: true,
        );
        return;
      }

      // Start a simulated progress timer
      int currentProgress = 0;
      progressTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
        if (currentProgress < 95) {
          currentProgress += (1 + (95 - currentProgress) ~/ 12).toInt();
          if (currentProgress > 95) currentProgress = 95;
          state = state.copyWith(downloadProgress: currentProgress);
        } else {
          timer.cancel();
        }
      });

      final sourceLang = _mapCodeToTranslateLanguage(state.fromLang);
      final targetLang = _mapCodeToTranslateLanguage(state.toLang);

      if (!state.isSourceModelDownloaded) {
        final success = await _modelManager.downloadModel(sourceLang.bcpCode);
        if (!success) throw Exception("Failed to download ${sourceLang.name} model");
      }

      if (!state.isTargetModelDownloaded) {
        final success = await _modelManager.downloadModel(targetLang.bcpCode);
        if (!success) throw Exception("Failed to download ${targetLang.name} model");
      }

      await checkModelStatus();
      state = state.copyWith(
        status: TranslationStatus.idle,
        downloadProgress: 100,
      );
    } catch (e) {
      state = state.copyWith(
        status: TranslationStatus.error,
        errorMessage: "Download failed. Please check storage space or internet: $e",
      );
    } finally {
      progressTimer?.cancel();
    }
  }

  void cancelWifiConfirmation() {
    state = state.copyWith(requiresWifiConfirmation: false);
  }

  void clearText() {
    state = state.copyWith(
      inputText: '',
      translatedText: '',
      status: TranslationStatus.idle,
      errorMessage: null,
    );
  }

  void loadRecent(RecentTranslation item) {
    state = state.copyWith(
      fromLang: item.fromLang,
      toLang: item.toLang,
      inputText: item.text,
      translatedText: item.translation,
      errorMessage: null,
    );
    checkModelStatus();
  }

  Future<void> translateText(String text) async {
    if (text.trim().isEmpty) return;

    state = state.copyWith(
      status: TranslationStatus.translating,
      inputText: text,
    );

    OnDeviceTranslator? translator;
    LanguageIdentifier? identifier;
    try {
      final sourceLang = _mapCodeToTranslateLanguage(state.fromLang);
      final targetLang = _mapCodeToTranslateLanguage(state.toLang);

      final sourceDownloaded = await _modelManager.isModelDownloaded(sourceLang.bcpCode);
      final targetDownloaded = await _modelManager.isModelDownloaded(targetLang.bcpCode);

      if (!sourceDownloaded || !targetDownloaded) {
        state = state.copyWith(
          status: TranslationStatus.error,
          errorMessage: "Translation models not downloaded. Please download models first.",
        );
        return;
      }

      identifier = LanguageIdentifier(confidenceThreshold: 0.5);
      final langCode = await identifier.identifyLanguage(text);
      debugPrint("Language Identifier matched input to: $langCode");

      translator = OnDeviceTranslator(
        sourceLanguage: sourceLang,
        targetLanguage: targetLang,
      );

      final translation = await translator.translateText(text);

      final newRecent = RecentTranslation(
        text: text,
        translation: translation,
        fromLang: state.fromLang,
        toLang: state.toLang,
      );

      // Avoid duplicate recent entries
      final updatedRecents = List<RecentTranslation>.from(state.recents)
        ..removeWhere((r) => r.text.trim().toLowerCase() == text.trim().toLowerCase() && r.fromLang == state.fromLang && r.toLang == state.toLang)
        ..insert(0, newRecent);

      state = state.copyWith(
        status: TranslationStatus.done,
        translatedText: translation,
        recents: updatedRecents.take(15).toList(),
      );
    } catch (e) {
      state = state.copyWith(
        status: TranslationStatus.error,
        errorMessage: "Translation failed: $e",
      );
    } finally {
      translator?.close();
      identifier?.close();
    }
  }

  Future<void> requestMicPermissionAndListen() async {
    final status = await Permission.microphone.status;
    
    if (status.isDenied) {
      final requestStatus = await Permission.microphone.request();
      if (!requestStatus.isGranted) {
        state = state.copyWith(
          status: TranslationStatus.error,
          errorMessage: "Microphone permission is required for speech recognition. Please grant permissions.",
        );
        return;
      }
    }

    if (status.isPermanentlyDenied) {
      state = state.copyWith(
        status: TranslationStatus.error,
        errorMessage: "Microphone permission is permanently denied. Please open app settings to enable it.",
      );
      return;
    }

    await startListening();
  }

  Future<void> startListening() async {
    if (!_speechInitialized) {
      await _initSpeech();
    }

    if (!state.isSpeechAvailable) {
      state = state.copyWith(
        status: TranslationStatus.error,
        errorMessage: "Speech recognition is not available or disabled on this device.",
      );
      return;
    }

    if (!state.isSpeechSupportedForLanguage) {
      state = state.copyWith(
        status: TranslationStatus.error,
        errorMessage: "Speech recognition is not supported on this device for ${state.fromLang.toUpperCase()}.",
      );
      return;
    }

    state = state.copyWith(
      status: TranslationStatus.listening,
      inputText: '',
      translatedText: '',
      errorMessage: null,
    );

    final localeId = _mapCodeToSpeechLocale(state.fromLang, _speechLocales);

    try {
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          partialResults: true,
          localeId: localeId,
        ),
        onResult: (result) {
          state = state.copyWith(
            inputText: result.recognizedWords,
          );
          if (result.finalResult) {
            final finalWords = result.recognizedWords;
            if (finalWords.trim().isNotEmpty) {
              translateText(finalWords);
            } else {
              state = state.copyWith(
                status: TranslationStatus.error,
                errorMessage: "Could not detect speech, please try again",
              );
            }
          }
        },
      );
    } catch (e) {
      state = state.copyWith(
        status: TranslationStatus.error,
        errorMessage: "Speech recognition failed: $e",
      );
    }
  }

  Future<void> stopListening() async {
    if (state.status == TranslationStatus.listening) {
      await _speech.stop();
      if (state.inputText.trim().isNotEmpty) {
        translateText(state.inputText);
      } else {
        await Future.delayed(const Duration(milliseconds: 300));
        if (state.inputText.trim().isNotEmpty) {
          translateText(state.inputText);
        } else {
          state = state.copyWith(
            status: TranslationStatus.error,
            errorMessage: "Could not detect speech, please try again",
          );
        }
      }
    }
  }
  
  void openSettings() {
    openAppSettings();
  }
}

final liveTranslateProvider = NotifierProvider<LiveTranslateNotifier, LiveTranslateState>(
  LiveTranslateNotifier.new,
);
