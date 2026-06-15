import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Reads [key] from dotenv only when [.env] was loaded (e.g. dev asset or file).
String? dotenvOptional(String key) {
  if (!dotenv.isInitialized) return null;
  final value = dotenv.env[key]?.trim();
  if (value == null || value.isEmpty) return null;
  return value;
}
