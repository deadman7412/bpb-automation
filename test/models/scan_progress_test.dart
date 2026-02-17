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

    group('Batch tracking', () {
      test('should track current batch correctly', () {
        final progress = ScanProgress(
          totalIPs: 150,
          processedIPs: 50,
          successfulIPs: 40,
          failedIPs: 10,
          stage: ScanStage.latencyTesting,
          timestamp: DateTime.now(),
          currentBatch: 2,
          totalBatchesPlanned: 5,
          batchesCompleted: 1,
        );

        expect(progress.currentBatch, 2);
        expect(progress.totalBatchesPlanned, 5);
        expect(progress.batchesCompleted, 1);
        expect(progress.batchProgress, 0.2); // 1/5
        expect(progress.batchProgressPercent, 20.0);
      });

      test('should handle zero batches planned', () {
        final progress = ScanProgress(
          totalIPs: 100,
          processedIPs: 50,
          successfulIPs: 40,
          failedIPs: 10,
          stage: ScanStage.latencyTesting,
          timestamp: DateTime.now(),
          totalBatchesPlanned: 0,
        );

        expect(progress.batchProgress, 0.0);
        expect(progress.batchProgressPercent, 0.0);
      });

      test('should copy with batch updates', () {
        final original = ScanProgress.initial(totalIPs: 100);

        final updated = original.copyWith(
          currentBatch: 3,
          totalBatchesPlanned: 10,
          batchesCompleted: 2,
        );

        expect(updated.currentBatch, 3);
        expect(updated.totalBatchesPlanned, 10);
        expect(updated.batchesCompleted, 2);
      });
    });

    group('Goal tracking', () {
      test('should track clean IP goals correctly', () {
        final progress = ScanProgress(
          totalIPs: 150,
          processedIPs: 100,
          successfulIPs: 80,
          failedIPs: 20,
          stage: ScanStage.speedTesting,
          timestamp: DateTime.now(),
          targetCleanIPs: 10,
          cleanIPsFound: 7,
          minAcceptableIPs: 5,
        );

        expect(progress.targetCleanIPs, 10);
        expect(progress.cleanIPsFound, 7);
        expect(progress.minAcceptableIPs, 5);
        expect(progress.goalProgress, 0.7); // 7/10
        expect(progress.goalProgressPercent, 70.0);
        expect(progress.isGoalMet, false);
        expect(progress.isMinAcceptableMet, true);
      });

      test('should detect goal met', () {
        final progress = ScanProgress(
          totalIPs: 150,
          processedIPs: 100,
          successfulIPs: 80,
          failedIPs: 20,
          stage: ScanStage.speedTesting,
          timestamp: DateTime.now(),
          targetCleanIPs: 10,
          cleanIPsFound: 10,
          minAcceptableIPs: 5,
        );

        expect(progress.isGoalMet, true);
        expect(progress.isMinAcceptableMet, true);
        expect(progress.goalProgress, 1.0);
        expect(progress.goalProgressPercent, 100.0);
      });

      test('should detect goal exceeded', () {
        final progress = ScanProgress(
          totalIPs: 150,
          processedIPs: 100,
          successfulIPs: 80,
          failedIPs: 20,
          stage: ScanStage.speedTesting,
          timestamp: DateTime.now(),
          targetCleanIPs: 10,
          cleanIPsFound: 15,
          minAcceptableIPs: 5,
        );

        expect(progress.isGoalMet, true);
        expect(progress.goalProgress, 1.5);
        expect(progress.goalProgressPercent, 150.0);
      });

      test('should handle zero target clean IPs', () {
        final progress = ScanProgress(
          totalIPs: 100,
          processedIPs: 50,
          successfulIPs: 40,
          failedIPs: 10,
          stage: ScanStage.latencyTesting,
          timestamp: DateTime.now(),
          targetCleanIPs: 0,
          cleanIPsFound: 0,
        );

        expect(progress.goalProgress, 0.0);
        expect(progress.goalProgressPercent, 0.0);
      });

      test('should copy with goal updates', () {
        final original = ScanProgress.initial(totalIPs: 100);

        final updated = original.copyWith(
          targetCleanIPs: 20,
          cleanIPsFound: 12,
          minAcceptableIPs: 8,
        );

        expect(updated.targetCleanIPs, 20);
        expect(updated.cleanIPsFound, 12);
        expect(updated.minAcceptableIPs, 8);
      });
    });

    group('Efficiency metrics', () {
      test('should calculate efficiency from totalIPsTested', () {
        final progress = ScanProgress(
          totalIPs: 150,
          processedIPs: 100,
          successfulIPs: 80,
          failedIPs: 20,
          stage: ScanStage.speedTesting,
          timestamp: DateTime.now(),
          cleanIPsFound: 8,
          totalIPsTested: 50,
        );

        expect(progress.totalIPsTested, 50);
        expect(progress.efficiency, 0.16); // 8/50
        expect(progress.efficiencyPercent, 16.0);
      });

      test('should use testEfficiency if provided', () {
        final progress = ScanProgress(
          totalIPs: 150,
          processedIPs: 100,
          successfulIPs: 80,
          failedIPs: 20,
          stage: ScanStage.speedTesting,
          timestamp: DateTime.now(),
          cleanIPsFound: 8,
          totalIPsTested: 50,
          testEfficiency: 0.25,
        );

        expect(progress.efficiency, 0.25);
        expect(progress.efficiencyPercent, 25.0);
      });

      test('should handle zero totalIPsTested', () {
        final progress = ScanProgress(
          totalIPs: 100,
          processedIPs: 50,
          successfulIPs: 40,
          failedIPs: 10,
          stage: ScanStage.latencyTesting,
          timestamp: DateTime.now(),
          cleanIPsFound: 5,
          totalIPsTested: 0,
        );

        expect(progress.efficiency, 0.0);
        expect(progress.efficiencyPercent, 0.0);
      });

      test('should track elapsed time', () {
        final elapsed = Duration(minutes: 5, seconds: 30);
        final progress = ScanProgress(
          totalIPs: 100,
          processedIPs: 50,
          successfulIPs: 40,
          failedIPs: 10,
          stage: ScanStage.latencyTesting,
          timestamp: DateTime.now(),
          elapsedTime: elapsed,
        );

        expect(progress.elapsedTime, elapsed);
        expect(progress.elapsedTime!.inSeconds, 330);
      });

      test('should copy with efficiency updates', () {
        final original = ScanProgress.initial(totalIPs: 100);

        final updated = original.copyWith(
          totalIPsTested: 75,
          testEfficiency: 0.18,
          elapsedTime: Duration(minutes: 3),
        );

        expect(updated.totalIPsTested, 75);
        expect(updated.testEfficiency, 0.18);
        expect(updated.elapsedTime, Duration(minutes: 3));
      });
    });

    group('Sub-stage tracking', () {
      test('should track sub-stage details', () {
        final progress = ScanProgress(
          totalIPs: 150,
          processedIPs: 50,
          successfulIPs: 40,
          failedIPs: 10,
          stage: ScanStage.speedTesting,
          timestamp: DateTime.now(),
          subStage: 'Testing top 20% of passing IPs',
        );

        expect(progress.subStage, 'Testing top 20% of passing IPs');
      });

      test('should copy with subStage updates', () {
        final original = ScanProgress.initial(totalIPs: 100);

        final updated = original.copyWith(subStage: 'Loading next batch');

        expect(updated.subStage, 'Loading next batch');
      });
    });

    group('Updated initial factory', () {
      test('should create initial progress with goal parameters', () {
        final progress = ScanProgress.initial(
          totalIPs: 150,
          targetCleanIPs: 20,
          minAcceptableIPs: 10,
          totalBatchesPlanned: 7,
        );

        expect(progress.totalIPs, 150);
        expect(progress.processedIPs, 0);
        expect(progress.successfulIPs, 0);
        expect(progress.failedIPs, 0);
        expect(progress.stage, ScanStage.initializing);
        expect(progress.targetCleanIPs, 20);
        expect(progress.minAcceptableIPs, 10);
        expect(progress.totalBatchesPlanned, 7);
        expect(progress.currentBatch, 1);
        expect(progress.batchesCompleted, 0);
        expect(progress.cleanIPsFound, 0);
        expect(progress.totalIPsTested, 0);
      });

      test('should use default goal parameters', () {
        final progress = ScanProgress.initial(totalIPs: 100);

        expect(progress.targetCleanIPs, 10);
        expect(progress.minAcceptableIPs, 5);
        expect(progress.totalBatchesPlanned, 1);
      });
    });

    group('Updated JSON serialization', () {
      test('should serialize all new fields to JSON', () {
        final original = ScanProgress(
          totalIPs: 150,
          processedIPs: 100,
          successfulIPs: 80,
          failedIPs: 20,
          currentIP: '1.1.1.1',
          stage: ScanStage.speedTesting,
          message: 'Testing downloads',
          timestamp: DateTime(2026, 2, 16, 12, 0, 0),
          currentBatch: 3,
          totalBatchesPlanned: 8,
          batchesCompleted: 2,
          targetCleanIPs: 15,
          cleanIPsFound: 10,
          minAcceptableIPs: 8,
          totalIPsTested: 120,
          testEfficiency: 0.083,
          elapsedTime: Duration(minutes: 5, seconds: 30),
          subStage: 'Testing Pareto batch 2',
        );

        final json = original.toJson();

        expect(json['currentBatch'], 3);
        expect(json['totalBatchesPlanned'], 8);
        expect(json['batchesCompleted'], 2);
        expect(json['targetCleanIPs'], 15);
        expect(json['cleanIPsFound'], 10);
        expect(json['minAcceptableIPs'], 8);
        expect(json['totalIPsTested'], 120);
        expect(json['testEfficiency'], 0.083);
        expect(json['elapsedTime'], 330000); // milliseconds
        expect(json['subStage'], 'Testing Pareto batch 2');
      });

      test('should deserialize all new fields from JSON', () {
        final json = {
          'totalIPs': 150,
          'processedIPs': 100,
          'successfulIPs': 80,
          'failedIPs': 20,
          'currentIP': '1.1.1.1',
          'stage': 'speedTesting',
          'message': 'Testing downloads',
          'timestamp': '2026-02-16T12:00:00.000',
          'currentBatch': 3,
          'totalBatchesPlanned': 8,
          'batchesCompleted': 2,
          'targetCleanIPs': 15,
          'cleanIPsFound': 10,
          'minAcceptableIPs': 8,
          'totalIPsTested': 120,
          'testEfficiency': 0.083,
          'elapsedTime': 330000,
          'subStage': 'Testing Pareto batch 2',
        };

        final restored = ScanProgress.fromJson(json);

        expect(restored.currentBatch, 3);
        expect(restored.totalBatchesPlanned, 8);
        expect(restored.batchesCompleted, 2);
        expect(restored.targetCleanIPs, 15);
        expect(restored.cleanIPsFound, 10);
        expect(restored.minAcceptableIPs, 8);
        expect(restored.totalIPsTested, 120);
        expect(restored.testEfficiency, 0.083);
        expect(restored.elapsedTime, Duration(minutes: 5, seconds: 30));
        expect(restored.subStage, 'Testing Pareto batch 2');
      });

      test('should handle missing new fields in JSON with defaults', () {
        final json = {
          'totalIPs': 100,
          'processedIPs': 50,
          'successfulIPs': 40,
          'failedIPs': 10,
          'stage': 'latencyTesting',
          'timestamp': '2026-02-16T12:00:00.000',
        };

        final restored = ScanProgress.fromJson(json);

        expect(restored.currentBatch, 1);
        expect(restored.totalBatchesPlanned, 1);
        expect(restored.batchesCompleted, 0);
        expect(restored.targetCleanIPs, 10);
        expect(restored.cleanIPsFound, 0);
        expect(restored.minAcceptableIPs, 5);
        expect(restored.totalIPsTested, 0);
        expect(restored.testEfficiency, null);
        expect(restored.elapsedTime, null);
        expect(restored.subStage, null);
      });

      test('should round-trip serialize all fields', () {
        final original = ScanProgress(
          totalIPs: 150,
          processedIPs: 100,
          successfulIPs: 80,
          failedIPs: 20,
          currentIP: '1.1.1.1',
          stage: ScanStage.speedTesting,
          message: 'Testing',
          timestamp: DateTime(2026, 2, 16, 12, 0, 0),
          currentBatch: 3,
          totalBatchesPlanned: 8,
          batchesCompleted: 2,
          targetCleanIPs: 15,
          cleanIPsFound: 10,
          minAcceptableIPs: 8,
          totalIPsTested: 120,
          testEfficiency: 0.083,
          elapsedTime: Duration(minutes: 5, seconds: 30),
          subStage: 'Testing batch',
        );

        final json = original.toJson();
        final restored = ScanProgress.fromJson(json);

        expect(restored.currentBatch, original.currentBatch);
        expect(restored.totalBatchesPlanned, original.totalBatchesPlanned);
        expect(restored.batchesCompleted, original.batchesCompleted);
        expect(restored.targetCleanIPs, original.targetCleanIPs);
        expect(restored.cleanIPsFound, original.cleanIPsFound);
        expect(restored.minAcceptableIPs, original.minAcceptableIPs);
        expect(restored.totalIPsTested, original.totalIPsTested);
        expect(restored.testEfficiency, original.testEfficiency);
        expect(restored.elapsedTime, original.elapsedTime);
        expect(restored.subStage, original.subStage);
      });
    });

    group('Updated toString', () {
      test('should include batch and goal info in toString', () {
        final progress = ScanProgress(
          totalIPs: 150,
          processedIPs: 100,
          successfulIPs: 80,
          failedIPs: 20,
          stage: ScanStage.speedTesting,
          timestamp: DateTime.now(),
          currentBatch: 3,
          totalBatchesPlanned: 8,
          targetCleanIPs: 15,
          cleanIPsFound: 10,
          totalIPsTested: 120,
        );

        final str = progress.toString();
        expect(str, contains('batch: 3/8'));
        expect(str, contains('clean IPs: 10/15'));
        expect(str, contains('efficiency'));
      });
    });
  });
}
