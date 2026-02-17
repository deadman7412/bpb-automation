import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/speed_result.dart';

void main() {
  group('SpeedResult', () {
    test('should calculate speed correctly in success factory', () {
      final result = SpeedResult.success(
        ip: '1.1.1.1',
        testUrl: 'https://speed.cloudflare.com/__down?bytes=1000000',
        bytesDownloaded: 1000000, // 1 MB
        durationSeconds: 1.0,
      );

      // 1,000,000 bytes * 8 bits / 1,000,000 microseconds = 8 Mbps
      expect(result.speedMbps, closeTo(8.0, 0.01));
      expect(result.isSuccessful, true);
      expect(result.isFailure, false);
    });

    test('should convert speed units correctly', () {
      final result = SpeedResult.success(
        ip: '1.1.1.1',
        testUrl: 'https://speed.cloudflare.com/__down?bytes=1000000',
        bytesDownloaded: 10000000, // 10 MB
        durationSeconds: 1.0,
      );

      // 10 MB in 1 second = 80 Mbps
      expect(result.speedMbps, closeTo(80.0, 0.01));
      // KB/s = Mbps * 1024
      expect(result.speedKbps, closeTo(81920.0, 0.01));
      // MB/s = Mbps / 8
      expect(result.speedMBps, closeTo(10.0, 0.01));
    });

    test('should identify successful result', () {
      final result = SpeedResult.success(
        ip: '1.1.1.1',
        testUrl: 'https://speed.cloudflare.com/__down?bytes=1000000',
        bytesDownloaded: 1000000,
        durationSeconds: 1.0,
      );

      expect(result.isSuccessful, true);
      expect(result.isFailure, false);
    });

    test('should identify failed result', () {
      final result = SpeedResult.failed(
        ip: '1.1.1.1',
        testUrl: 'https://speed.cloudflare.com/__down?bytes=1000000',
        error: 'Connection timeout',
      );

      expect(result.isSuccessful, false);
      expect(result.isFailure, true);
      expect(result.error, 'Connection timeout');
      expect(result.bytesDownloaded, 0);
      expect(result.qualityScore, 0);
    });

    test('should serialize to and from JSON', () {
      final original = SpeedResult.success(
        ip: '1.1.1.1',
        testUrl: 'https://speed.cloudflare.com/__down?bytes=1000000',
        bytesDownloaded: 5000000,
        durationSeconds: 2.5,
      );

      final json = original.toJson();
      final restored = SpeedResult.fromJson(json);

      expect(restored.ip, original.ip);
      expect(restored.testUrl, original.testUrl);
      expect(restored.bytesDownloaded, original.bytesDownloaded);
      expect(
        restored.durationSeconds,
        closeTo(original.durationSeconds, 0.001),
      );
      expect(restored.speedMbps, closeTo(original.speedMbps, 0.001));
      expect(restored.error, original.error);
    });

    test('should handle failed result in JSON', () {
      final original = SpeedResult.failed(
        ip: '1.1.1.1',
        testUrl: 'https://speed.cloudflare.com/__down?bytes=1000000',
        error: 'Network error',
      );

      final json = original.toJson();
      final restored = SpeedResult.fromJson(json);

      expect(restored.ip, original.ip);
      expect(restored.error, 'Network error');
      expect(restored.isFailure, true);
    });

    test('should have descriptive toString for success', () {
      final result = SpeedResult.success(
        ip: '1.1.1.1',
        testUrl: 'https://speed.cloudflare.com/__down?bytes=1000000',
        bytesDownloaded: 10000000,
        durationSeconds: 2.0,
      );

      final str = result.toString();
      expect(str, contains('1.1.1.1'));
      expect(str, contains('Quality'));
      expect(str, contains('10000000 bytes'));
    });

    test('should have descriptive toString for failure', () {
      final result = SpeedResult.failed(
        ip: '1.1.1.1',
        testUrl: 'https://speed.cloudflare.com/__down?bytes=1000000',
        error: 'Timeout',
      );

      final str = result.toString();
      expect(str, contains('1.1.1.1'));
      expect(str, contains('FAILED'));
      expect(str, contains('Timeout'));
    });

    test('should handle zero-duration edge case', () {
      // This shouldn't happen in practice, but testing edge case
      final result = SpeedResult(
        ip: '1.1.1.1',
        testUrl: 'https://speed.cloudflare.com/__down?bytes=1000000',
        bytesDownloaded: 1000000,
        durationSeconds: 0,
        qualityScore: 0,
        timestamp: DateTime.now(),
      );

      expect(result.qualityScore, 0);
      expect(result.speedMbps, double.infinity); // bytes/0 = infinity
      // With bytes downloaded but zero duration, technically successful
      // (edge case that shouldn't happen in practice)
      expect(result.isSuccessful, true);
    });
  });
}
