import 'dart:convert';
import 'dart:io';
import 'dart:math';

class WorkerApp {
  static const _defaultStateDir = '/var/lib/bpb-automation';
  static const _defaultLogDir = '/var/log/bpb-automation';
  static const _defaultRetentionDays = 7;
  static const _defaultMinWorkingIps = 1;
  static const _defaultMaxRetryDelayMs = 60000;

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
      case 'rollback':
        return _rollback(opts);
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
    final updateMode = opts['update-mode'] ?? 'command';
    final scanRetries = int.tryParse(opts['scan-retries'] ?? '3') ?? 3;
    final applyRetries = int.tryParse(opts['apply-retries'] ?? '3') ?? 3;
    final minWorkingIps =
        int.tryParse(opts['min-working-ips'] ?? '$_defaultMinWorkingIps') ??
        _defaultMinWorkingIps;
    final initialRetryDelayMs =
        int.tryParse(opts['initial-retry-delay-ms'] ?? '1000') ?? 1000;
    final maxRetryDelayMs =
        int.tryParse(
          opts['max-retry-delay-ms'] ?? '$_defaultMaxRetryDelayMs',
        ) ??
        _defaultMaxRetryDelayMs;
    final requestedBy = opts['requested-by'] ?? 'unknown';
    final requestIp = opts['request-ip'] ?? '-';

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
    try {
      await statusFile.writeAsString(
        jsonEncode({
          'running': true,
          'run_id': runId,
          'started_at': runStart.toIso8601String(),
        }),
      );

      await logger.info(
        runId,
        'Run started (trigger=$trigger, host=$hostLabel, requested_by=$requestedBy, request_ip=$requestIp)',
      );

      RunResult result;
      try {
        result = await _withRetries<RunResult>(
          runId: runId,
          logger: logger,
          opName: 'scan',
          maxAttempts: scanRetries,
          initialRetryDelay: Duration(milliseconds: initialRetryDelayMs),
          maxRetryDelay: Duration(milliseconds: maxRetryDelayMs),
          operation: () =>
              _executeScan(runId: runId, scanCmd: scanCmd, logger: logger),
        );
      } catch (e) {
        await logger.error(runId, 'Scan execution failed: $e');
        result = RunResult.failure(errorSummary: e.toString());
      }

      bool applied = false;
      String? applyError;
      String? applySkippedReason;
      List<String> previousAppliedIps = const [];
      List<String> rollbackIps = const [];
      if (applyEnabled &&
          result.status == 'success' &&
          result.workingIps.isNotEmpty) {
        if (result.workingIps.length < minWorkingIps) {
          applySkippedReason =
              'apply skipped: working_count ${result.workingIps.length} below min-working-ips $minWorkingIps';
          await logger.warn(runId, applySkippedReason);
        } else {
          previousAppliedIps = await _readCurrentAppliedIps(stateDir);
          if (previousAppliedIps.isNotEmpty) {
            rollbackIps = List<String>.from(previousAppliedIps);
          }
          try {
            await _withRetries<void>(
              runId: runId,
              logger: logger,
              opName: 'apply',
              maxAttempts: applyRetries,
              initialRetryDelay: Duration(milliseconds: initialRetryDelayMs),
              maxRetryDelay: Duration(milliseconds: maxRetryDelayMs),
              operation: () => _executeApply(
                runId: runId,
                applyCmd: applyCmd,
                workingIps: result.workingIps,
                logger: logger,
              ),
            );
            applied = true;
            await _writeApplySnapshots(
              stateDir: stateDir,
              runId: runId,
              newIps: result.workingIps,
              previousIps: previousAppliedIps,
              updateMode: updateMode,
              requestedBy: requestedBy,
              requestIp: requestIp,
            );
          } catch (e) {
            applyError = e.toString();
            await logger.error(runId, 'Apply failed: $applyError');
          }
        }
      }

      final runEnd = DateTime.now().toUtc();
      final durationMs = runEnd.difference(runStart).inMilliseconds;
      final finalStatus = result.status != 'success'
          ? 'failed'
          : (applyEnabled && (applyError != null || applySkippedReason != null)
                ? 'partial'
                : 'success');

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
        'min_working_ips': minWorkingIps,
        'apply_skipped_reason': applySkippedReason,
        'rollback_available': rollbackIps.isNotEmpty,
        'rollback_ips_count': rollbackIps.length,
        'update_mode': updateMode,
        'error_summary': applyError ?? result.errorSummary,
        'apply_error': applyError,
        'requested_by': requestedBy,
        'request_ip': requestIp,
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
      final cleanupReport = await _cleanupLogs(
        logDir: logDir,
        retentionDays: retentionDays,
        logger: logger,
      );
      final runCleanupReport = await _cleanupRunArtifacts(
        stateDir: stateDir,
        retentionDays: retentionDays,
        logger: logger,
      );
      await _writeCleanupReport(
        stateDir: stateDir,
        report: cleanupReport.withRunStats(
          runFilesDeleted: runCleanupReport.runFilesDeleted,
          runsIndexPruned: runCleanupReport.runsIndexPruned,
        ),
      );

      return finalStatus == 'success' ? 0 : 1;
    } catch (e) {
      final failedAt = DateTime.now().toUtc();
      await logger.error(runId, 'Run crashed unexpectedly: $e');
      await statusFile.writeAsString(
        jsonEncode({
          'running': false,
          'last_run_id': runId,
          'last_status': 'failed',
          'last_finished_at': failedAt.toIso8601String(),
        }),
      );
      return 1;
    } finally {
      try {
        await raf.unlock();
      } catch (_) {}
      await raf.close();
    }
  }

  Future<int> _rollback(Map<String, String> opts) async {
    final stateDir = Directory(opts['state-dir'] ?? _defaultStateDir);
    final logDir = Directory(opts['log-dir'] ?? _defaultLogDir);
    final applyCmd = opts['apply-cmd'];
    final applyRetries = int.tryParse(opts['apply-retries'] ?? '3') ?? 3;
    final initialRetryDelayMs =
        int.tryParse(opts['initial-retry-delay-ms'] ?? '1000') ?? 1000;
    final maxRetryDelayMs =
        int.tryParse(
          opts['max-retry-delay-ms'] ?? '$_defaultMaxRetryDelayMs',
        ) ??
        _defaultMaxRetryDelayMs;
    final requestedBy = opts['requested-by'] ?? 'unknown';
    final requestIp = opts['request-ip'] ?? '-';

    await _ensureDirectory(stateDir);
    await _ensureDirectory(logDir);
    final logger = WorkerLogger(logDir: logDir);
    final runId = 'rollback-${_buildRunId(DateTime.now().toUtc())}';
    final rollbackIps = await _readRollbackIps(stateDir);
    if (rollbackIps.isEmpty) {
      await logger.warn(runId, 'Rollback skipped: no rollback snapshot found');
      return 1;
    }

    await logger.info(
      runId,
      'Rollback started (requested_by=$requestedBy, request_ip=$requestIp, ips=${rollbackIps.length})',
    );
    try {
      await _withRetries<void>(
        runId: runId,
        logger: logger,
        opName: 'rollback',
        maxAttempts: applyRetries,
        initialRetryDelay: Duration(milliseconds: initialRetryDelayMs),
        maxRetryDelay: Duration(milliseconds: maxRetryDelayMs),
        operation: () => _executeApply(
          runId: runId,
          applyCmd: applyCmd,
          workingIps: rollbackIps,
          logger: logger,
        ),
      );
      await _writeCurrentAppliedSnapshot(
        stateDir: stateDir,
        runId: runId,
        ips: rollbackIps,
        updateMode: opts['update-mode'] ?? 'command',
        requestedBy: requestedBy,
        requestIp: requestIp,
      );
      await logger.info(runId, 'Rollback applied successfully');
      return 0;
    } catch (e) {
      await logger.error(runId, 'Rollback failed: $e');
      return 1;
    }
  }

  Future<int> _cleanupOnly(Map<String, String> opts) async {
    final stateDir = Directory(opts['state-dir'] ?? _defaultStateDir);
    final logDir = Directory(opts['log-dir'] ?? _defaultLogDir);
    final retentionDays =
        int.tryParse(opts['retention-days'] ?? '$_defaultRetentionDays') ??
        _defaultRetentionDays;
    await _ensureDirectory(stateDir);
    await _ensureDirectory(logDir);
    final logger = WorkerLogger(logDir: logDir);
    final cleanupReport = await _cleanupLogs(
      logDir: logDir,
      retentionDays: retentionDays,
      logger: logger,
    );
    final runCleanupReport = await _cleanupRunArtifacts(
      stateDir: stateDir,
      retentionDays: retentionDays,
      logger: logger,
    );
    await _writeCleanupReport(
      stateDir: stateDir,
      report: cleanupReport.withRunStats(
        runFilesDeleted: runCleanupReport.runFilesDeleted,
        runsIndexPruned: runCleanupReport.runsIndexPruned,
      ),
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
      throw StateError('--scan-cmd is required for run-once');
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

  Future<T> _withRetries<T>({
    required String runId,
    required WorkerLogger logger,
    required String opName,
    required int maxAttempts,
    required Duration initialRetryDelay,
    required Duration maxRetryDelay,
    required Future<T> Function() operation,
  }) async {
    var attempt = 0;
    var delay = initialRetryDelay;
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;

    while (true) {
      attempt++;
      try {
        return await operation();
      } catch (e) {
        if (attempt >= attempts) rethrow;
        await logger.warn(
          runId,
          '$opName attempt $attempt failed, retrying in ${delay.inMilliseconds}ms: $e',
        );
        await Future.delayed(delay);
        final nextDelay = delay * 2;
        delay = nextDelay > maxRetryDelay ? maxRetryDelay : nextDelay;
      }
    }
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

  Future<List<String>> _readCurrentAppliedIps(Directory stateDir) async {
    final file = File('${stateDir.path}/current_applied.json');
    if (!await file.exists()) return const [];
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final ips = data['ips'] as List<dynamic>? ?? const [];
      return ips.map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _readRollbackIps(Directory stateDir) async {
    final file = File('${stateDir.path}/rollback_candidate.json');
    if (!await file.exists()) return const [];
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final ips = data['ips'] as List<dynamic>? ?? const [];
      return ips.map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeApplySnapshots({
    required Directory stateDir,
    required String runId,
    required List<String> newIps,
    required List<String> previousIps,
    required String updateMode,
    required String requestedBy,
    required String requestIp,
  }) async {
    if (previousIps.isNotEmpty) {
      final rollbackFile = File('${stateDir.path}/rollback_candidate.json');
      await rollbackFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'from_run_id': runId,
          'ips': previousIps,
          'source': 'previous_current_applied',
        }),
      );
    }
    await _writeCurrentAppliedSnapshot(
      stateDir: stateDir,
      runId: runId,
      ips: newIps,
      updateMode: updateMode,
      requestedBy: requestedBy,
      requestIp: requestIp,
    );
  }

  Future<void> _writeCurrentAppliedSnapshot({
    required Directory stateDir,
    required String runId,
    required List<String> ips,
    required String updateMode,
    required String requestedBy,
    required String requestIp,
  }) async {
    final file = File('${stateDir.path}/current_applied.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'run_id': runId,
        'update_mode': updateMode,
        'requested_by': requestedBy,
        'request_ip': requestIp,
        'ips': ips,
      }),
    );
  }

  Future<void> _writeCleanupReport({
    required Directory stateDir,
    required CleanupReport report,
  }) async {
    final file = File('${stateDir.path}/cleanup_status.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
    );
  }

  Future<CleanupReport> _cleanupLogs({
    required Directory logDir,
    required int retentionDays,
    required WorkerLogger logger,
  }) async {
    final cutoff = DateTime.now().toUtc().subtract(
      Duration(days: retentionDays),
    );
    var deletedFiles = 0;
    var remainingFiles = 0;
    var nonCompliantFiles = 0;
    DateTime? oldestRemainingModifiedAt;
    final entities = await logDir.list().toList();
    for (final entity in entities) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('app-') || !name.endsWith('.log')) continue;
      final stat = await entity.stat();
      if (stat.modified.toUtc().isBefore(cutoff)) {
        try {
          await entity.delete();
          deletedFiles++;
          await logger.info(
            'maintenance',
            'Deleted old log file: ${entity.path}',
          );
        } catch (_) {
          nonCompliantFiles++;
          remainingFiles++;
          await logger.warn(
            'maintenance',
            'Failed to delete expired log file: ${entity.path}',
          );
        }
        continue;
      }
      remainingFiles++;
      final modified = stat.modified.toUtc();
      if (oldestRemainingModifiedAt == null ||
          modified.isBefore(oldestRemainingModifiedAt)) {
        oldestRemainingModifiedAt = modified;
      }
    }
    return CleanupReport(
      checkedAt: DateTime.now().toUtc(),
      retentionDays: retentionDays,
      deletedFiles: deletedFiles,
      remainingFiles: remainingFiles,
      nonCompliantFiles: nonCompliantFiles,
      oldestRemainingModifiedAt: oldestRemainingModifiedAt,
    );
  }

  Future<RunCleanupReport> _cleanupRunArtifacts({
    required Directory stateDir,
    required int retentionDays,
    required WorkerLogger logger,
  }) async {
    final cutoff = DateTime.now().toUtc().subtract(
      Duration(days: retentionDays),
    );
    final runsDir = Directory('${stateDir.path}/runs');
    var runFilesDeleted = 0;
    if (await runsDir.exists()) {
      await for (final entity in runsDir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.endsWith('.json')) continue;
        final stat = await entity.stat();
        if (stat.modified.toUtc().isBefore(cutoff)) {
          try {
            await entity.delete();
            runFilesDeleted++;
            await logger.info(
              'maintenance',
              'Deleted old run artifact: ${entity.path}',
            );
          } catch (_) {
            await logger.warn(
              'maintenance',
              'Failed to delete old run artifact: ${entity.path}',
            );
          }
        }
      }
    }

    final indexFile = File('${stateDir.path}/runs_index.jsonl');
    var runsIndexPruned = 0;
    if (await indexFile.exists()) {
      final lines = await indexFile.readAsLines();
      final kept = <String>[];
      for (final line in lines) {
        final t = line.trim();
        if (t.isEmpty) continue;
        var keep = true;
        try {
          final decoded = jsonDecode(t) as Map<String, dynamic>;
          final finishedAtRaw = decoded['finished_at']?.toString();
          if (finishedAtRaw != null) {
            final finishedAt = DateTime.tryParse(finishedAtRaw)?.toUtc();
            if (finishedAt != null && finishedAt.isBefore(cutoff)) {
              keep = false;
            }
          }
        } catch (_) {
          keep = false;
        }
        if (keep) {
          kept.add(t);
        } else {
          runsIndexPruned++;
        }
      }
      await indexFile.writeAsString(kept.isEmpty ? '' : '${kept.join('\n')}\n');
    }

    return RunCleanupReport(
      runFilesDeleted: runFilesDeleted,
      runsIndexPruned: runsIndexPruned,
    );
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
  bpb_autoscan.dart rollback [options]
  bpb_autoscan.dart cleanup [options]

Options:
  --state-dir <path>       state dir (default: $_defaultStateDir)
  --log-dir <path>         log dir (default: $_defaultLogDir)
  --retention-days <n>     log retention days (default: $_defaultRetentionDays)
  --trigger <name>         trigger label (manual|scheduled|api)
  --host-label <name>      host/device label for history records
  --update-mode <name>     update mode label (panel_api|cloudflare_api|command)
  --scan-retries <n>       scan retries with backoff (default: 3)
  --apply-retries <n>      apply retries with backoff (default: 3)
  --min-working-ips <n>    require at least n working IPs before apply (default: $_defaultMinWorkingIps)
  --initial-retry-delay-ms retry backoff initial delay in ms (default: 1000)
  --max-retry-delay-ms <n> retry backoff cap in ms (default: $_defaultMaxRetryDelayMs)
  --requested-by <id>      audit label for caller (default: unknown)
  --request-ip <ip>        caller IP for audit metadata
  --scan-cmd <cmd>         shell command returning scan JSON on stdout
  --apply                  enable apply step after successful scan
  --apply-cmd <cmd>        shell command for apply step
''');
  }
}

class CleanupReport {
  CleanupReport({
    required this.checkedAt,
    required this.retentionDays,
    required this.deletedFiles,
    required this.remainingFiles,
    required this.nonCompliantFiles,
    required this.oldestRemainingModifiedAt,
    this.runFilesDeleted = 0,
    this.runsIndexPruned = 0,
  });

  final DateTime checkedAt;
  final int retentionDays;
  final int deletedFiles;
  final int remainingFiles;
  final int nonCompliantFiles;
  final DateTime? oldestRemainingModifiedAt;
  final int runFilesDeleted;
  final int runsIndexPruned;

  CleanupReport withRunStats({
    required int runFilesDeleted,
    required int runsIndexPruned,
  }) {
    return CleanupReport(
      checkedAt: checkedAt,
      retentionDays: retentionDays,
      deletedFiles: deletedFiles,
      remainingFiles: remainingFiles,
      nonCompliantFiles: nonCompliantFiles,
      oldestRemainingModifiedAt: oldestRemainingModifiedAt,
      runFilesDeleted: runFilesDeleted,
      runsIndexPruned: runsIndexPruned,
    );
  }

  Map<String, dynamic> toJson() => {
    'checked_at': checkedAt.toUtc().toIso8601String(),
    'retention_days': retentionDays,
    'deleted_files': deletedFiles,
    'remaining_files': remainingFiles,
    'non_compliant_files': nonCompliantFiles,
    'compliant': nonCompliantFiles == 0,
    'run_files_deleted': runFilesDeleted,
    'runs_index_pruned': runsIndexPruned,
    'oldest_remaining_modified_at': oldestRemainingModifiedAt
        ?.toUtc()
        .toIso8601String(),
  };
}

class RunCleanupReport {
  RunCleanupReport({
    required this.runFilesDeleted,
    required this.runsIndexPruned,
  });

  final int runFilesDeleted;
  final int runsIndexPruned;
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
