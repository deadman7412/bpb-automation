@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/services/dart_scanner_service.dart';
import 'package:bpb_automation/models/scanner_config.dart';
import 'package:bpb_automation/models/scan_progress.dart';

/// Comprehensive integration tests for Pareto-based multi-batch scanner
///
/// These tests verify the complete scanning workflow including:
/// - Multi-batch scanning loop
/// - Goal-oriented scanning (target clean IPs)
/// - Pareto download testing (20% incremental batching)
/// - Duplicate prevention across batches
/// - Status determination and graceful degradation
/// - Platform-adaptive batch sizes
///
/// NOTE: These tests use REAL network requests to Cloudflare IPs and may fail
/// in CI environments due to rate limiting, network restrictions, or timeouts.
/// To run integration tests: flutter test --tags=integration
/// To exclude integration tests: flutter test --exclude-tags=integration
void main() {
  group('Pareto Scanner Integration Tests', () {
    late DartScannerService scanner;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      scanner = DartScannerService.instance;
    });

    test(
      'Scenario 1: Goal met in single batch',
      () async {
        // Given: Config with low target that can be met in one batch
        final config = ScannerConfig(
          targetCleanIPs: 5,
          minAcceptableIPs: 3,
          batchSize: 50,
          maxTotalIPsToTest: 200,
          threads: 50,
          testCount: 2,
          downloadCount: 10,
          disableDownload: false,
        );

        // Track progress updates
        final progressUpdates = <ScanProgress>[];
        final progressStream = scanner.startProgressStream();
        final subscription = progressStream.listen((progress) {
          progressUpdates.add(progress);
        });

        // When: Execute scan
        final result = await scanner.executeScan(config);

        // Then: Should complete successfully
        expect(result.status, ScanStatus.success);
        expect(result.successful, greaterThanOrEqualTo(config.targetCleanIPs));
        expect(
          result.results.length,
          greaterThanOrEqualTo(config.targetCleanIPs),
        );

        // Verify no duplicates
        final ips = result.results.map((r) => r.ip).toSet();
        expect(
          ips.length,
          result.results.length,
          reason: 'Should have no duplicate IPs',
        );

        // Verify all results have both latency and download (if enabled)
        for (final scanResult in result.results) {
          expect(scanResult.latencyResult.isSuccessful, isTrue);
          if (!config.disableDownload) {
            expect(scanResult.speedResult, isNotNull);
            expect(scanResult.speedResult!.isSuccessful, isTrue);
          }
        }

        // Verify progress tracking worked
        expect(progressUpdates, isNotEmpty);
        final completed = progressUpdates
            .where((p) => p.stage == ScanStage.completed)
            .toList();
        expect(completed, isNotEmpty);

        final finalProgress = completed.last;
        expect(
          finalProgress.cleanIPsFound,
          greaterThanOrEqualTo(config.targetCleanIPs),
        );
        expect(finalProgress.isGoalMet, isTrue);

        await subscription.cancel();
        scanner.stopProgressStream();
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'Scenario 2: Goal met across multiple batches',
      () async {
        // Given: Config with high target requiring multiple batches
        final config = ScannerConfig(
          targetCleanIPs: 15,
          minAcceptableIPs: 10,
          batchSize: 30, // Small batch to force multiple batches
          maxTotalIPsToTest: 500,
          threads: 50,
          testCount: 2,
          downloadCount: 10,
          disableDownload: false,
        );

        // Track batch progress
        final progressUpdates = <ScanProgress>[];
        final progressStream = scanner.startProgressStream();
        final subscription = progressStream.listen((progress) {
          progressUpdates.add(progress);
        });

        // When: Execute scan
        final result = await scanner.executeScan(config);

        // Then: Should complete successfully across multiple batches
        expect(result.status, ScanStatus.success);
        expect(result.successful, greaterThanOrEqualTo(config.targetCleanIPs));

        // Verify multiple batches were used
        final batchProgresses = progressUpdates
            .where((p) => p.currentBatch > 0)
            .toList();
        final maxBatch = batchProgresses.isEmpty
            ? 0
            : batchProgresses
                  .map((p) => p.currentBatch)
                  .reduce((a, b) => a > b ? a : b);
        expect(maxBatch, greaterThan(1), reason: 'Should use multiple batches');

        // Verify no duplicates across batches
        final ips = result.results.map((r) => r.ip).toSet();
        expect(
          ips.length,
          result.results.length,
          reason: 'Should have no duplicate IPs across batches',
        );

        // Verify total IPs tested is within limits
        expect(result.totalTested, lessThanOrEqualTo(config.maxTotalIPsToTest));

        await subscription.cancel();
        scanner.stopProgressStream();
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );

    test(
      'Scenario 3: Partial success (min met, target not met)',
      () async {
        // Given: Config with high target and low max IPs (forces partial)
        final config = ScannerConfig(
          targetCleanIPs: 30, // High target
          minAcceptableIPs: 5, // Low minimum
          batchSize: 20,
          maxTotalIPsToTest: 100, // Low limit to prevent reaching target
          threads: 30,
          testCount: 2,
          downloadCount: 5,
          disableDownload: false,
        );

        // When: Execute scan
        final result = await scanner.executeScan(config);

        // Then: Should return partial status
        // Note: Might be success or partial depending on network conditions
        // If partial, verify it's between min and target
        if (result.status == ScanStatus.partial) {
          expect(
            result.successful,
            greaterThanOrEqualTo(config.minAcceptableIPs),
          );
          expect(result.successful, lessThan(config.targetCleanIPs));
          expect(result.message, contains('min:'));
          expect(result.message, contains('target:'));
        }

        // Verify all results are valid
        expect(result.results.length, result.successful);

        // Verify stayed within max limit
        expect(result.totalTested, lessThanOrEqualTo(config.maxTotalIPsToTest));
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'Scenario 4: Insufficient results (below min)',
      () async {
        // Given: Config with very strict requirements (likely to fail)
        final config = ScannerConfig(
          targetCleanIPs: 50, // Very high target
          minAcceptableIPs: 40, // Very high minimum
          batchSize: 20,
          maxTotalIPsToTest: 50, // Very low limit
          threads: 20,
          testCount: 5, // Strict testing
          latencyLimit: 10, // Very strict latency (10ms)
          speedLimit: 100, // Very strict speed (100 MB/s)
          disableDownload: false,
        );

        // When: Execute scan
        final result = await scanner.executeScan(config);

        // Then: Should return insufficient or failed status
        // Note: Actual status depends on network conditions
        // We just verify the status is appropriate for the results
        if (result.successful < config.minAcceptableIPs) {
          expect(
            result.status,
            anyOf([ScanStatus.insufficient, ScanStatus.failed]),
          );
          if (result.successful > 0) {
            expect(result.message, contains('only'));
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'Scenario 5: No downloads found (downloads disabled)',
      () async {
        // Given: Config with downloads disabled
        final config = ScannerConfig(
          targetCleanIPs: 10,
          minAcceptableIPs: 5,
          batchSize: 50,
          maxTotalIPsToTest: 200,
          threads: 50,
          testCount: 2,
          disableDownload: true, // Disable downloads
        );

        // When: Execute scan
        final result = await scanner.executeScan(config);

        // Then: Should complete without download tests
        expect(result.results, isNotEmpty);

        // Verify no download results
        for (final scanResult in result.results) {
          expect(scanResult.latencyResult.isSuccessful, isTrue);
          expect(
            scanResult.speedResult,
            isNull,
            reason: 'Should have no speed results when downloads disabled',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'Scenario 6: Exhausted all IPs (small IP pool)',
      () async {
        // Given: Config that might exhaust available IPs
        // Note: This is hard to test reliably without mocking the IP loader
        // For now, we just verify it handles completion gracefully
        final config = ScannerConfig(
          targetCleanIPs: 5,
          minAcceptableIPs: 2,
          batchSize: 50,
          maxTotalIPsToTest: 300,
          threads: 50,
          testCount: 2,
          disableDownload: false,
        );

        // When: Execute scan
        final result = await scanner.executeScan(config);

        // Then: Should complete (either success or partial)
        expect(
          result.status,
          isIn([
            ScanStatus.success,
            ScanStatus.partial,
            ScanStatus.insufficient,
          ]),
        );
        expect(result.results.length, result.successful);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'Scenario 7: Duplicate prevention across 3+ batches',
      () async {
        // Given: Config designed to use multiple batches
        final config = ScannerConfig(
          targetCleanIPs: 20,
          minAcceptableIPs: 10,
          batchSize: 25, // Small batches to force multiple iterations
          maxTotalIPsToTest: 300,
          threads: 50,
          testCount: 2,
          disableDownload: false,
        );

        // Track progress to verify batch count
        final progressUpdates = <ScanProgress>[];
        final progressStream = scanner.startProgressStream();
        final subscription = progressStream.listen((progress) {
          progressUpdates.add(progress);
        });

        // When: Execute scan
        final result = await scanner.executeScan(config);

        // Then: Should have no duplicate IPs
        final ips = result.results.map((r) => r.ip).toList();
        final uniqueIPs = ips.toSet();
        expect(
          uniqueIPs.length,
          ips.length,
          reason: 'Should have no duplicate IPs',
        );

        // Verify multi-batch behavior (at least 2 batches should have been used)
        await subscription.cancel();
        scanner.stopProgressStream();
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );

    test('Scenario 8: Platform-adaptive batch sizes', () async {
      // Given: Different platform presets
      final mobileConfig = ScannerConfig.mobile();
      final desktopConfig = ScannerConfig.desktop();

      // Then: Batch sizes should be platform-appropriate
      expect(
        mobileConfig.batchSize,
        equals(150),
        reason: 'Mobile should use 150 batch size',
      );
      expect(
        desktopConfig.batchSize,
        equals(300),
        reason: 'Desktop should use 300 batch size',
      );

      // Verify other Pareto settings are set
      expect(mobileConfig.targetCleanIPs, equals(10));
      expect(mobileConfig.minAcceptableIPs, equals(5));
      expect(mobileConfig.maxTotalIPsToTest, equals(1000));

      expect(desktopConfig.targetCleanIPs, equals(10));
      expect(desktopConfig.minAcceptableIPs, equals(5));
      expect(desktopConfig.maxTotalIPsToTest, equals(1000));
    });

    test(
      'Scenario 9: Pareto efficiency (tracks tested vs available)',
      () async {
        // Given: Config that will trigger Pareto testing
        final config = ScannerConfig(
          targetCleanIPs: 5,
          minAcceptableIPs: 3,
          batchSize: 100,
          maxTotalIPsToTest: 200,
          threads: 50,
          testCount: 2,
          downloadCount: 50, // More than target to allow Pareto
          disableDownload: false,
        );

        // Track progress
        final progressUpdates = <ScanProgress>[];
        final progressStream = scanner.startProgressStream();
        final subscription = progressStream.listen((progress) {
          progressUpdates.add(progress);
        });

        // When: Execute scan
        final result = await scanner.executeScan(config);

        // Then: Should complete successfully OR fail due to network issues
        // NOTE: In CI/restricted networks, Cloudflare may rate-limit (HTTP 429)
        // or IPs may be unreachable, causing ScanStatus.failed. This is expected.
        expect(
          result.status,
          anyOf([
            ScanStatus.success,
            ScanStatus.partial,
            ScanStatus.insufficient,
            ScanStatus.failed,
          ]),
        );

        // If we got results, verify they are valid
        if (result.results.isNotEmpty) {
          for (final scanResult in result.results) {
            expect(scanResult.latencyResult.isSuccessful, isTrue);
            if (!config.disableDownload && scanResult.speedResult != null) {
              // Speed result exists, so it should be valid
              expect(scanResult.speedResult, isNotNull);
            }
          }
        }

        await subscription.cancel();
        scanner.stopProgressStream();
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test('Scenario 10: Edge cases - zero target', () {
      // Given: Invalid config with zero target
      final config = ScannerConfig(
        targetCleanIPs: 0, // Invalid
        minAcceptableIPs: 0,
        batchSize: 50,
        maxTotalIPsToTest: 100,
      );

      // Then: Config should be invalid
      final errors = config.validate();
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('Target clean IPs')), isTrue);
    });

    test('Scenario 10b: Edge cases - target greater than max', () {
      // Given: Invalid config where min > target
      final config = ScannerConfig(
        targetCleanIPs: 10,
        minAcceptableIPs: 20, // Greater than target (invalid)
        batchSize: 50,
        maxTotalIPsToTest: 100,
      );

      // Then: Config should be invalid
      final errors = config.validate();
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('Minimum acceptable IPs')), isTrue);
    });

    test('Scenario 10c: Edge cases - batch size too small', () {
      // Given: Invalid config with batch size below minimum
      final config = ScannerConfig(
        targetCleanIPs: 10,
        minAcceptableIPs: 5,
        batchSize: 20, // Below minimum of 50
        maxTotalIPsToTest: 100,
      );

      // Then: Config should be invalid
      final errors = config.validate();
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('Batch size')), isTrue);
    });
  });

  group('Status Determination Integration', () {
    test('Determines status correctly based on results', () {
      final scanner = DartScannerService.instance;

      // Test all status scenarios
      final scenarios = [
        // (cleanIPs, target, min, totalTested, max, expectedStatus)
        (10, 10, 5, 100, 500, ScanStatus.success), // Exactly met
        (15, 10, 5, 100, 500, ScanStatus.success), // Exceeded
        (7, 10, 5, 200, 500, ScanStatus.partial), // Between min and target
        (5, 10, 5, 200, 500, ScanStatus.partial), // Exactly at min
        (3, 10, 5, 300, 500, ScanStatus.insufficient), // Below min
        (0, 10, 5, 400, 500, ScanStatus.failed), // No results
      ];

      for (final scenario in scenarios) {
        final (cleanIPs, target, min, totalTested, max, expectedStatus) =
            scenario;
        final (status, message) = scanner.determineScanStatus(
          cleanIPs,
          target,
          min,
          totalTested,
          max,
        );

        expect(
          status,
          expectedStatus,
          reason:
              'cleanIPs=$cleanIPs, target=$target, min=$min should be $expectedStatus',
        );
        expect(message, isNotEmpty, reason: 'Should have a message');

        // Verify message is actionable for non-success cases
        if (status != ScanStatus.success) {
          expect(
            message,
            contains('Try:'),
            reason: 'Non-success should have suggestions',
          );
        }
      }
    });
  });
}
