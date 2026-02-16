import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/latency_result.dart';

void main() {
  group('LatencyResult', () {
    test('should calculate success rate correctly', () {
      final result = LatencyResult(
        ip: '1.1.1.1',
        port: 443,
        successCount: 8,
        totalAttempts: 10,
        averageLatencyMs: 50.0,
        minLatencyMs: 45.0,
        maxLatencyMs: 55.0,
        latencies: [45.0, 48.0, 50.0, 52.0, 55.0, 47.0, 49.0, 51.0],
        timestamp: DateTime.now(),
      );

      expect(result.successRate, 0.8);
      expect(result.successRatePercent, 80.0);
    });

    test('should identify successful result', () {
      final result = LatencyResult(
        ip: '1.1.1.1',
        port: 443,
        successCount: 5,
        totalAttempts: 10,
        averageLatencyMs: 50.0,
        minLatencyMs: 45.0,
        maxLatencyMs: 55.0,
        latencies: [45.0, 48.0, 50.0, 52.0, 55.0],
        timestamp: DateTime.now(),
      );

      expect(result.isSuccessful, true);
      expect(result.isFailure, false);
    });

    test('should identify failed result', () {
      final result = LatencyResult(
        ip: '1.1.1.1',
        port: 443,
        successCount: 0,
        totalAttempts: 10,
        averageLatencyMs: 0,
        minLatencyMs: 0,
        maxLatencyMs: 0,
        latencies: [],
        timestamp: DateTime.now(),
        error: 'Connection timeout',
      );

      expect(result.isSuccessful, false);
      expect(result.isFailure, true);
    });

    test('should create failed result with factory', () {
      final result = LatencyResult.failed(
        ip: '1.1.1.1',
        port: 443,
        totalAttempts: 10,
        error: 'Network error',
      );

      expect(result.ip, '1.1.1.1');
      expect(result.port, 443);
      expect(result.successCount, 0);
      expect(result.totalAttempts, 10);
      expect(result.error, 'Network error');
      expect(result.isFailure, true);
    });

    test('should serialize to and from JSON', () {
      final original = LatencyResult(
        ip: '1.1.1.1',
        port: 443,
        successCount: 8,
        totalAttempts: 10,
        averageLatencyMs: 50.5,
        minLatencyMs: 45.2,
        maxLatencyMs: 55.8,
        latencies: [45.2, 48.0, 50.5, 52.0, 55.8],
        timestamp: DateTime(2025, 1, 1, 12, 0, 0),
      );

      final json = original.toJson();
      final restored = LatencyResult.fromJson(json);

      expect(restored.ip, original.ip);
      expect(restored.port, original.port);
      expect(restored.successCount, original.successCount);
      expect(restored.totalAttempts, original.totalAttempts);
      expect(restored.averageLatencyMs, original.averageLatencyMs);
      expect(restored.minLatencyMs, original.minLatencyMs);
      expect(restored.maxLatencyMs, original.maxLatencyMs);
      expect(restored.latencies, original.latencies);
      expect(restored.error, original.error);
    });

    test('should handle zero total attempts', () {
      final result = LatencyResult(
        ip: '1.1.1.1',
        port: 443,
        successCount: 0,
        totalAttempts: 0,
        averageLatencyMs: 0,
        minLatencyMs: 0,
        maxLatencyMs: 0,
        latencies: [],
        timestamp: DateTime.now(),
      );

      expect(result.successRate, 0.0);
      expect(result.successRatePercent, 0.0);
    });

    test('should have descriptive toString', () {
      final result = LatencyResult(
        ip: '1.1.1.1',
        port: 443,
        successCount: 8,
        totalAttempts: 10,
        averageLatencyMs: 50.5,
        minLatencyMs: 45.0,
        maxLatencyMs: 55.0,
        latencies: [45.0, 48.0, 50.5, 52.0, 55.0],
        timestamp: DateTime.now(),
      );

      final str = result.toString();
      expect(str, contains('1.1.1.1'));
      expect(str, contains('443'));
      expect(str, contains('50.50ms'));
      expect(str, contains('80.0%'));
    });
  });
}
