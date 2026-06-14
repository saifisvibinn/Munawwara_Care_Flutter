import '../env/app_env.dart';
import '../env/dotenv_safe.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';

/// Verify required and optional environment variables and
/// print warnings or throw for missing required keys.
Future<void> verifyEnv() async {
  final requiredKeys = <String>['API_BASE_URL'];

  final missingRequired = requiredKeys.where((k) {
    if (k == 'API_BASE_URL') {
      return resolvedApiBaseUrl.isEmpty;
    }
    return envValue(k, '').isEmpty;
  }).toList();
  final missingOptional = <String>[
    if (agoraAppId.isEmpty) 'AGORA_APP_ID',
    if (googleMapsApiKey.isEmpty) 'GOOGLE_MAPS_API_KEY',
    if (ummahApiKey.isEmpty) 'UMMAH_API_KEY',
  ];

  if (missingRequired.isNotEmpty) {
    final msg =
        'Missing API_BASE_URL: set it in .env or pass '
        '--dart-define=API_BASE_URL=https://your-api.example.com/api '
        '(or --dart-define-from-file=.env)';
    // Fail-fast so developers notice immediately when a critical value is missing.
    throw Exception(msg);
  }

  if (missingOptional.isNotEmpty) {
    // Log a friendly warning to remind developers to fill optional integrations.
    AppLogger.w('Missing optional .env keys: ${missingOptional.join(', ')}');
  }

  final socketExplicit = dotenvOptional('SOCKET_BASE_URL');
  if (socketExplicit == null || socketExplicit.isEmpty) {
    AppLogger.w(
      '[Env] SOCKET_BASE_URL unset — using socketOrigin=${ApiService.socketOrigin} '
      '(must support Socket.IO for call-offer signaling)',
    );
  }

  _warnIfPrivateNetworkBackend(resolvedApiBaseUrl, label: 'API_BASE_URL');
  if (socketExplicit != null && socketExplicit.isNotEmpty) {
    _warnIfPrivateNetworkBackend(socketExplicit, label: 'SOCKET_BASE_URL');
  }
}

/// LAN / emulator hosts are unreachable off the local network — calls fail on 4G.
void _warnIfPrivateNetworkBackend(String url, {required String label}) {
  final lower = url.toLowerCase();
  final isPrivate = lower.contains('192.168.') ||
      lower.contains('10.0.2.2') ||
      lower.contains('localhost') ||
      lower.contains('127.0.0.1') ||
      RegExp(r'http://10\.\d+\.\d+').hasMatch(lower);
  if (!isPrivate) return;
  AppLogger.w(
    '[Env] $label points at a private/dev host ($url). '
    'API, Socket.IO signaling, and call tokens will not work off Wi‑Fi. '
    'Use production HTTPS for Play/QA builds. See docs/voice-calls-networking.md',
  );
}
