/// Result of download speed test for a single IP address
class SpeedResult {
  final String ip;
  final String testUrl;
  final int bytesDownloaded;
  final double durationSeconds;

  /// Quality score calculated using EWMA (Exponentially Weighted Moving Average)
  /// This is a dimensionless metric that represents sustained throughput quality
  /// rather than instantaneous speed. Higher values indicate better quality.
  ///
  /// Matches the Go scanner's approach: EWMA value / (timeout_seconds / 120)
  final double qualityScore;

  final DateTime timestamp;
  final String? error;

  const SpeedResult({
    required this.ip,
    required this.testUrl,
    required this.bytesDownloaded,
    required this.durationSeconds,
    required this.qualityScore,
    required this.timestamp,
    this.error,
  });

  /// Whether the test was successful
  bool get isSuccessful => error == null && bytesDownloaded > 0;

  /// Whether the test failed
  bool get isFailure => error != null || bytesDownloaded == 0;

  /// Raw average speed in Mbps (for backward compatibility)
  /// Note: This is the simple average, not the quality score
  double get speedMbps => (bytesDownloaded * 8) / (durationSeconds * 1000000);

  /// Speed in KB/s (simple average)
  double get speedKbps => speedMbps * 1024;

  /// Speed in MB/s (simple average)
  double get speedMBps => speedMbps / 8;

  /// Create a failed result
  factory SpeedResult.failed({
    required String ip,
    required String testUrl,
    required String error,
  }) {
    return SpeedResult(
      ip: ip,
      testUrl: testUrl,
      bytesDownloaded: 0,
      durationSeconds: 0,
      qualityScore: 0,
      timestamp: DateTime.now(),
      error: error,
    );
  }

  /// Create from successful test
  factory SpeedResult.success({
    required String ip,
    required String testUrl,
    required int bytesDownloaded,
    required double durationSeconds,
    double? qualityScore,
  }) {
    // If quality score not provided, fall back to simple average
    final score = qualityScore ?? (bytesDownloaded / durationSeconds);

    return SpeedResult(
      ip: ip,
      testUrl: testUrl,
      bytesDownloaded: bytesDownloaded,
      durationSeconds: durationSeconds,
      qualityScore: score,
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() {
    if (isFailure) {
      return 'SpeedResult($ip - FAILED: $error)';
    }
    return 'SpeedResult($ip - Quality: ${qualityScore.toStringAsFixed(2)}, '
        '$bytesDownloaded bytes in ${durationSeconds.toStringAsFixed(2)}s)';
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'testUrl': testUrl,
      'bytesDownloaded': bytesDownloaded,
      'durationSeconds': durationSeconds,
      'qualityScore': qualityScore,
      'speedMbps': speedMbps, // Include for backward compatibility
      'timestamp': timestamp.toIso8601String(),
      'error': error,
    };
  }

  /// Create from JSON
  factory SpeedResult.fromJson(Map<String, dynamic> json) {
    return SpeedResult(
      ip: json['ip'] as String,
      testUrl: json['testUrl'] as String,
      bytesDownloaded: json['bytesDownloaded'] as int,
      durationSeconds: (json['durationSeconds'] as num).toDouble(),
      qualityScore:
          (json['qualityScore'] as num?)?.toDouble() ??
          (json['speedMbps'] as num?)?.toDouble() ??
          0.0,
      timestamp: DateTime.parse(json['timestamp'] as String),
      error: json['error'] as String?,
    );
  }
}
