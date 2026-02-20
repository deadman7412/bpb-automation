import 'dart:convert';
import 'dart:io';
import 'dart:math';

class WorkerApp {
  static const _defaultStateDir = '/var/lib/bpb-automation';
  static const _defaultLogDir = '/var/log/bpb-automation';
  static const _defaultRetentionDays = 7;

  Future<int> run(List<String> args) async {
    if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
      _printUsage();
      return 0;
    }

    final command = args.first;
    final opts = _parseOptions(args.skip(1).toList());

    switch (command) {
      case 'run-once':
        return _runOnce(opts);
      case 'cleanup':
        return _cleanupOnly(opts);
      default:
        stderr.writeln('Unknown command: $command');
        _printUsage();
        return 2;
    }
  }

  Future<int> _runOnce(Map<String, String> opts) async {
    final stateDir = Directory(opts['state-dir'] ?? _defaultStateDir);
    final logDir = Directory(opts['log-dir'] ?? _defaultLogDir);
    final trigger = opts['trigger'] ?? 'manual';
    final hostLabel = opts['host-label'] ?? 'server-host';
    final retentionDays =
        int.tryParse(opts['retention-days'] ?? '$_defaultRetentionDays') ??
        _defaultRetentionDays;
    final scanCmd = opts['scan-cmd'];
    final applyCmd = opts['apply-cmd'];
    final applyEnabled = opts['apply'] == 'true';

    await _ensureDirectory(stateDir);
    await _ensureDirectory(logDir);
    await _ensureDirectory(Directory('${stateDir.path}/runs'));

    final logger = WorkerLogger(logDir: logDir);
    final lock = File('${stateDir.path}/run.lock');
    final raf = await lock.open(mode: FileMode.write);

    try {
      await raf.lock(FileLock.blockingExclusive);
    } catch (e) {
      stderr.writeln('Failed to acquire lock: $e');
      await raf.close();
      return 1;
    }

    final runStart = DateTime.now().toUtc();
    final runId = _buildRunId(runStart);

    final statusFile = File('${stateDir.path}/status.json');
    await statusFile.writeAsString(
      jsonEncode({
        'running': true,
        'run_id': runId,
        'started_at': runStart.toIso8601String(),
      }),
    );

    await logger.info(runId, 'Run started (trigger=$trigger, host=$hostLabel)');

    RunResult result;
    try {
      result = await _executeScan(
        runId: runId,
        scanCmd: scanCmd,
        logger: logger,
      );
    } catch (e) {
      await logger.error(runId, 'Scan execution failed: $e');
      result = RunResult.failure(errorSummary: e.toString());
    }

    bool applied = false;
    String? applyError;
    if (applyEnabled &&
        result.status == 'success' &&
        result.workingIps.isNotEmpty) {
      try {
        await _executeApply(
          runId: runId,
          applyCmd: applyCmd,
          workingIps: result.workingIps,
          logger: logger,
        );
        applied = true;
      } catch (e) {
        applyError = e.toString();
        await logger.error(runId, 'Apply failed: $applyError');
      }
    }

    final runEnd = DateTime.now().toUtc();
    final durationMs = runEnd.difference(runStart).inMilliseconds;
    final finalStatus = (result.status == 'success' && applyError == null)
        ? 'success'
        : result.status;

    final runSummary = <String, dynamic>{
      'run_id': runId,
      'trigger': trigger,
      'host_label': hostLabel,
      'status': finalStatus,
      'started_at': runStart.toIso8601String(),
      'finished_at': runEnd.toIso8601String(),
      'duration_ms': durationMs,
      'phase1_passed': result.phase1Passed,
      'phase2_tested': result.phase2Tested,
      'working_count': result.workingIps.length,
      'selected_ips': result.workingIps,
      'applied': applied,
      'error_summary': applyError ?? result.errorSummary,
    };

    await _persistRun(stateDir: stateDir, runId: runId, payload: runSummary);
    await _appendRunIndex(stateDir: stateDir, payload: runSummary);

    await statusFile.writeAsString(
      jsonEncode({
        'running': false,
        'last_run_id': runId,
        'last_status': finalStatus,
        'last_finished_at': runEnd.toIso8601String(),
      }),
    );

    await logger.info(
      runId,
      'Run finished (status=$finalStatus, applied=$applied)',
    );
    await _cleanupLogs(
      logDir: logDir,
      retentionDays: retentionDays,
      logger: logger,
    );

    await raf.unlock();
    await raf.close();
    return finalStatus == 'success' ? 0 : 1;
  }

  Future<int> _cleanupOnly(Map<String, String> opts) async {
    final logDir = Directory(opts['log-dir'] ?? _defaultLogDir);
    final retentionDays =
        int.tryParse(opts['retention-days'] ?? '$_defaultRetentionDays') ??
        _defaultRetentionDays;
    await _ensureDirectory(logDir);
    final logger = WorkerLogger(logDir: logDir);
    await _cleanupLogs(
      logDir: logDir,
      retentionDays: retentionDays,
      logger: logger,
    );
    return 0;
  }

  Future<void> _executeApply({
    required String runId,
    required String? applyCmd,
    required List<String> workingIps,
    required WorkerLogger logger,
  }) async {
    if (applyCmd == null || applyCmd.trim().isEmpty) {
      throw StateError('apply requested but --apply-cmd is missing');
    }
    await logger.info(runId, 'Executing apply command');
    final proc = await Process.start(
      '/bin/sh',
      ['-lc', applyCmd],
      environment: {'BPB_WORKING_IPS_JSON': jsonEncode(workingIps)},
    );
    final stdoutText = await utf8.decoder.bind(proc.stdout).join();
    final stderrText = await utf8.decoder.bind(proc.stderr).join();
    final code = await proc.exitCode;
    if (stdoutText.trim().isNotEmpty) {
      await logger.info(runId, 'Apply stdout: ${stdoutText.trim()}');
    }
    if (stderrText.trim().isNotEmpty) {
      await logger.warn(runId, 'Apply stderr: ${stderrText.trim()}');
    }
    if (code != 0) {
      throw StateError('apply command exited with code $code');
    }
  }

  Future<RunResult> _executeScan({
    required String runId,
    required String? scanCmd,
    required WorkerLogger logger,
  }) async {
    if (scanCmd == null || scanCmd.trim().isEmpty) {
      await logger.warn(
        runId,
        'No --scan-cmd provided. Using fallback mock run result.',
      );
      return RunResult.success(
        phase1Passed: 0,
        phase2Tested: 0,
        workingIps: const [],
      );
    }

    await logger.info(runId, 'Executing scan command');
    final proc = await Process.start('/bin/sh', ['-lc', scanCmd]);
    final stdoutText = await utf8.decoder.bind(proc.stdout).join();
    final stderrText = await utf8.decoder.bind(proc.stderr).join();
    final code = await proc.exitCode;

    if (stderrText.trim().isNotEmpty) {
      await logger.warn(runId, 'Scan stderr: ${stderrText.trim()}');
    }
    if (code != 0) {
      throw StateError('scan command exited with code $code');
    }

    if (stdoutText.trim().isEmpty) {
      throw StateError('scan command produced empty output');
    }

    final decoded = jsonDecode(stdoutText) as Map<String, dynamic>;
    final status = (decoded['status'] ?? 'success').toString();
    final phase1Passed = (decoded['phase1_passed'] ?? 0) as int;
    final phase2Tested = (decoded['phase2_tested'] ?? 0) as int;
    final working = (decoded['working_ips'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList();
    final errorSummary = decoded['error_summary']?.toString();

    if (status != 'success') {
      return RunResult.failure(errorSummary: errorSummary ?? 'scan failed');
    }

    return RunResult.success(
      phase1Passed: phase1Passed,
      phase2Tested: phase2Tested,
      workingIps: working,
    );
  }

  Future<void> _persistRun({
    required Directory stateDir,
    required String runId,
    required Map<String, dynamic> payload,
  }) async {
    final runFile = File('${stateDir.path}/runs/$runId.json');
    final latestFile = File('${stateDir.path}/latest.json');
    await runFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    await latestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<void> _appendRunIndex({
    required Directory stateDir,
    required Map<String, dynamic> payload,
  }) async {
    final file = File('${stateDir.path}/runs_index.jsonl');
    await file.writeAsString('${jsonEncode(payload)}\n', mode: FileMode.append);
  }

  Future<void> _cleanupLogs({
    required Directory logDir,
    required int retentionDays,
    required WorkerLogger logger,
  }) async {
    final cutoff = DateTime.now().toUtc().subtract(
      Duration(days: retentionDays),
    );
    final entities = await logDir.list().toList();
    for (final entity in entities) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('app-') || !name.endsWith('.log')) continue;
      final stat = await entity.stat();
      if (stat.modified.toUtc().isBefore(cutoff)) {
        await entity.delete();
        await logger.info(
          'maintenance',
          'Deleted old log file: ${entity.path}',
        );
      }
    }
  }

  Future<void> _ensureDirectory(Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  String _buildRunId(DateTime t) {
    final z = t.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final rand = Random().nextInt(900000) + 100000;
    return '$z-$rand';
  }

  Map<String, String> _parseOptions(List<String> args) {
    final out = <String, String>{};
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (!arg.startsWith('--')) continue;
      final key = arg.substring(2);
      if (key.contains('=')) {
        final parts = key.split('=');
        out[parts[0]] = parts.sublist(1).join('=');
        continue;
      }
      final next = (i + 1 < args.length) ? args[i + 1] : null;
      if (next == null || next.startsWith('--')) {
        out[key] = 'true';
      } else {
        out[key] = next;
        i++;
      }
    }
    return out;
  }

  void _printUsage() {
    stdout.writeln('''
BPB autoscan worker

Usage:
  bpb_autoscan.dart run-once [options]
  bpb_autoscan.dart cleanup [options]

Options:
  --state-dir <path>       state dir (default: $_defaultStateDir)
  --log-dir <path>         log dir (default: $_defaultLogDir)
  --retention-days <n>     log retention days (default: $_defaultRetentionDays)
  --trigger <name>         trigger label (manual|scheduled|api)
  --host-label <name>      host/device label for history records
  --scan-cmd <cmd>         shell command returning scan JSON on stdout
  --apply                  enable apply step after successful scan
  --apply-cmd <cmd>        shell command for apply step
''');
  }
}

class RunResult {
  final String status;
  final int phase1Passed;
  final int phase2Tested;
  final List<String> workingIps;
  final String? errorSummary;

  RunResult.success({
    required this.phase1Passed,
    required this.phase2Tested,
    required this.workingIps,
  }) : status = 'success',
       errorSummary = null;

  RunResult.failure({required this.errorSummary})
    : status = 'failed',
      phase1Passed = 0,
      phase2Tested = 0,
      workingIps = const [];
}

class WorkerLogger {
  WorkerLogger({required this.logDir});

  final Directory logDir;

  Future<void> info(String runId, String message) =>
      _write('INFO', runId, message);
  Future<void> warn(String runId, String message) =>
      _write('WARN', runId, message);
  Future<void> error(String runId, String message) =>
      _write('ERROR', runId, message);

  Future<void> _write(String level, String runId, String message) async {
    final now = DateTime.now().toUtc();
    final day =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final file = File('${logDir.path}/app-$day.log');
    final line = '[${now.toIso8601String()}] [$level] [$runId] $message\n';
    await file.writeAsString(line, mode: FileMode.append);
  }
}
