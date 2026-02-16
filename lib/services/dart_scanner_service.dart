import 'dart:async';
import 'package:bpb_automation/models/scan_progress.dart';
import 'package:bpb_automation/models/scan_result.dart';
import 'package:bpb_automation/models/latency_result.dart';
import 'package:bpb_automation/models/speed_result.dart';
import 'package:bpb_automation/models/scanner_config.dart';
import 'package:bpb_automation/services/ip_loader.dart';
import 'package:bpb_automation/services/latency_tester.dart';
import 'package:bpb_automation/services/speed_tester.dart';
import 'package:bpb_automation/services/log_service.dart';

/// Result of a complete scan operation
class DartScanResult {
  final List<ScanResult> results;
  final DateTime timestamp;
  final int totalTested;
  final int successful;
  final int failed;

  const DartScanResult({
    required this.results,
    required this.timestamp,
    required this.totalTested,
    required this.successful,
    required this.failed,
  });
}

/// Pure Dart implementation of the IP scanner
///
/// This replaces the binary-based scanner with a native Dart implementation
/// that works across all platforms without sandboxing issues.
class DartScannerService {
  static final DartScannerService _instance = DartScannerService._internal();
  static DartScannerService get instance => _instance;

  DartScannerService._internal();

  final LogService _logService = LogService.instance;
  final IPLoader _ipLoader = IPLoader();
  final LatencyTester _latencyTester = LatencyTester();
  final SpeedTester _speedTester = SpeedTester();

  /// Stream controller for progress updates
  StreamController<ScanProgress>? _progressController;

  /// Execute a complete scan with the given configuration
  ///
  /// Returns the scan results. Progress updates can be monitored via [progressStream].
  Future<DartScanResult> executeScan(ScannerConfig config) async {
    _logService.logInfo('Starting Dart scanner execution');

    try {
      // Step 1: Initialize
      _emitProgress(ScanProgress.initial(totalIPs: 0).copyWith(
        stage: ScanStage.initializing,
        message: 'Initializing scanner',
      ));

      // Step 2: Load IPs
      _emitProgress(ScanProgress.initial(totalIPs: 0).copyWith(
        stage: ScanStage.loadingIPs,
        message: 'Loading IP addresses',
      ));

      final allIPs = await _ipLoader.loadAllAddresses();
      _logService.logInfo('Loaded ${allIPs.length} total IP addresses');

      // For now, only use IPv4 addresses
      final filteredIPs = _ipLoader.filterByType(allIPs, IPType.ipv4);

      // Select subset - use all filtered IPs for now
      final selectedIPs = filteredIPs;

      _logService.logOk('Selected ${selectedIPs.length} IPs to test');

      final totalIPs = selectedIPs.length;
      var processedIPs = 0;
      var successfulIPs = 0;
      var failedIPs = 0;

      // Step 3: Latency testing
      _emitProgress(ScanProgress(
        totalIPs: totalIPs,
        processedIPs: 0,
        successfulIPs: 0,
        failedIPs: 0,
        stage: ScanStage.latencyTesting,
        message: 'Testing latency for $totalIPs IPs',
        timestamp: DateTime.now(),
      ));

      final latencyResults = <String, LatencyResult>{};

      await for (final latencyResult in _latencyTester.testMultiple(
        ips: selectedIPs,
        port: config.testPort,
        count: config.testCount,
        timeout: Duration(milliseconds: config.latencyLimit),
        maxConcurrent: config.threads,
      )) {
        latencyResults[latencyResult.ip] = latencyResult;
        processedIPs++;

        if (latencyResult.isSuccessful) {
          successfulIPs++;
        } else {
          failedIPs++;
        }

        _emitProgress(ScanProgress(
          totalIPs: totalIPs,
          processedIPs: processedIPs,
          successfulIPs: successfulIPs,
          failedIPs: failedIPs,
          currentIP: latencyResult.ip,
          stage: ScanStage.latencyTesting,
          message: 'Tested latency: $processedIPs/$totalIPs',
          timestamp: DateTime.now(),
        ));
      }

      _logService.logOk('Latency testing complete: $successfulIPs successful, $failedIPs failed');

      // Filter to only successful latency results
      final successfulLatencies = latencyResults.entries
          .where((e) => e.value.isSuccessful)
          .map((e) => e.key)
          .toList();

      if (successfulLatencies.isEmpty) {
        _logService.logError('No IPs passed latency test');
        _emitProgress(ScanProgress(
          totalIPs: totalIPs,
          processedIPs: totalIPs,
          successfulIPs: 0,
          failedIPs: totalIPs,
          stage: ScanStage.failed,
          message: 'Scan failed: No IPs passed latency test',
          timestamp: DateTime.now(),
        ));

        return DartScanResult(
          results: [],
          timestamp: DateTime.now(),
          totalTested: totalIPs,
          successful: 0,
          failed: totalIPs,
        );
      }

      // Step 4: Speed testing (optional, based on config)
      final speedResults = <String, SpeedResult>{};

      if (!config.disableDownload) {
        processedIPs = 0;

        // Only test top N IPs for speed (from config.downloadCount)
        final ipsToTest = successfulLatencies.take(config.downloadCount).toList();

        _emitProgress(ScanProgress(
          totalIPs: ipsToTest.length,
          processedIPs: 0,
          successfulIPs: 0,
          failedIPs: 0,
          stage: ScanStage.speedTesting,
          message: 'Testing download speed for ${ipsToTest.length} IPs',
          timestamp: DateTime.now(),
        ));

        var speedSuccess = 0;
        var speedFail = 0;

        // Extract download size from testUrl or use default (10 MB)
        final downloadBytes = _extractDownloadBytes(config.testUrl) ?? 10000000;

        await for (final speedResult in _speedTester.testMultiple(
          ips: ipsToTest,
          port: config.testPort,
          testUrl: config.testUrl,
          downloadBytes: downloadBytes,
          timeout: Duration(seconds: config.downloadTestTime),
          maxConcurrent: config.threads,
        )) {
          speedResults[speedResult.ip] = speedResult;
          processedIPs++;

          if (speedResult.isSuccessful) {
            speedSuccess++;
          } else {
            speedFail++;
          }

          _emitProgress(ScanProgress(
            totalIPs: ipsToTest.length,
            processedIPs: processedIPs,
            successfulIPs: speedSuccess,
            failedIPs: speedFail,
            currentIP: speedResult.ip,
            stage: ScanStage.speedTesting,
            message: 'Tested speed: $processedIPs/${ipsToTest.length}',
            timestamp: DateTime.now(),
          ));
        }

        _logService.logOk('Speed testing complete: $speedSuccess successful, $speedFail failed');
      }

      // Step 5: Build final results
      _emitProgress(ScanProgress(
        totalIPs: totalIPs,
        processedIPs: totalIPs,
        successfulIPs: successfulIPs,
        failedIPs: failedIPs,
        stage: ScanStage.sorting,
        message: 'Sorting results',
        timestamp: DateTime.now(),
      ));

      final scanResults = <ScanResult>[];

      for (final ip in successfulLatencies) {
        final scanResult = ScanResult.fromTests(
          ip: ip,
          latencyResult: latencyResults[ip]!,
          speedResult: speedResults[ip],
        );
        scanResults.add(scanResult);
      }

      // Sort by quality
      scanResults.sort((a, b) => a.compareQuality(b));

      _logService.logOk('Generated ${scanResults.length} scan results');

      // Step 6: Complete
      _emitProgress(ScanProgress(
        totalIPs: totalIPs,
        processedIPs: totalIPs,
        successfulIPs: successfulIPs,
        failedIPs: failedIPs,
        stage: ScanStage.completed,
        message: 'Scan completed: ${scanResults.length} results',
        timestamp: DateTime.now(),
      ));

      return DartScanResult(
        results: scanResults,
        timestamp: DateTime.now(),
        totalTested: totalIPs,
        successful: successfulIPs,
        failed: failedIPs,
      );

    } catch (e, stackTrace) {
      _logService.logError('Scan failed', e, stackTrace);

      _emitProgress(ScanProgress(
        totalIPs: 0,
        processedIPs: 0,
        successfulIPs: 0,
        failedIPs: 0,
        stage: ScanStage.failed,
        message: 'Scan failed: $e',
        timestamp: DateTime.now(),
      ));

      rethrow;
    }
  }

  /// Start listening for progress updates before calling executeScan
  Stream<ScanProgress> startProgressStream() {
    _progressController?.close();
    _progressController = StreamController<ScanProgress>.broadcast();
    return _progressController!.stream;
  }

  /// Stop progress stream
  void stopProgressStream() {
    _progressController?.close();
    _progressController = null;
  }

  /// Emit progress update
  void _emitProgress(ScanProgress progress) {
    _progressController?.add(progress);
  }

  /// Check if the service is available (always true for Dart scanner)
  bool get isAvailable => true;

  /// Get scanner version
  String get version => '1.0.0-dart';

  /// Extract download bytes from test URL
  ///
  /// Parses URLs like "https://speed.cloudflare.com/__down?bytes=52428800"
  /// Returns null if bytes parameter not found
  int? _extractDownloadBytes(String testUrl) {
    try {
      final uri = Uri.parse(testUrl);
      final bytesParam = uri.queryParameters['bytes'];
      if (bytesParam != null) {
        return int.tryParse(bytesParam);
      }
    } catch (e) {
      _logService.logWarn('Failed to parse download bytes from URL: $e');
    }
    return null;
  }
}
