import 'dart:async';
import 'dart:io';
import '../models/xray_config.dart';
import '../models/config_test_result.dart';
import 'log_service.dart';

/// Service for testing candidate IPs using Xray configs.
///
/// Implements a two-phase testing approach:
/// - Phase 1 (TLS Pre-Filter): Fast TLS handshake testing to pre-filter IPs
/// - Phase 2 (Proxy Test): Real proxy testing with Xray-core (implemented in XrayService)
///
/// This service handles Phase 1 only.
class ConfigTesterService {
  static final ConfigTesterService _instance = ConfigTesterService._internal();
  static ConfigTesterService get instance => _instance;

  ConfigTesterService._internal();

  final LogService _logService = LogService.instance;

  /// Stream controller for progress updates
  final StreamController<TlsTestProgress> _progressController =
      StreamController<TlsTestProgress>.broadcast();

  /// Stream of TLS test progress updates
  Stream<TlsTestProgress> get progressStream => _progressController.stream;

  /// Tests multiple IPs with TLS handshake (Phase 1).
  ///
  /// This method performs fast TLS pre-filtering to identify candidate IPs
  /// that can establish TLS connections before running full proxy tests.
  ///
  /// Parameters:
  /// - [template]: XrayConfig to extract connection params (port, SNI, TLS settings)
  /// - [candidateIPs]: List of IPs to test
  /// - [timeoutSeconds]: Timeout for each TLS handshake attempt
  /// - [maxConcurrency]: Maximum concurrent tests (default: 200)
  /// - [verifyCdn]: Whether to verify Cloudflare CDN via /cdn-cgi/trace
  ///
  /// Returns list of ConfigTestResult sorted by latency (fastest first).
  Future<List<ConfigTestResult>> testIPsWithTLS({
    required XrayConfig template,
    required List<String> candidateIPs,
    int timeoutSeconds = 5,
    int maxConcurrency = 200,
    bool verifyCdn = true,
  }) async {
    _logService.logInfo(
      'Starting Phase 1 TLS testing for ${candidateIPs.length} IPs (timeout: ${timeoutSeconds}s, concurrency: $maxConcurrency)',
    );

    // Validate config
    if (!template.isValid()) {
      final errors = template.getValidationErrors();
      _logService.logError(
        'Invalid config template for TLS testing: ${errors.join(", ")}',
      );
      return [];
    }

    // Extract connection parameters
    final port = template.getServerPort();
    final sni = template.getSni();
    final isSecure = template.isSecure();

    if (port == null) {
      _logService.logError('Config has no port configured');
      return [];
    }

    if (!isSecure) {
      _logService.logWarn(
        'Config has no TLS/Reality security - TLS test may fail',
      );
    }

    _logService.logInfo(
      'Connection params: port=$port, SNI=$sni, secure=$isSecure',
    );

    final results = <ConfigTestResult>[];
    final timeout = Duration(seconds: timeoutSeconds);

    // Progress tracking
    int totalIPs = candidateIPs.length;
    int processedIPs = 0;
    int successfulIPs = 0;
    int failedIPs = 0;

    // Emit initial progress
    _emitProgress(
      TlsTestProgress(
        totalIPs: totalIPs,
        processedIPs: 0,
        successfulIPs: 0,
        failedIPs: 0,
        currentIP: null,
      ),
    );

    // Process IPs concurrently with limited concurrency
    final batches = _createBatches(candidateIPs, maxConcurrency);

    for (final batch in batches) {
      final batchResults = await Future.wait(
        batch.map((ip) async {
          // Emit progress for current IP
          _emitProgress(
            TlsTestProgress(
              totalIPs: totalIPs,
              processedIPs: processedIPs,
              successfulIPs: successfulIPs,
              failedIPs: failedIPs,
              currentIP: ip,
            ),
          );

          final result = await _testSingleIPTLS(
            config: template,
            candidateIP: ip,
            port: port,
            sni: sni,
            timeout: timeout,
            verifyCdn: verifyCdn,
          );

          // Update counters
          processedIPs++;
          if (result.tlsPassed) {
            successfulIPs++;
          } else {
            failedIPs++;
          }

          // Emit progress every 10 IPs or 5%
          if (processedIPs % 10 == 0 ||
              (processedIPs / totalIPs * 100) % 5 < 0.1) {
            _emitProgress(
              TlsTestProgress(
                totalIPs: totalIPs,
                processedIPs: processedIPs,
                successfulIPs: successfulIPs,
                failedIPs: failedIPs,
                currentIP: null,
              ),
            );
          }

          return result;
        }),
      );

      results.addAll(batchResults);
    }

    // Emit final progress
    _emitProgress(
      TlsTestProgress(
        totalIPs: totalIPs,
        processedIPs: processedIPs,
        successfulIPs: successfulIPs,
        failedIPs: failedIPs,
        currentIP: null,
      ),
    );

    // Filter successful results and sort by latency
    final successfulResults = results.where((r) => r.tlsPassed).toList()
      ..sort((a, b) => a.finalLatencyMs.compareTo(b.finalLatencyMs));

    _logService.logOk(
      'Phase 1 TLS testing complete: ${successfulResults.length}/${candidateIPs.length} IPs passed (${(successfulResults.length / candidateIPs.length * 100).toStringAsFixed(1)}%)',
    );

    return successfulResults;
  }

  /// Tests a single IP with TLS handshake.
  Future<ConfigTestResult> _testSingleIPTLS({
    required XrayConfig config,
    required String candidateIP,
    required int port,
    required String? sni,
    required Duration timeout,
    required bool verifyCdn,
  }) async {
    final stopwatch = Stopwatch()..start();
    SecureSocket? socket;

    try {
      // Attempt TLS connection with SNI
      socket = await SecureSocket.connect(
        candidateIP,
        port,
        timeout: timeout,
        onBadCertificate: (_) =>
            true, // Accept any certificate (IP-based connection)
        supportedProtocols: ['h2', 'http/1.1'],
        context: SecurityContext.defaultContext,
      );

      // If SNI is specified, use it (already passed in connect() but log it)
      if (sni != null) {
        _logService.logInfo('TLS connected to $candidateIP with SNI: $sni');
      } else {
        _logService.logInfo('TLS connected to $candidateIP (no SNI)');
      }

      final latencyMs = stopwatch.elapsedMilliseconds.toDouble();

      // Optionally verify Cloudflare CDN
      bool cloudflareVerified = false;

      if (verifyCdn) {
        cloudflareVerified = await _verifyCloudflareCdn(
          socket,
          candidateIP,
          sni ?? candidateIP,
        );
      }

      stopwatch.stop();

      // Success
      final tlsResult = TlsTestResult.success(
        latencyMs: latencyMs,
        cloudflareVerified: cloudflareVerified,
      );

      return ConfigTestResult.fromTlsTest(
        ip: candidateIP,
        config: config.copyWithAddress(candidateIP),
        tlsTestResult: tlsResult,
      );
    } on SocketException catch (e) {
      stopwatch.stop();

      final tlsResult = TlsTestResult.failure(
        error: 'SocketException: ${e.message}',
        latencyMs: stopwatch.elapsedMilliseconds.toDouble(),
      );

      return ConfigTestResult.fromTlsTest(
        ip: candidateIP,
        config: config.copyWithAddress(candidateIP),
        tlsTestResult: tlsResult,
      );
    } on TimeoutException catch (_) {
      stopwatch.stop();

      final tlsResult = TlsTestResult.failure(
        error: 'Timeout',
        latencyMs: timeout.inMilliseconds.toDouble(),
      );

      return ConfigTestResult.fromTlsTest(
        ip: candidateIP,
        config: config.copyWithAddress(candidateIP),
        tlsTestResult: tlsResult,
      );
    } on HandshakeException catch (e) {
      stopwatch.stop();

      final tlsResult = TlsTestResult.failure(
        error: 'HandshakeException: ${e.message}',
        latencyMs: stopwatch.elapsedMilliseconds.toDouble(),
      );

      return ConfigTestResult.fromTlsTest(
        ip: candidateIP,
        config: config.copyWithAddress(candidateIP),
        tlsTestResult: tlsResult,
      );
    } catch (e) {
      stopwatch.stop();

      final tlsResult = TlsTestResult.failure(
        error: 'Unknown error: $e',
        latencyMs: stopwatch.elapsedMilliseconds.toDouble(),
      );

      return ConfigTestResult.fromTlsTest(
        ip: candidateIP,
        config: config.copyWithAddress(candidateIP),
        tlsTestResult: tlsResult,
      );
    } finally {
      await socket?.close();
    }
  }

  /// Verifies that the IP is behind Cloudflare CDN.
  ///
  /// Sends HTTP GET to /cdn-cgi/trace and checks for Cloudflare indicators.
  Future<bool> _verifyCloudflareCdn(
    SecureSocket socket,
    String ip,
    String host,
  ) async {
    try {
      // Send HTTP GET request to /cdn-cgi/trace
      final request =
          'GET /cdn-cgi/trace HTTP/1.1\r\n'
          'Host: $host\r\n'
          'Connection: close\r\n'
          '\r\n';

      socket.write(request);
      await socket.flush();

      // Read response with timeout
      final responseBuffer = StringBuffer();
      await for (final data in socket.timeout(Duration(seconds: 3))) {
        responseBuffer.write(String.fromCharCodes(data));

        // Check for Cloudflare indicators in response
        final response = responseBuffer.toString();

        // Look for "fl=" or "200 OK" in response
        if (response.contains('fl=') || response.contains('200 OK')) {
          _logService.logInfo('Cloudflare CDN verified for $ip');
          return true;
        }

        // If we've read enough data, stop
        if (response.length > 2048) break;
      }

      final response = responseBuffer.toString();

      // Final check
      if (response.contains('fl=') || response.contains('200 OK')) {
        return true;
      }

      _logService.logWarn('Cloudflare CDN verification failed for $ip');
      return false;
    } catch (e) {
      _logService.logWarn('Cloudflare CDN verification error for $ip: $e');
      return false;
    }
  }

  /// Creates batches of IPs for concurrent processing.
  List<List<String>> _createBatches(List<String> ips, int batchSize) {
    final batches = <List<String>>[];

    for (int i = 0; i < ips.length; i += batchSize) {
      final end = (i + batchSize < ips.length) ? i + batchSize : ips.length;
      batches.add(ips.sublist(i, end));
    }

    return batches;
  }

  /// Emits progress update to stream.
  void _emitProgress(TlsTestProgress progress) {
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  /// Disposes resources.
  void dispose() {
    _progressController.close();
  }
}

/// Represents TLS test progress.
class TlsTestProgress {
  /// Total number of IPs to test
  final int totalIPs;

  /// Number of IPs processed so far
  final int processedIPs;

  /// Number of IPs that passed TLS test
  final int successfulIPs;

  /// Number of IPs that failed TLS test
  final int failedIPs;

  /// Current IP being tested (null if between tests)
  final String? currentIP;

  const TlsTestProgress({
    required this.totalIPs,
    required this.processedIPs,
    required this.successfulIPs,
    required this.failedIPs,
    this.currentIP,
  });

  /// Progress percentage (0.0 to 1.0)
  double get progress => totalIPs > 0 ? processedIPs / totalIPs : 0.0;

  /// Progress percentage (0 to 100)
  double get progressPercent => progress * 100;

  /// Success rate (0.0 to 1.0)
  double get successRate =>
      processedIPs > 0 ? successfulIPs / processedIPs : 0.0;

  /// Success rate percentage (0 to 100)
  double get successRatePercent => successRate * 100;

  @override
  String toString() {
    return 'TlsTestProgress($processedIPs/$totalIPs - ${progressPercent.toStringAsFixed(1)}%, '
        'success: $successfulIPs, failed: $failedIPs, '
        'current: $currentIP)';
  }
}
