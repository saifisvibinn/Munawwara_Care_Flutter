import 'package:dio/dio.dart';

import '../../../core/services/api_service.dart';

/// Type of in-app support submission.
enum SupportRequestType {
  support('support'),
  accountDeletion('account_deletion');

  const SupportRequestType(this.apiValue);
  final String apiValue;
}

/// Sends contact / deletion requests to the backend (emailed to support).
class SupportApi {
  SupportApi._();

  static Future<void> deleteOwnAccount() async {
    await ApiService.dio.delete('/auth/account');
  }

  static Future<void> submitRequest({
    required SupportRequestType type,
    String? message,
    String? contactHint,
  }) async {
    await ApiService.dio.post(
      '/support/request',
      data: {
        'type': type.apiValue,
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
        if (contactHint != null && contactHint.trim().isNotEmpty)
          'contact_hint': contactHint.trim(),
      },
    );
  }

  static String parseError(DioException error) {
    return ApiService.parseError(error);
  }
}
