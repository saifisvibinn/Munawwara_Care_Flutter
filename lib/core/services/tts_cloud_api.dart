import 'package:dio/dio.dart';

import '../utils/app_logger.dart';
import 'api_service.dart';

/// Fetches a Cloud TTS (GCS) MP3 URL for [text] in [lang], same pipeline as
/// server-side message [audio_url]. Used when UI shows translated copy so
/// playback matches the visible language before device [flutter_tts].
class TtsCloudApi {
  TtsCloudApi._();

  static const _supported = {'en', 'ar', 'ur', 'fr', 'id', 'tr', 'fa', 'ms'};

  /// API accepts same short codes as [tts_service] / Joi schema.
  static String normalizeLang(String lang) {
    final c = lang.toLowerCase().split(RegExp(r'[-_]')).first;
    return _supported.contains(c) ? c : 'en';
  }

  static Future<String?> fetchAudioUrl({
    required String text,
    required String lang,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return null;
    final langCode = normalizeLang(lang);
    try {
      final Response<dynamic> res = await ApiService.dio.post(
        '/auth/tts-audio-url',
        data: <String, String>{'text': t, 'lang': langCode},
      );
      final data = res.data;
      if (data is! Map) return null;
      final url = data['audioUrl']?.toString().trim();
      if (url != null && url.isNotEmpty) return url;
    } on DioException catch (e) {
      AppLogger.w('[TtsCloudApi] fetchAudioUrl: ${e.message}');
    } catch (e) {
      AppLogger.w('[TtsCloudApi] fetchAudioUrl: $e');
    }
    return null;
  }
}
