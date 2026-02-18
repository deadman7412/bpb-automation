import 'xray_config.dart';

/// Represents the result of testing a Cloudflare IP with an Xray config.
///
/// This model contains results from both Phase 1 (TLS pre-filter) and
/// Phase 2 (Xray proxy test) of the config-based scanning process.
class ConfigTestResult {
  /// The IP address that was tested
  final String ip;

  /// The Xray config used for testing (with IP replaced)
  final XrayConfig config;

  /// Phase 1: TLS handshake test result
  final TlsTestResult? tlsTestResult;

  /// Phase 2: Xray proxy test result
  final ProxyTestResult? proxyTestResult;

  /// Combined quality score (0-100)
  final double qualityScore;

  /// Timestamp when testing completed
  final DateTime timestamp;

  /// Creates a ConfigTestResult instance.
  const ConfigTestResult({
    required this.ip,
    required this.config,
    this.tlsTestResult,
    this.proxyTestResult,
    required this.qualityScore,
    required this.timestamp,
  });

  /// Creates a result from TLS test only (Phase 1).
  factory ConfigTestResult.fromTlsTest({
    required String ip,
    required XrayConfig config,
    required TlsTestResult tlsTestResult,
  }) {
    // Calculate quality score from TLS test (0-50 range for Phase 1 only)
    double score = 0;

    if (tlsTestResult.success) {
      // Base success score: 25 points
      score = 25;

      // Latency component: 0-25 points (lower is better)
      // Map 0-500ms to 25-0 points
      final latencyScore =
          (1 - (tlsTestResult.latencyMs / 500).clamp(0, 1)) * 25;
      score += latencyScore;
    }

    return ConfigTestResult(
      ip: ip,
      config: config,
      tlsTestResult: tlsTestResult,
      proxyTestResult: null,
      qualityScore: score,
      timestamp: DateTime.now(),
    );
  }

  /// Creates a result from both TLS and Proxy tests (Phase 1 + Phase 2).
  factory ConfigTestResult.fromBothTests({
    required String ip,
    required XrayConfig config,
    required TlsTestResult tlsTestResult,
    required ProxyTestResult proxyTestResult,
  }) {
    // Calculate combined quality score (0-100)
    double score = 0;

    // Phase 1 (TLS) - 40% weight
    if (tlsTestResult.success) {
      score += 20; // Base success

      // Latency: 0-20 points
      final tlsLatencyScore =
          (1 - (tlsTestResult.latencyMs / 500).clamp(0, 1)) * 20;
      score += tlsLatencyScore;
    }

    // Phase 2 (Proxy) - 60% weight
    if (proxyTestResult.success) {
      score += 30; // Base success

      // Latency: 0-30 points
      final proxyLatencyScore =
          (1 - (proxyTestResult.latencyMs / 1000).clamp(0, 1)) * 30;
      score += proxyLatencyScore;
    }

    return ConfigTestResult(
      ip: ip,
      config: config,
      tlsTestResult: tlsTestResult,
      proxyTestResult: proxyTestResult,
      qualityScore: score,
      timestamp: DateTime.now(),
    );
  }

  /// Returns true if the IP passed TLS testing (Phase 1).
  bool get tlsPassed => tlsTestResult?.success ?? false;

  /// Returns true if the IP passed proxy testing (Phase 2).
  bool get proxyPassed => proxyTestResult?.success ?? false;

  /// Returns true if the IP is fully tested and working.
  bool get isFullyTested => tlsPassed && proxyPassed;

  /// Returns true if the IP is acceptable for use.
  ///
  /// An IP is acceptable if:
  /// - For TLS-only: TLS test succeeded
  /// - For full test: Both TLS and Proxy tests succeeded
  bool isAcceptable() {
    if (proxyTestResult != null) {
      return isFullyTested;
    } else {
      return tlsPassed;
    }
  }

  /// Gets the final latency (proxy test latency if available, else TLS latency).
  double get finalLatencyMs {
    if (proxyTestResult != null) {
      return proxyTestResult!.latencyMs;
    } else if (tlsTestResult != null) {
      return tlsTestResult!.latencyMs;
    }
    return double.infinity;
  }

  /// Compares quality with another result (for sorting).
  ///
  /// Returns negative if this is better, positive if other is better.
  /// Prioritizes: fully tested > TLS-only > failed, then by quality score.
  int compareQuality(ConfigTestResult other) {
    // 1. Prioritize fully tested results
    if (isFullyTested && !other.isFullyTested) return -1;
    if (!isFullyTested && other.isFullyTested) return 1;

    // 2. Then prioritize successful results
    if (isAcceptable() && !other.isAcceptable()) return -1;
    if (!isAcceptable() && other.isAcceptable()) return 1;

    // 3. Compare by latency (lower is better)
    if (finalLatencyMs != other.finalLatencyMs) {
      return finalLatencyMs.compareTo(other.finalLatencyMs);
    }

    // 4. Fall back to quality score (higher is better)
    return -qualityScore.compareTo(other.qualityScore);
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'config': config.toJson(),
      'tlsTestResult': tlsTestResult?.toJson(),
      'proxyTestResult': proxyTestResult?.toJson(),
      'qualityScore': qualityScore,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Creates from JSON.
  factory ConfigTestResult.fromJson(Map<String, dynamic> json) {
    return ConfigTestResult(
      ip: json['ip'] as String,
      config: XrayConfig.fromJson(json['config'] as Map<String, dynamic>),
      tlsTestResult: json['tlsTestResult'] != null
          ? TlsTestResult.fromJson(
              json['tlsTestResult'] as Map<String, dynamic>,
            )
          : null,
      proxyTestResult: json['proxyTestResult'] != null
          ? ProxyTestResult.fromJson(
              json['proxyTestResult'] as Map<String, dynamic>,
            )
          : null,
      qualityScore: (json['qualityScore'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  @override
  String toString() {
    final phase1Status = tlsPassed ? 'TLS-OK' : 'TLS-FAIL';
    final phase2Status = proxyTestResult != null
        ? (proxyPassed ? 'PROXY-OK' : 'PROXY-FAIL')
        : 'PROXY-PENDING';

    return 'ConfigTestResult($ip - $phase1Status, $phase2Status, '
        'score: ${qualityScore.toStringAsFixed(1)}, '
        'latency: ${finalLatencyMs.toStringAsFixed(2)}ms)';
  }

  /// Returns a brief status description for UI display.
  String getStatusDescription() {
    if (isFullyTested) {
      return 'Working';
    } else if (tlsPassed && proxyTestResult == null) {
      return 'TLS OK (testing proxy...)';
    } else if (tlsPassed && !proxyPassed) {
      return 'TLS OK, Proxy Failed';
    } else {
      return 'Failed';
    }
  }
}

/// Represents the result of a TLS handshake test (Phase 1).
class TlsTestResult {
  /// Whether the TLS handshake succeeded
  final bool success;

  /// Latency in milliseconds
  final double latencyMs;

  /// Error message if test failed
  final String? error;

  /// Whether Cloudflare CDN was verified (via /cdn-cgi/trace)
  final bool cloudflareVerified;

  /// Creates a TlsTestResult instance.
  const TlsTestResult({
    required this.success,
    required this.latencyMs,
    this.error,
    this.cloudflareVerified = false,
  });

  /// Creates a successful TLS test result.
  factory TlsTestResult.success({
    required double latencyMs,
    bool cloudflareVerified = false,
  }) {
    return TlsTestResult(
      success: true,
      latencyMs: latencyMs,
      cloudflareVerified: cloudflareVerified,
    );
  }

  /// Creates a failed TLS test result.
  factory TlsTestResult.failure({required String error, double latencyMs = 0}) {
    return TlsTestResult(success: false, latencyMs: latencyMs, error: error);
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'latencyMs': latencyMs,
      'error': error,
      'cloudflareVerified': cloudflareVerified,
    };
  }

  /// Creates from JSON.
  factory TlsTestResult.fromJson(Map<String, dynamic> json) {
    return TlsTestResult(
      success: json['success'] as bool,
      latencyMs: (json['latencyMs'] as num).toDouble(),
      error: json['error'] as String?,
      cloudflareVerified: json['cloudflareVerified'] as bool? ?? false,
    );
  }

  @override
  String toString() {
    if (success) {
      return 'TlsTestResult(OK, ${latencyMs.toStringAsFixed(2)}ms, CF: $cloudflareVerified)';
    } else {
      return 'TlsTestResult(FAIL, error: $error)';
    }
  }
}

/// Represents the result of an Xray proxy test (Phase 2).
class ProxyTestResult {
  /// Whether the proxy test succeeded
  final bool success;

  /// Latency in milliseconds (full request through proxy)
  final double latencyMs;

  /// Error message if test failed
  final String? error;

  /// HTTP status code received (should be 204 for success)
  final int? statusCode;

  /// Download speed in Mbps (optional, if speed test was performed)
  final double? speedMbps;

  /// Creates a ProxyTestResult instance.
  const ProxyTestResult({
    required this.success,
    required this.latencyMs,
    this.error,
    this.statusCode,
    this.speedMbps,
  });

  /// Creates a successful proxy test result.
  factory ProxyTestResult.success({
    required double latencyMs,
    int statusCode = 204,
    double? speedMbps,
  }) {
    return ProxyTestResult(
      success: true,
      latencyMs: latencyMs,
      statusCode: statusCode,
      speedMbps: speedMbps,
    );
  }

  /// Creates a failed proxy test result.
  factory ProxyTestResult.failure({
    required String error,
    double latencyMs = 0,
    int? statusCode,
  }) {
    return ProxyTestResult(
      success: false,
      latencyMs: latencyMs,
      error: error,
      statusCode: statusCode,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'latencyMs': latencyMs,
      'error': error,
      'statusCode': statusCode,
      'speedMbps': speedMbps,
    };
  }

  /// Creates from JSON.
  factory ProxyTestResult.fromJson(Map<String, dynamic> json) {
    return ProxyTestResult(
      success: json['success'] as bool,
      latencyMs: (json['latencyMs'] as num).toDouble(),
      error: json['error'] as String?,
      statusCode: json['statusCode'] as int?,
      speedMbps: json['speedMbps'] != null
          ? (json['speedMbps'] as num).toDouble()
          : null,
    );
  }

  @override
  String toString() {
    if (success) {
      final speedInfo = speedMbps != null
          ? ', speed: ${speedMbps!.toStringAsFixed(2)}Mbps'
          : '';
      return 'ProxyTestResult(OK, ${latencyMs.toStringAsFixed(2)}ms, status: $statusCode$speedInfo)';
    } else {
      return 'ProxyTestResult(FAIL, error: $error)';
    }
  }
}
