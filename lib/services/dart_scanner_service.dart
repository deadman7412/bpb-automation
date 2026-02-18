import 'dart:async';
import 'dart:io' show Platform;
import 'package:bpb_automation/models/config_scan_result.dart';
import 'package:bpb_automation/models/config_test_result.dart';
import 'package:bpb_automation/models/xray_config.dart';
import 'package:bpb_automation/services/ip_loader.dart';
import 'package:bpb_automation/services/log_service.dart';
import 'package:bpb_automation/services/subscription_service.dart';
import 'package:bpb_automation/services/config_tester_service.dart';
import 'package:bpb_automation/services/xray_service.dart';

/// Progress information for Phase 2 proxy testing
class Phase2Progress {
  /// Total number of IPs to test in Phase 2
  final int totalIPs;

  /// Number of IPs tested so far
  final int testedIPs;

  /// Number of IPs that work (proxy test passed)
  final int workingIPs;

  /// Current IP being tested (null if between tests)
  final String? currentIP;

  const Phase2Progress({
    required this.totalIPs,
    required this.testedIPs,
    required this.workingIPs,
    this.currentIP,
  });

  /// Progress percentage (0.0 to 1.0)
  double get progress => totalIPs > 0 ? testedIPs / totalIPs : 0.0;

  /// Progress percentage (0 to 100)
  double get progressPercent => progress * 100;

  @override
  String toString() {
    return 'Phase2Progress($testedIPs/$totalIPs tested, $workingIPs working, current: $currentIP)';
  }
}

/// Pure Dart implementation of config-based IP scanner
///
/// This scanner uses actual BPB subscription configs and tests IPs
/// with real Xray proxy connections in two phases:
///
/// **Phase 1**: Fast TLS handshake testing (concurrent, many IPs)
/// **Phase 2**: Real proxy testing via Xray-core (sequential, top candidates)
class DartScannerService {
  static final DartScannerService _instance = DartScannerService._internal();
  static DartScannerService get instance => _instance;

  DartScannerService._internal();

  final LogService _logService = LogService.instance;
  final IPLoader _ipLoader = IPLoader();
  final SubscriptionService _subscriptionService = SubscriptionService.instance;
  final ConfigTesterService _configTester = ConfigTesterService.instance;
  final XrayService _xrayService = XrayService.instance;

  // Scan session management
  bool _isScanning = false;
  bool _isCancelled = false;

  // Phase 2 progress stream
  final _phase2ProgressController =
      StreamController<Phase2Progress>.broadcast();
  Stream<Phase2Progress> get phase2ProgressStream =>
      _phase2ProgressController.stream;

  /// Check if a scan is currently running
  bool get isScanning => _isScanning;

  /// Cancel the current scan
  void cancelScan() {
    _isCancelled = true;
    _logService.logWarn('Scan cancellation requested by user');
  }

  /// Dispose resources
  void dispose() {
    _phase2ProgressController.close();
  }

  /// Get CIDR expansion samples per range based on platform
  int _getCIDRSamplesForPlatform() {
    if (Platform.isAndroid || Platform.isIOS) {
      return 50; // Mobile: ~750 total IPs with 15 CIDR ranges
    } else if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      return 100; // Desktop: ~1500 total IPs with 15 CIDR ranges
    }
    return 50; // Fallback
  }

  /// Execute config-based scan with 2-phase testing
  ///
  /// **NEW WORKFLOW**: Accepts pre-fetched configs directly (no network calls)
  ///
  /// **Phase 1**: Fast TLS handshake testing (concurrent)
  /// - Tests all candidate IPs with TLS handshake
  /// - Filters successful IPs
  /// - Sorts by latency (fastest first)
  ///
  /// **Phase 2**: Real proxy testing via Xray-core (low concurrency)
  /// - Tests top N candidates from Phase 1
  /// - Actually connects through Xray proxy
  /// - Tests HTTP connection via SOCKS5
  /// - Continues until desired IP count found or all tested
  ///
  /// Parameters:
  /// - [configs]: Pre-fetched Xray configs from subscription
  /// - [desiredIPCount]: Target number of working IPs to find
  /// - [phase2TestDepth]: How many Phase 1 winners to test in Phase 2
  ///
  /// Returns [ConfigScanResult] with working IPs and detailed test results.
  Future<ConfigScanResult> executeConfigScanWithConfigs({
    required List<XrayConfig> configs,
    int desiredIPCount = 10,
    int phase2TestDepth = 50,
    bool enableIPv6 = false,
  }) async {
    // Prevent multiple concurrent scans
    if (_isScanning) {
      _logService.logWarn(
        'Scan already in progress, rejecting new scan request',
      );
      final emptyConfig = XrayConfig(outbounds: [], inbounds: [], log: {});
      return ConfigScanResult.failure(
        totalTested: 0,
        phase1Passed: 0,
        phase2Tested: 0,
        allResults: [],
        scanDuration: Duration.zero,
        templateConfig: emptyConfig,
      );
    }

    _isScanning = true;
    _isCancelled = false;

    _logService.logInfo('===== STARTING CONFIG-BASED SCAN =====');
    _logService.logInfo(
      'Goal: Find $desiredIPCount working IPs using Xray config',
    );
    _logService.logInfo('Phase 2 test depth: $phase2TestDepth IPs');
    _logService.logInfo(
      'IPv6 scanning: ${enableIPv6 ? "ENABLED" : "DISABLED"}',
    );

    final scanStartTime = DateTime.now();

    // Use downloadTestTime from default config for timeouts
    const timeoutSeconds = 10;

    try {
      // Step 1: Initialize Xray service
      _logService.logInfo('Initializing Xray service...');
      await _xrayService.initialize();
      _logService.logOk('Xray service initialized');

      // Step 2: Select IP-based config
      if (configs.isEmpty) {
        _logService.logError('No configs provided');
        _isScanning = false;
        final emptyConfig = XrayConfig(outbounds: [], inbounds: [], log: {});
        return ConfigScanResult.failure(
          totalTested: 0,
          phase1Passed: 0,
          phase2Tested: 0,
          allResults: [],
          scanDuration: DateTime.now().difference(scanStartTime),
          templateConfig: emptyConfig,
        );
      }

      final ipBasedConfigs = configs.where((c) => c.isIpBased()).toList();

      if (ipBasedConfigs.isEmpty) {
        _logService.logError('No IP-based configs found');
        _isScanning = false;
        return ConfigScanResult.failure(
          totalTested: 0,
          phase1Passed: 0,
          phase2Tested: 0,
          allResults: [],
          scanDuration: DateTime.now().difference(scanStartTime),
          templateConfig: configs.first,
        );
      }

      final selectedConfig = ipBasedConfigs.first;
      _logService.logOk('Selected config: ${selectedConfig.getDescription()}');

      // Step 3: Load candidate IPs
      _logService.logInfo('Loading candidate IPs...');
      final candidateIPs = enableIPv6
          ? await _ipLoader.loadAllAddresses(
              maxSamplesPerCIDR: _getCIDRSamplesForPlatform(),
            )
          : await _ipLoader.loadIPv4Addresses(
              maxSamplesPerCIDR: _getCIDRSamplesForPlatform(),
            );

      _logService.logOk('Loaded ${candidateIPs.length} candidate IPs');

      // Step 4: Phase 1 - TLS Testing (concurrent)
      _logService.logInfo('===== PHASE 1: TLS HANDSHAKE TESTING =====');
      _logService.logInfo('Testing ${candidateIPs.length} IPs...');

      final phase1Results = await _configTester.testIPsWithTLS(
        template: selectedConfig,
        candidateIPs: candidateIPs,
        timeoutSeconds: timeoutSeconds,
        maxConcurrency: 200, // High concurrency for fast TLS tests
      );

      // Filter successful TLS results
      final phase1Successful = phase1Results
          .where((r) => r.tlsTestResult != null && r.tlsTestResult!.success)
          .toList();

      // Sort by TLS latency (fastest first)
      phase1Successful.sort((a, b) {
        final aLatency = a.tlsTestResult?.latencyMs ?? double.infinity;
        final bLatency = b.tlsTestResult?.latencyMs ?? double.infinity;
        return aLatency.compareTo(bLatency);
      });

      _logService.logOk(
        'Phase 1 complete: ${phase1Successful.length}/${candidateIPs.length} passed TLS test',
      );

      if (phase1Successful.isEmpty) {
        _logService.logError('No IPs passed Phase 1 TLS testing');
        _isScanning = false;
        return ConfigScanResult.failure(
          totalTested: candidateIPs.length,
          phase1Passed: 0,
          phase2Tested: 0,
          allResults: phase1Results,
          scanDuration: DateTime.now().difference(scanStartTime),
          templateConfig: selectedConfig,
        );
      }

      // Step 5: Phase 2 - Proxy Testing (low concurrency)
      _logService.logInfo('===== PHASE 2: XRAY PROXY TESTING =====');

      // Determine how many IPs to test in Phase 2
      final phase2Candidates = phase1Successful.take(phase2TestDepth).toList();
      _logService.logInfo(
        'Testing top ${phase2Candidates.length} IPs with Xray proxy...',
      );

      final phase2Results = <ConfigTestResult>[];
      var workingCount = 0;

      // Emit initial Phase 2 progress
      _phase2ProgressController.add(
        Phase2Progress(
          totalIPs: phase2Candidates.length,
          testedIPs: 0,
          workingIPs: 0,
        ),
      );

      // Test IPs one by one (low concurrency to avoid resource exhaustion)
      for (var i = 0; i < phase2Candidates.length; i++) {
        if (_isCancelled) {
          _logService.logWarn('Scan cancelled by user');
          break;
        }

        final candidateResult = phase2Candidates[i];
        final candidateIP = candidateResult.ip;

        _logService.logInfo(
          'Testing ${i + 1}/${phase2Candidates.length}: $candidateIP',
        );

        // Emit progress update - testing started
        _phase2ProgressController.add(
          Phase2Progress(
            totalIPs: phase2Candidates.length,
            testedIPs: i,
            workingIPs: workingCount,
            currentIP: candidateIP,
          ),
        );

        // Test IP with Xray proxy
        final proxyResult = await _xrayService.testIPWithProxy(
          config: selectedConfig,
          candidateIP: candidateIP,
          timeoutSeconds: timeoutSeconds,
        );

        phase2Results.add(proxyResult);

        // Check if IP works
        if (proxyResult.proxyTestResult != null &&
            proxyResult.proxyTestResult!.success &&
            proxyResult.proxyTestResult!.statusCode == 204) {
          workingCount++;
          _logService.logOk(
            '$candidateIP works! ($workingCount/$desiredIPCount found)',
          );

          // Emit progress update - IP worked
          _phase2ProgressController.add(
            Phase2Progress(
              totalIPs: phase2Candidates.length,
              testedIPs: i + 1,
              workingIPs: workingCount,
            ),
          );

          // Early exit if we found enough working IPs
          if (workingCount >= desiredIPCount) {
            _logService.logOk(
              'Target reached! Found $workingCount working IPs',
            );
            break;
          }
        } else {
          _logService.logWarn('$candidateIP failed proxy test');

          // Emit progress update - IP failed
          _phase2ProgressController.add(
            Phase2Progress(
              totalIPs: phase2Candidates.length,
              testedIPs: i + 1,
              workingIPs: workingCount,
            ),
          );
        }
      }

      // Emit final Phase 2 progress
      _phase2ProgressController.add(
        Phase2Progress(
          totalIPs: phase2Candidates.length,
          testedIPs: phase2Results.length,
          workingIPs: workingCount,
        ),
      );

      // Combine Phase 1 and Phase 2 results
      final allResults = <ConfigTestResult>[];

      // Add Phase 2 results
      allResults.addAll(phase2Results);

      // Add Phase 1 only results (not tested in Phase 2)
      final phase2IPs = phase2Results.map((r) => r.ip).toSet();
      final phase1OnlyResults = phase1Results
          .where((r) => !phase2IPs.contains(r.ip))
          .toList();
      allResults.addAll(phase1OnlyResults);

      final scanDuration = DateTime.now().difference(scanStartTime);

      _logService.logOk('===== CONFIG SCAN COMPLETE =====');
      _logService.logOk(
        'Found $workingCount working IPs in ${scanDuration.inSeconds}s',
      );
      _logService.logOk(
        'Phase 1: ${phase1Successful.length}/${candidateIPs.length} passed TLS',
      );
      _logService.logOk(
        'Phase 2: $workingCount/${phase2Results.length} passed proxy test',
      );

      _isScanning = false;

      return ConfigScanResult.success(
        totalTested: candidateIPs.length,
        phase1Passed: phase1Successful.length,
        phase2Tested: phase2Results.length,
        allResults: allResults,
        scanDuration: scanDuration,
        templateConfig: selectedConfig,
      );
    } catch (e, stackTrace) {
      _logService.logError('Config scan failed: $e');
      _logService.logError('Stack trace: $stackTrace');

      _isScanning = false;

      final emptyConfig = XrayConfig(outbounds: [], inbounds: [], log: {});
      return ConfigScanResult.failure(
        totalTested: 0,
        phase1Passed: 0,
        phase2Tested: 0,
        allResults: [],
        scanDuration: DateTime.now().difference(scanStartTime),
        templateConfig: emptyConfig,
      );
    }
  }
}
