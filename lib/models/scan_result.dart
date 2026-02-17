import 'latency_result.dart';
import 'speed_result.dart';

/// Complete result of a scan operation
class ScanResult {
  final String ip;
  final LatencyResult latencyResult;
  final SpeedResult? speedResult;
  final double qualityScore;
  final DateTime timestamp;

  const ScanResult({
    required this.ip,
    required this.latencyResult,
    this.speedResult,
    required this.qualityScore,
    required this.timestamp,
  });

  /// Whether this result is acceptable for use
  bool isAcceptable({
    double minSuccessRate = 0.5,
    double maxAverageLatency = 300.0,
  }) {
    return latencyResult.isSuccessful &&
        latencyResult.successRate >= minSuccessRate &&
        latencyResult.averageLatencyMs <= maxAverageLatency;
  }

  /// Create from latency and speed tests
  factory ScanResult.fromTests({
    required String ip,
    required LatencyResult latencyResult,
    SpeedResult? speedResult,
  }) {
    // Calculate quality score (0-100)
    double score = 0;

    // Latency component (60% weight)
    if (latencyResult.isSuccessful) {
      // Success rate (30%)
      score += latencyResult.successRate * 30;

      // Latency quality (30%) - lower is better
      // Map 0-300ms to 30-0 points
      final latencyScore =
          (1 - (latencyResult.averageLatencyMs / 300).clamp(0, 1)) * 30;
      score += latencyScore;
    }

    // Speed component (40% weight) - only if speed test was performed
    if (speedResult != null && speedResult.isSuccessful) {
      // Map 0-100 Mbps to 0-40 points
      final speedScore = (speedResult.speedMbps / 100).clamp(0, 1) * 40;
      score += speedScore;
    } else if (speedResult == null) {
      // If no speed test, redistribute weight to latency
      // Add bonus 20 points if latency is excellent
      if (latencyResult.averageLatencyMs < 100 &&
          latencyResult.successRate > 0.8) {
        score += 20;
      }
    }

    return ScanResult(
      ip: ip,
      latencyResult: latencyResult,
      speedResult: speedResult,
      qualityScore: score.clamp(0, 100),
      timestamp: DateTime.now(),
    );
  }

  /// Compare quality with another result (for sorting)
  /// Matches Go scanner behavior: sort by loss rate first, then by latency
  /// Returns negative if this is better, positive if other is better
  int compareQuality(ScanResult other) {
    // 1. Compare by loss rate first (lower loss is better)
    final thisLoss = 1.0 - latencyResult.successRate;
    final otherLoss = 1.0 - other.latencyResult.successRate;

    if (thisLoss != otherLoss) {
      return thisLoss.compareTo(otherLoss); // Lower loss wins
    }

    // 2. If loss rate is equal, compare by average latency (lower is better)
    final thisLatency = latencyResult.averageLatencyMs;
    final otherLatency = other.latencyResult.averageLatencyMs;

    if (thisLatency != otherLatency) {
      return thisLatency.compareTo(otherLatency); // Lower latency wins
    }

    // 3. If both equal, fall back to quality score
    return other.qualityScore.compareTo(qualityScore); // Higher score wins
  }

  @override
  String toString() {
    final speedInfo = speedResult != null
        ? ', speed: ${speedResult!.speedMbps.toStringAsFixed(2)} Mbps'
        : '';
    return 'ScanResult($ip - score: ${qualityScore.toStringAsFixed(1)}, '
        'latency: ${latencyResult.averageLatencyMs.toStringAsFixed(2)}ms$speedInfo)';
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'latencyResult': latencyResult.toJson(),
      'speedResult': speedResult?.toJson(),
      'qualityScore': qualityScore,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Create from JSON
  factory ScanResult.fromJson(Map<String, dynamic> json) {
    return ScanResult(
      ip: json['ip'] as String,
      latencyResult: LatencyResult.fromJson(
        json['latencyResult'] as Map<String, dynamic>,
      ),
      speedResult: json['speedResult'] != null
          ? SpeedResult.fromJson(json['speedResult'] as Map<String, dynamic>)
          : null,
      qualityScore: (json['qualityScore'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// Convert to CSV row (compatible with CleanIP format)
  String toCsvRow() {
    final sent = latencyResult.totalAttempts;
    final received = latencyResult.successCount;
    final loss = 100 - latencyResult.successRatePercent;
    final avgLatency = latencyResult.averageLatencyMs;
    final downloadSpeed = speedResult?.speedMbps ?? 0;

    return '$ip,$sent,$received,${loss.toStringAsFixed(1)}%,'
        '${avgLatency.toStringAsFixed(2)},'
        '${downloadSpeed.toStringAsFixed(2)}';
  }
}
