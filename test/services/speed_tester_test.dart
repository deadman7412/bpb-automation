import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/services/speed_tester.dart';

void main() {
  group('SpeedTester', () {
    late SpeedTester tester;

    setUp(() {
      tester = SpeedTester();
    });

    test('should test single IP speed', () async {
      // Test with small download (100KB) to keep test fast
      final result = await tester.testSpeed(
        ip: '1.1.1.1',
        port: 443,
        downloadBytes: 100000, // 100 KB
        timeout: const Duration(seconds: 10),
      );

      // Note: This test may fail in CI/no-network environments
      // In those cases, result.isFailure will be true
      expect(result.ip, '1.1.1.1');
      expect(result.testUrl, contains('100000'));

      if (result.isSuccessful) {
        expect(result.bytesDownloaded, greaterThan(0));
        expect(result.speedMbps, greaterThan(0));
        expect(result.durationSeconds, greaterThan(0));
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('should handle connection timeout', () async {
      // Use an IP that will timeout
      final result = await tester.testSpeed(
        port: 443,
        ip: '192.0.2.1', // Reserved for documentation
        downloadBytes: 10000,
        timeout: const Duration(milliseconds: 500),
      );

      // Should fail
      expect(result.ip, '192.0.2.1');
      expect(result.isFailure, true);
      expect(result.error, isNotNull);
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('should calculate speed correctly', () async {
      // Test with public Cloudflare server
      final result = await tester.testSpeed(
        port: 443,
        ip: '1.1.1.1',
        downloadBytes: 50000, // 50 KB for fast test
        timeout: const Duration(seconds: 10),
      );

      if (result.isSuccessful) {
        // Verify speed calculation
        final expectedSpeedMbps =
            (result.bytesDownloaded * 8) / (result.durationSeconds * 1000000);
        expect(result.speedMbps, closeTo(expectedSpeedMbps, 0.01));

        // Verify unit conversions
        expect(result.speedKbps, closeTo(result.speedMbps * 1024, 0.01));
        expect(result.speedMBps, closeTo(result.speedMbps / 8, 0.01));
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('should test multiple IPs concurrently', () async {
      final ips = [
        '1.1.1.1',
        '8.8.8.8',
      ];

      final results = <String>[];

      await for (final result in tester.testMultiple(
        port: 443,
        ips: ips,
        downloadBytes: 50000, // Small download
        timeout: const Duration(seconds: 10),
        maxConcurrent: 2,
      )) {
        results.add(result.ip);
      }

      // Should receive results for all IPs
      expect(results.length, ips.length);
      expect(results.toSet().length, ips.length); // All unique
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('should test batch and sort by speed', () async {
      final ips = [
        '1.1.1.1',
        '8.8.8.8',
        '192.0.2.1', // Will fail
      ];

      final results = await tester.testBatch(
        port: 443,
        ips: ips,
        downloadBytes: 50000,
        timeout: const Duration(seconds: 10),
        maxConcurrent: 2,
      );

      // Should return all results
      expect(results.length, ips.length);

      // Results should be sorted (successful first, then by speed)
      var lastSuccessful = true;
      double? lastSpeed;

      for (final result in results) {
        if (!result.isSuccessful && lastSuccessful) {
          lastSuccessful = false;
          lastSpeed = null;
        } else if (result.isSuccessful) {
          if (!lastSuccessful) {
            fail('Results not sorted - successful after failed');
          }
          if (lastSpeed != null && result.speedMbps > lastSpeed) {
            fail('Results not sorted by speed - slower before faster');
          }
          lastSpeed = result.speedMbps;
        }
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('should handle all failures gracefully', () async {
      final ips = [
        '192.0.2.1',
        '192.0.2.2',
        '192.0.2.3',
      ];

      final results = await tester.testBatch(
        port: 443,
        ips: ips,
        downloadBytes: 10000,
        timeout: const Duration(milliseconds: 500),
        maxConcurrent: 2,
      );

      // Should return all results (all failed)
      expect(results.length, ips.length);
      for (final result in results) {
        expect(result.isFailure, true);
        expect(result.error, isNotNull);
      }
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('should use custom test URL', () async {
      final result = await tester.testSpeed(
        port: 443,
        ip: '1.1.1.1',
        testUrl: 'https://speed.cloudflare.com/__down?bytes=',
        downloadBytes: 25000,
        timeout: const Duration(seconds: 10),
      );

      expect(result.testUrl, contains('25000'));
      expect(result.testUrl, contains('cloudflare'));
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
