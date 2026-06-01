import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 80,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  static void v(dynamic message) {
    if (kDebugMode) {
      _logger.t(message);
    }
  }

  static void d(dynamic message) {
    if (kDebugMode) {
      _logger.d(message);
    }
  }
  static void i(dynamic message) {
    if (kDebugMode) {
      _logger.i(message);
    }
  }

  static void w(dynamic message) {
    if (kDebugMode) {
      _logger.w(message);
    }
  }

  static void e(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _logger.e(message, error: error, stackTrace: stackTrace);
    }
  }

  static void f(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _logger.f(message, error: error, stackTrace: stackTrace);
    }
  }
}
