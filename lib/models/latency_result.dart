/// Result of latency test for a single IP address
class LatencyResult {
  final String ip;
  final int port;
  final int successCount;
  final int totalAttempts;
  final double averageLatencyMs;
  final double minLatencyMs;
  final double maxLatencyMs;
  final List<double> latencies;
  final DateTime timestamp;
  final String? error;

  const LatencyResult({
    required this.ip,
    required this.port,
    required this.successCount,
    required this.totalAttempts,
    required this.averageLatencyMs,
    required this.minLatencyMs,
    required this.maxLatencyMs,
    required this.latencies,
    required this.timestamp,
    this.error,
  });

  /// Success rate (0.0 to 1.0)
  double get successRate => totalAttempts > 0 ? successCount / totalAttempts : 0.0;

  /// Success rate as percentage (0 to 100)
  double get successRatePercent => successRate * 100;

  /// Whether the test was successful (at least one successful ping)
  bool get isSuccessful => successCount > 0 && error == null;

  /// Whether all attempts failed
  bool get isFailure => successCount == 0 || error != null;

  /// Create a failed result
  factory LatencyResult.failed({
    required String ip,
    required int port,
    required int totalAttempts,
    required String error,
  }) {
    return LatencyResult(
      ip: ip,
      port: port,
      successCount: 0,
      totalAttempts: totalAttempts,
      averageLatencyMs: 0,
      minLatencyMs: 0,
      maxLatencyMs: 0,
      latencies: [],
      timestamp: DateTime.now(),
      error: error,
    );
  }

  @override
  String toString() {
    if (isFailure) {
      return 'LatencyResult($ip:$port - FAILED: $error)';
    }
    return 'LatencyResult($ip:$port - avg: ${averageLatencyMs.toStringAsFixed(2)}ms, '
        'success: ${successRatePercent.toStringAsFixed(1)}%)';
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'port': port,
      'successCount': successCount,
      'totalAttempts': totalAttempts,
      'averageLatencyMs': averageLatencyMs,
      'minLatencyMs': minLatencyMs,
      'maxLatencyMs': maxLatencyMs,
      'latencies': latencies,
      'timestamp': timestamp.toIso8601String(),
      'error': error,
    };
  }

  /// Create from JSON
  factory LatencyResult.fromJson(Map<String, dynamic> json) {
    return LatencyResult(
      ip: json['ip'] as String,
      port: json['port'] as int,
      successCount: json['successCount'] as int,
      totalAttempts: json['totalAttempts'] as int,
      averageLatencyMs: (json['averageLatencyMs'] as num).toDouble(),
      minLatencyMs: (json['minLatencyMs'] as num).toDouble(),
      maxLatencyMs: (json['maxLatencyMs'] as num).toDouble(),
      latencies: (json['latencies'] as List).map((e) => (e as num).toDouble()).toList(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      error: json['error'] as String?,
    );
  }
}
