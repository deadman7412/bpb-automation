/// Result of download speed test for a single IP address
class SpeedResult {
  final String ip;
  final String testUrl;
  final int bytesDownloaded;
  final double durationSeconds;
  final double speedMbps;
  final DateTime timestamp;
  final String? error;

  const SpeedResult({
    required this.ip,
    required this.testUrl,
    required this.bytesDownloaded,
    required this.durationSeconds,
    required this.speedMbps,
    required this.timestamp,
    this.error,
  });

  /// Whether the test was successful
  bool get isSuccessful => error == null && bytesDownloaded > 0;

  /// Whether the test failed
  bool get isFailure => error != null || bytesDownloaded == 0;

  /// Speed in KB/s
  double get speedKbps => speedMbps * 1024;

  /// Speed in MB/s
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
      speedMbps: 0,
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
  }) {
    final speedMbps = (bytesDownloaded * 8) / (durationSeconds * 1000000);
    return SpeedResult(
      ip: ip,
      testUrl: testUrl,
      bytesDownloaded: bytesDownloaded,
      durationSeconds: durationSeconds,
      speedMbps: speedMbps,
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() {
    if (isFailure) {
      return 'SpeedResult($ip - FAILED: $error)';
    }
    return 'SpeedResult($ip - ${speedMbps.toStringAsFixed(2)} Mbps, '
        '${bytesDownloaded} bytes in ${durationSeconds.toStringAsFixed(2)}s)';
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'testUrl': testUrl,
      'bytesDownloaded': bytesDownloaded,
      'durationSeconds': durationSeconds,
      'speedMbps': speedMbps,
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
      speedMbps: (json['speedMbps'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      error: json['error'] as String?,
    );
  }
}
