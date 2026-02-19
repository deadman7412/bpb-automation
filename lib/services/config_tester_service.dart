import 'dart:async';
import 'dart:io';
import '../models/xray_config.dart';
import '../models/config_test_result.dart';
import 'log_service.dart';

/// Which scanning phase a [TlsTestProgress] event belongs to.
enum ScanPhaseType { tcp, tls }

/// Service for testing candidate IPs using Xray configs.
///
/// Phase 0 — Two-probe TCP filter (1 s per probe, 100 ms gap, 200 concurrent):
///   Two sequential TCP connections to candidate:443. Both must pass.
///   Eliminates IPs with >50 % loss or unstable routing. Survivors sorted by
///   average TCP latency ascending.
///
/// Phase 1a — First TLS pass (3 s, 200 concurrent):
///   Full TLS handshake. Confirms the IP is a reachable Cloudflare edge.
///   Sort key: TLS handshake latency.
///
/// Phase 1b — Second TLS pass — re-validation (3 s, 200 concurrent):
///   Re-tests Phase 1a survivors only. An IP that passes two independent TLS
///   tests is genuinely stable. Only IPs that pass BOTH passes are kept.
///   Final sort key: avg(1a, 1b) + |1a - 1b| * 0.5  (jitter penalty).
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
      'Starting scan for ${candidateIPs.length} IPs '
      '(TCP 2-probe/1s, TLS 2-pass/${tlsTimeoutSeconds}s, concurrency: $maxConcurrency)',
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
    _logService.logInfo(
      'Phase 0 TCP: checking $total IPs on port $port (2 probes each)...',
    );

    _emitProgress(TlsTestProgress(
      phase: ScanPhaseType.tcp,
      totalIPs: total,
      processedIPs: 0,
      successfulIPs: 0,
      failedIPs: 0,
    ));

    const tcpTimeout = Duration(seconds: 1);
    const probeGap = Duration(milliseconds: 100);

    // Shared list — each lambda appends immediately so cancel preserves results
    final tcpResults = <_TcpProbeResult>[];
    int checkedCount = 0;

    final batches = _createBatches(candidateIPs, maxConcurrency);
    final batchCount = batches.length;

    for (int bi = 0; bi < batchCount; bi++) {
      if (_isCancelled) break;

      final batch = batches[bi];
      final batchStart = DateTime.now();

      // Race batch against cancel — on cancel Future.any returns immediately.
      // Results already appended inside each lambda are kept.
      await Future.any<void>([
        Future.wait(batch.map((ip) async {
          // Probe 1
          final sw1 = Stopwatch()..start();
          bool probe1Passed = false;
          try {
            final s = await Socket.connect(ip, port, timeout: tcpTimeout);
            await s.close();
            probe1Passed = true;
          } catch (_) {}
          sw1.stop();
          final lat1 = sw1.elapsedMilliseconds.toDouble();

          if (!probe1Passed) {
            checkedCount++;
            return;
          }

          // Brief gap to catch IPs that only pass momentarily
          await Future.delayed(probeGap);

          // Probe 2
          final sw2 = Stopwatch()..start();
          bool probe2Passed = false;
          try {
            final s = await Socket.connect(ip, port, timeout: tcpTimeout);
            await s.close();
            probe2Passed = true;
          } catch (_) {}
          sw2.stop();
          final lat2 = sw2.elapsedMilliseconds.toDouble();

          checkedCount++;

          if (probe2Passed) {
            final avgLatency = (lat1 + lat2) / 2;
            tcpResults.add(_TcpProbeResult(ip: ip, avgLatencyMs: avgLatency));
          }
        })).then((_) {}),
        _cancelSignal.future,
      ]);

      if (_isCancelled) break;

      final batchMs = DateTime.now().difference(batchStart).inMilliseconds;
      _logService.logInfo(
        'TCP batch ${bi + 1}/$batchCount done in ${batchMs}ms:'
        ' ${tcpResults.length} passed both probes ($checkedCount/$total checked)',
      );

      _emitProgress(TlsTestProgress(
        phase: ScanPhaseType.tcp,
        totalIPs: total,
        processedIPs: checkedCount,
        successfulIPs: tcpResults.length,
        failedIPs: checkedCount - tcpResults.length,
      ));
    }

    // Sort survivors by average latency — fastest IPs go first into Phase 1
    tcpResults.sort((a, b) => a.avgLatencyMs.compareTo(b.avgLatencyMs));

    _logService.logOk(
      'Phase 0 complete: ${tcpResults.length}/$total passed both TCP probes'
      ' (sorted by avg latency)',
    );
    return tcpResults.map((r) => r.ip).toList();
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
    final timeout = Duration(seconds: tlsTimeoutSeconds);

    // --- Phase 1a: first TLS pass on all candidates ---
    _logService.logInfo(
      'Phase 1a TLS: $total IPs (timeout: ${tlsTimeoutSeconds}s)',
    );
    final pass1Latencies = await _tlsSinglePassBatch(
      ips: candidateIPs,
      template: template,
      port: port,
      sni: sni,
      timeout: timeout,
      maxConcurrency: maxConcurrency,
      passLabel: '1a',
    );

    if (_isCancelled) return [];

    _logService.logOk(
      'Phase 1a complete: ${pass1Latencies.length}/$total passed TLS',
    );

    if (pass1Latencies.isEmpty) return [];

    // --- Phase 1b: re-validate survivors only ---
    final pass1IPs = pass1Latencies.keys.toList();
    _logService.logInfo(
      'Phase 1b TLS: ${pass1IPs.length} survivors (re-validation)',
    );
    final pass2Latencies = await _tlsSinglePassBatch(
      ips: pass1IPs,
      template: template,
      port: port,
      sni: sni,
      timeout: timeout,
      maxConcurrency: maxConcurrency,
      passLabel: '1b',
    );

    _logService.logOk(
      'Phase 1b complete: ${pass2Latencies.length}/${pass1IPs.length} re-validated',
    );

    // --- Combine: only IPs that passed both passes ---
    final results = <ConfigTestResult>[];
    for (final ip in pass2Latencies.keys) {
      final lat1 = pass1Latencies[ip]!;
      final lat2 = pass2Latencies[ip]!;
      final avgLatency = (lat1 + lat2) / 2;
      final jitter = (lat1 - lat2).abs();

      results.add(
        ConfigTestResult.fromTlsTest(
          ip: ip,
          config: template.copyWithAddress(ip),
          tlsTestResult: TlsTestResult.success(
            latencyMs: avgLatency,
            jitterMs: jitter,
          ),
        ),
      );
    }

    // Sort by sortScore = avg_latency + jitter * 0.5 (penalise instability)
    results.sort(
      (a, b) => a.tlsTestResult!.sortScore.compareTo(b.tlsTestResult!.sortScore),
    );

    _emitProgress(TlsTestProgress(
      phase: ScanPhaseType.tls,
      totalIPs: pass1IPs.length,
      processedIPs: pass1IPs.length,
      successfulIPs: results.length,
      failedIPs: pass1IPs.length - results.length,
      passLabel: 'done',
    ));

    _logService.logOk(
      'Phase 1 complete: ${results.length} IPs passed both TLS passes'
      '${_isCancelled ? " (cancelled early)" : ""}',
    );

    return results;
  }

  /// Runs a single concurrent TLS pass over [ips].
  ///
  /// Returns a map of ip -> latencyMs for every IP that completed a successful
  /// TLS handshake. IPs that timed out or errored are absent from the map.
  Future<Map<String, double>> _tlsSinglePassBatch({
    required List<String> ips,
    required XrayConfig template,
    required int port,
    required String? sni,
    required Duration timeout,
    required int maxConcurrency,
    required String passLabel,
  }) async {
    final latencies = <String, double>{};
    int processedIPs = 0;
    int successfulIPs = 0;

    // Convert internal passLabel ("1a"/"1b") to user-facing label ("1/2"/"2/2")
    final displayPassLabel = passLabel == '1a'
        ? '1/2'
        : passLabel == '1b'
        ? '2/2'
        : null;

    _emitProgress(TlsTestProgress(
      phase: ScanPhaseType.tls,
      totalIPs: ips.length,
      processedIPs: 0,
      successfulIPs: 0,
      failedIPs: 0,
      passLabel: displayPassLabel,
    ));

    final batches = _createBatches(ips, maxConcurrency);
    final batchCount = batches.length;

    for (int bi = 0; bi < batchCount; bi++) {
      if (_isCancelled) break;

      final batch = batches[bi];
      final batchStart = DateTime.now();
      final startTs = '${batchStart.hour.toString().padLeft(2, '0')}:'
          '${batchStart.minute.toString().padLeft(2, '0')}:'
          '${batchStart.second.toString().padLeft(2, '0')}';
      _logService.logInfo(
        'Phase $passLabel batch ${bi + 1}/$batchCount: ${batch.length} IPs'
        ' (started $startTs)',
      );

      final batchErrors = <String, int>{};

      await Future.any<void>([
        Future.wait(batch.map((ip) async {
          final result = await _testSingleIPTLS(
            config: template,
            candidateIP: ip,
            port: port,
            sni: sni,
            timeout: timeout,
          );

          processedIPs++;
          if (result.tlsPassed) {
            successfulIPs++;
            latencies[ip] = result.tlsTestResult!.latencyMs;
          } else {
            final errKey = result.tlsTestResult?.error ?? 'unknown';
            batchErrors[errKey] = (batchErrors[errKey] ?? 0) + 1;
          }

          if (processedIPs % 10 == 0 || result.tlsPassed) {
            _emitProgress(TlsTestProgress(
              phase: ScanPhaseType.tls,
              totalIPs: ips.length,
              processedIPs: processedIPs,
              successfulIPs: successfulIPs,
              failedIPs: processedIPs - successfulIPs,
              currentIP: result.tlsPassed ? ip : null,
              passLabel: displayPassLabel,
            ));
          }
        })).then((_) {}),
        _cancelSignal.future,
      ]);

      if (_isCancelled) {
        _logService.logWarn(
          'Phase $passLabel cancelled — $successfulIPs/$processedIPs passed so far',
        );
        break;
      }

      final batchMs = DateTime.now().difference(batchStart).inMilliseconds;
      _logService.logInfo(
        'Phase $passLabel batch ${bi + 1}/$batchCount done in ${batchMs}ms:'
        ' $successfulIPs/$processedIPs passed',
      );

      if (batchErrors.isNotEmpty) {
        final sorted = batchErrors.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        for (final e in sorted.take(5)) {
          _logService.logInfo('  [$passLabel errors] ${e.value}x ${e.key}');
        }
      }
    }

    return latencies;
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

/// Internal result holder for Phase 0 two-probe TCP filter.
class _TcpProbeResult {
  final String ip;
  final double avgLatencyMs;
  const _TcpProbeResult({required this.ip, required this.avgLatencyMs});
}

/// Progress event emitted during Phase 0 (TCP) and Phase 1 (TLS).
class TlsTestProgress {
  final ScanPhaseType phase;
  final int totalIPs;
  final int processedIPs;
  final int successfulIPs;
  final int failedIPs;
  final String? currentIP;

  /// Human-readable pass label for two-pass TLS.
  /// "1/2" during Phase 1a, "2/2" during Phase 1b, null otherwise.
  final String? passLabel;

  const TlsTestProgress({
    this.phase = ScanPhaseType.tls,
    required this.totalIPs,
    required this.processedIPs,
    required this.successfulIPs,
    required this.failedIPs,
    this.currentIP,
    this.passLabel,
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
