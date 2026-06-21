class TranslateLanguage {
  final String bcpCode;
  final String name;

  const TranslateLanguage._(this.bcpCode, this.name);

  static const arabic = TranslateLanguage._('ar', 'Arabic');
  static const english = TranslateLanguage._('en', 'English');
  static const urdu = TranslateLanguage._('ur', 'Urdu');
  static const turkish = TranslateLanguage._('tr', 'Turkish');
  static const indonesian = TranslateLanguage._('id', 'Indonesian');
  static const french = TranslateLanguage._('fr', 'French');
  static const persian = TranslateLanguage._('fa', 'Persian');
  static const malay = TranslateLanguage._('ms', 'Malay');
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
  static const String unavailableMessage =
      'On-device translation is unavailable on the iOS simulator. '
      'Use a physical device for ML Kit translation.';

  Future<bool> isModelDownloaded(String bcpCode) async => false;

  Future<bool> downloadModel(String bcpCode) async {
    throw UnsupportedError(unavailableMessage);
  }
}

class OnDeviceTranslator {
  OnDeviceTranslator({
    required TranslateLanguage sourceLanguage,
    required TranslateLanguage targetLanguage,
  });

  Future<String> translateText(String text) async {
    throw UnsupportedError(
      OnDeviceTranslationModelManager.unavailableMessage,
    );
  }

  Future<void> close() async {}
}

class OnDeviceLanguageIdentifier {
  OnDeviceLanguageIdentifier({double confidenceThreshold = 0.5});

  Future<String> identifyLanguage(String text) async => 'und';

  Future<void> close() async {}
}
