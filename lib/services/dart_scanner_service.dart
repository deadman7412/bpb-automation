import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:bpb_automation/models/scan_progress.dart';
import 'package:bpb_automation/models/scan_result.dart';
import 'package:bpb_automation/models/latency_result.dart';
import 'package:bpb_automation/models/speed_result.dart';
import 'package:bpb_automation/models/scanner_config.dart';
import 'package:bpb_automation/services/ip_loader.dart';
import 'package:bpb_automation/services/latency_tester.dart';
import 'package:bpb_automation/services/speed_tester.dart';
import 'package:bpb_automation/services/log_service.dart';

/// Status of a scan operation
enum ScanStatus {
  /// Target number of clean IPs successfully found
  success,

  /// Minimum acceptable IPs met, but target not reached
  partial,

  /// Below minimum acceptable IPs
  insufficient,

  /// No results found or error occurred
  failed,

  /// Scan was cancelled by user
  cancelled,
}

/// Result of a complete scan operation
class DartScanResult {
  final List<ScanResult> results;
  final DateTime timestamp;
  final int totalTested;
  final int successful;
  final int failed;
  final ScanStatus status;
  final String message;

  const DartScanResult({
    required this.results,
    required this.timestamp,
    required this.totalTested,
    required this.successful,
    required this.failed,
    required this.status,
    required this.message,
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

  // Session state tracking for duplicate prevention
  final Set<String> _testedIPsInSession = {};
  final Set<String> _cleanIPAddresses = {};

  // Cancellation flag
  bool _isCancelled = false;

  /// Reset session state before starting a new scan
  void _resetSessionState() {
    _testedIPsInSession.clear();
    _cleanIPAddresses.clear();
    _isCancelled = false; // Reset cancellation flag
    _logService.logInfo('[INFO] Session state reset');
  }

  /// Cancel the current scan
  ///
  /// Sets a flag that will be checked during the scan loop.
  /// The scan will stop and return partial results.
  void cancelScan() {
    _isCancelled = true;
    _logService.logWarn('[WARN] Scan cancellation requested by user');
  }

  /// Filter out IPs that have already been tested in this session
  ///
  /// Returns only IPs that haven't been tested yet
  List<String> _filterDuplicates(List<String> ips) {
    final uniqueIPs = ips
        .where((ip) => !_testedIPsInSession.contains(ip))
        .toList();
    final duplicateCount = ips.length - uniqueIPs.length;

    if (duplicateCount > 0) {
      _logService.logInfo(
        '[INFO] Filtered out $duplicateCount duplicate IPs (already tested)',
      );
    }

    return uniqueIPs;
  }

  /// Add a clean IP to the results, checking for duplicates
  ///
  /// Returns true if IP was added, false if it was a duplicate
  bool _addCleanIP(String ip, ScanResult result, List<ScanResult> cleanIPs) {
    if (_cleanIPAddresses.contains(ip)) {
      _logService.logWarn('[WARN] Duplicate clean IP detected: $ip (skipping)');
      return false;
    }

    _cleanIPAddresses.add(ip);
    cleanIPs.add(result);
    return true;
  }

  /// Determine scan status and generate user-friendly message
  ///
  /// Returns a tuple of (ScanStatus, String message) based on results vs goals
  @visibleForTesting
  (ScanStatus, String) determineScanStatus(
    int cleanIPsFound,
    int targetCleanIPs,
    int minAcceptableIPs,
    int totalIPsTested,
    int maxTotalIPsToTest,
  ) {
    // No results at all
    if (cleanIPsFound == 0) {
      return (
        ScanStatus.failed,
        'No clean IPs found after testing $totalIPsTested IPs. '
            'Try: (1) Check network connection, (2) Lower latency/speed requirements, '
            'or (3) Use different IP ranges.',
      );
    }

    // Target met or exceeded
    if (cleanIPsFound >= targetCleanIPs) {
      return (
        ScanStatus.success,
        'Found $cleanIPsFound clean IPs (target: $targetCleanIPs). '
            'Scan completed successfully.',
      );
    }

    // Minimum acceptable met but not target
    if (cleanIPsFound >= minAcceptableIPs) {
      return (
        ScanStatus.partial,
        'Found $cleanIPsFound clean IPs (min: $minAcceptableIPs, target: $targetCleanIPs). '
            'Try: (1) Lower target to $cleanIPsFound IPs, (2) Increase max IPs to test from '
            '$maxTotalIPsToTest to ${maxTotalIPsToTest + 500}, or (3) Lower requirements.',
      );
    }

    // Below minimum acceptable
    return (
      ScanStatus.insufficient,
      'Found only $cleanIPsFound clean IPs (min: $minAcceptableIPs, target: $targetCleanIPs). '
          'Try: (1) Increase max IPs to test from $maxTotalIPsToTest to ${maxTotalIPsToTest + 1000}, '
          '(2) Lower latency threshold, (3) Lower speed requirements, or (4) Use different IP ranges.',
    );
  }

  /// Test downloads using Pareto principle (20% incremental batching)
  ///
  /// Tests top 20% of IPs first, then next 20%, etc. until target is met.
  /// Returns Map of IP -> SpeedResult for tested IPs.
  ///
  /// Parameters:
  /// - `successfulLatencies`: Map of IP to LatencyResult for IPs that passed latency test
  /// - `config`: Scanner configuration
  /// - `targetCleanIPs`: Number of clean IPs needed
  /// - `currentCleanCount`: Number of clean IPs already found
  /// - `currentBatch`: Current batch number for progress reporting
  /// - `totalIPsTested`: Total IPs tested so far across all batches
  ///
  /// Returns: `Map<String, SpeedResult>` containing speed test results
  Future<Map<String, SpeedResult>> _testDownloadsPareto({
    required Map<String, LatencyResult> successfulLatencies,
    required ScannerConfig config,
    required int targetCleanIPs,
    required int currentCleanCount,
    required int currentBatch,
    required int totalIPsTested,
  }) async {
    final speedResults = <String, SpeedResult>{};

    // Sort IPs by latency quality (best first)
    final sortedIPs = successfulLatencies.entries.toList()
      ..sort((a, b) {
        // Lower average latency is better
        return a.value.averageLatencyMs.compareTo(b.value.averageLatencyMs);
      });

    final totalAvailable = sortedIPs.length;

    // Calculate how many more clean IPs we need
    var cleanIPsNeeded = targetCleanIPs - currentCleanCount;
    if (cleanIPsNeeded <= 0) {
      _logService.logOk('[OK] Target already met, skipping download tests');
      return speedResults;
    }

    // Download test configuration
    final downloadBytes = _extractDownloadBytes(config.testUrl) ?? 10000000;
    final paretoPercentage = config.downloadTestPercentage / 100.0;

    _logService.logInfo('[INFO] ===== PARETO DOWNLOAD TESTING START =====');
    _logService.logInfo(
      '[INFO] Available IPs for download testing: $totalAvailable (sorted by latency)',
    );
    _logService.logInfo(
      '[INFO] Target: $targetCleanIPs clean IPs, currently have: $currentCleanCount, need: $cleanIPsNeeded more',
    );
    _logService.logInfo(
      '[INFO] Download config: ${(downloadBytes / 1000000).toStringAsFixed(1)} MB, timeout: ${config.downloadTestTime}s, threads: ${config.threads}',
    );

    var totalTested = 0;
    var currentIndex = 0;

    // Process in Pareto batches (20% at a time by default)
    while (currentIndex < totalAvailable && cleanIPsNeeded > 0) {
      // Calculate batch size (20% of remaining IPs)
      final remaining = totalAvailable - currentIndex;
      final batchSize = (remaining * paretoPercentage).ceil();
      final actualBatchSize = batchSize.clamp(1, remaining);

      final batchStart = currentIndex;
      final batchEnd = (currentIndex + actualBatchSize).clamp(
        0,
        totalAvailable,
      );
      final batch = sortedIPs.sublist(batchStart, batchEnd);

      // Get IPs for this batch
      final batchIPs = batch.map((e) => e.key).toList();

      _logService.logInfo(
        '[INFO] Pareto batch ${(currentIndex / totalAvailable * 100).toInt()}-${(batchEnd / totalAvailable * 100).toInt()}%: Testing downloads for ${batch.length} IPs',
      );

      // Log the IPs being tested
      final ipsPreview = batchIPs.take(3).join(', ');
      final moreCount = batchIPs.length > 3
          ? ' and ${batchIPs.length - 3} more'
          : '';
      _logService.logInfo('[INFO] Testing IPs: $ipsPreview$moreCount');

      _emitProgress(
        ScanProgress(
          totalIPs: batch.length,
          processedIPs: 0,
          successfulIPs: 0,
          failedIPs: 0,
          currentBatch: currentBatch,
          targetCleanIPs: config.targetCleanIPs,
          cleanIPsFound: currentCleanCount,
          minAcceptableIPs: config.minAcceptableIPs,
          totalIPsTested: totalIPsTested,
          stage: ScanStage.speedTesting,
          subStage:
              'Testing downloads for ${batch.length}/$totalAvailable IPs (top ${(batchEnd / totalAvailable * 100).toInt()}%)',
          message:
              'Testing downloads for top ${(batchEnd / totalAvailable * 100).toInt()}% IPs',
          timestamp: DateTime.now(),
        ),
      );

      var processedInBatch = 0;
      var successInBatch = 0;

      // Test this batch
      await for (final speedResult in _speedTester.testMultiple(
        ips: batchIPs,
        port: config.testPort,
        testUrl: config.testUrl,
        downloadBytes: downloadBytes,
        timeout: Duration(seconds: config.downloadTestTime),
        maxConcurrent: config.threads,
        isCancelled: () => _isCancelled,
      )) {
        speedResults[speedResult.ip] = speedResult;
        processedInBatch++;
        totalTested++;

        if (speedResult.isSuccessful) {
          successInBatch++;
        }

        _emitProgress(
          ScanProgress(
            totalIPs: batch.length,
            processedIPs: processedInBatch,
            successfulIPs: successInBatch,
            failedIPs: processedInBatch - successInBatch,
            currentIP: speedResult.ip,
            currentBatch: currentBatch,
            targetCleanIPs: config.targetCleanIPs,
            cleanIPsFound: currentCleanCount,
            minAcceptableIPs: config.minAcceptableIPs,
            totalIPsTested: totalIPsTested,
            stage: ScanStage.speedTesting,
            subStage: 'Testing $totalTested/$totalAvailable IPs',
            message:
                'Tested: $processedInBatch/${batch.length} ($successInBatch clean)',
            timestamp: DateTime.now(),
          ),
        );
      }

      _logService.logOk(
        '[OK] Pareto batch complete: $successInBatch/${batch.length} passed download test, $cleanIPsNeeded more needed',
      );

      // Update clean IPs needed (approximation - actual count done later)
      cleanIPsNeeded -= successInBatch;
      currentIndex = batchEnd;

      // Stop if we've likely met our goal
      if (cleanIPsNeeded <= 0) {
        _logService.logOk(
          'Target likely met after testing ${(batchEnd / totalAvailable * 100).toInt()}% of IPs',
        );
        break;
      }
    }

    _logService.logOk(
      'Pareto download testing complete: $totalTested/$totalAvailable IPs tested (${(totalTested / totalAvailable * 100).toStringAsFixed(1)}%)',
    );

    return speedResults;
  }

  /// Execute a complete scan with the given configuration
  ///
  /// Returns the scan results. Progress updates can be monitored via [progressStream].
  Future<DartScanResult> executeScan(ScannerConfig config) async {
    _logService.logInfo('Starting Dart scanner execution');
    _logService.logInfo(
      'Goal: Find ${config.targetCleanIPs} clean IPs (min ${config.minAcceptableIPs})',
    );

    // Reset session state at start of new scan
    _resetSessionState();

    final scanStartTime = DateTime.now();
    final allScanResults = <ScanResult>[]; // Accumulate results across batches
    var totalIPsTested = 0;
    var currentBatch = 0;

    try {
      // Step 1: Initialize
      _emitProgress(
        ScanProgress.initial(
          totalIPs: 0,
          targetCleanIPs: config.targetCleanIPs,
          minAcceptableIPs: config.minAcceptableIPs,
        ).copyWith(
          stage: ScanStage.initializing,
          message: 'Initializing scanner',
        ),
      );

      // Step 2: Load all available IPs once
      _emitProgress(
        ScanProgress.initial(
          totalIPs: 0,
          targetCleanIPs: config.targetCleanIPs,
          minAcceptableIPs: config.minAcceptableIPs,
        ).copyWith(
          stage: ScanStage.loadingIPs,
          message: 'Loading IP addresses',
        ),
      );

      // Load IPs with platform-aware CIDR sampling
      final cidrSamples = _getCIDRSamplesForPlatform();
      _logService.logInfo(
        'Platform: ${Platform.operatingSystem}, CIDR samples: $cidrSamples per range',
      );

      final allIPs = await _ipLoader.loadAllAddresses(
        maxSamplesPerCIDR: cidrSamples,
      );
      _logService.logInfo(
        'Loaded ${allIPs.length} total IP addresses from CIDR ranges',
      );

      // For now, only use IPv4 addresses
      final availableIPs = _ipLoader.filterByType(allIPs, IPType.ipv4);
      _logService.logInfo('Filtered to ${availableIPs.length} IPv4 addresses');

      // Calculate maximum batches based on config
      final maxBatches = (config.maxTotalIPsToTest / config.batchSize).ceil();
      _logService.logInfo(
        'Will test up to $maxBatches batches of ${config.batchSize} IPs each (max ${config.maxTotalIPsToTest} total IPs)',
      );

      // Multi-batch scanning loop
      while (true) {
        currentBatch++;
        _logService.logInfo('=== Starting Batch $currentBatch ===');

        // Check cancellation FIRST
        if (_isCancelled) {
          _logService.logWarn(
            '[WARN] Scan cancelled by user after $currentBatch batches',
          );
          break;
        }

        // Check stopping conditions
        if (allScanResults.length >= config.targetCleanIPs) {
          _logService.logOk(
            'Target reached: ${allScanResults.length}/${config.targetCleanIPs} clean IPs',
          );
          break;
        }

        if (totalIPsTested >= config.maxTotalIPsToTest) {
          _logService.logWarn(
            'Max IP limit reached: $totalIPsTested/${config.maxTotalIPsToTest}',
          );
          break;
        }

        if (currentBatch > maxBatches) {
          _logService.logWarn('Max batch limit reached: $currentBatch');
          break;
        }

        // Select batch of IPs
        final remainingBudget = config.maxTotalIPsToTest - totalIPsTested;
        final batchSize = config.batchSize.clamp(1, remainingBudget);

        final selectedIPs = availableIPs.length > batchSize
            ? _ipLoader.selectRandomIPs(availableIPs, batchSize)
            : availableIPs;

        // Filter out duplicates (IPs already tested in this session)
        final uniqueIPs = _filterDuplicates(selectedIPs);

        if (uniqueIPs.isEmpty) {
          _logService.logWarn(
            'Batch $currentBatch: No unique IPs to test (all already tested)',
          );
          break; // No more unique IPs available
        }

        _logService.logInfo(
          'Batch $currentBatch: Testing ${uniqueIPs.length} unique IPs',
        );

        final batchTotalIPs = uniqueIPs.length;
        var batchProcessedIPs = 0;
        var batchSuccessfulIPs = 0;
        var batchFailedIPs = 0;

        // Step 3: Latency testing for this batch
        _emitProgress(
          ScanProgress(
            totalIPs: batchTotalIPs,
            processedIPs: 0,
            successfulIPs: 0,
            failedIPs: 0,
            currentBatch: currentBatch,
            totalBatchesPlanned: maxBatches,
            targetCleanIPs: config.targetCleanIPs,
            cleanIPsFound: allScanResults.length,
            minAcceptableIPs: config.minAcceptableIPs,
            totalIPsTested: totalIPsTested,
            stage: ScanStage.latencyTesting,
            message: 'Batch $currentBatch: Testing latency',
            timestamp: DateTime.now(),
          ),
        );

        final latencyResults = <String, LatencyResult>{};

        await for (final latencyResult in _latencyTester.testMultiple(
          ips: uniqueIPs,
          port: config.testPort,
          count: config.testCount,
          timeout: Duration(milliseconds: config.latencyLimit),
          maxConcurrent: config.threads,
          isCancelled: () => _isCancelled,
        )) {
          latencyResults[latencyResult.ip] = latencyResult;

          // Track that this IP has been tested in this session
          _testedIPsInSession.add(latencyResult.ip);
          totalIPsTested++;
          batchProcessedIPs++;

          if (latencyResult.isSuccessful) {
            batchSuccessfulIPs++;
          } else {
            batchFailedIPs++;
          }

          _emitProgress(
            ScanProgress(
              totalIPs: batchTotalIPs,
              processedIPs: batchProcessedIPs,
              successfulIPs: batchSuccessfulIPs,
              failedIPs: batchFailedIPs,
              currentIP: latencyResult.ip,
              currentBatch: currentBatch,
              totalBatchesPlanned: maxBatches,
              targetCleanIPs: config.targetCleanIPs,
              cleanIPsFound: allScanResults.length,
              minAcceptableIPs: config.minAcceptableIPs,
              totalIPsTested: totalIPsTested,
              stage: ScanStage.latencyTesting,
              message:
                  'Batch $currentBatch: Latency $batchProcessedIPs/$batchTotalIPs',
              timestamp: DateTime.now(),
            ),
          );
        }

        _logService.logOk(
          'Batch $currentBatch latency: $batchSuccessfulIPs passed, $batchFailedIPs failed',
        );

        // Filter to only successful latency results
        final successfulLatencies = Map.fromEntries(
          latencyResults.entries.where((e) => e.value.isSuccessful),
        );

        if (successfulLatencies.isEmpty) {
          _logService.logWarn(
            'Batch $currentBatch: No IPs passed latency test, trying next batch',
          );
          continue; // Try next batch
        }

        // Step 4: Speed testing (Pareto-based, optional)
        final speedResults = <String, SpeedResult>{};

        if (!config.disableDownload) {
          // Use Pareto principle: test downloads for top 20% batches until target met
          final testResults = await _testDownloadsPareto(
            successfulLatencies: successfulLatencies,
            config: config,
            targetCleanIPs: config.targetCleanIPs,
            currentCleanCount: allScanResults.length,
            currentBatch: currentBatch,
            totalIPsTested: totalIPsTested,
          );
          speedResults.addAll(testResults);
        }

        // Step 5: Build results for this batch
        _emitProgress(
          ScanProgress(
            totalIPs: batchTotalIPs,
            processedIPs: batchProcessedIPs,
            successfulIPs: batchSuccessfulIPs,
            failedIPs: batchFailedIPs,
            currentBatch: currentBatch,
            totalBatchesPlanned: maxBatches,
            targetCleanIPs: config.targetCleanIPs,
            cleanIPsFound: allScanResults.length,
            minAcceptableIPs: config.minAcceptableIPs,
            totalIPsTested: totalIPsTested,
            stage: ScanStage.sorting,
            message: 'Batch $currentBatch: Building results',
            timestamp: DateTime.now(),
          ),
        );

        var batchResults = 0;
        var duplicateCount = 0;
        var skippedNoDownload = 0;
        var skippedFailedDownload = 0;

        // Iterate over IPs that passed latency test
        for (final entry in successfulLatencies.entries) {
          final ip = entry.key;

          // If download testing is enabled, ONLY include IPs with successful downloads
          if (!config.disableDownload) {
            if (!speedResults.containsKey(ip)) {
              skippedNoDownload++;
              continue; // Skip IPs without download test results
            }

            // Skip IPs with failed download tests (0 MB/s)
            if (!speedResults[ip]!.isSuccessful) {
              skippedFailedDownload++;
              continue;
            }
          }

          final scanResult = ScanResult.fromTests(
            ip: ip,
            latencyResult: latencyResults[ip]!,
            speedResult: speedResults[ip],
          );

          // Use _addCleanIP to prevent duplicates in results
          final added = _addCleanIP(ip, scanResult, allScanResults);
          if (added) {
            batchResults++;
          } else {
            duplicateCount++;
          }
        }

        if (skippedNoDownload > 0) {
          _logService.logInfo(
            'Batch $currentBatch: Skipped $skippedNoDownload IPs without download tests',
          );
        }

        if (skippedFailedDownload > 0) {
          _logService.logInfo(
            'Batch $currentBatch: Skipped $skippedFailedDownload IPs with failed downloads',
          );
        }

        if (duplicateCount > 0) {
          _logService.logWarn(
            'Batch $currentBatch: Skipped $duplicateCount duplicate IPs',
          );
        }

        _logService.logOk(
          'Batch $currentBatch complete: Added $batchResults clean IPs (total: ${allScanResults.length}/${config.targetCleanIPs})',
        );

        // Check if we've met our goal
        if (allScanResults.length >= config.targetCleanIPs) {
          _logService.logOk(
            'Target reached after batch $currentBatch: ${allScanResults.length}/${config.targetCleanIPs} clean IPs',
          );
          break;
        }
      }

      // Sort all results by quality
      allScanResults.sort((a, b) => a.compareQuality(b));

      final elapsedTime = DateTime.now().difference(scanStartTime);
      _logService.logOk(
        'Scan complete: ${allScanResults.length} clean IPs found in $currentBatch batches ($totalIPsTested IPs tested, ${elapsedTime.inSeconds}s)',
      );

      // Determine scan status and generate message
      final (status, statusMessage) = _isCancelled
          ? (
              ScanStatus.cancelled,
              'Scan cancelled by user. Found ${allScanResults.length} clean IPs before cancellation (target: ${config.targetCleanIPs}).',
            )
          : determineScanStatus(
              allScanResults.length,
              config.targetCleanIPs,
              config.minAcceptableIPs,
              totalIPsTested,
              config.maxTotalIPsToTest,
            );

      // Log status
      switch (status) {
        case ScanStatus.success:
          _logService.logOk('[OK] $statusMessage');
          break;
        case ScanStatus.partial:
          _logService.logWarn('[WARN] $statusMessage');
          break;
        case ScanStatus.insufficient:
          _logService.logWarn('[WARN] $statusMessage');
          break;
        case ScanStatus.failed:
          _logService.logError('[ERROR] $statusMessage', null, null);
          break;
        case ScanStatus.cancelled:
          _logService.logWarn('[WARN] $statusMessage');
          break;
      }

      // Step 6: Complete
      _emitProgress(
        ScanProgress(
          totalIPs: totalIPsTested,
          processedIPs: totalIPsTested,
          successfulIPs: allScanResults.length,
          failedIPs: totalIPsTested - allScanResults.length,
          currentBatch: currentBatch,
          batchesCompleted: currentBatch,
          totalBatchesPlanned: maxBatches,
          targetCleanIPs: config.targetCleanIPs,
          cleanIPsFound: allScanResults.length,
          minAcceptableIPs: config.minAcceptableIPs,
          totalIPsTested: totalIPsTested,
          elapsedTime: elapsedTime,
          stage: ScanStage.completed,
          message: statusMessage,
          timestamp: DateTime.now(),
        ),
      );

      return DartScanResult(
        results: allScanResults,
        timestamp: DateTime.now(),
        totalTested: totalIPsTested,
        successful: allScanResults.length,
        failed: totalIPsTested - allScanResults.length,
        status: status,
        message: statusMessage,
      );
    } catch (e, stackTrace) {
      _logService.logError('Scan failed', e, stackTrace);

      _emitProgress(
        ScanProgress(
          totalIPs: totalIPsTested,
          processedIPs: totalIPsTested,
          successfulIPs: allScanResults.length,
          failedIPs: totalIPsTested - allScanResults.length,
          currentBatch: currentBatch,
          targetCleanIPs: config.targetCleanIPs,
          cleanIPsFound: allScanResults.length,
          stage: ScanStage.failed,
          message: 'Scan failed: $e',
          timestamp: DateTime.now(),
        ),
      );

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

  /// Get CIDR expansion samples per range based on platform
  int _getCIDRSamplesForPlatform() {
    if (Platform.isAndroid || Platform.isIOS) {
      // Mobile: Sample only 10 IPs per CIDR range
      return 10;
    } else if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      // Desktop: Sample more IPs per range
      return 50;
    }
    // Fallback
    return 10;
  }
}
