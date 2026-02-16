/// Configuration for the Cloudflare IP Scanner.
///
/// This model contains all parameters that can be passed to the scanner binary,
/// with sensible defaults for each option.
class ScannerConfig {
  /// Number of threads for latency testing (1-1000)
  /// Higher values = faster scanning, but may overload low-performance devices
  final int threads;

  /// Number of latency test iterations per IP (1-10)
  /// More iterations = more accurate latency measurement
  final int testCount;

  /// Number of IPs to test for download speed (1-100)
  /// After latency testing, test download speed for top N IPs
  final int downloadCount;

  /// Maximum acceptable latency in milliseconds (1-1000)
  /// IPs with latency above this will be filtered out
  final int latencyLimit;

  /// Minimum acceptable latency in milliseconds (0-1000)
  /// IPs with latency below this will be filtered out (anti-fraud)
  final int latencyLowerLimit;

  /// Minimum acceptable download speed in MB/s (1-100)
  /// IPs with speed below this will be filtered out
  final int speedLimit;

  /// Test port to use (1-65535)
  /// Default is 443 (HTTPS)
  final int testPort;

  /// URL to use for download speed test
  /// Should be a large file (50MB+) for accurate speed measurement
  final String testUrl;

  /// Disable download speed test
  /// If true, only latency testing is performed
  final bool disableDownload;

  /// Enable HTTPing mode for latency testing
  /// Uses HTTP requests instead of ICMP ping
  final bool httpingMode;

  /// Maximum download test time per IP in seconds (1-60)
  /// Prevents tests from running too long
  final int downloadTestTime;

  /// Creates a ScannerConfig with the specified values.
  ///
  /// All parameters are optional and will use defaults if not specified.
  const ScannerConfig({
    this.threads = 200,
    this.testCount = 4,
    this.downloadCount = 20,
    this.latencyLimit = 200,
    this.latencyLowerLimit = 40,
    this.speedLimit = 5,
    this.testPort = 443,
    this.testUrl = 'https://speed.cloudflare.com/__down?bytes=',
    this.disableDownload = false,
    this.httpingMode = false,
    this.downloadTestTime = 10,
  });

  /// Creates a ScannerConfig from JSON.
  factory ScannerConfig.fromJson(Map<String, dynamic> json) {
    return ScannerConfig(
      threads: json['threads'] as int? ?? 200,
      testCount: json['test_count'] as int? ?? 4,
      downloadCount: json['download_count'] as int? ?? 20,
      latencyLimit: json['latency_limit'] as int? ?? 200,
      latencyLowerLimit: json['latency_lower_limit'] as int? ?? 40,
      speedLimit: json['speed_limit'] as int? ?? 5,
      testPort: json['test_port'] as int? ?? 443,
      testUrl: json['test_url'] as String? ??
          'https://speed.cloudflare.com/__down?bytes=',
      disableDownload: json['disable_download'] as bool? ?? false,
      httpingMode: json['httping_mode'] as bool? ?? false,
      downloadTestTime: json['download_test_time'] as int? ?? 10,
    );
  }

  /// Converts this ScannerConfig to JSON.
  Map<String, dynamic> toJson() {
    return {
      'threads': threads,
      'test_count': testCount,
      'download_count': downloadCount,
      'latency_limit': latencyLimit,
      'latency_lower_limit': latencyLowerLimit,
      'speed_limit': speedLimit,
      'test_port': testPort,
      'test_url': testUrl,
      'disable_download': disableDownload,
      'httping_mode': httpingMode,
      'download_test_time': downloadTestTime,
    };
  }

  /// Converts this config to command-line arguments for the scanner binary.
  ///
  /// Returns a list of arguments to pass to the scanner executable.
  /// Example: ['-n', '200', '-t', '4', '-dn', '10']
  List<String> toCommandLineArgs() {
    final args = <String>[];

    // Threads
    args.addAll(['-n', threads.toString()]);

    // Test count
    args.addAll(['-t', testCount.toString()]);

    // Download count
    args.addAll(['-dn', downloadCount.toString()]);

    // Download test time
    args.addAll(['-dt', downloadTestTime.toString()]);

    // Test port
    args.addAll(['-tp', testPort.toString()]);

    // Test URL
    args.addAll(['-url', testUrl]);

    // HTTPing mode
    if (httpingMode) {
      args.add('-httping');
    }

    // Disable download
    if (disableDownload) {
      args.add('-disable-download');
    }

    return args;
  }

  /// Creates a default configuration optimized for mobile devices.
  ///
  /// Uses fewer threads and shorter test times to reduce battery usage.
  factory ScannerConfig.mobile() {
    return const ScannerConfig(
      threads: 100,
      testCount: 3,
      downloadCount: 5,
      downloadTestTime: 5,
    );
  }

  /// Creates a default configuration optimized for desktop devices.
  ///
  /// Uses more threads for faster scanning.
  factory ScannerConfig.desktop() {
    return const ScannerConfig(
      threads: 300,
      testCount: 5,
      downloadCount: 15,
      downloadTestTime: 15,
    );
  }

  /// Creates a fast configuration with minimal testing.
  ///
  /// Good for quick scans when you want results fast.
  factory ScannerConfig.fast() {
    return const ScannerConfig(
      threads: 400,
      testCount: 2,
      downloadCount: 5,
      downloadTestTime: 5,
    );
  }

  /// Creates a thorough configuration with extensive testing.
  ///
  /// Good for finding the absolute best IPs.
  factory ScannerConfig.thorough() {
    return const ScannerConfig(
      threads: 200,
      testCount: 10,
      downloadCount: 20,
      downloadTestTime: 20,
    );
  }

  /// Validates the configuration.
  ///
  /// Returns a list of validation errors, or empty list if valid.
  List<String> validate() {
    final errors = <String>[];

    if (threads < 1 || threads > 1000) {
      errors.add('Threads must be between 1 and 1000');
    }

    if (testCount < 1 || testCount > 10) {
      errors.add('Test count must be between 1 and 10');
    }

    if (downloadCount < 1 || downloadCount > 100) {
      errors.add('Download count must be between 1 and 100');
    }

    if (latencyLimit < 1 || latencyLimit > 1000) {
      errors.add('Latency limit must be between 1 and 1000');
    }

    if (latencyLowerLimit < 0 || latencyLowerLimit > 1000) {
      errors.add('Latency lower limit must be between 0 and 1000');
    }

    if (latencyLowerLimit >= latencyLimit) {
      errors.add('Latency lower limit must be less than latency limit');
    }

    if (speedLimit < 1 || speedLimit > 100) {
      errors.add('Speed limit must be between 1 and 100');
    }

    if (testPort < 1 || testPort > 65535) {
      errors.add('Test port must be between 1 and 65535');
    }

    if (testUrl.isEmpty) {
      errors.add('Test URL cannot be empty');
    }

    if (downloadTestTime < 1 || downloadTestTime > 60) {
      errors.add('Download test time must be between 1 and 60 seconds');
    }

    return errors;
  }

  /// Returns true if this configuration is valid.
  bool isValid() {
    return validate().isEmpty;
  }

  /// Creates a copy of this config with modified values.
  ScannerConfig copyWith({
    int? threads,
    int? testCount,
    int? downloadCount,
    int? latencyLimit,
    int? latencyLowerLimit,
    int? speedLimit,
    int? testPort,
    String? testUrl,
    bool? disableDownload,
    bool? httpingMode,
    int? downloadTestTime,
  }) {
    return ScannerConfig(
      threads: threads ?? this.threads,
      testCount: testCount ?? this.testCount,
      downloadCount: downloadCount ?? this.downloadCount,
      latencyLimit: latencyLimit ?? this.latencyLimit,
      latencyLowerLimit: latencyLowerLimit ?? this.latencyLowerLimit,
      speedLimit: speedLimit ?? this.speedLimit,
      testPort: testPort ?? this.testPort,
      testUrl: testUrl ?? this.testUrl,
      disableDownload: disableDownload ?? this.disableDownload,
      httpingMode: httpingMode ?? this.httpingMode,
      downloadTestTime: downloadTestTime ?? this.downloadTestTime,
    );
  }

  @override
  String toString() {
    return 'ScannerConfig('
        'threads: $threads, '
        'testCount: $testCount, '
        'downloadCount: $downloadCount, '
        'latencyLimit: ${latencyLimit}ms, '
        'speedLimit: ${speedLimit}MB/s)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ScannerConfig &&
        other.threads == threads &&
        other.testCount == testCount &&
        other.downloadCount == downloadCount &&
        other.latencyLimit == latencyLimit &&
        other.latencyLowerLimit == latencyLowerLimit &&
        other.speedLimit == speedLimit &&
        other.testPort == testPort &&
        other.testUrl == testUrl &&
        other.disableDownload == disableDownload &&
        other.httpingMode == httpingMode &&
        other.downloadTestTime == downloadTestTime;
  }

  @override
  int get hashCode {
    return Object.hash(
      threads,
      testCount,
      downloadCount,
      latencyLimit,
      latencyLowerLimit,
      speedLimit,
      testPort,
      testUrl,
      disableDownload,
      httpingMode,
      downloadTestTime,
    );
  }
}
