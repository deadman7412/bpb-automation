/// Real-time progress update during scanning
class ScanProgress {
  // Original fields
  final int totalIPs;
  final int processedIPs;
  final int successfulIPs;
  final int failedIPs;
  final String? currentIP;
  final ScanStage stage;
  final String? message;
  final DateTime timestamp;

  // NEW: Batch tracking fields
  final int currentBatch;
  final int totalBatchesPlanned;
  final int batchesCompleted;

  // NEW: Goal tracking fields
  final int targetCleanIPs;
  final int cleanIPsFound;
  final int minAcceptableIPs;

  // NEW: Efficiency metrics
  final int totalIPsTested;
  final double? testEfficiency;
  final Duration? elapsedTime;

  // NEW: Sub-stage detail for better UX
  final String? subStage;

  // NEW: Last batch latency results (preserved during download testing)
  final int? lastBatchLatencyPass;
  final int? lastBatchLatencyFail;

  const ScanProgress({
    required this.totalIPs,
    required this.processedIPs,
    required this.successfulIPs,
    required this.failedIPs,
    this.currentIP,
    required this.stage,
    this.message,
    required this.timestamp,
    this.currentBatch = 1,
    this.totalBatchesPlanned = 1,
    this.batchesCompleted = 0,
    this.targetCleanIPs = 10,
    this.cleanIPsFound = 0,
    this.minAcceptableIPs = 5,
    this.totalIPsTested = 0,
    this.testEfficiency,
    this.elapsedTime,
    this.subStage,
    this.lastBatchLatencyPass,
    this.lastBatchLatencyFail,
  });

  /// Progress as percentage (0.0 to 1.0)
  double get progress => totalIPs > 0 ? processedIPs / totalIPs : 0.0;

  /// Progress as percentage (0 to 100)
  double get progressPercent => progress * 100;

  /// Success rate (0.0 to 1.0)
  double get successRate =>
      processedIPs > 0 ? successfulIPs / processedIPs : 0.0;

  /// Success rate as percentage (0 to 100)
  double get successRatePercent => successRate * 100;

  /// NEW: Goal progress as percentage (0.0 to 1.0)
  double get goalProgress =>
      targetCleanIPs > 0 ? cleanIPsFound / targetCleanIPs : 0.0;

  /// NEW: Goal progress as percentage (0 to 100)
  double get goalProgressPercent => goalProgress * 100;

  /// NEW: Is goal met?
  bool get isGoalMet => cleanIPsFound >= targetCleanIPs;

  /// NEW: Is minimum acceptable met?
  bool get isMinAcceptableMet => cleanIPsFound >= minAcceptableIPs;

  /// NEW: Calculated test efficiency (clean IPs / total IPs tested)
  /// Returns testEfficiency if set, otherwise calculates from totalIPsTested
  double get efficiency {
    if (testEfficiency != null) return testEfficiency!;
    return totalIPsTested > 0 ? cleanIPsFound / totalIPsTested : 0.0;
  }

  /// NEW: Efficiency as percentage
  double get efficiencyPercent => efficiency * 100;

  /// NEW: Batch progress as percentage (0.0 to 1.0)
  double get batchProgress =>
      totalBatchesPlanned > 0 ? batchesCompleted / totalBatchesPlanned : 0.0;

  /// NEW: Batch progress as percentage (0 to 100)
  double get batchProgressPercent => batchProgress * 100;

  /// Create initial progress
  factory ScanProgress.initial({
    required int totalIPs,
    int targetCleanIPs = 10,
    int minAcceptableIPs = 5,
    int totalBatchesPlanned = 1,
  }) {
    return ScanProgress(
      totalIPs: totalIPs,
      processedIPs: 0,
      successfulIPs: 0,
      failedIPs: 0,
      stage: ScanStage.initializing,
      timestamp: DateTime.now(),
      targetCleanIPs: targetCleanIPs,
      minAcceptableIPs: minAcceptableIPs,
      totalBatchesPlanned: totalBatchesPlanned,
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
    int? currentBatch,
    int? totalBatchesPlanned,
    int? batchesCompleted,
    int? targetCleanIPs,
    int? cleanIPsFound,
    int? minAcceptableIPs,
    int? totalIPsTested,
    double? testEfficiency,
    Duration? elapsedTime,
    String? subStage,
    int? lastBatchLatencyPass,
    int? lastBatchLatencyFail,
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
      currentBatch: currentBatch ?? this.currentBatch,
      totalBatchesPlanned: totalBatchesPlanned ?? this.totalBatchesPlanned,
      batchesCompleted: batchesCompleted ?? this.batchesCompleted,
      targetCleanIPs: targetCleanIPs ?? this.targetCleanIPs,
      cleanIPsFound: cleanIPsFound ?? this.cleanIPsFound,
      minAcceptableIPs: minAcceptableIPs ?? this.minAcceptableIPs,
      totalIPsTested: totalIPsTested ?? this.totalIPsTested,
      testEfficiency: testEfficiency ?? this.testEfficiency,
      elapsedTime: elapsedTime ?? this.elapsedTime,
      subStage: subStage ?? this.subStage,
      lastBatchLatencyPass: lastBatchLatencyPass ?? this.lastBatchLatencyPass,
      lastBatchLatencyFail: lastBatchLatencyFail ?? this.lastBatchLatencyFail,
    );
  }

  @override
  String toString() {
    return 'ScanProgress(${progressPercent.toStringAsFixed(1)}% - '
        '$processedIPs/$totalIPs - '
        'success: $successfulIPs, failed: $failedIPs - '
        'stage: ${stage.name} - '
        'batch: $currentBatch/$totalBatchesPlanned - '
        'clean IPs: $cleanIPsFound/$targetCleanIPs - '
        'efficiency: ${efficiencyPercent.toStringAsFixed(1)}%)';
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
      'currentBatch': currentBatch,
      'totalBatchesPlanned': totalBatchesPlanned,
      'batchesCompleted': batchesCompleted,
      'targetCleanIPs': targetCleanIPs,
      'cleanIPsFound': cleanIPsFound,
      'minAcceptableIPs': minAcceptableIPs,
      'totalIPsTested': totalIPsTested,
      'testEfficiency': testEfficiency,
      'elapsedTime': elapsedTime?.inMilliseconds,
      'subStage': subStage,
      'lastBatchLatencyPass': lastBatchLatencyPass,
      'lastBatchLatencyFail': lastBatchLatencyFail,
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
      currentBatch: json['currentBatch'] as int? ?? 1,
      totalBatchesPlanned: json['totalBatchesPlanned'] as int? ?? 1,
      batchesCompleted: json['batchesCompleted'] as int? ?? 0,
      targetCleanIPs: json['targetCleanIPs'] as int? ?? 10,
      cleanIPsFound: json['cleanIPsFound'] as int? ?? 0,
      minAcceptableIPs: json['minAcceptableIPs'] as int? ?? 5,
      totalIPsTested: json['totalIPsTested'] as int? ?? 0,
      testEfficiency: json['testEfficiency'] as double?,
      elapsedTime: json['elapsedTime'] != null
          ? Duration(milliseconds: json['elapsedTime'] as int)
          : null,
      subStage: json['subStage'] as String?,
      lastBatchLatencyPass: json['lastBatchLatencyPass'] as int?,
      lastBatchLatencyFail: json['lastBatchLatencyFail'] as int?,
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
