/// Structured logging utility for the application.
///
/// Provides consistent log output with levels, timestamps, and context.
class AppLogger {
  final String _tag;

  const AppLogger(this._tag);

  void debug(String message, [Object? data]) {
    _log('DEBUG', message, data);
  }

  void info(String message, [Object? data]) {
    _log('INFO', message, data);
  }

  void warning(String message, [Object? data]) {
    _log('WARN', message, data);
  }

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log('ERROR', message, error);
    if (stackTrace != null) {
      // ignore: avoid_print
      print('  StackTrace: $stackTrace');
    }
  }

  void _log(String level, String message, [Object? data]) {
    final timestamp = DateTime.now().toIso8601String();
    final logLine = '[$timestamp] [$level] [$_tag] $message';
    // ignore: avoid_print
    print(data != null ? '$logLine | $data' : logLine);
  }
}
