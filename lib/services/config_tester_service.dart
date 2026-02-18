import 'dart:async';
import 'dart:io';
import '../models/xray_config.dart';
import '../models/config_test_result.dart';
import 'log_service.dart';

/// Which scanning phase a [TlsTestProgress] event belongs to.
enum ScanPhaseType { tcp, tls }

/// Service for testing candidate IPs using Xray configs.
///
/// Phase 0 — TCP port check (1 s, 200 concurrent):
///   Connects TCP to candidate:443. Eliminates ~70-85 % of candidates.
///
/// Phase 1 — TLS handshake (3 s, 200 concurrent):
///   Full TLS handshake. Confirms the IP is a reachable Cloudflare edge.
///
/// Cancellation: cancel() fires a Completer that races against every batch
/// via Future.any. The batch is abandoned immediately; results already
/// collected (added to a shared list inside each IP lambda) are preserved.
class ConfigTesterService {
  static final ConfigTesterService _instance = ConfigTesterService._internal();
  static ConfigTesterService get instance => _instance;

  ConfigTesterService._internal();

  final LogService _logService = LogService.instance;

  bool _isCancelled = false;
  Completer<void> _cancelSignal = Completer<void>();

  final StreamController<TlsTestProgress> _progressController =
      StreamController<TlsTestProgress>.broadcast();

  Stream<TlsTestProgress> get progressStream => _progressController.stream;

  /// Last emitted progress per phase — lets newly-attached screens show current state.
  TlsTestProgress? _lastTcpProgress;
  TlsTestProgress? _lastTlsProgress;
  TlsTestProgress? get lastTcpProgress => _lastTcpProgress;
  TlsTestProgress? get lastTlsProgress => _lastTlsProgress;

  /// Stop immediately. The current batch is abandoned via Future.any;
  /// results already collected are preserved and returned.
  void cancel() {
    _isCancelled = true;
    if (!_cancelSignal.isCompleted) _cancelSignal.complete();
  }

  /// Reset before each new scan.
  void resetCancel() {
    _isCancelled = false;
    _cancelSignal = Completer<void>();
    _lastTcpProgress = null;
    _lastTlsProgress = null;
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  Future<List<ConfigTestResult>> testIPsWithTLS({
    required XrayConfig template,
    required List<String> candidateIPs,
    int tlsTimeoutSeconds = 3,
    int maxConcurrency = 200,
    @Deprecated('CDN verification removed') bool verifyCdn = false,
    @Deprecated('Use tlsTimeoutSeconds') int timeoutSeconds = 3,
  }) async {
    _logService.logInfo(
      'Starting TLS scan for ${candidateIPs.length} IPs '
      '(TCP 1 s, TLS ${tlsTimeoutSeconds}s, concurrency: $maxConcurrency)',
    );

    if (!template.isValid()) {
      _logService.logError(
        'Invalid config: ${template.getValidationErrors().join(", ")}',
      );
      return [];
    }

    final port = template.getServerPort();
    final sni = template.getSni();
    final isSecure = template.isSecure();

    if (port == null) {
      _logService.logError('Config has no port configured');
      return [];
    }
    if (!isSecure) _logService.logWarn('Config has no TLS/Reality security');

    _logService.logInfo('port=$port, SNI=$sni, secure=$isSecure');

    // Phase 0: TCP pre-filter
    final tcpPassed = await _tcpPreFilter(
      candidateIPs: candidateIPs,
      port: port,
      maxConcurrency: maxConcurrency,
    );

    if (_isCancelled) return [];

    // Phase 1: TLS on survivors
    return _tlsTest(
      template: template,
      candidateIPs: tcpPassed,
      port: port,
      sni: sni,
      tlsTimeoutSeconds: tlsTimeoutSeconds,
      maxConcurrency: maxConcurrency,
    );
  }

  // -------------------------------------------------------------------------
  // Phase 0 — TCP
  // -------------------------------------------------------------------------

  Future<List<String>> _tcpPreFilter({
    required List<String> candidateIPs,
    required int port,
    required int maxConcurrency,
  }) async {
    final total = candidateIPs.length;
    _logService.logInfo('Phase 0 TCP: checking $total IPs on port $port...');

    _emitProgress(TlsTestProgress(
      phase: ScanPhaseType.tcp,
      totalIPs: total,
      processedIPs: 0,
      successfulIPs: 0,
      failedIPs: 0,
    ));

    const tcpTimeout = Duration(seconds: 1);
    // Shared list — each lambda appends immediately so cancel preserves results
    final passed = <String>[];
    int checkedCount = 0;

    final batches = _createBatches(candidateIPs, maxConcurrency);
    final batchCount = batches.length;

    for (int bi = 0; bi < batchCount; bi++) {
      if (_isCancelled) break;

      final batch = batches[bi];
      final batchStart = DateTime.now();

      // Race batch against cancel — on cancel Future.any returns immediately.
      // Results already appended to `passed` inside each lambda are kept.
      await Future.any<void>([
        Future.wait(batch.map((ip) async {
          try {
            final s = await Socket.connect(ip, port, timeout: tcpTimeout);
            await s.close();
            passed.add(ip);
          } catch (_) {
            // unreachable — skip
          }
          checkedCount++;
        })).then((_) {}),
        _cancelSignal.future,
      ]);

      if (_isCancelled) break;

      final batchMs = DateTime.now().difference(batchStart).inMilliseconds;
      _logService.logInfo(
        'TCP batch ${bi + 1}/$batchCount done in ${batchMs}ms:'
        ' ${passed.length} reachable ($checkedCount/$total checked)',
      );

      _emitProgress(TlsTestProgress(
        phase: ScanPhaseType.tcp,
        totalIPs: total,
        processedIPs: checkedCount,
        successfulIPs: passed.length,
        failedIPs: checkedCount - passed.length,
      ));
    }

    _logService.logOk(
      'Phase 0 complete: ${passed.length}/$total reachable on port $port',
    );
    return passed;
  }

  // -------------------------------------------------------------------------
  // Phase 1 — TLS
  // -------------------------------------------------------------------------

  Future<List<ConfigTestResult>> _tlsTest({
    required XrayConfig template,
    required List<String> candidateIPs,
    required int port,
    required String? sni,
    required int tlsTimeoutSeconds,
    required int maxConcurrency,
  }) async {
    if (candidateIPs.isEmpty) return [];

    final total = candidateIPs.length;
    _logService.logInfo('Phase 1 TLS: $total IPs (timeout: ${tlsTimeoutSeconds}s)');

    final timeout = Duration(seconds: tlsTimeoutSeconds);

    // Shared list — each IP lambda appends as it completes.
    // When cancel fires, Future.any returns immediately but results already
    // in this list are preserved (no batch-level discard).
    final results = <ConfigTestResult>[];
    int processedIPs = 0;
    int successfulIPs = 0;
    int failedIPs = 0;

    _emitProgress(TlsTestProgress(
      phase: ScanPhaseType.tls,
      totalIPs: total,
      processedIPs: 0,
      successfulIPs: 0,
      failedIPs: 0,
    ));

    final batches = _createBatches(candidateIPs, maxConcurrency);
    final batchCount = batches.length;

    for (int bi = 0; bi < batchCount; bi++) {
      if (_isCancelled) break;

      final batch = batches[bi];
      final batchStart = DateTime.now();
      final startTs = '${batchStart.hour.toString().padLeft(2, '0')}:'
          '${batchStart.minute.toString().padLeft(2, '0')}:'
          '${batchStart.second.toString().padLeft(2, '0')}';
      _logService.logInfo(
        'Phase 1 batch ${bi + 1}/$batchCount: testing ${batch.length} IPs'
        ' (started $startTs, timeout ${tlsTimeoutSeconds}s each)',
      );

      // Per-batch error tally for diagnostics
      final batchErrors = <String, int>{};

      // Race batch against cancel.
      await Future.any<void>([
        Future.wait(batch.map((ip) async {
          final result = await _testSingleIPTLS(
            config: template,
            candidateIP: ip,
            port: port,
            sni: sni,
            timeout: timeout,
          );

          // Append immediately — visible even if the batch is abandoned by cancel
          results.add(result);
          processedIPs++;
          if (result.tlsPassed) {
            successfulIPs++;
          } else {
            failedIPs++;
            final errKey = result.tlsTestResult?.error ?? 'unknown';
            batchErrors[errKey] = (batchErrors[errKey] ?? 0) + 1;
          }

          if (processedIPs % 10 == 0 || result.tlsPassed) {
            _emitProgress(TlsTestProgress(
              phase: ScanPhaseType.tls,
              totalIPs: total,
              processedIPs: processedIPs,
              successfulIPs: successfulIPs,
              failedIPs: failedIPs,
              currentIP: result.tlsPassed ? ip : null,
            ));
          }
        })).then((_) {}),
        _cancelSignal.future,
      ]);

      if (_isCancelled) {
        _logService.logWarn(
          'Phase 1 cancelled — ${results.length} results collected, '
          '$successfulIPs passed TLS so far',
        );
        break;
      }

      final batchMs = DateTime.now().difference(batchStart).inMilliseconds;
      _logService.logInfo(
        'Phase 1 batch ${bi + 1}/$batchCount done in ${batchMs}ms:'
        ' $successfulIPs/$processedIPs passed TLS',
      );

      // Log error breakdown so we can see WHY IPs are failing
      if (batchErrors.isNotEmpty) {
        final sorted = batchErrors.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        for (final e in sorted.take(5)) {
          _logService.logInfo('  [batch errors] ${e.value}x ${e.key}');
        }
      }
    }

    _emitProgress(TlsTestProgress(
      phase: ScanPhaseType.tls,
      totalIPs: total,
      processedIPs: processedIPs,
      successfulIPs: successfulIPs,
      failedIPs: failedIPs,
    ));

    final successfulResults = results.where((r) => r.tlsPassed).toList()
      ..sort((a, b) => a.finalLatencyMs.compareTo(b.finalLatencyMs));

    _logService.logOk(
      'Phase 1 TLS complete: ${successfulResults.length}/$total passed'
      '${_isCancelled ? " (cancelled early)" : ""}',
    );

    return successfulResults;
  }

  Future<ConfigTestResult> _testSingleIPTLS({
    required XrayConfig config,
    required String candidateIP,
    required int port,
    required String? sni,
    required Duration timeout,
  }) async {
    final sw = Stopwatch()..start();
    RawSocket? rawSocket;
    RawSecureSocket? secureSocket;
    Timer? timer;

    try {
      // Step 1: TCP connect.
      rawSocket = await RawSocket.connect(candidateIP, port, timeout: timeout);

      // Step 2: TLS handshake via RawSecureSocket + Completer + Timer.
      //
      // WHY RawSecureSocket instead of SecureSocket:
      // SecureSocket.secure(socket) calls socket._detachRaw() synchronously
      // before the handshake starts. After detach, the original `socket` object
      // no longer references the OS file descriptor — calling destroy() on it is
      // a no-op. This caused EMFILE (error 24) after a few batches because every
      // timed-out handshake leaked an FD until GC ran.
      //
      // RawSecureSocket.secure(rawSocket) does NOT detach/invalidate rawSocket.
      // It holds a direct reference to the same RawSocket object. Calling
      // rawSocket.close() in the timer therefore closes the actual OS FD,
      // aborting the in-progress handshake and releasing the descriptor.
      //
      // WHY sni, not candidateIP as host:
      // RFC 6066 forbids IP addresses in the TLS SNI extension. Cloudflare edge
      // nodes stall or reject the handshake when they receive an IP as SNI,
      // producing ~176 timeouts per 200-IP batch. Using the domain from the
      // config (e.g. the VLESS URL host) is the correct value.
      final tlsCompleter = Completer<RawSecureSocket>();

      RawSecureSocket.secure(
        rawSocket,
        host: sni ?? candidateIP,
        context: SecurityContext.defaultContext,
        onBadCertificate: (_) => true,
        supportedProtocols: ['h2', 'http/1.1'],
      ).then((s) {
        if (!tlsCompleter.isCompleted) {
          tlsCompleter.complete(s);
        } else {
          // Timer already fired — close the late-arriving socket immediately.
          s.close();
        }
      }, onError: (Object e) {
        if (!tlsCompleter.isCompleted) {
          tlsCompleter.completeError(e);
        }
      });

      timer = Timer(timeout, () {
        if (!tlsCompleter.isCompleted) {
          // rawSocket.close() releases the actual OS FD here because
          // RawSecureSocket holds a direct reference (not a detached copy).
          try {
            rawSocket?.close();
          } catch (_) {}
          rawSocket = null;
          tlsCompleter.completeError(TimeoutException('TLS handshake timeout'));
        }
      });

      secureSocket = await tlsCompleter.future;
      timer.cancel();
      timer = null;
      rawSocket = null; // RawSecureSocket now owns the RawSocket

      final latencyMs = sw.elapsedMilliseconds.toDouble();
      sw.stop();

      _logService.logInfo('TLS ok $candidateIP (${latencyMs.toStringAsFixed(0)}ms)');

      return ConfigTestResult.fromTlsTest(
        ip: candidateIP,
        config: config.copyWithAddress(candidateIP),
        tlsTestResult: TlsTestResult.success(latencyMs: latencyMs),
      );
    } on SocketException catch (e) {
      sw.stop();
      if (sw.elapsedMilliseconds < 50) {
        _logService.logInfo(
          'TLS instant-fail $candidateIP (${sw.elapsedMilliseconds}ms): '
          '[${e.osError?.errorCode ?? "?"}] ${e.message}',
        );
      }
      return ConfigTestResult.fromTlsTest(
        ip: candidateIP,
        config: config.copyWithAddress(candidateIP),
        tlsTestResult: TlsTestResult.failure(
          error: e.message,
          latencyMs: sw.elapsedMilliseconds.toDouble(),
        ),
      );
    } on TimeoutException {
      sw.stop();
      return ConfigTestResult.fromTlsTest(
        ip: candidateIP,
        config: config.copyWithAddress(candidateIP),
        tlsTestResult: TlsTestResult.failure(
          error: 'Timeout',
          latencyMs: timeout.inMilliseconds.toDouble(),
        ),
      );
    } on HandshakeException catch (e) {
      sw.stop();
      return ConfigTestResult.fromTlsTest(
        ip: candidateIP,
        config: config.copyWithAddress(candidateIP),
        tlsTestResult: TlsTestResult.failure(
          error: e.message,
          latencyMs: sw.elapsedMilliseconds.toDouble(),
        ),
      );
    } catch (e) {
      sw.stop();
      _logService.logInfo(
        'TLS unknown error $candidateIP (${sw.elapsedMilliseconds}ms):'
        ' ${e.runtimeType}: $e',
      );
      return ConfigTestResult.fromTlsTest(
        ip: candidateIP,
        config: config.copyWithAddress(candidateIP),
        tlsTestResult: TlsTestResult.failure(
          error: e.toString(),
          latencyMs: sw.elapsedMilliseconds.toDouble(),
        ),
      );
    } finally {
      timer?.cancel();
      await secureSocket?.close();
      try {
        rawSocket?.close();
      } catch (_) {}
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  List<List<String>> _createBatches(List<String> ips, int batchSize) {
    final batches = <List<String>>[];
    for (int i = 0; i < ips.length; i += batchSize) {
      batches.add(ips.sublist(i, (i + batchSize).clamp(0, ips.length)));
    }
    return batches;
  }

  void _emitProgress(TlsTestProgress progress) {
    if (progress.phase == ScanPhaseType.tcp) {
      _lastTcpProgress = progress;
    } else {
      _lastTlsProgress = progress;
    }
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  void dispose() {
    _progressController.close();
  }
}

/// Progress event emitted during Phase 0 (TCP) and Phase 1 (TLS).
class TlsTestProgress {
  final ScanPhaseType phase;
  final int totalIPs;
  final int processedIPs;
  final int successfulIPs;
  final int failedIPs;
  final String? currentIP;

  const TlsTestProgress({
    this.phase = ScanPhaseType.tls,
    required this.totalIPs,
    required this.processedIPs,
    required this.successfulIPs,
    required this.failedIPs,
    this.currentIP,
  });

  double get progress => totalIPs > 0 ? processedIPs / totalIPs : 0.0;
  double get progressPercent => progress * 100;
  double get successRate =>
      processedIPs > 0 ? successfulIPs / processedIPs : 0.0;
  double get successRatePercent => successRate * 100;

  @override
  String toString() {
    final ipPart = currentIP != null ? ', current: $currentIP' : '';
    return 'TlsTestProgress(${phase.name}: $processedIPs/$totalIPs '
        '${progressPercent.toStringAsFixed(1)}%, success: $successfulIPs, '
        'failed: $failedIPs$ipPart)';
  }
}
