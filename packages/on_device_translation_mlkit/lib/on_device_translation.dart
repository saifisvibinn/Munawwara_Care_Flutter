import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart'
    as mlkit;

class TranslateLanguage {
  final String bcpCode;
  final String name;
  final mlkit.TranslateLanguage _language;

  const TranslateLanguage._(this.bcpCode, this.name, this._language);

  static final arabic = TranslateLanguage._(
    'ar',
    'Arabic',
    mlkit.TranslateLanguage.arabic,
  );
  static final english = TranslateLanguage._(
    'en',
    'English',
    mlkit.TranslateLanguage.english,
  );
  static final urdu = TranslateLanguage._(
    'ur',
    'Urdu',
    mlkit.TranslateLanguage.urdu,
  );
  static final turkish = TranslateLanguage._(
    'tr',
    'Turkish',
    mlkit.TranslateLanguage.turkish,
  );
  static final indonesian = TranslateLanguage._(
    'id',
    'Indonesian',
    mlkit.TranslateLanguage.indonesian,
  );
  static final french = TranslateLanguage._(
    'fr',
    'French',
    mlkit.TranslateLanguage.french,
  );
  static final persian = TranslateLanguage._(
    'fa',
    'Persian',
    mlkit.TranslateLanguage.persian,
  );
  static final malay = TranslateLanguage._(
    'ms',
    'Malay',
    mlkit.TranslateLanguage.malay,
  );

  mlkit.TranslateLanguage get mlkitLanguage => _language;
}

TranslateLanguage mapCodeToTranslateLanguage(String code) {
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

class OnDeviceTranslationModelManager {
  final mlkit.OnDeviceTranslatorModelManager _manager =
      mlkit.OnDeviceTranslatorModelManager();

  Future<bool> isModelDownloaded(String bcpCode) =>
      _manager.isModelDownloaded(bcpCode);

  Future<bool> downloadModel(String bcpCode) => _manager.downloadModel(bcpCode);
}

class OnDeviceTranslator {
  OnDeviceTranslator({
    required TranslateLanguage sourceLanguage,
    required TranslateLanguage targetLanguage,
  }) : _translator = mlkit.OnDeviceTranslator(
          sourceLanguage: sourceLanguage.mlkitLanguage,
          targetLanguage: targetLanguage.mlkitLanguage,
        );

  final mlkit.OnDeviceTranslator _translator;

  Future<String> translateText(String text) => _translator.translateText(text);

  Future<void> close() => _translator.close();
}

class OnDeviceLanguageIdentifier {
  OnDeviceLanguageIdentifier({double confidenceThreshold = 0.5})
      : _identifier = LanguageIdentifier(
          confidenceThreshold: confidenceThreshold,
        );

  final LanguageIdentifier _identifier;

  Future<String> identifyLanguage(String text) =>
      _identifier.identifyLanguage(text);

  Future<void> close() => _identifier.close();
}
