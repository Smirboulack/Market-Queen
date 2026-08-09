import 'package:flutter/foundation.dart';

enum LogLevel { info, success, warning, error }

class LogEntry {
  LogEntry(this.time, this.level, this.message);

  final DateTime time;
  final LogLevel level;
  final String message;

  String get clock =>
      '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class LogModel extends ChangeNotifier {
  static const _maxEntries = 2000;

  final List<LogEntry> _entries = [];

  List<LogEntry> get entries => List.unmodifiable(_entries);
  int get count => _entries.length;

  void append(LogLevel level, String message) {
    if (message.isEmpty) return;

    if (_entries.length >= _maxEntries) _entries.removeAt(0);
    _entries.add(LogEntry(DateTime.now(), level, message));

    if (kDebugMode) debugPrint('[${level.name}] $message');
    notifyListeners();
  }

  void info(String message) => append(LogLevel.info, message);
  void success(String message) => append(LogLevel.success, message);
  void warning(String message) => append(LogLevel.warning, message);
  void error(String message) => append(LogLevel.error, message);

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  String asPlainText() => _entries
      .map((e) => '${e.time.toIso8601String()}  ${e.message}')
      .join('\n');
}
