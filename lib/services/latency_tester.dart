import 'dart:async';
import 'dart:io';
import 'package:bpb_automation/models/latency_result.dart';
import 'log_service.dart';

/// Service for testing IP latency using TCP sockets
class LatencyTester {
  final LogService _logService = LogService.instance;

  /// Test latency for a single IP address
  ///
  /// Connects to [ip]:[port] and measures connection time.
  /// Repeats [count] times and calculates statistics.
  Future<LatencyResult> testLatency({
    required String ip,
    required int port,
    required int count,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    _logService.logInfo('Testing latency for $ip:$port ($count attempts)');

    final latencies = <double>[];
    int successCount = 0;
    String? error;

    for (var i = 0; i < count; i++) {
      try {
        final latency = await _singleLatencyTest(ip, port, timeout);
        latencies.add(latency);
        successCount++;
      } catch (e) {
        _logService.logWarn('Latency test failed for $ip:$port attempt ${i + 1}: $e');
        error ??= e.toString(); // Capture first error
      }
    }

    if (latencies.isEmpty) {
      _logService.logError('All latency tests failed for $ip:$port');
      return LatencyResult.failed(
        ip: ip,
        port: port,
        totalAttempts: count,
        error: error ?? 'All connection attempts failed',
      );
    }

    // Calculate statistics
    final avgLatency = latencies.reduce((a, b) => a + b) / latencies.length;
    final minLatency = latencies.reduce((a, b) => a < b ? a : b);
    final maxLatency = latencies.reduce((a, b) => a > b ? a : b);

    final result = LatencyResult(
      ip: ip,
      port: port,
      successCount: successCount,
      totalAttempts: count,
      averageLatencyMs: avgLatency,
      minLatencyMs: minLatency,
      maxLatencyMs: maxLatency,
      latencies: latencies,
      timestamp: DateTime.now(),
      error: successCount < count ? 'Some attempts failed' : null,
    );

    _logService.logOk(
      'Latency test complete for $ip:$port - '
      'avg: ${avgLatency.toStringAsFixed(2)}ms, '
      'success: ${result.successRatePercent.toStringAsFixed(1)}%',
    );

    return result;
  }

  /// Perform a single latency test
  Future<double> _singleLatencyTest(
    String ip,
    int port,
    Duration timeout,
  ) async {
    final stopwatch = Stopwatch()..start();

    Socket? socket;
    try {
      socket = await Socket.connect(
        ip,
        port,
        timeout: timeout,
      );

      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMicroseconds / 1000.0;

      return latencyMs;
    } on SocketException catch (e) {
      throw Exception('Connection failed: ${e.message}');
    } on TimeoutException {
      throw Exception('Connection timeout after ${timeout.inMilliseconds}ms');
    } finally {
      socket?.destroy();
    }
  }

  /// Test multiple IPs concurrently with limited parallelism
  ///
  /// Returns Stream of results as they complete.
  Stream<LatencyResult> testMultiple({
    required List<String> ips,
    required int port,
    required int count,
    Duration timeout = const Duration(seconds: 3),
    int maxConcurrent = 10,
  }) async* {
    _logService.logInfo(
      'Testing ${ips.length} IPs with max $maxConcurrent concurrent workers',
    );

    var completed = 0;
    var started = 0;
    final pending = <String, Future<LatencyResult>>{};

    while (started < ips.length || pending.isNotEmpty) {
      // Start new tasks up to max concurrent
      while (started < ips.length && pending.length < maxConcurrent) {
        final ip = ips[started];
        started++;

        final task = testLatency(
          ip: ip,
          port: port,
          count: count,
          timeout: timeout,
        );

        pending[ip] = task;
      }

      // Wait for at least one to complete
      if (pending.isNotEmpty) {
        final result = await Future.any(pending.values);

        // Remove completed task from pending
        pending.remove(result.ip);

        completed++;
        _logService.logInfo(
          'Latency test progress: $completed/${ips.length}',
        );

        yield result;
      }
    }

    _logService.logOk('All latency tests completed: $completed results');
  }

  /// Test IPs in batches and collect all results
  Future<List<LatencyResult>> testBatch({
    required List<String> ips,
    required int port,
    required int count,
    Duration timeout = const Duration(seconds: 3),
    int maxConcurrent = 10,
  }) async {
    _logService.logInfo('Starting batch latency test for ${ips.length} IPs');

    final results = <LatencyResult>[];

    await for (final result in testMultiple(
      ips: ips,
      port: port,
      count: count,
      timeout: timeout,
      maxConcurrent: maxConcurrent,
    )) {
      results.add(result);
    }

    // Sort by quality (best first)
    results.sort((a, b) {
      // Successful results come first
      if (a.isSuccessful != b.isSuccessful) {
        return a.isSuccessful ? -1 : 1;
      }
      // Among successful, lower latency is better
      return a.averageLatencyMs.compareTo(b.averageLatencyMs);
    });

    _logService.logOk(
      'Batch latency test complete: ${results.length} results',
    );

    return results;
  }
}
