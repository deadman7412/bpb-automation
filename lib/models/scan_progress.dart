/// Real-time progress update during scanning
class ScanProgress {
  final int totalIPs;
  final int processedIPs;
  final int successfulIPs;
  final int failedIPs;
  final String? currentIP;
  final ScanStage stage;
  final String? message;
  final DateTime timestamp;

  const ScanProgress({
    required this.totalIPs,
    required this.processedIPs,
    required this.successfulIPs,
    required this.failedIPs,
    this.currentIP,
    required this.stage,
    this.message,
    required this.timestamp,
  });

  /// Progress as percentage (0.0 to 1.0)
  double get progress => totalIPs > 0 ? processedIPs / totalIPs : 0.0;

  /// Progress as percentage (0 to 100)
  double get progressPercent => progress * 100;

  /// Success rate (0.0 to 1.0)
  double get successRate => processedIPs > 0 ? successfulIPs / processedIPs : 0.0;

  /// Success rate as percentage (0 to 100)
  double get successRatePercent => successRate * 100;

  /// Create initial progress
  factory ScanProgress.initial({required int totalIPs}) {
    return ScanProgress(
      totalIPs: totalIPs,
      processedIPs: 0,
      successfulIPs: 0,
      failedIPs: 0,
      stage: ScanStage.initializing,
      timestamp: DateTime.now(),
    );
  }

  /// Create progress update
  ScanProgress copyWith({
    int? totalIPs,
    int? processedIPs,
    int? successfulIPs,
    int? failedIPs,
    String? currentIP,
    ScanStage? stage,
    String? message,
  }) {
    return ScanProgress(
      totalIPs: totalIPs ?? this.totalIPs,
      processedIPs: processedIPs ?? this.processedIPs,
      successfulIPs: successfulIPs ?? this.successfulIPs,
      failedIPs: failedIPs ?? this.failedIPs,
      currentIP: currentIP ?? this.currentIP,
      stage: stage ?? this.stage,
      message: message ?? this.message,
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'ScanProgress(${progressPercent.toStringAsFixed(1)}% - '
        '$processedIPs/$totalIPs - '
        'success: $successfulIPs, failed: $failedIPs - '
        'stage: ${stage.name})';
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'totalIPs': totalIPs,
      'processedIPs': processedIPs,
      'successfulIPs': successfulIPs,
      'failedIPs': failedIPs,
      'currentIP': currentIP,
      'stage': stage.name,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Create from JSON
  factory ScanProgress.fromJson(Map<String, dynamic> json) {
    return ScanProgress(
      totalIPs: json['totalIPs'] as int,
      processedIPs: json['processedIPs'] as int,
      successfulIPs: json['successfulIPs'] as int,
      failedIPs: json['failedIPs'] as int,
      currentIP: json['currentIP'] as String?,
      stage: ScanStage.values.firstWhere((e) => e.name == json['stage']),
      message: json['message'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

/// Stages of the scanning process
enum ScanStage {
  initializing,
  loadingIPs,
  latencyTesting,
  speedTesting,
  sorting,
  completed,
  failed,
}
