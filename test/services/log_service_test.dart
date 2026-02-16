import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/services/log_service.dart';

void main() {
  group('LogService', () {
    late LogService logService;

    setUp(() {
      logService = LogService.instance;
      logService.clearLogs();
    });

    tearDown(() {
      logService.clearLogs();
    });

    group('Singleton', () {
      test('returns same instance', () {
        final instance1 = LogService.instance;
        final instance2 = LogService.instance;

        expect(identical(instance1, instance2), isTrue);
      });
    });

    group('LogEntry', () {
      test('format() creates readable output', () {
        final entry = LogEntry(
          timestamp: DateTime(2026, 2, 15, 14, 30, 45),
          level: LogLevel.info,
          message: 'Test message',
        );

        final formatted = entry.format();

        expect(formatted, contains('2026-02-15 14:30:45'));
        expect(formatted, contains('[INFO]'));
        expect(formatted, contains('Test message'));
      });

      test('format() includes error if present', () {
        final entry = LogEntry(
          timestamp: DateTime(2026, 2, 15, 14, 30, 45),
          level: LogLevel.error,
          message: 'Error occurred',
          error: 'Something went wrong',
        );

        final formatted = entry.format();

        expect(formatted, contains('Error: Something went wrong'));
      });

      test('formatSingleLine() creates single line output', () {
        final entry = LogEntry(
          timestamp: DateTime(2026, 2, 15, 14, 30, 45),
          level: LogLevel.warn,
          message: 'Warning',
          error: 'Issue detected',
        );

        final formatted = entry.formatSingleLine();

        expect(formatted, contains('[WARN]'));
        expect(formatted, contains('Warning'));
        expect(formatted, contains('| Error: Issue detected'));
        expect(formatted, isNot(contains('\n')));
      });
    });

    group('Logging Methods', () {
      test('logOk() adds OK log entry', () {
        logService.logOk('Success message');

        final logs = logService.getLogs();
        expect(logs.length, equals(2)); // clearLogs() + our log
        expect(logs.last.level, equals(LogLevel.ok));
        expect(logs.last.message, equals('Success message'));
      });

      test('logInfo() adds INFO log entry', () {
        logService.logInfo('Info message');

        final logs = logService.getLogs();
        expect(logs.length, equals(2)); // clearLogs() + our log
        expect(logs.last.level, equals(LogLevel.info));
        expect(logs.last.message, equals('Info message'));
      });

      test('logWarn() adds WARN log entry', () {
        logService.logWarn('Warning message');

        final logs = logService.getLogs();
        expect(logs.length, equals(2)); // clearLogs() + our log
        expect(logs.last.level, equals(LogLevel.warn));
        expect(logs.last.message, equals('Warning message'));
      });

      test('logWarn() can include error object', () {
        logService.logWarn('Warning', 'Error details');

        final logs = logService.getLogs();
        expect(logs.last.error, equals('Error details'));
      });

      test('logError() adds ERROR log entry', () {
        logService.logError('Error message');

        final logs = logService.getLogs();
        expect(logs.length, equals(2)); // clearLogs() + our log
        expect(logs.last.level, equals(LogLevel.error));
        expect(logs.last.message, equals('Error message'));
      });

      test('logError() can include error and stack trace', () {
        final stackTrace = StackTrace.current;
        logService.logError('Error', 'Details', stackTrace);

        final logs = logService.getLogs();
        expect(logs.last.error, equals('Details'));
        expect(logs.last.stackTrace, equals(stackTrace));
      });
    });

    group('Log Retrieval', () {
      setUp(() {
        logService.logOk('OK 1');
        logService.logInfo('INFO 1');
        logService.logWarn('WARN 1');
        logService.logError('ERROR 1');
        logService.logOk('OK 2');
      });

      test('getLogs() returns all logs', () {
        final logs = logService.getLogs();
        expect(logs.length, equals(6)); // clearLogs() + 5 test logs
      });

      test('getLogs() returns immutable list', () {
        final logs = logService.getLogs();

        expect(() => logs.add(LogEntry(
              timestamp: DateTime.now(),
              level: LogLevel.info,
              message: 'test',
            )), throwsUnsupportedError);
      });

      test('getLogsByLevel() filters by level', () {
        final okLogs = logService.getLogsByLevel(LogLevel.ok);
        final infoLogs = logService.getLogsByLevel(LogLevel.info);
        final warnLogs = logService.getLogsByLevel(LogLevel.warn);
        final errorLogs = logService.getLogsByLevel(LogLevel.error);

        expect(okLogs.length, equals(2));
        expect(infoLogs.length, equals(2)); // clearLogs() + INFO 1
        expect(warnLogs.length, equals(1));
        expect(errorLogs.length, equals(1));
      });

      test('getRecentLogs() returns last N logs', () {
        final recent = logService.getRecentLogs(3);

        expect(recent.length, equals(3));
        expect(recent[0].message, equals('WARN 1'));
        expect(recent[1].message, equals('ERROR 1'));
        expect(recent[2].message, equals('OK 2'));
      });

      test('getRecentLogs() returns all logs if count > total', () {
        final recent = logService.getRecentLogs(100);

        expect(recent.length, equals(6)); // clearLogs() + 5 test logs
      });
    });

    group('Log Buffer Management', () {
      test('maintains maximum log count', () {
        // Add more than max logs
        for (int i = 0; i < 600; i++) {
          logService.logInfo('Message $i');
        }

        expect(logService.logCount, equals(500)); // Max is 500
      });

      test('removes oldest logs when buffer is full', () {
        // Add logs
        for (int i = 0; i < 600; i++) {
          logService.logInfo('Message $i');
        }

        final logs = logService.getLogs();
        // First message should be Message 100 (0-99 removed)
        expect(logs.first.message, equals('Message 100'));
        expect(logs.last.message, equals('Message 599'));
      });

      test('clearLogs() removes all logs', () {
        logService.logOk('Test 1');
        logService.logInfo('Test 2');
        logService.clearLogs();

        // clearLogs() itself adds a log
        final logs = logService.getLogs();
        expect(logs.length, equals(1));
        expect(logs.first.message, equals('Logs cleared'));
      });
    });

    group('Log Export', () {
      setUp(() {
        logService.logOk('Success');
        logService.logInfo('Information');
        logService.logWarn('Warning');
        logService.logError('Error');
      });

      test('exportLogs() creates formatted string', () {
        final exported = logService.exportLogs();

        expect(exported, contains('=== BPB Automation Logs ==='));
        expect(exported, contains('[INFO] Logs cleared')); // From setup
        expect(exported, contains('[OK] Success'));
        expect(exported, contains('[INFO] Information'));
        expect(exported, contains('[WARN] Warning'));
        expect(exported, contains('[ERROR] Error'));
      });

      test('exportLogs() includes timestamp', () {
        final exported = logService.exportLogs();

        expect(exported, contains('Exported:'));
      });
    });

    group('Log Stream', () {
      test('emits log entries when logged', () async {
        final logs = <LogEntry>[];

        // Start listening AFTER setup's clearLogs()
        final subscription = logService.logStream.listen((entry) {
          logs.add(entry);
        });

        logService.logOk('Test 1');
        logService.logInfo('Test 2');

        await Future.delayed(Duration(milliseconds: 100));

        expect(logs.length, equals(2));
        expect(logs[0].message, equals('Test 1'));
        expect(logs[1].message, equals('Test 2'));

        await subscription.cancel();
      });

      test('multiple listeners receive same events', () async {
        final logs1 = <LogEntry>[];
        final logs2 = <LogEntry>[];

        // Start listening AFTER setup's clearLogs()
        final sub1 = logService.logStream.listen((entry) {
          logs1.add(entry);
        });

        final sub2 = logService.logStream.listen((entry) {
          logs2.add(entry);
        });

        logService.logOk('Test');

        await Future.delayed(Duration(milliseconds: 100));

        expect(logs1.length, equals(1));
        expect(logs2.length, equals(1));

        await sub1.cancel();
        await sub2.cancel();
      });
    });

    group('Properties', () {
      test('logCount returns number of logs in memory', () {
        final initialCount = logService.logCount;

        logService.logOk('Test 1');
        expect(logService.logCount, equals(initialCount + 1));

        logService.logInfo('Test 2');
        logService.logWarn('Test 3');
        expect(logService.logCount, equals(initialCount + 3));
      });
    });

    group('Log Levels', () {
      test('LogLevel enum has correct tags', () {
        expect(LogLevel.ok.tag, equals('[OK]'));
        expect(LogLevel.info.tag, equals('[INFO]'));
        expect(LogLevel.warn.tag, equals('[WARN]'));
        expect(LogLevel.error.tag, equals('[ERROR]'));
      });
    });

    group('Edge Cases', () {
      test('handles empty messages', () {
        logService.logInfo('');

        final logs = logService.getLogs();
        expect(logs.last.message, equals(''));
      });

      test('handles very long messages', () {
        final longMessage = 'A' * 10000;
        logService.logInfo(longMessage);

        final logs = logService.getLogs();
        expect(logs.last.message, equals(longMessage));
      });

      test('handles special characters in messages', () {
        const special = 'Test\n\t\r!@#\$%^&*()_+-=[]{}|;:\'",.<>?/`~';
        logService.logInfo(special);

        final logs = logService.getLogs();
        expect(logs.last.message, equals(special));
      });

      test('handles null error gracefully', () {
        logService.logWarn('Warning', null);

        final logs = logService.getLogs();
        expect(logs.last.error, isNull);
      });
    });
  });
}
