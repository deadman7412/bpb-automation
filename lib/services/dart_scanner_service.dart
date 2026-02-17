import 'dart:async';
import 'dart:io' show Platform;
import 'package:bpb_automation/models/scan_progress.dart';
import 'package:bpb_automation/models/scan_result.dart';
import 'package:bpb_automation/models/latency_result.dart';
import 'package:bpb_automation/models/scanner_config.dart';
import 'package:bpb_automation/services/ip_loader.dart';
import 'package:bpb_automation/services/latency_tester.dart';
import 'package:bpb_automation/services/speed_tester.dart';
import 'package:bpb_automation/services/log_service.dart';

/// Status of a scan operation
enum ScanStatus {
  /// Target number of clean IPs successfully found
  success,

  /// Partial success - some clean IPs found but below target
  partial,

  /// Insufficient results - very few clean IPs found
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
/// Implements the proven algorithm from the Go scanner:
/// https://github.com/bia-pain-bache/Cloudflare-Clean-IP-Scanner
///
/// Algorithm:
/// 1. Load all IPs (1 random per /24 subnet)
/// 2. Test ALL IPs concurrently for latency (200+ threads, 4 pings each)
/// 3. Sort by [loss rate ASC, latency ASC], filter by criteria
/// 4. Test IPs one-by-one serially for download speed with early exit
/// 5. Sort final results by download speed DESC
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

  // Cancellation flag
  bool _isCancelled = false;

  /// Cancel the current scan
  void cancelScan() {
    _isCancelled = true;
    _logService.logWarn('[WARN] Scan cancellation requested by user');
  }

  /// Execute a complete scan with the given configuration
  ///
  /// Implements multi-round sampling strategy:
  /// - Each round tests ~696 random IPs (or all 5956 if testAllIPs=true)
  /// - Accumulates clean IPs across rounds
  /// - Stops when target is reached (early exit mid-round)
  /// - Maximum 5 rounds before suggesting deep scan
  /// - Skips duplicate IPs across rounds using Set tracker
  ///
  /// Per-round phases:
  /// 1. Load IPs (filter duplicates from previous rounds)
  /// 2. Latency test ALL IPs concurrently
  /// 3. Sort and filter by latency/loss criteria
  /// 4. Download test serially with early exit when round target met
  ///
  /// After all rounds:
  /// 5. Final sort by download speed (fastest first)
  Future<DartScanResult> executeScan(ScannerConfig config) async {
    _logService.logInfo('[INFO] ===== STARTING MULTI-ROUND SCAN =====');
    _logService.logInfo(
      '[INFO] Goal: Find ${config.targetCleanIPs} clean IPs '
      '(max latency: ${config.maxLatency}ms, max loss: ${(config.maxLossRate * 100).toStringAsFixed(0)}%, '
      'min speed: ${config.minDownloadSpeed} MB/s)',
    );
    _logService.logInfo(
      '[INFO] Strategy: Multi-round sampling (max 5 rounds, ~696 IPs per round)',
    );

    _isCancelled = false;
    final scanStartTime = DateTime.now();

    // Track results across all rounds
    final allCleanResults = <ScanResult>[];
    final testedIPs = <String>{};
    var totalIPsTested = 0;
    const maxRounds = 5;

    // Multi-round sampling loop
    for (var round = 1; round <= maxRounds; round++) {
      _logService.logInfo('[INFO] ===== ROUND $round/$maxRounds =====');
      _logService.logInfo(
        '[INFO] Progress: ${allCleanResults.length}/${config.targetCleanIPs} clean IPs found so far',
      );

      if (allCleanResults.length >= config.targetCleanIPs) {
        _logService.logOk(
          '[OK] Target reached! Found ${allCleanResults.length}/${config.targetCleanIPs} clean IPs',
        );
        break;
      }

      final needed = config.targetCleanIPs - allCleanResults.length;
      _logService.logInfo('[INFO] Need $needed more clean IPs to reach target');

      // Execute single round
      final roundResult = await _executeSingleRound(
        config: config,
        roundNumber: round,
        maxRounds: maxRounds,
        testedIPs: testedIPs,
        existingCleanResults: allCleanResults,
      );

      // Check if cancelled
      if (roundResult.status == ScanStatus.cancelled) {
        return roundResult;
      }

      // Accumulate results
      allCleanResults.addAll(roundResult.results);
      totalIPsTested += roundResult.totalTested;

      _logService.logInfo(
        '[INFO] Round $round complete: +${roundResult.successful} clean IPs found, '
        '${allCleanResults.length}/${config.targetCleanIPs} total',
      );

      // Early exit if target reached
      if (allCleanResults.length >= config.targetCleanIPs) {
        _logService.logOk(
          '[OK] TARGET REACHED! Found ${allCleanResults.length}/${config.targetCleanIPs} clean IPs in $round rounds',
        );
        break;
      }

      // Check cancellation between rounds
      if (_isCancelled) {
        return _cancelledResult(totalIPsTested, scanStartTime, allCleanResults);
      }
    }

    // ===== FINAL SORT =====
    _logService.logInfo('[INFO] ===== FINAL SORT (ALL ROUNDS) =====');
    _logService.logInfo(
      '[INFO] Sorting ${allCleanResults.length} clean IPs by download speed',
    );

    // Sort all accumulated results by download speed DESC
    allCleanResults.sort((a, b) {
      final aSpeed = a.speedResult?.speedMBps ?? 0.0;
      final bSpeed = b.speedResult?.speedMBps ?? 0.0;
      return bSpeed.compareTo(aSpeed); // Descending
    });

    // Log top 5 results
    final topResults = allCleanResults.take(5);
    for (var i = 0; i < topResults.length; i++) {
      final result = topResults.elementAt(i);
      _logService.logInfo(
        '[INFO] Top ${i + 1}: ${result.ip} - '
        'speed: ${result.speedResult?.speedMBps.toStringAsFixed(2)} MB/s, '
        'latency: ${result.latencyResult.averageLatencyMs.toStringAsFixed(2)}ms',
      );
    }

    // ===== COMPLETE =====
    final elapsedTime = DateTime.now().difference(scanStartTime);
    final (status, message) = _determineStatus(
      allCleanResults.length,
      config.targetCleanIPs,
      totalIPsTested,
      config.maxIPsToTest,
    );

    _logService.logInfo('[INFO] ===== SCAN COMPLETE =====');
    _logService.logInfo(
      '[INFO] Found ${allCleanResults.length} clean IPs in ${elapsedTime.inSeconds}s '
      '(tested $totalIPsTested total IPs across all rounds)',
    );

    switch (status) {
      case ScanStatus.success:
        _logService.logOk('[OK] $message');
        break;
      case ScanStatus.partial:
        _logService.logWarn('[WARN] $message');
        break;
      case ScanStatus.insufficient:
        _logService.logWarn('[WARN] $message');
        _logService.logInfo(
          '[INFO] After $maxRounds rounds, only ${allCleanResults.length}/${config.targetCleanIPs} clean IPs found. '
          'Consider: (1) Run deep scan (test all 5,956 IPs), (2) Lower quality filters, or (3) Accept current results',
        );
        break;
      case ScanStatus.failed:
        _logService.logError('[ERROR] $message', null, null);
        break;
      case ScanStatus.cancelled:
        _logService.logWarn('[WARN] $message');
        break;
    }

    _emitProgress(
      ScanProgress(
        totalIPs: totalIPsTested,
        processedIPs: totalIPsTested,
        successfulIPs: allCleanResults.length,
        failedIPs: totalIPsTested - allCleanResults.length,
        targetCleanIPs: config.targetCleanIPs,
        cleanIPsFound: allCleanResults.length,
        totalIPsTested: totalIPsTested,
        elapsedTime: elapsedTime,
        stage: ScanStage.completed,
        message: message,
        timestamp: DateTime.now(),
      ),
    );

    return DartScanResult(
      results: allCleanResults,
      timestamp: DateTime.now(),
      totalTested: totalIPsTested,
      successful: allCleanResults.length,
      failed: totalIPsTested - allCleanResults.length,
      status: status,
      message: message,
    );
  }

  /// Execute a single round of IP testing
  ///
  /// Core 4-phase algorithm per round:
  /// Phase 1: Load IPs (filter duplicates from previous rounds)
  /// Phase 2: Latency test ALL IPs concurrently
  /// Phase 3: Sort and filter by latency/loss criteria
  /// Phase 4: Download test serially with early exit when round target met
  ///
  /// Results are NOT sorted here - final sorting happens once after all rounds.
  Future<DartScanResult> _executeSingleRound({
    required ScannerConfig config,
    required int roundNumber,
    required int maxRounds,
    required Set<String> testedIPs,
    required List<ScanResult> existingCleanResults,
  }) async {
    final roundStartTime = DateTime.now();

    try {
      // ===== PHASE 1: LOAD IPS =====
      _emitProgress(
        ScanProgress.initial(
          totalIPs: 0,
          targetCleanIPs: config.targetCleanIPs,
        ).copyWith(
          stage: ScanStage.loadingIPs,
          message:
              'Round $roundNumber/$maxRounds - Phase 1/5: Loading IP addresses',
        ),
      );

      _logService.logInfo('[INFO] ===== PHASE 1: LOADING IPS =====');

      final cidrSamples = config.testAllIPs
          ? 999999
          : _getCIDRSamplesForPlatform();
      _logService.logInfo(
        '[INFO] Platform: ${Platform.operatingSystem}, CIDR samples: ${config.testAllIPs ? "ALL (testAllIPs=true)" : "$cidrSamples per range"}',
      );

      final allIPs = await _ipLoader.loadAllAddresses(
        maxSamplesPerCIDR: cidrSamples,
      );
      _logService.logInfo(
        '[INFO] Loaded ${allIPs.length} total IPs from CIDR ranges',
      );

      // Filter to IPv4 only
      final availableIPs = _ipLoader.filterByType(allIPs, IPType.ipv4);
      _logService.logInfo(
        '[INFO] Filtered to ${availableIPs.length} IPv4 addresses',
      );

      // Remove already-tested IPs from previous rounds (deduplication)
      final newIPs = availableIPs
          .where((ip) => !testedIPs.contains(ip))
          .toList();
      final duplicatesSkipped = availableIPs.length - newIPs.length;

      if (duplicatesSkipped > 0) {
        _logService.logInfo(
          '[INFO] Skipped $duplicatesSkipped duplicate IPs (already tested in previous rounds)',
        );
      }

      _logService.logInfo('[INFO] ${newIPs.length} new IPs to test this round');

      // Apply maxIPsToTest limit
      final ipsToTest = newIPs.length > config.maxIPsToTest
          ? _ipLoader.selectRandomIPs(newIPs, config.maxIPsToTest)
          : newIPs;

      if (ipsToTest.length < newIPs.length) {
        _logService.logInfo(
          '[INFO] Limited to ${ipsToTest.length} IPs (max allowed: ${config.maxIPsToTest})',
        );
      }

      // Add to tested IPs set
      testedIPs.addAll(ipsToTest);

      if (ipsToTest.isEmpty) {
        _logService.logError(
          '[ERROR] No IPs available for testing',
          null,
          null,
        );
        return DartScanResult(
          results: [],
          timestamp: DateTime.now(),
          totalTested: 0,
          successful: 0,
          failed: 0,
          status: ScanStatus.failed,
          message: 'No IP addresses available for testing',
        );
      }

      _logService.logOk(
        '[OK] Phase 1 complete: ${ipsToTest.length} IPs ready for testing',
      );

      // Check cancellation
      if (_isCancelled) {
        return _cancelledResult(0, roundStartTime);
      }

      // ===== PHASE 2: LATENCY TESTING (ALL IPS CONCURRENTLY) =====
      _emitProgress(
        ScanProgress(
          totalIPs: ipsToTest.length,
          processedIPs: 0,
          successfulIPs: 0,
          failedIPs: 0,
          targetCleanIPs: config.targetCleanIPs,
          cleanIPsFound: 0,
          totalIPsTested: 0,
          stage: ScanStage.latencyTesting,
          message:
              'Round $roundNumber/$maxRounds - Phase 2/5: Testing latency for ${ipsToTest.length} IPs',
          timestamp: DateTime.now(),
        ),
      );

      _logService.logInfo('[INFO] ===== PHASE 2: LATENCY TESTING =====');
      _logService.logInfo(
        '[INFO] Testing ${ipsToTest.length} IPs concurrently '
        '(threads: ${config.threads}, pings per IP: ${config.testCount})',
      );

      final latencyResults = <String, LatencyResult>{};
      var processedCount = 0;
      var successCount = 0;
      var failCount = 0;

      await for (final result in _latencyTester.testMultiple(
        ips: ipsToTest,
        port: config.testPort,
        count: config.testCount,
        timeout: Duration(
          milliseconds: config.maxLatency * 2,
        ), // 2x for timeout
        maxConcurrent: config.threads,
        isCancelled: () => _isCancelled,
      )) {
        latencyResults[result.ip] = result;
        processedCount++;

        if (result.isSuccessful) {
          successCount++;
        } else {
          failCount++;
        }

        // Emit progress every 10 IPs or at completion
        if (processedCount % 10 == 0 || processedCount == ipsToTest.length) {
          _emitProgress(
            ScanProgress(
              totalIPs: ipsToTest.length,
              processedIPs: processedCount,
              successfulIPs: successCount,
              failedIPs: failCount,
              currentIP: result.ip,
              targetCleanIPs: config.targetCleanIPs,
              cleanIPsFound: 0,
              totalIPsTested: processedCount,
              stage: ScanStage.latencyTesting,
              message:
                  'Phase 2/5: Latency testing $processedCount/${ipsToTest.length}',
              timestamp: DateTime.now(),
            ),
          );
        }
      }

      _logService.logOk(
        '[OK] Phase 2 complete: $successCount passed, $failCount failed latency test',
      );

      // Check cancellation
      if (_isCancelled) {
        return _cancelledResult(processedCount, roundStartTime);
      }

      // ===== PHASE 3: SORT & FILTER =====
      _emitProgress(
        ScanProgress(
          totalIPs: ipsToTest.length,
          processedIPs: processedCount,
          successfulIPs: successCount,
          failedIPs: failCount,
          targetCleanIPs: config.targetCleanIPs,
          cleanIPsFound: 0,
          totalIPsTested: processedCount,
          stage: ScanStage.sorting,
          message:
              'Round $roundNumber/$maxRounds - Phase 3/5: Filtering and sorting results',
          timestamp: DateTime.now(),
        ),
      );

      _logService.logInfo('[INFO] ===== PHASE 3: SORT & FILTER =====');
      _logService.logInfo(
        '[INFO] Filters: latency <= ${config.maxLatency}ms, loss <= ${(config.maxLossRate * 100).toStringAsFixed(0)}%',
      );

      // Filter by criteria
      final filteredResults = latencyResults.entries.where((entry) {
        final result = entry.value;
        if (!result.isSuccessful) return false;

        final lossRate = 1.0 - result.successRate;
        final meetsLatency = result.averageLatencyMs <= config.maxLatency;
        final meetsLoss = lossRate <= config.maxLossRate;

        return meetsLatency && meetsLoss;
      }).toList();

      _logService.logInfo(
        '[INFO] After filtering: ${filteredResults.length} IPs meet criteria '
        '(${successCount - filteredResults.length} filtered out)',
      );

      if (filteredResults.isEmpty) {
        _logService.logError(
          '[ERROR] No IPs passed latency/loss filters',
          null,
          null,
        );
        return DartScanResult(
          results: [],
          timestamp: DateTime.now(),
          totalTested: processedCount,
          successful: 0,
          failed: processedCount,
          status: ScanStatus.failed,
          message:
              'No IPs passed latency/loss filters. '
              'Try: (1) Increase max latency from ${config.maxLatency}ms, '
              '(2) Increase max loss rate from ${(config.maxLossRate * 100).toStringAsFixed(0)}%',
        );
      }

      // Sort by [loss rate ASC, latency ASC] - CRITICAL: matches Go scanner
      filteredResults.sort((a, b) {
        final aLoss = 1.0 - a.value.successRate;
        final bLoss = 1.0 - b.value.successRate;

        // 1. Lower loss rate wins
        if (aLoss != bLoss) {
          return aLoss.compareTo(bLoss);
        }

        // 2. Lower latency wins
        return a.value.averageLatencyMs.compareTo(b.value.averageLatencyMs);
      });

      _logService.logOk(
        '[OK] Phase 3 complete: ${filteredResults.length} IPs sorted by loss rate and latency',
      );

      // Log top 5 IPs for debugging
      final top5 = filteredResults.take(5);
      for (var i = 0; i < top5.length; i++) {
        final entry = top5.elementAt(i);
        final lossRate = 1.0 - entry.value.successRate;
        _logService.logInfo(
          '[INFO] Top ${i + 1}: ${entry.key} - '
          'loss: ${(lossRate * 100).toStringAsFixed(1)}%, '
          'latency: ${entry.value.averageLatencyMs.toStringAsFixed(2)}ms',
        );
      }

      // Check cancellation
      if (_isCancelled) {
        return _cancelledResult(processedCount, roundStartTime);
      }

      // ===== PHASE 4: DOWNLOAD TESTING (SERIAL WITH EARLY EXIT) =====
      _logService.logInfo('[INFO] ===== PHASE 4: DOWNLOAD TESTING =====');
      _logService.logInfo(
        '[INFO] Testing downloads serially (1 at a time), need ${config.targetCleanIPs - existingCleanResults.length} more clean IPs',
      );
      _logService.logInfo(
        '[INFO] Download config: ${(config.downloadBytes / 1000000).toStringAsFixed(1)} MB, '
        'timeout: ${config.downloadTestTime}s, min speed: ${config.minDownloadSpeed} MB/s',
      );

      final cleanResults = <ScanResult>[];
      var downloadTestCount = 0;
      var downloadSuccessCount = 0;

      // Calculate target for THIS round (overall target - already found)
      final roundTarget = config.targetCleanIPs - existingCleanResults.length;
      final totalSoFar = existingCleanResults.length;

      for (var i = 0; i < filteredResults.length; i++) {
        // Check if we've met our target for THIS ROUND (EARLY EXIT)
        if (cleanResults.length >= roundTarget) {
          _logService.logOk(
            '[OK] Round target reached! Found ${cleanResults.length} new clean IPs this round '
            '(${totalSoFar + cleanResults.length}/${config.targetCleanIPs} total)',
          );
          break;
        }

        // Check cancellation
        if (_isCancelled) {
          return _cancelledResult(processedCount, roundStartTime, cleanResults);
        }

        final entry = filteredResults[i];
        final ip = entry.key;
        final latencyResult = entry.value;

        downloadTestCount++;

        _emitProgress(
          ScanProgress(
            totalIPs: filteredResults.length,
            processedIPs: downloadTestCount,
            successfulIPs: downloadSuccessCount,
            failedIPs: downloadTestCount - downloadSuccessCount,
            currentIP: ip,
            targetCleanIPs: config.targetCleanIPs,
            cleanIPsFound: totalSoFar + cleanResults.length,
            totalIPsTested: processedCount,
            stage: ScanStage.speedTesting,
            subStage:
                'Found ${totalSoFar + cleanResults.length}/${config.targetCleanIPs} total (${cleanResults.length} this round)',
            message:
                'Round $roundNumber/$maxRounds - Phase 4/5: Download testing $downloadTestCount/${filteredResults.length}',
            timestamp: DateTime.now(),
          ),
        );

        // Test download speed (SERIAL - one at a time)
        final speedResult = await _speedTester.testSpeed(
          ip: ip,
          port: config.testPort,
          testUrl: config.testUrl,
          downloadBytes: config.downloadBytes,
          timeout: Duration(seconds: config.downloadTestTime),
          isCancelled: () => _isCancelled,
        );

        // Check if download meets minimum speed requirement
        if (speedResult.isSuccessful) {
          final speedMBps = speedResult.speedMBps;

          if (speedMBps >= config.minDownloadSpeed) {
            downloadSuccessCount++;

            // Create ScanResult with nested latencyResult and speedResult
            final scanResult = ScanResult.fromTests(
              ip: ip,
              latencyResult: latencyResult,
              speedResult: speedResult,
            );

            cleanResults.add(scanResult);

            _logService.logOk(
              '[OK] Clean IP found (${cleanResults.length}/${config.targetCleanIPs}): $ip - '
              'speed: ${speedMBps.toStringAsFixed(2)} MB/s, '
              'latency: ${latencyResult.averageLatencyMs.toStringAsFixed(2)}ms',
            );
          } else {
            _logService.logInfo(
              '[INFO] IP rejected (speed too low): $ip - '
              '${speedMBps.toStringAsFixed(2)} MB/s < ${config.minDownloadSpeed} MB/s',
            );
          }
        } else {
          _logService.logInfo(
            '[INFO] IP rejected (download failed): $ip - ${speedResult.error}',
          );
        }
      }

      _logService.logOk(
        '[OK] Phase 4 complete: Found ${cleanResults.length} clean IPs '
        '(tested $downloadTestCount/${filteredResults.length} IPs for downloads)',
      );

      // Check cancellation
      if (_isCancelled) {
        return _cancelledResult(processedCount, roundStartTime, cleanResults);
      }

      // ===== COMPLETE =====
      final elapsedTime = DateTime.now().difference(roundStartTime);

      _logService.logInfo('[INFO] ===== ROUND $roundNumber COMPLETE =====');
      _logService.logInfo(
        '[INFO] Round stats: +${cleanResults.length} clean IPs found this round, tested $processedCount IPs in ${elapsedTime.inSeconds}s',
      );

      // Return results for this round (will be accumulated and sorted later)
      return DartScanResult(
        results: cleanResults,
        timestamp: DateTime.now(),
        totalTested: processedCount,
        successful: cleanResults.length,
        failed: processedCount - cleanResults.length,
        status: ScanStatus
            .success, // Individual round status (final status determined in main method)
        message:
            'Round $roundNumber complete: found ${cleanResults.length} clean IPs',
      );
    } catch (e, stackTrace) {
      _logService.logError('[ERROR] Scan failed with exception', e, stackTrace);

      _emitProgress(
        ScanProgress(
          totalIPs: 0,
          processedIPs: 0,
          successfulIPs: 0,
          failedIPs: 0,
          targetCleanIPs: config.targetCleanIPs,
          cleanIPsFound: 0,
          totalIPsTested: 0,
          stage: ScanStage.failed,
          message: 'Scan failed: $e',
          timestamp: DateTime.now(),
        ),
      );

      rethrow;
    }
  }

  /// Helper: Create cancelled result
  DartScanResult _cancelledResult(
    int totalTested,
    DateTime startTime, [
    List<ScanResult>? partialResults,
  ]) {
    final results = partialResults ?? [];
    final message =
        'Scan cancelled by user. Found ${results.length} clean IPs before cancellation.';

    _logService.logWarn('[WARN] $message');

    _emitProgress(
      ScanProgress(
        totalIPs: totalTested,
        processedIPs: totalTested,
        successfulIPs: results.length,
        failedIPs: totalTested - results.length,
        targetCleanIPs: 0,
        cleanIPsFound: results.length,
        totalIPsTested: totalTested,
        elapsedTime: DateTime.now().difference(startTime),
        stage: ScanStage.completed,
        message: message,
        timestamp: DateTime.now(),
      ),
    );

    return DartScanResult(
      results: results,
      timestamp: DateTime.now(),
      totalTested: totalTested,
      successful: results.length,
      failed: totalTested - results.length,
      status: ScanStatus.cancelled,
      message: message,
    );
  }

  /// Helper: Determine scan status
  (ScanStatus, String) _determineStatus(
    int found,
    int target,
    int tested,
    int maxAllowed,
  ) {
    if (found == 0) {
      return (
        ScanStatus.failed,
        'No clean IPs found after testing $tested IPs. '
            'Try: (1) Lower quality requirements, (2) Check network connection',
      );
    }

    if (found >= target) {
      return (
        ScanStatus.success,
        'Found $found clean IPs (target: $target). Scan completed successfully.',
      );
    }

    if (tested >= maxAllowed * 0.9) {
      return (
        ScanStatus.partial,
        'Found $found clean IPs (target: $target). '
            'Tested $tested of $maxAllowed allowed IPs. '
            'Try: (1) Increase max IPs to test, (2) Lower quality requirements',
      );
    }

    return (
      ScanStatus.insufficient,
      'Found only $found clean IPs (target: $target). '
          'Try: (1) Lower quality requirements, (2) Run scan again',
    );
  }

  /// Start listening for progress updates
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

  /// Get CIDR expansion samples per range based on platform
  int _getCIDRSamplesForPlatform() {
    if (Platform.isAndroid || Platform.isIOS) {
      return 50; // Mobile: ~750 total IPs with 15 CIDR ranges
    } else if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      return 100; // Desktop: ~1500 total IPs with 15 CIDR ranges
    }
    return 50; // Fallback
  }

  /// Check if the service is available
  bool get isAvailable => true;

  /// Get scanner version
  String get version => '2.0.0-dart-go-algorithm';
}
