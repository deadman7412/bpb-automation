import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/scan_progress.dart';

void main() {
  group('ScanProgress', () {
    test('should calculate progress percentage correctly', () {
      final progress = ScanProgress(
        totalIPs: 100,
        processedIPs: 25,
        successfulIPs: 20,
        failedIPs: 5,
        stage: ScanStage.latencyTesting,
        timestamp: DateTime.now(),
      );

      expect(progress.progress, 0.25);
      expect(progress.progressPercent, 25.0);
    });

    test('should calculate success rate correctly', () {
      final progress = ScanProgress(
        totalIPs: 100,
        processedIPs: 50,
        successfulIPs: 40,
        failedIPs: 10,
        stage: ScanStage.latencyTesting,
        timestamp: DateTime.now(),
      );

      expect(progress.successRate, 0.8);
      expect(progress.successRatePercent, 80.0);
    });

    test('should handle zero total IPs', () {
      final progress = ScanProgress(
        totalIPs: 0,
        processedIPs: 0,
        successfulIPs: 0,
        failedIPs: 0,
        stage: ScanStage.initializing,
        timestamp: DateTime.now(),
      );

      expect(progress.progress, 0.0);
      expect(progress.progressPercent, 0.0);
    });

    test('should handle zero processed IPs', () {
      final progress = ScanProgress(
        totalIPs: 100,
        processedIPs: 0,
        successfulIPs: 0,
        failedIPs: 0,
        stage: ScanStage.loadingIPs,
        timestamp: DateTime.now(),
      );

      expect(progress.successRate, 0.0);
      expect(progress.successRatePercent, 0.0);
    });

    test('should create initial progress', () {
      final progress = ScanProgress.initial(totalIPs: 100);

      expect(progress.totalIPs, 100);
      expect(progress.processedIPs, 0);
      expect(progress.successfulIPs, 0);
      expect(progress.failedIPs, 0);
      expect(progress.stage, ScanStage.initializing);
    });

    test('should copy with updates', () {
      final original = ScanProgress.initial(totalIPs: 100);

      final updated = original.copyWith(
        processedIPs: 25,
        successfulIPs: 20,
        failedIPs: 5,
        stage: ScanStage.latencyTesting,
        currentIP: '1.1.1.1',
        message: 'Testing latency',
      );

      expect(updated.totalIPs, 100); // Unchanged
      expect(updated.processedIPs, 25);
      expect(updated.successfulIPs, 20);
      expect(updated.failedIPs, 5);
      expect(updated.stage, ScanStage.latencyTesting);
      expect(updated.currentIP, '1.1.1.1');
      expect(updated.message, 'Testing latency');
    });

    test('should serialize to and from JSON', () {
      final original = ScanProgress(
        totalIPs: 100,
        processedIPs: 50,
        successfulIPs: 40,
        failedIPs: 10,
        currentIP: '1.1.1.1',
        stage: ScanStage.latencyTesting,
        message: 'Testing',
        timestamp: DateTime(2025, 1, 1, 12, 0, 0),
      );

      final json = original.toJson();
      final restored = ScanProgress.fromJson(json);

      expect(restored.totalIPs, original.totalIPs);
      expect(restored.processedIPs, original.processedIPs);
      expect(restored.successfulIPs, original.successfulIPs);
      expect(restored.failedIPs, original.failedIPs);
      expect(restored.currentIP, original.currentIP);
      expect(restored.stage, original.stage);
      expect(restored.message, original.message);
    });

    test('should have descriptive toString', () {
      final progress = ScanProgress(
        totalIPs: 100,
        processedIPs: 25,
        successfulIPs: 20,
        failedIPs: 5,
        stage: ScanStage.latencyTesting,
        timestamp: DateTime.now(),
      );

      final str = progress.toString();
      expect(str, contains('25.0%'));
      expect(str, contains('25/100'));
      expect(str, contains('success: 20'));
      expect(str, contains('failed: 5'));
      expect(str, contains('latencyTesting'));
    });

    test('should handle all scan stages', () {
      for (final stage in ScanStage.values) {
        final progress = ScanProgress(
          totalIPs: 100,
          processedIPs: 0,
          successfulIPs: 0,
          failedIPs: 0,
          stage: stage,
          timestamp: DateTime.now(),
        );

        expect(progress.stage, stage);
      }
    });
  });
}
