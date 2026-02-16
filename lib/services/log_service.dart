import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

/// Log level enum for categorizing log entries.
enum LogLevel {
  ok('[OK]'),
  info('[INFO]'),
  warn('[WARN]'),
  error('[ERROR]');

  final String tag;
  const LogLevel(this.tag);
}

/// Represents a single log entry.
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });

  /// Formats the log entry for display.
  String format() {
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);
    final buffer = StringBuffer('[$timeStr] ${level.tag} $message');

    if (error != null) {
      buffer.write('\n  Error: $error');
    }

    if (stackTrace != null) {
      buffer.write('\n  Stack trace:\n$stackTrace');
    }

    return buffer.toString();
  }

  /// Formats the log entry as a single line (for file storage).
  String formatSingleLine() {
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);
    final buffer = StringBuffer('[$timeStr] ${level.tag} $message');

    if (error != null) {
      buffer.write(' | Error: $error');
    }

    return buffer.toString();
  }
}

/// Service for centralized logging with tagged output.
///
/// Features:
/// - Tagged logging: [OK], [INFO], [WARN], [ERROR]
/// - Console output in debug mode
/// - File logging for persistence
/// - Log rotation (max file size)
/// - In-memory log buffer for UI display
///
/// This is a singleton service - use LogService.instance to access.
class LogService {
  static final LogService _instance = LogService._internal();
  static LogService get instance => _instance;

  // In-memory log buffer (limited size)
  final List<LogEntry> _logs = [];
  static const int _maxLogsInMemory = 500;

  // File logging
  File? _logFile;
  static const int _maxLogFileSizeBytes = 5 * 1024 * 1024; // 5MB
  bool _isInitialized = false;

  // Stream controller for real-time log updates
  final StreamController<LogEntry> _logStreamController =
      StreamController<LogEntry>.broadcast();

  LogService._internal();

  /// Initializes the log service.
  ///
  /// Must be called before logging to files.
  /// Logging to console and memory works without initialization.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final logDir = Directory('${directory.path}/logs');

      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      _logFile = File('${logDir.path}/app.log');
      _isInitialized = true;

      logInfo('Log service initialized');
    } catch (e) {
      // If initialization fails, continue without file logging
      // ignore: avoid_print
      print('[WARN] Failed to initialize log service: $e');
    }
  }

  /// Stream of log entries for real-time updates.
  Stream<LogEntry> get logStream => _logStreamController.stream;

  /// Logs a success message with [OK] tag.
  void logOk(String message) {
    _log(LogLevel.ok, message);
  }

  /// Logs an informational message with [INFO] tag.
  void logInfo(String message) {
    _log(LogLevel.info, message);
  }

  /// Logs a warning message with [WARN] tag.
  void logWarn(String message, [Object? error]) {
    _log(LogLevel.warn, message, error: error);
  }

  /// Logs an error message with [ERROR] tag.
  void logError(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.error, message, error: error, stackTrace: stackTrace);
  }

  /// Internal logging method.
  void _log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      error: error?.toString(),
      stackTrace: stackTrace,
    );

    // Add to in-memory buffer
    _logs.add(entry);
    if (_logs.length > _maxLogsInMemory) {
      _logs.removeAt(0); // Remove oldest
    }

    // Emit to stream
    _logStreamController.add(entry);

    // Console output
    // ignore: avoid_print
    print(entry.format());

    // File output
    _writeToFile(entry);
  }

  /// Writes a log entry to file.
  Future<void> _writeToFile(LogEntry entry) async {
    if (!_isInitialized || _logFile == null) return;

    try {
      // Check file size and rotate if needed
      if (await _logFile!.exists()) {
        final size = await _logFile!.length();
        if (size > _maxLogFileSizeBytes) {
          await _rotateLogFile();
        }
      }

      // Append log entry
      await _logFile!.writeAsString(
        '${entry.formatSingleLine()}\n',
        mode: FileMode.append,
      );
    } catch (e) {
      // Silent failure - don't want logging failures to crash app
      // ignore: avoid_print
      print('[WARN] Failed to write to log file: $e');
    }
  }

  /// Rotates the log file when it gets too large.
  Future<void> _rotateLogFile() async {
    if (_logFile == null) return;

    try {
      final directory = _logFile!.parent;
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final archiveFile = File('${directory.path}/app_$timestamp.log');

      // Rename current log file
      await _logFile!.rename(archiveFile.path);

      // Create new log file
      _logFile = File('${directory.path}/app.log');

      logInfo('Log file rotated: ${archiveFile.path}');
    } catch (e) {
      // ignore: avoid_print
      print('[WARN] Failed to rotate log file: $e');
    }
  }

  /// Returns all logs in memory.
  List<LogEntry> getLogs() {
    return List.unmodifiable(_logs);
  }

  /// Returns logs filtered by level.
  List<LogEntry> getLogsByLevel(LogLevel level) {
    return _logs.where((log) => log.level == level).toList();
  }

  /// Returns recent logs (last N entries).
  List<LogEntry> getRecentLogs(int count) {
    if (_logs.length <= count) {
      return List.from(_logs);
    }
    return _logs.sublist(_logs.length - count);
  }

  /// Clears all logs from memory.
  void clearLogs() {
    _logs.clear();
    logInfo('Logs cleared');
  }

  /// Exports all logs as a formatted string.
  String exportLogs() {
    final buffer = StringBuffer();
    buffer.writeln('=== BPB Automation Logs ===');
    buffer.writeln('Exported: ${DateTime.now()}');
    buffer.writeln('Total entries: ${_logs.length}');
    buffer.writeln('=' * 50);
    buffer.writeln();

    for (final log in _logs) {
      buffer.writeln(log.format());
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Exports logs to a file.
  Future<File?> exportLogsToFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final exportFile = File('${directory.path}/logs_export_$timestamp.txt');

      await exportFile.writeAsString(exportLogs());

      logOk('Logs exported to: ${exportFile.path}');
      return exportFile;
    } catch (e) {
      logError('Failed to export logs', e);
      return null;
    }
  }

  /// Returns the current log file path if available.
  String? get logFilePath => _logFile?.path;

  /// Returns true if the service is initialized for file logging.
  bool get isInitialized => _isInitialized;

  /// Returns the number of logs in memory.
  int get logCount => _logs.length;

  /// Disposes the log service.
  void dispose() {
    _logStreamController.close();
  }
}
