import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/utils/ewma.dart';

void main() {
  group('EWMA Tests', () {
    test('Initial state', () {
      final ewma = EWMA();
      expect(ewma.isInitialized, false);
      expect(ewma.value, 0.0);
    });

    test('First value becomes initial average', () {
      final ewma = EWMA();
      ewma.add(100.0);

      expect(ewma.isInitialized, true);
      expect(ewma.value, 100.0);
    });

    test('Second value applies exponential weighting', () {
      final ewma = EWMA(0.2); // 20% new, 80% old

      ewma.add(100.0);
      expect(ewma.value, 100.0);

      ewma.add(200.0);
      // Expected: 0.2 * 200 + 0.8 * 100 = 40 + 80 = 120
      expect(ewma.value, 120.0);
    });

    test('Multiple values show smoothing effect', () {
      final ewma = EWMA(0.2);

      ewma.add(100.0);
      expect(ewma.value, 100.0);

      ewma.add(200.0);
      expect(ewma.value, 120.0);

      ewma.add(200.0);
      // Expected: 0.2 * 200 + 0.8 * 120 = 40 + 96 = 136
      expect(ewma.value, 136.0);

      ewma.add(200.0);
      // Expected: 0.2 * 200 + 0.8 * 136 = 40 + 108.8 = 148.8
      expect(ewma.value, closeTo(148.8, 0.01));
    });

    test('EWMA smooths out spikes', () {
      final ewma = EWMA(0.2);

      // Establish baseline
      for (var i = 0; i < 10; i++) {
        ewma.add(100.0);
      }

      final baseline = ewma.value;
      expect(baseline, closeTo(100.0, 0.01));

      // Single spike
      ewma.add(1000.0);

      // EWMA should only move 20% toward the spike
      // New value = 0.2 * 1000 + 0.8 * 100 = 200 + 80 = 280
      expect(ewma.value, closeTo(280.0, 0.01));
      expect(ewma.value, lessThan(500.0)); // Much less than spike value
    });

    test('EWMA favors sustained changes over brief changes', () {
      final ewma = EWMA(0.2);

      // Start at 100
      ewma.add(100.0);

      // Brief spike then back to normal
      ewma.add(200.0);
      ewma.add(100.0);

      final afterSpike = ewma.value;

      // Reset and test sustained change
      ewma.reset();
      ewma.add(100.0);
      ewma.add(200.0);
      ewma.add(200.0);

      final afterSustained = ewma.value;

      // Sustained change should have higher value
      expect(afterSustained, greaterThan(afterSpike));
    });

    test('Reset clears state', () {
      final ewma = EWMA();

      ewma.add(100.0);
      ewma.add(200.0);
      expect(ewma.isInitialized, true);

      ewma.reset();
      expect(ewma.isInitialized, false);
      expect(ewma.value, 0.0);
    });

    test('Custom alpha validation', () {
      expect(() => EWMA(0.0), throwsArgumentError);
      expect(() => EWMA(-0.1), throwsArgumentError);
      expect(() => EWMA(1.1), throwsArgumentError);

      // Valid alphas
      expect(() => EWMA(0.1), returnsNormally);
      expect(() => EWMA(0.5), returnsNormally);
      expect(() => EWMA(1.0), returnsNormally);
    });

    test('Window-based factory', () {
      // Window of 5 means alpha = 2 / (5 + 1) = 2/6 = 0.333...
      final ewma = EWMA.withWindow(5);

      ewma.add(100.0);
      expect(ewma.value, 100.0);

      ewma.add(200.0);
      final expected = (2 / 6) * 200 + (4 / 6) * 100;
      expect(ewma.value, closeTo(expected, 0.01));
    });

    test('Window size validation', () {
      expect(() => EWMA.withWindow(0), throwsArgumentError);
      expect(() => EWMA.withWindow(-1), throwsArgumentError);
      expect(() => EWMA.withWindow(1), returnsNormally);
      expect(() => EWMA.withWindow(100), returnsNormally);
    });

    test('Matching Go scanner behavior - sustained throughput detection', () {
      // Simulate Go scanner's use case:
      // Sample download speed 100 times during a test

      // Scenario 1: Steady fast speed
      final steady = EWMA(0.2);
      for (var i = 0; i < 100; i++) {
        steady.add(1000.0); // 1000 bytes/sample consistently
      }

      // Scenario 2: Fast start but degrading
      final degrading = EWMA(0.2);
      for (var i = 0; i < 50; i++) {
        degrading.add(1000.0);
      }
      for (var i = 0; i < 50; i++) {
        degrading.add(100.0);
      }

      // Steady connection should have higher EWMA
      expect(steady.value, greaterThan(degrading.value));

      // Steady should be close to actual speed
      expect(steady.value, closeTo(1000.0, 1.0));

      // Degrading should be somewhere in between
      expect(degrading.value, greaterThan(100.0));
      expect(degrading.value, lessThan(1000.0));
    });
  });
}
