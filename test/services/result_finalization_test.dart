import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/services/dart_scanner_service.dart';

void main() {
  group('ScanStatus Determination', () {
    late DartScannerService service;

    setUp(() {
      service = DartScannerService.instance;
    });

    test('should return success when target is met', () {
      final (status, message) = service.determineScanStatus(
        10, // cleanIPsFound
        10, // targetCleanIPs
        5, // minAcceptableIPs
        150, // totalIPsTested
        1000, // maxTotalIPsToTest
        750, // totalIPsAvailable
      );

      expect(status, ScanStatus.success);
      expect(message, contains('Found 10 clean IPs'));
      expect(message, contains('target: 10'));
      expect(message, contains('successfully'));
    });

    test('should return success when target is exceeded', () {
      final (status, message) = service.determineScanStatus(
        15, // cleanIPsFound (exceeded target)
        10, // targetCleanIPs
        5, // minAcceptableIPs
        150, // totalIPsTested
        1000, // maxTotalIPsToTest
        750, // totalIPsAvailable
      );

      expect(status, ScanStatus.success);
      expect(message, contains('Found 15 clean IPs'));
      expect(message, contains('target: 10'));
      expect(message, contains('successfully'));
    });

    test('should return partial when min acceptable met but not target', () {
      final (status, message) = service.determineScanStatus(
        7, // cleanIPsFound (between min and target)
        10, // targetCleanIPs
        5, // minAcceptableIPs
        300, // totalIPsTested
        1000, // maxTotalIPsToTest
        750, // totalIPsAvailable
      );

      expect(status, ScanStatus.partial);
      expect(message, contains('Found 7 clean IPs'));
      expect(message, contains('min: 5'));
      expect(message, contains('target: 10'));
      expect(message, contains('Try:'));
      expect(message, contains('Lower target'));
      expect(message, contains('Increase max IPs'));
      expect(message, contains('1500')); // maxTotalIPsToTest + 500
    });

    test('should return partial when exactly at min acceptable', () {
      final (status, message) = service.determineScanStatus(
        5, // cleanIPsFound (exactly at min)
        10, // targetCleanIPs
        5, // minAcceptableIPs
        300, // totalIPsTested
        1000, // maxTotalIPsToTest
        750, // totalIPsAvailable
      );

      expect(status, ScanStatus.partial);
      expect(message, contains('Found 5 clean IPs'));
      expect(message, contains('min: 5'));
      expect(message, contains('target: 10'));
    });

    test('should return insufficient when below min acceptable', () {
      final (status, message) = service.determineScanStatus(
        3, // cleanIPsFound (below min)
        10, // targetCleanIPs
        5, // minAcceptableIPs
        800, // totalIPsTested
        1000, // maxTotalIPsToTest
        1500, // totalIPsAvailable (plenty available, quality issue)
      );

      expect(status, ScanStatus.insufficient);
      expect(message, contains('Found only 3 clean IPs'));
      expect(message, contains('min: 5'));
      expect(message, contains('target: 10'));
      expect(message, contains('Try:'));
      expect(message, contains('Increase max IPs'));
      expect(message, contains('2000')); // maxTotalIPsToTest + 1000
      expect(message, contains('Lower latency threshold'));
      expect(message, contains('Lower speed requirements'));
    });

    test('should return failed when no clean IPs found', () {
      final (status, message) = service.determineScanStatus(
        0, // cleanIPsFound (none)
        10, // targetCleanIPs
        5, // minAcceptableIPs
        500, // totalIPsTested
        1000, // maxTotalIPsToTest
        750, // totalIPsAvailable
      );

      expect(status, ScanStatus.failed);
      expect(message, contains('No clean IPs found'));
      expect(message, contains('testing 500 IPs'));
      expect(message, contains('Try:'));
      expect(message, contains('Check network connection'));
      expect(message, contains('Lower latency/speed requirements'));
      expect(message, contains('Use different IP ranges'));
    });

    test('should handle edge case: 1 clean IP found with high targets', () {
      final (status, message) = service.determineScanStatus(
        1, // cleanIPsFound
        20, // targetCleanIPs
        10, // minAcceptableIPs
        1000, // totalIPsTested
        1000, // maxTotalIPsToTest (hit limit)
        1500, // totalIPsAvailable
      );

      expect(status, ScanStatus.insufficient);
      expect(message, contains('Found only 1 clean IPs'));
      expect(message, contains('min: 10'));
      expect(message, contains('target: 20'));
    });

    test('should provide actionable suggestions in partial status', () {
      final (status, message) = service.determineScanStatus(
        8, // cleanIPsFound
        12, // targetCleanIPs
        6, // minAcceptableIPs
        600, // totalIPsTested
        1000, // maxTotalIPsToTest
        750, // totalIPsAvailable
      );

      expect(status, ScanStatus.partial);
      expect(message, contains('Lower target to 8 IPs'));
      expect(message, contains('Increase max IPs to test from 1000 to 1500'));
      expect(message, contains('Lower requirements'));
    });

    test('should provide actionable suggestions in insufficient status', () {
      final (status, message) = service.determineScanStatus(
        2, // cleanIPsFound
        10, // targetCleanIPs
        5, // minAcceptableIPs
        900, // totalIPsTested
        1000, // maxTotalIPsToTest
        1500, // totalIPsAvailable (plenty available, quality issue)
      );

      expect(status, ScanStatus.insufficient);
      expect(message, contains('Increase max IPs to test from 1000 to 2000'));
      expect(message, contains('Lower latency threshold'));
      expect(message, contains('Lower speed requirements'));
      expect(message, contains('Use different IP ranges'));
    });

    test('should provide network troubleshooting in failed status', () {
      final (status, message) = service.determineScanStatus(
        0, // cleanIPsFound
        10, // targetCleanIPs
        5, // minAcceptableIPs
        300, // totalIPsTested
        1000, // maxTotalIPsToTest
        750, // totalIPsAvailable
      );

      expect(status, ScanStatus.failed);
      expect(message, contains('Check network connection'));
      expect(message, contains('Lower latency/speed requirements'));
      expect(message, contains('Use different IP ranges'));
    });

    test('should detect IP pool exhaustion in partial status', () {
      final (status, message) = service.determineScanStatus(
        7, // cleanIPsFound (meets min but not target)
        15, // targetCleanIPs
        5, // minAcceptableIPs
        145, // totalIPsTested (95% of available)
        1000, // maxTotalIPsToTest
        150, // totalIPsAvailable (small pool - mobile scenario)
      );

      expect(status, ScanStatus.partial);
      expect(message, contains('Found 7 clean IPs'));
      expect(message, contains('target: 15'));
      expect(message, contains('Tested 145 of 150 available IPs'));
      expect(message, contains('Run on desktop for larger IP pool'));
      expect(message, contains('Lower quality requirements'));
    });

    test('should detect IP pool exhaustion in insufficient status', () {
      final (status, message) = service.determineScanStatus(
        4, // cleanIPsFound (below min)
        15, // targetCleanIPs
        5, // minAcceptableIPs
        145, // totalIPsTested (95% of available)
        1000, // maxTotalIPsToTest
        150, // totalIPsAvailable (small pool - mobile scenario)
      );

      expect(status, ScanStatus.insufficient);
      expect(message, contains('Found only 4 clean IPs'));
      expect(message, contains('min: 5'));
      expect(message, contains('Tested 145 of 150 available IPs'));
      expect(message, contains('Run on desktop for larger IP pool'));
      expect(message, contains('Lower latency threshold'));
      expect(message, contains('Disable download test'));
    });

    test('should suggest increasing max IPs when pool not exhausted', () {
      final (status, message) = service.determineScanStatus(
        4, // cleanIPsFound (below min)
        15, // targetCleanIPs
        5, // minAcceptableIPs
        200, // totalIPsTested (only 25% of available)
        1000, // maxTotalIPsToTest
        750, // totalIPsAvailable (plenty available)
      );

      expect(status, ScanStatus.insufficient);
      expect(message, contains('Found only 4 clean IPs'));
      // Should NOT mention IP pool exhaustion
      expect(message.contains('Tested 200 of 750'), isFalse);
      // Should suggest increasing max IPs since plenty are available
      expect(message, contains('Increase max IPs to test from 1000 to 2000'));
    });
  });

  group('ScanStatus Enum', () {
    test('should have all expected status values', () {
      expect(ScanStatus.values.length, 5);
      expect(ScanStatus.values, contains(ScanStatus.success));
      expect(ScanStatus.values, contains(ScanStatus.partial));
      expect(ScanStatus.values, contains(ScanStatus.insufficient));
      expect(ScanStatus.values, contains(ScanStatus.failed));
      expect(ScanStatus.values, contains(ScanStatus.cancelled));
    });
  });

  group('DartScanResult', () {
    test('should include status and message fields', () {
      final result = DartScanResult(
        results: [],
        timestamp: DateTime.now(),
        totalTested: 100,
        successful: 5,
        failed: 95,
        status: ScanStatus.partial,
        message: 'Test message',
      );

      expect(result.status, ScanStatus.partial);
      expect(result.message, 'Test message');
      expect(result.totalTested, 100);
      expect(result.successful, 5);
      expect(result.failed, 95);
    });

    test('should support all status types', () {
      for (final status in ScanStatus.values) {
        final result = DartScanResult(
          results: [],
          timestamp: DateTime.now(),
          totalTested: 0,
          successful: 0,
          failed: 0,
          status: status,
          message: 'Status: ${status.name}',
        );

        expect(result.status, status);
        expect(result.message, contains(status.name));
      }
    });
  });
}
