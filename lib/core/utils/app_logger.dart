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

  static void v(dynamic message) => _logger.t(message); // Trace/Verbose
  static void d(dynamic message) => _logger.d(message); // Debug
  static void i(dynamic message) => _logger.i(message); // Info
  static void w(dynamic message) => _logger.w(message); // Warning
  static void e(dynamic message, [dynamic error, StackTrace? stackTrace]) =>
      _logger.e(message, error: error, stackTrace: stackTrace); // Error
  static void f(dynamic message, [dynamic error, StackTrace? stackTrace]) =>
      _logger.f(message, error: error, stackTrace: stackTrace); // Fatal/Wtf
}
