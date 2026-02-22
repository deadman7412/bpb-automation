import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/update_mode.dart';
import '../models/config_scan_result.dart';
import '../models/xray_config.dart';
import 'cloudflare_api_service.dart';
import 'dart_scanner_service.dart';
import 'log_service.dart';
import 'native_notification_service.dart';
import 'panel_api_service.dart';
import 'server_backend_service.dart';
import 'storage_service.dart';
import 'subscription_service.dart';

class LocalSchedulerStatus {
  const LocalSchedulerStatus({
    required this.enabled,
    required this.intervalHours,
    required this.running,
    this.nextRunAt,
    this.lastRunAt,
    this.lastResult,
    this.lastError,
  });

  final bool enabled;
  final int intervalHours;
  final bool running;
  final DateTime? nextRunAt;
  final DateTime? lastRunAt;
  final String? lastResult;
  final String? lastError;

  LocalSchedulerStatus copyWith({
    bool? enabled,
    int? intervalHours,
    bool? running,
    DateTime? nextRunAt,
    bool clearNextRunAt = false,
    DateTime? lastRunAt,
    bool clearLastRunAt = false,
    String? lastResult,
    bool clearLastResult = false,
    String? lastError,
    bool clearLastError = false,
  }) {
    return LocalSchedulerStatus(
      enabled: enabled ?? this.enabled,
      intervalHours: intervalHours ?? this.intervalHours,
      running: running ?? this.running,
      nextRunAt: clearNextRunAt ? null : (nextRunAt ?? this.nextRunAt),
      lastRunAt: clearLastRunAt ? null : (lastRunAt ?? this.lastRunAt),
      lastResult: clearLastResult ? null : (lastResult ?? this.lastResult),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}

class LocalSchedulerService {
  LocalSchedulerService._();
  static final LocalSchedulerService instance = LocalSchedulerService._();

  static const String localSchedulerEnabledKey = 'local_scheduler_enabled';
  static const String localSchedulerIntervalKey =
      'local_scheduler_interval_hours';
  static const String _keyLastRunAtMs = 'local_scheduler_last_run_at_ms';
  static const String _keyNextRunAtMs = 'local_scheduler_next_run_at_ms';
  static const String _keyLastResult = 'local_scheduler_last_result';
  static const String _keyLastError = 'local_scheduler_last_error';

  final StorageService _storage = StorageService.instance;
  final LogService _log = LogService.instance;
  final SubscriptionService _subscription = SubscriptionService.instance;
  final DartScannerService _scanner = DartScannerService.instance;
  final ServerBackendService _serverApi = ServerBackendService.instance;
  final PanelApiService _panelApi = PanelApiService.instance;
  final CloudflareApiService _cloudflareApi = CloudflareApiService.instance;
  final NativeNotificationService _notifications =
      NativeNotificationService.instance;

  final StreamController<LocalSchedulerStatus> _statusController =
      StreamController<LocalSchedulerStatus>.broadcast();

  LocalSchedulerStatus _status = const LocalSchedulerStatus(
    enabled: false,
    intervalHours: 6,
    running: false,
  );
  Timer? _timer;
  bool _initialized = false;
  Future<void>? _initializeFuture;

  LocalSchedulerStatus get status => _status;
  Stream<LocalSchedulerStatus> get statusStream => _statusController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    if (_initializeFuture != null) {
      return _initializeFuture!;
    }
    _initializeFuture = _initializeInternal();
    return _initializeFuture!;
  }

  Future<void> _initializeInternal() async {
    try {
      final enabled = await _storage.getBool(localSchedulerEnabledKey) ?? false;
      final interval = await _storage.getInt(localSchedulerIntervalKey) ?? 6;
      final lastRunAtMs = await _storage.getInt(_keyLastRunAtMs);
      final lastResult = await _storage.getString(_keyLastResult);
      final lastError = await _storage.getString(_keyLastError);

      _status = LocalSchedulerStatus(
        enabled: enabled,
        intervalHours: interval.clamp(1, 24),
        running: false,
        lastRunAt: _dateFromMs(lastRunAtMs),
        lastResult: _nonEmptyOrNull(lastResult),
        lastError: _nonEmptyOrNull(lastError),
      );

      _emitStatus();
      if (enabled) {
        _scheduleNextRun(resetAnchor: false);
        _log.logInfo(
          'Local scheduler initialized (enabled=true, interval=${_status.intervalHours}h)',
        );
      } else {
        _log.logInfo('Local scheduler initialized (enabled=false)');
      }
      _initialized = true;
    } finally {
      _initializeFuture = null;
    }
  }

  Future<void> applySettings({
    required bool enabled,
    required int intervalHours,
  }) async {
    final normalizedInterval = intervalHours.clamp(1, 24);
    await _storage.saveBool(localSchedulerEnabledKey, enabled);
    await _storage.saveInt(localSchedulerIntervalKey, normalizedInterval);

    _status = _status.copyWith(
      enabled: enabled,
      intervalHours: normalizedInterval,
      clearLastError: true,
    );
    if (!enabled) {
      _cancelTimer();
      await _storage.remove(_keyNextRunAtMs);
      _status = _status.copyWith(clearNextRunAt: true);
      _log.logInfo('Local scheduler disabled');
      _emitStatus();
      return;
    }

    _scheduleNextRun(resetAnchor: true);
    _log.logInfo('Local scheduler updated (interval=${normalizedInterval}h)');
  }

  Future<void> runNow({String trigger = 'manual'}) async {
    if (!_status.enabled) {
      throw StateError('Local scheduler is disabled');
    }
    await _runScheduledJob(trigger: trigger, scheduleNextWhenDone: true);
  }

  void _emitStatus() {
    _statusController.add(_status);
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  DateTime? _dateFromMs(int? ms) {
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  String? _nonEmptyOrNull(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> _scheduleNextRun({required bool resetAnchor}) async {
    _cancelTimer();
    if (!_status.enabled) return;

    final now = DateTime.now();
    final anchor = (!resetAnchor && _status.lastRunAt != null)
        ? _status.lastRunAt!
        : now;
    var nextRun = anchor.add(Duration(hours: _status.intervalHours));
    if (!nextRun.isAfter(now)) {
      nextRun = now.add(Duration(minutes: 1));
    }

    await _storage.saveInt(_keyNextRunAtMs, nextRun.millisecondsSinceEpoch);
    _status = _status.copyWith(nextRunAt: nextRun);
    _emitStatus();

    final delay = nextRun.difference(now);
    _timer = Timer(delay, () {
      unawaited(
        _runScheduledJob(trigger: 'scheduled', scheduleNextWhenDone: true),
      );
    });

    _log.logInfo(
      'Local scheduler next run planned at ${nextRun.toIso8601String()}',
    );
  }

  Future<void> _runScheduledJob({
    required String trigger,
    required bool scheduleNextWhenDone,
  }) async {
    if (!_status.enabled) {
      _log.logInfo('Local scheduler run ignored: scheduler disabled');
      return;
    }

    if (_status.running) {
      _log.logWarn(
        'Local scheduler run skipped: another run is already active',
      );
      if (scheduleNextWhenDone) {
        await _scheduleNextRun(resetAnchor: false);
      }
      return;
    }

    _status = _status.copyWith(running: true, clearLastError: true);
    _emitStatus();
    _log.logInfo('Local scheduler run started (trigger=$trigger)');
    await _notifications.notifySchedulerStarted(detail: 'Trigger: $trigger');

    try {
      final resultMessage = await _executeRun(trigger: trigger);
      final runAt = DateTime.now();
      await _storage.saveInt(_keyLastRunAtMs, runAt.millisecondsSinceEpoch);
      await _storage.saveString(_keyLastResult, resultMessage);
      await _storage.remove(_keyLastError);

      _status = _status.copyWith(
        running: false,
        lastRunAt: runAt,
        lastResult: resultMessage,
        clearLastError: true,
      );
      _emitStatus();
      _log.logOk('Local scheduler run completed: $resultMessage');
      await _notifications.notifySchedulerFinished(detail: resultMessage);
    } catch (e, st) {
      final message = e.toString();
      await _storage.saveString(_keyLastError, message);
      _status = _status.copyWith(running: false, lastError: message);
      _emitStatus();
      _log.logError('Local scheduler run failed', e, st);
      await _notifications.notifySchedulerFailed(detail: message);
    } finally {
      if (scheduleNextWhenDone) {
        await _scheduleNextRun(resetAnchor: false);
      }
    }
  }

  Future<String> _executeRun({required String trigger}) async {
    final useServerBackend = await _storage.getUseServerBackend();
    if (useServerBackend) {
      await _executeServerRun(trigger: trigger);
      return 'Server run accepted';
    }

    final result = await _executeLocalScan(trigger: trigger);
    final working = result.workingIPs.length;
    var summary = 'Local scan completed (working_ips=$working)';

    final shouldAutoApply = await _storage.getAutoApplyAfterScan();
    if (shouldAutoApply && working > 0) {
      final applied = await _autoApply(result.workingIPs);
      summary = '$summary, auto_apply=${applied ? "ok" : "failed"}';
    } else if (shouldAutoApply) {
      summary = '$summary, auto_apply=skipped(no_ips)';
    }

    return summary;
  }

  Future<void> _executeServerRun({required String trigger}) async {
    final baseUrl = (await _storage.getServerBackendBaseUrl())?.trim() ?? '';
    final token = await _resolveServerToken();
    if (baseUrl.isEmpty || token.isEmpty) {
      throw StateError(
        'Server backend mode is enabled but server URL/token is missing',
      );
    }
    await _serverApi.triggerRun(
      baseUrl: baseUrl,
      token: token,
      trigger: trigger,
    );
  }

  Future<String> _resolveServerToken() async {
    final jwt = (await _storage.getServerBackendJwt())?.trim() ?? '';
    final internalToken =
        (await _storage.getServerBackendToken())?.trim() ?? '';
    if (kIsWeb) return jwt;
    if (internalToken.isNotEmpty) return internalToken;
    return jwt;
  }

  Future<ConfigScanResult> _executeLocalScan({required String trigger}) async {
    if (_scanner.isScanning) {
      throw StateError('Local scanner is already running');
    }

    final url = (await _storage.getSubscriptionUrl())?.trim() ?? '';
    if (url.isEmpty) {
      throw StateError('Subscription URL is not configured');
    }

    final params = await _storage.getScanParameters();
    final desiredIPCount = params['desiredIPCount'] ?? 5;
    final phase2TestDepth = params['phase2TestDepth'] ?? 50;
    final enableIPv6 = params['enableIPv6'] == 1;
    final ipPoolSize = params['ipPoolSize'] ?? 1000;
    final batchSize = params['scanBatchSize'] ?? 200;
    final fullScan = await _storage.getFullScan();

    _log.logInfo('Local scheduler loading subscription configs');
    var configs = await _subscription.fetchConfigs(url);
    if (configs.isEmpty) {
      final cached = await _storage.getCachedConfigs();
      if (cached != null && cached.isNotEmpty) {
        configs = cached
            .map((json) => XrayConfig.fromJson(json as Map<String, dynamic>))
            .toList();
        _log.logWarn(
          'Local scheduler using cached configs because subscription refresh failed',
        );
      }
    }
    if (configs.isEmpty) {
      throw StateError('No valid configs available for scheduled local scan');
    }

    final result = await _scanner.executeConfigScanWithConfigs(
      configs: configs,
      desiredIPCount: desiredIPCount,
      phase2TestDepth: phase2TestDepth,
      enableIPv6: enableIPv6,
      ipPoolSize: ipPoolSize,
      batchSize: batchSize,
      fullScan: fullScan,
    );

    await _storage.saveLastScanTime(result.timestamp);
    await _storage.saveLastScanResult(result.toJson());

    _log.logInfo(
      'Local scheduler scan finished (trigger=$trigger, working_ips=${result.workingIPCount})',
    );
    return result;
  }

  Future<bool> _autoApply(List<String> workingIps) async {
    final mode = await _storage.getUpdateMode();
    try {
      if (mode == UpdateMode.cloudflareApi) {
        final credentials = await _storage.getCredentials();
        if (credentials == null) {
          throw StateError(
            'Cloudflare credentials are missing while auto-apply is enabled',
          );
        }
        await _cloudflareApi.updateCleanIPs(credentials, workingIps);
      } else {
        final credentials = await _storage.getPanelCredentials();
        if (credentials == null) {
          throw StateError(
            'Panel credentials are missing while auto-apply is enabled',
          );
        }
        await _panelApi.updateCleanIPs(credentials, workingIps);
      }
      return true;
    } catch (e, st) {
      _log.logError('Local scheduler auto-apply failed', e, st);
      return false;
    }
  }
}
