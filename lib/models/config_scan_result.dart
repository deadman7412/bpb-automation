import 'package:bpb_automation/models/config_test_result.dart';
import 'package:bpb_automation/models/xray_config.dart';

/// Result of a complete config-based scan operation
///
/// Contains results from both Phase 1 (TLS testing) and Phase 2 (Proxy testing):
/// - Phase 1: Fast TLS handshake testing of all candidate IPs
/// - Phase 2: Actual proxy testing via Xray-core for top candidates
///
/// Usage:
/// ```dart
/// final scanResult = await scannerService.executeConfigScan(...);
/// print('Working IPs: ${scanResult.workingIPCount}');
/// print('Scan took: ${scanResult.scanDuration}');
/// ```
class ConfigScanResult {
  /// Total number of IPs tested in Phase 1 (TLS testing)
  final int totalTested;

  /// Number of IPs that passed Phase 1 (TLS handshake successful)
  final int phase1Passed;

  /// Number of IPs tested in Phase 2 (proxy testing)
  final int phase2Tested;

  /// Number of IPs that successfully work as proxies (Phase 2 passed)
  final int workingIPCount;

  /// List of working IP addresses (sorted by proxy latency)
  final List<String> workingIPs;

  /// Detailed test results for all tested IPs
  ///
  /// Includes both Phase 1 and Phase 2 results.
  /// Phase 1 only results will have `proxyTestResult` as null.
  final List<ConfigTestResult> allResults;

  /// Total duration of the entire scan operation
  final Duration scanDuration;

  /// The Xray config template used for testing
  ///
  /// This is the original config from subscription.
  /// Working IPs can be substituted into this config's outbound address.
  final XrayConfig templateConfig;

  /// Timestamp when the scan completed
  final DateTime timestamp;

  const ConfigScanResult({
    required this.totalTested,
    required this.phase1Passed,
    required this.phase2Tested,
    required this.workingIPCount,
    required this.workingIPs,
    required this.allResults,
    required this.scanDuration,
    required this.templateConfig,
    required this.timestamp,
  });

  /// Create result from successful scan
  factory ConfigScanResult.success({
    required int totalTested,
    required int phase1Passed,
    required int phase2Tested,
    required List<ConfigTestResult> allResults,
    required Duration scanDuration,
    required XrayConfig templateConfig,
  }) {
    // Filter working IPs (those with successful proxy tests)
    final workingResults = allResults
        .where(
          (r) =>
              r.proxyTestResult != null &&
              r.proxyTestResult!.success &&
              r.proxyTestResult!.statusCode == 204,
        )
        .toList();

    // Sort by proxy latency (fastest first)
    workingResults.sort((a, b) {
      final aLatency = a.proxyTestResult?.latencyMs ?? double.infinity;
      final bLatency = b.proxyTestResult?.latencyMs ?? double.infinity;
      return aLatency.compareTo(bLatency);
    });

    final workingIPs = workingResults.map((r) => r.ip).toList();

    return ConfigScanResult(
      totalTested: totalTested,
      phase1Passed: phase1Passed,
      phase2Tested: phase2Tested,
      workingIPCount: workingIPs.length,
      workingIPs: workingIPs,
      allResults: allResults,
      scanDuration: scanDuration,
      templateConfig: templateConfig,
      timestamp: DateTime.now(),
    );
  }

  /// Create result from failed/cancelled scan
  factory ConfigScanResult.failure({
    required int totalTested,
    required int phase1Passed,
    required int phase2Tested,
    required List<ConfigTestResult> allResults,
    required Duration scanDuration,
    required XrayConfig templateConfig,
  }) {
    return ConfigScanResult(
      totalTested: totalTested,
      phase1Passed: phase1Passed,
      phase2Tested: phase2Tested,
      workingIPCount: 0,
      workingIPs: [],
      allResults: allResults,
      scanDuration: scanDuration,
      templateConfig: templateConfig,
      timestamp: DateTime.now(),
    );
  }

  /// Get phase 1 success rate (percentage)
  double get phase1SuccessRate {
    if (totalTested == 0) return 0.0;
    return (phase1Passed / totalTested) * 100;
  }

  /// Get phase 2 success rate (percentage)
  double get phase2SuccessRate {
    if (phase2Tested == 0) return 0.0;
    return (workingIPCount / phase2Tested) * 100;
  }

  /// Get overall success rate (percentage)
  double get overallSuccessRate {
    if (totalTested == 0) return 0.0;
    return (workingIPCount / totalTested) * 100;
  }

  /// Get average TLS latency for Phase 1 successful IPs
  double get averageTlsLatency {
    final successfulResults = allResults
        .where((r) => r.tlsTestResult != null && r.tlsTestResult!.success)
        .toList();

    if (successfulResults.isEmpty) return 0.0;

    final totalLatency = successfulResults.fold<double>(
      0.0,
      (sum, r) => sum + (r.tlsTestResult?.latencyMs ?? 0.0),
    );

    return totalLatency / successfulResults.length;
  }

  /// Get average proxy latency for working IPs
  double get averageProxyLatency {
    final workingResults = allResults
        .where(
          (r) =>
              r.proxyTestResult != null &&
              r.proxyTestResult!.success &&
              r.proxyTestResult!.statusCode == 204,
        )
        .toList();

    if (workingResults.isEmpty) return 0.0;

    final totalLatency = workingResults.fold<double>(
      0.0,
      (sum, r) => sum + (r.proxyTestResult?.latencyMs ?? 0.0),
    );

    return totalLatency / workingResults.length;
  }

  /// Get the fastest working IP (by proxy latency)
  String? get fastestIP {
    if (workingIPs.isEmpty) return null;
    return workingIPs.first; // Already sorted by latency
  }

  /// Get detailed result for a specific IP
  ConfigTestResult? getResultForIP(String ip) {
    try {
      return allResults.firstWhere((r) => r.ip == ip);
    } catch (e) {
      return null;
    }
  }

  /// Check if scan was successful (found at least one working IP)
  bool get isSuccess => workingIPCount > 0;

  /// Get summary message
  String get summaryMessage {
    if (workingIPCount == 0) {
      return 'No working IPs found. Tested $totalTested IPs, $phase1Passed passed TLS, $phase2Tested tested with proxy.';
    }

    return 'Found $workingIPCount working IP${workingIPCount > 1 ? 's' : ''} out of $totalTested tested. '
        'Phase 1: $phase1Passed/$totalTested passed (${phase1SuccessRate.toStringAsFixed(1)}%). '
        'Phase 2: $workingIPCount/$phase2Tested passed (${phase2SuccessRate.toStringAsFixed(1)}%).';
  }

  @override
  String toString() {
    return 'ConfigScanResult('
        'totalTested: $totalTested, '
        'phase1Passed: $phase1Passed, '
        'phase2Tested: $phase2Tested, '
        'workingIPCount: $workingIPCount, '
        'scanDuration: $scanDuration, '
        'timestamp: $timestamp'
        ')';
  }
}
