import 'dart:io' show Platform;

/// Configuration for the Cloudflare IP Scanner.
///
/// Simplified configuration matching the Go scanner's proven algorithm.
/// Based on: https://github.com/bia-pain-bache/Cloudflare-Clean-IP-Scanner
class ScannerConfig {
  // ===== ESSENTIAL PARAMETERS (User-facing) =====

  /// TARGET: Number of clean IPs to find (1-50)
  /// Scanner continues until this many IPs pass both latency and download tests
  final int targetCleanIPs;

  /// CONCURRENCY: Number of concurrent threads for latency testing (50-500)
  /// Higher = faster but more resource intensive
  /// Default: 200 (Go scanner default)
  final int threads;

  /// LATENCY FILTER: Maximum acceptable latency in milliseconds (50-9999)
  /// IPs with latency above this are filtered out before download testing
  /// Default: 9999ms (no filter) matching Go scanner
  final int maxLatency;

  /// LOSS FILTER: Maximum acceptable packet loss rate (0.0-1.0)
  /// 0.0 = no loss allowed, 1.0 = any loss acceptable
  /// Default: 1.0 (no filter) matching Go scanner
  final double maxLossRate;

  /// SPEED FILTER: Minimum download speed in MB/s (0-100)
  /// IPs slower than this are filtered from results
  /// Default: 0.0 (no filter) matching Go scanner
  final double minDownloadSpeed;

  // ===== ADVANCED PARAMETERS (Technical) =====

  /// Number of latency tests per IP (1-10)
  /// More tests = more accurate but slower
  /// Default: 4 (Go scanner default)
  final int testCount;

  /// Test port (1-65535)
  /// Default: 443 (HTTPS)
  final int testPort;

  /// Download test timeout per IP in seconds (5-60)
  /// Prevents hanging on slow IPs
  final int downloadTestTime;

  /// Download test file size in bytes
  /// Default: 52428800 (50MB) matching Go scanner
  final int downloadBytes;

  /// Test URL for download speed testing
  /// Should point to a large file on Cloudflare CDN
  final String testUrl;

  /// Use HTTP protocol for latency testing instead of TCP
  /// HTTPing is more accurate but slower and may trigger rate limits
  final bool httpingMode;

  /// SAFETY LIMIT: Maximum total IPs to test (1000-20000)
  /// Prevents infinite scanning if target cannot be met
  /// Default: 10000
  final int maxIPsToTest;

  /// TEST ALL IPs: Test all 256 IPs in each /24 subnet instead of 1 random
  /// Matches Go scanner's -allip flag
  /// Default: false (test 1 random IP per /24 for speed)
  /// When enabled: ~5956 IPs tested, when disabled: ~696 IPs tested
  /// Note: Enabling this makes scans MUCH slower (4+ min vs 30 sec for latency phase)
  final bool testAllIPs;

  /// Creates a ScannerConfig with the specified values.
  ///
  /// All parameters are optional and will use defaults if not specified.
  const ScannerConfig({
    // Essential
    this.targetCleanIPs = 10,
    this.threads = 200,
    this.maxLatency = 9999,
    this.maxLossRate = 1.0,
    this.minDownloadSpeed = 0.0,

    // Advanced
    this.testCount = 4,
    this.testPort = 443,
    this.downloadTestTime = 10,
    this.downloadBytes = 52428800, // 50MB
    this.testUrl = 'https://speed.cloudflare.com/__down?bytes=52428800',
    this.httpingMode = false,
    this.maxIPsToTest = 10000,
    this.testAllIPs = false,
  });

  /// Creates a ScannerConfig from JSON.
  factory ScannerConfig.fromJson(Map<String, dynamic> json) {
    return ScannerConfig(
      targetCleanIPs: json['target_clean_ips'] as int? ?? 10,
      threads: json['threads'] as int? ?? 200,
      maxLatency: json['max_latency'] as int? ?? 9999,
      maxLossRate: (json['max_loss_rate'] as num?)?.toDouble() ?? 1.0,
      minDownloadSpeed: (json['min_download_speed'] as num?)?.toDouble() ?? 0.0,
      testCount: json['test_count'] as int? ?? 4,
      testPort: json['test_port'] as int? ?? 443,
      downloadTestTime: json['download_test_time'] as int? ?? 10,
      downloadBytes: json['download_bytes'] as int? ?? 52428800,
      testUrl:
          json['test_url'] as String? ??
          'https://speed.cloudflare.com/__down?bytes=52428800',
      httpingMode: json['httping_mode'] as bool? ?? false,
      maxIPsToTest: json['max_ips_to_test'] as int? ?? 10000,
      testAllIPs: json['test_all_ips'] as bool? ?? false,
    );
  }

  /// Converts this ScannerConfig to JSON.
  Map<String, dynamic> toJson() {
    return {
      'target_clean_ips': targetCleanIPs,
      'threads': threads,
      'max_latency': maxLatency,
      'max_loss_rate': maxLossRate,
      'min_download_speed': minDownloadSpeed,
      'test_count': testCount,
      'test_port': testPort,
      'download_test_time': downloadTestTime,
      'download_bytes': downloadBytes,
      'test_url': testUrl,
      'httping_mode': httpingMode,
      'max_ips_to_test': maxIPsToTest,
      'test_all_ips': testAllIPs,
    };
  }

  /// Returns the appropriate default config based on the current platform.
  ///
  /// - Mobile platforms (Android/iOS): Returns [mobile] preset (conservative)
  /// - Desktop/Web platforms (macOS/Windows/Linux): Returns [desktop] preset (unrestricted)
  ///
  /// This is used for first-time app launch when no config is saved.
  static ScannerConfig defaultForPlatform() {
    if (Platform.isAndroid || Platform.isIOS) {
      return mobile;
    }
    // Desktop/Web platforms (including VPS servers)
    return desktop;
  }

  /// Returns a human-readable name for the detected platform preset.
  ///
  /// Returns 'Mobile' for Android/iOS, 'Desktop' for all other platforms.
  static String detectedPresetName() {
    if (Platform.isAndroid || Platform.isIOS) {
      return 'Mobile';
    }
    return 'Desktop';
  }

  /// Default configuration for mobile devices (conservative)
  static const mobile = ScannerConfig(
    targetCleanIPs: 5,
    threads: 100,
    maxLatency: 300,
    maxLossRate: 0.2,
    minDownloadSpeed: 2.0,
    maxIPsToTest: 5000,
    testAllIPs: false,
  );

  /// Default configuration for desktop devices (balanced)
  static const desktop = ScannerConfig(
    targetCleanIPs: 10,
    threads: 200,
    maxLatency: 9999,
    maxLossRate: 1.0,
    minDownloadSpeed: 0.0,
    maxIPsToTest: 10000,
    testAllIPs: false,
  );

  /// Validates the configuration.
  ///
  /// Returns an error message if invalid, null if valid.
  String? validate() {
    if (targetCleanIPs < 1 || targetCleanIPs > 50) {
      return 'Target clean IPs must be between 1 and 50';
    }

    if (threads < 50 || threads > 500) {
      return 'Threads must be between 50 and 500';
    }

    if (maxLatency < 50 || maxLatency > 9999) {
      return 'Max latency must be between 50 and 9999 ms';
    }

    if (maxLossRate < 0.0 || maxLossRate > 1.0) {
      return 'Max loss rate must be between 0.0 and 1.0';
    }

    if (minDownloadSpeed < 0.0 || minDownloadSpeed > 100.0) {
      return 'Min download speed must be between 0 and 100 MB/s';
    }

    if (testCount < 1 || testCount > 10) {
      return 'Test count must be between 1 and 10';
    }

    if (testPort < 1 || testPort > 65535) {
      return 'Test port must be between 1 and 65535';
    }

    if (downloadTestTime < 5 || downloadTestTime > 60) {
      return 'Download test time must be between 5 and 60 seconds';
    }

    if (maxIPsToTest < 1000 || maxIPsToTest > 20000) {
      return 'Max IPs to test must be between 1000 and 20000';
    }

    if (testUrl.isEmpty) {
      return 'Test URL cannot be empty';
    }

    return null; // Valid
  }

  /// Creates a copy with the specified fields replaced.
  ScannerConfig copyWith({
    int? targetCleanIPs,
    int? threads,
    int? maxLatency,
    double? maxLossRate,
    double? minDownloadSpeed,
    int? testCount,
    int? testPort,
    int? downloadTestTime,
    int? downloadBytes,
    String? testUrl,
    bool? httpingMode,
    int? maxIPsToTest,
    bool? testAllIPs,
  }) {
    return ScannerConfig(
      targetCleanIPs: targetCleanIPs ?? this.targetCleanIPs,
      threads: threads ?? this.threads,
      maxLatency: maxLatency ?? this.maxLatency,
      maxLossRate: maxLossRate ?? this.maxLossRate,
      minDownloadSpeed: minDownloadSpeed ?? this.minDownloadSpeed,
      testCount: testCount ?? this.testCount,
      testPort: testPort ?? this.testPort,
      downloadTestTime: downloadTestTime ?? this.downloadTestTime,
      downloadBytes: downloadBytes ?? this.downloadBytes,
      testUrl: testUrl ?? this.testUrl,
      httpingMode: httpingMode ?? this.httpingMode,
      maxIPsToTest: maxIPsToTest ?? this.maxIPsToTest,
      testAllIPs: testAllIPs ?? this.testAllIPs,
    );
  }

  @override
  String toString() {
    return 'ScannerConfig('
        'targetCleanIPs: $targetCleanIPs, '
        'threads: $threads, '
        'maxLatency: $maxLatency, '
        'maxLossRate: $maxLossRate, '
        'minDownloadSpeed: $minDownloadSpeed, '
        'testCount: $testCount, '
        'testPort: $testPort, '
        'downloadTestTime: $downloadTestTime, '
        'httpingMode: $httpingMode, '
        'maxIPsToTest: $maxIPsToTest, '
        'testAllIPs: $testAllIPs'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ScannerConfig &&
        other.targetCleanIPs == targetCleanIPs &&
        other.threads == threads &&
        other.maxLatency == maxLatency &&
        other.maxLossRate == maxLossRate &&
        other.minDownloadSpeed == minDownloadSpeed &&
        other.testCount == testCount &&
        other.testPort == testPort &&
        other.downloadTestTime == downloadTestTime &&
        other.downloadBytes == downloadBytes &&
        other.testUrl == testUrl &&
        other.httpingMode == httpingMode &&
        other.maxIPsToTest == maxIPsToTest &&
        other.testAllIPs == testAllIPs;
  }

  @override
  int get hashCode {
    return Object.hash(
      targetCleanIPs,
      threads,
      maxLatency,
      maxLossRate,
      minDownloadSpeed,
      testCount,
      testPort,
      downloadTestTime,
      downloadBytes,
      testUrl,
      httpingMode,
      maxIPsToTest,
      testAllIPs,
    );
  }
}
