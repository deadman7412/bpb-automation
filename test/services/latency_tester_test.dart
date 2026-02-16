import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/services/latency_tester.dart';

void main() {
  group('LatencyTester', () {
    late LatencyTester tester;

    setUp(() {
      tester = LatencyTester();
    });

    test('should test single IP latency', () async {
      // Test against a reliable public server (Cloudflare DNS)
      final result = await tester.testLatency(
        ip: '1.1.1.1',
        port: 53, // DNS port
        count: 3,
        timeout: const Duration(seconds: 5),
      );

      // Should succeed with at least some successful attempts
      expect(result.ip, '1.1.1.1');
      expect(result.port, 53);
      expect(result.totalAttempts, 3);

      // May have some failures due to network conditions, but should have at least 1 success
      // (commented out since CI/testing environments may not have network access)
      // expect(result.successCount, greaterThan(0));
    });

    test('should handle connection timeout', () async {
      // Use an IP that will timeout (TEST-NET-1 from RFC 5737)
      final result = await tester.testLatency(
        ip: '192.0.2.1', // Reserved for documentation
        port: 12345,
        count: 2,
        timeout: const Duration(milliseconds: 100),
      );

      // Should fail with timeout
      expect(result.ip, '192.0.2.1');
      expect(result.isFailure, true);
      expect(result.error, isNotNull);
    });

    test('should calculate statistics correctly', () async {
      // Test with public server
      final result = await tester.testLatency(
        ip: '8.8.8.8', // Google DNS
        port: 53,
        count: 5,
        timeout: const Duration(seconds: 5),
      );

      if (result.isSuccessful) {
        // If any tests succeeded, verify statistics
        expect(result.latencies.length, result.successCount);
        expect(result.averageLatencyMs, greaterThan(0));
        expect(result.minLatencyMs, greaterThan(0));
        expect(result.maxLatencyMs, greaterThan(0));
        expect(result.minLatencyMs, lessThanOrEqualTo(result.averageLatencyMs));
        expect(result.averageLatencyMs, lessThanOrEqualTo(result.maxLatencyMs));
      }
    });

    test('should test multiple IPs concurrently', () async {
      final ips = [
        '1.1.1.1', // Cloudflare
        '8.8.8.8', // Google
        '1.0.0.1', // Cloudflare
      ];

      final results = <String>[];

      await for (final result in tester.testMultiple(
        ips: ips,
        port: 53,
        count: 2,
        timeout: const Duration(seconds: 5),
        maxConcurrent: 2,
      )) {
        results.add(result.ip);
      }

      // Should receive results for all IPs
      expect(results.length, ips.length);
      expect(results.toSet().length, ips.length); // All unique IPs
    });

    test('should test batch and sort results', () async {
      final ips = [
        '1.1.1.1',
        '8.8.8.8',
        '192.0.2.1', // This one will fail
      ];

      final results = await tester.testBatch(
        ips: ips,
        port: 53,
        count: 2,
        timeout: const Duration(seconds: 5),
        maxConcurrent: 2,
      );

      // Should return all results
      expect(results.length, ips.length);

      // Results should be sorted (successful first)
      var lastSuccessful = true;
      for (final result in results) {
        if (!result.isSuccessful && lastSuccessful) {
          lastSuccessful = false;
        } else if (result.isSuccessful && !lastSuccessful) {
          fail('Results not properly sorted - successful result after failed');
        }
      }
    });

    test('should respect max concurrent limit', () async {
      // This test verifies the logic works, but actual concurrency
      // would require more sophisticated testing
      final ips = List.generate(10, (i) => '1.1.1.$i');

      // We can't easily measure actual concurrency without instrumenting the code,
      // but we can verify all IPs are tested
      final results = await tester.testBatch(
        ips: ips,
        port: 53,
        count: 1,
        timeout: const Duration(milliseconds: 100),
        maxConcurrent: 3,
      );

      expect(results.length, ips.length);
    });

    test('should handle all failures gracefully', () async {
      final ips = [
        '192.0.2.1', // Reserved
        '192.0.2.2', // Reserved
        '192.0.2.3', // Reserved
      ];

      final results = await tester.testBatch(
        ips: ips,
        port: 12345,
        count: 1,
        timeout: const Duration(milliseconds: 100),
        maxConcurrent: 2,
      );

      // Should return results for all IPs (all failed)
      expect(results.length, ips.length);
      for (final result in results) {
        expect(result.isFailure, true);
        expect(result.error, isNotNull);
      }
    });
  });
}
