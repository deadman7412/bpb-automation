import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/scan_result.dart';
import 'package:bpb_automation/models/latency_result.dart';
import 'package:bpb_automation/models/speed_result.dart';

void main() {
  group('ScanResult', () {
    test('should identify acceptable result', () {
      final latency = LatencyResult(
        ip: '1.1.1.1',
        port: 443,
        successCount: 8,
        totalAttempts: 10,
        averageLatencyMs: 100.0,
        minLatencyMs: 90.0,
        maxLatencyMs: 110.0,
        latencies: [90.0, 95.0, 100.0, 105.0, 110.0],
        timestamp: DateTime.now(),
      );

      final result = ScanResult.fromTests(
        ip: '1.1.1.1',
        latencyResult: latency,
      );

      expect(result.isAcceptable(), true);
    });

    test('should identify unacceptable result - high latency', () {
      final latency = LatencyResult(
        ip: '1.1.1.1',
        port: 443,
        successCount: 8,
        totalAttempts: 10,
        averageLatencyMs: 350.0, // Too high
        minLatencyMs: 340.0,
        maxLatencyMs: 360.0,
        latencies: [340.0, 345.0, 350.0, 355.0, 360.0],
        timestamp: DateTime.now(),
      );

      final result = ScanResult.fromTests(
        ip: '1.1.1.1',
        latencyResult: latency,
      );

      expect(result.isAcceptable(), false);
    });

    test('should identify unacceptable result - low success rate', () {
      final latency = LatencyResult(
        ip: '1.1.1.1',
        port: 443,
        successCount: 3, // Only 30% success
        totalAttempts: 10,
        averageLatencyMs: 100.0,
        minLatencyMs: 90.0,
        maxLatencyMs: 110.0,
        latencies: [90.0, 100.0, 110.0],
        timestamp: DateTime.now(),
      );

      final result = ScanResult.fromTests(
        ip: '1.1.1.1',
        latencyResult: latency,
      );

      expect(result.isAcceptable(), false);
    });

    test('should calculate quality score with latency only', () {
      final latency = LatencyResult(
        ip: '1.1.1.1',
        port: 443,
        successCount: 10, // 100% success
        totalAttempts: 10,
        averageLatencyMs: 50.0, // Excellent latency
        minLatencyMs: 45.0,
        maxLatencyMs: 55.0,
        latencies: [45.0, 48.0, 50.0, 52.0, 55.0],
        timestamp: DateTime.now(),
      );

      final result = ScanResult.fromTests(
        ip: '1.1.1.1',
        latencyResult: latency,
      );

      // Should get high score for excellent latency and 100% success
      expect(result.qualityScore, greaterThan(70.0));
    });

    test('should calculate quality score with latency and speed', () {
      final latency = LatencyResult(
        ip: '1.1.1.1',
        port: 443,
        successCount: 10,
        totalAttempts: 10,
        averageLatencyMs: 50.0,
        minLatencyMs: 45.0,
        maxLatencyMs: 55.0,
        latencies: [45.0, 48.0, 50.0, 52.0, 55.0],
        timestamp: DateTime.now(),
      );

      final speed = SpeedResult.success(
        ip: '1.1.1.1',
        testUrl: 'https://speed.cloudflare.com/__down?bytes=1000000',
        bytesDownloaded: 10000000,
        durationSeconds: 1.0, // 80 Mbps
      );

      final result = ScanResult.fromTests(
        ip: '1.1.1.1',
        latencyResult: latency,
        speedResult: speed,
      );

      // Should get very high score with both excellent latency and good speed
      expect(result.qualityScore, greaterThan(80.0));
    });

    test('should compare quality correctly', () {
      final better = ScanResult.fromTests(
        ip: '1.1.1.1',
        latencyResult: LatencyResult(
          ip: '1.1.1.1',
          port: 443,
          successCount: 10,
          totalAttempts: 10,
          averageLatencyMs: 50.0,
          minLatencyMs: 45.0,
          maxLatencyMs: 55.0,
          latencies: [50.0],
          timestamp: DateTime.now(),
        ),
      );

      final worse = ScanResult.fromTests(
        ip: '1.1.1.2',
        latencyResult: LatencyResult(
          ip: '1.1.1.2',
          port: 443,
          successCount: 5,
          totalAttempts: 10,
          averageLatencyMs: 200.0,
          minLatencyMs: 180.0,
          maxLatencyMs: 220.0,
          latencies: [200.0],
          timestamp: DateTime.now(),
        ),
      );

      // better.compareQuality(worse) should return negative (better quality)
      expect(better.compareQuality(worse), lessThan(0));
      // worse.compareQuality(better) should return positive (worse quality)
      expect(worse.compareQuality(better), greaterThan(0));
    });

    test('should convert to CSV row', () {
      final latency = LatencyResult(
        ip: '1.1.1.1',
        port: 443,
        successCount: 8,
        totalAttempts: 10,
        averageLatencyMs: 100.5,
        minLatencyMs: 90.0,
        maxLatencyMs: 110.0,
        latencies: [90.0, 95.0, 100.5, 105.0, 110.0],
        timestamp: DateTime.now(),
      );

      final speed = SpeedResult.success(
        ip: '1.1.1.1',
        testUrl: 'https://speed.cloudflare.com/__down?bytes=1000000',
        bytesDownloaded: 10000000,
        durationSeconds: 1.0,
      );

      final result = ScanResult.fromTests(
        ip: '1.1.1.1',
        latencyResult: latency,
        speedResult: speed,
      );

      final csv = result.toCsvRow();

      // Should contain IP, sent, received, loss%, avg latency, speed
      expect(csv, contains('1.1.1.1'));
      expect(csv, contains('10')); // sent
      expect(csv, contains('8')); // received
      expect(csv, contains('20.0%')); // loss
      expect(csv, contains('100.50')); // latency
    });

    test('should serialize to and from JSON', () {
      final latency = LatencyResult(
        ip: '1.1.1.1',
        port: 443,
        successCount: 8,
        totalAttempts: 10,
        averageLatencyMs: 100.0,
        minLatencyMs: 90.0,
        maxLatencyMs: 110.0,
        latencies: [90.0, 95.0, 100.0, 105.0, 110.0],
        timestamp: DateTime.now(),
      );

      final original = ScanResult.fromTests(
        ip: '1.1.1.1',
        latencyResult: latency,
      );

      final json = original.toJson();
      final restored = ScanResult.fromJson(json);

      expect(restored.ip, original.ip);
      expect(restored.qualityScore, closeTo(original.qualityScore, 0.01));
      expect(restored.latencyResult.ip, original.latencyResult.ip);
      expect(restored.latencyResult.averageLatencyMs,
             original.latencyResult.averageLatencyMs);
    });

    test('should have descriptive toString', () {
      final latency = LatencyResult(
        ip: '1.1.1.1',
        port: 443,
        successCount: 8,
        totalAttempts: 10,
        averageLatencyMs: 100.0,
        minLatencyMs: 90.0,
        maxLatencyMs: 110.0,
        latencies: [90.0, 95.0, 100.0, 105.0, 110.0],
        timestamp: DateTime.now(),
      );

      final result = ScanResult.fromTests(
        ip: '1.1.1.1',
        latencyResult: latency,
      );

      final str = result.toString();
      expect(str, contains('1.1.1.1'));
      expect(str, contains('score:'));
      expect(str, contains('latency:'));
      expect(str, contains('100.00ms'));
    });
  });
}
