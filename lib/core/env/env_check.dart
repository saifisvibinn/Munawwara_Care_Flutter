import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../services/api_service.dart';
import '../utils/app_logger.dart';

/// Verify required and optional environment variables and
/// print warnings or throw for missing required keys.
Future<void> verifyEnv() async {
  final requiredKeys = <String>['API_BASE_URL'];
  final optionalKeys = <String>[
    'AGORA_APP_ID',
    'GOOGLE_MAPS_API_KEY',
  ];

  final missingRequired = requiredKeys.where((k) {
    if (k == 'API_BASE_URL') {
      return ApiService.baseUrl.isEmpty;
    }
    return (dotenv.env[k] ?? '').trim().isEmpty;
  }).toList();
  final missingOptional = optionalKeys
      .where((k) => (dotenv.env[k] ?? '').trim().isEmpty)
      .toList();

  if (missingRequired.isNotEmpty) {
    final msg = 'Missing required .env keys: ${missingRequired.join(', ')}';
    // Fail-fast so developers notice immediately when a critical value is missing.
    throw Exception(msg);
  }

  if (missingOptional.isNotEmpty) {
    // Log a friendly warning to remind developers to fill optional integrations.
    AppLogger.w('Missing optional .env keys: ${missingOptional.join(', ')}');
  }

  final socketExplicit = dotenv.env['SOCKET_BASE_URL']?.trim();
  if (socketExplicit == null || socketExplicit.isEmpty) {
    AppLogger.w(
      '[Env] SOCKET_BASE_URL unset — using socketOrigin=${ApiService.socketOrigin} '
      '(must support Socket.IO for call-offer signaling)',
    );
  }
}
