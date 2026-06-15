import '../config/backend_config.dart';
import 'dotenv_safe.dart';

/// Compile-time integration keys (set via `--dart-define` or
/// `--dart-define-from-file=.env`).
const String kAgoraAppId = String.fromEnvironment('AGORA_APP_ID');
const String kUmmahApiKey = String.fromEnvironment('UMMAH_API_KEY');
const String kGoogleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

/// Resolves an env value: dart-define first, then loaded `.env`.
String envValue(String envKey, String fromDefine) {
  final defined = fromDefine.trim();
  if (defined.isNotEmpty) return defined;
  return dotenvOptional(envKey) ?? '';
}

String get agoraAppId => envValue('AGORA_APP_ID', kAgoraAppId);

String get ummahApiKey => envValue('UMMAH_API_KEY', kUmmahApiKey);

String get googleMapsApiKey =>
    envValue('GOOGLE_MAPS_API_KEY', kGoogleMapsApiKey);

/// Same resolution as [ApiService.baseUrl] for env validation.
String get resolvedApiBaseUrl =>
    envValue('API_BASE_URL', kDefaultProductionApiBaseUrl);
