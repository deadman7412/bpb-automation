import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/scanner_config.dart';

void main() {
  group('ScannerConfig', () {
    group('Constructor', () {
      test('creates instance with default values', () {
        const config = ScannerConfig();

        expect(config.threads, equals(200));
        expect(config.testCount, equals(4));
        expect(config.downloadCount, equals(10));
        expect(config.latencyLimit, equals(200));
        expect(config.latencyLowerLimit, equals(40));
        expect(config.speedLimit, equals(5));
        expect(config.testPort, equals(443));
        expect(config.disableDownload, isFalse);
        expect(config.httpingMode, isFalse);
        expect(config.downloadTestTime, equals(10));
      });

      test('creates instance with custom values', () {
        const config = ScannerConfig(
          threads: 100,
          testCount: 5,
          downloadCount: 15,
          latencyLimit: 150,
          speedLimit: 10,
        );

        expect(config.threads, equals(100));
        expect(config.testCount, equals(5));
        expect(config.downloadCount, equals(15));
        expect(config.latencyLimit, equals(150));
        expect(config.speedLimit, equals(10));
      });
    });

    group('fromJson', () {
      test('creates instance from valid JSON', () {
        final json = {
          'threads': 100,
          'test_count': 5,
          'download_count': 15,
          'latency_limit': 150,
          'latency_lower_limit': 30,
          'speed_limit': 10,
          'test_port': 443,
          'test_url': 'https://example.com/test',
          'disable_download': true,
          'httping_mode': true,
          'download_test_time': 15,
        };

        final config = ScannerConfig.fromJson(json);

        expect(config.threads, equals(100));
        expect(config.testCount, equals(5));
        expect(config.downloadCount, equals(15));
        expect(config.latencyLimit, equals(150));
        expect(config.latencyLowerLimit, equals(30));
        expect(config.speedLimit, equals(10));
        expect(config.testPort, equals(443));
        expect(config.testUrl, equals('https://example.com/test'));
        expect(config.disableDownload, isTrue);
        expect(config.httpingMode, isTrue);
        expect(config.downloadTestTime, equals(15));
      });

      test('uses defaults for missing fields', () {
        final json = <String, dynamic>{};
        final config = ScannerConfig.fromJson(json);

        expect(config.threads, equals(200));
        expect(config.testCount, equals(4));
        expect(config.downloadCount, equals(10));
      });
    });

    group('toJson', () {
      test('converts instance to JSON correctly', () {
        const config = ScannerConfig(
          threads: 100,
          testCount: 5,
          speedLimit: 10,
        );

        final json = config.toJson();

        expect(json['threads'], equals(100));
        expect(json['test_count'], equals(5));
        expect(json['speed_limit'], equals(10));
      });

      test('round-trip JSON serialization preserves data', () {
        const original = ScannerConfig(
          threads: 150,
          testCount: 6,
          downloadCount: 12,
          disableDownload: true,
          httpingMode: true,
        );

        final json = original.toJson();
        final restored = ScannerConfig.fromJson(json);

        expect(restored, equals(original));
      });
    });

    group('toCommandLineArgs', () {
      test('generates correct command-line arguments', () {
        const config = ScannerConfig(
          threads: 200,
          testCount: 4,
          downloadCount: 10,
          downloadTestTime: 10,
          testPort: 443,
        );

        final args = config.toCommandLineArgs();

        expect(args, contains('-n'));
        expect(args, contains('200'));
        expect(args, contains('-t'));
        expect(args, contains('4'));
        expect(args, contains('-dn'));
        expect(args, contains('10'));
        expect(args, contains('-dt'));
        expect(args, contains('10'));
        expect(args, contains('-tp'));
        expect(args, contains('443'));
        expect(args, contains('-url'));
      });

      test('includes httping flag when enabled', () {
        const config = ScannerConfig(httpingMode: true);
        final args = config.toCommandLineArgs();

        expect(args, contains('-httping'));
      });

      test('includes disable-download flag when enabled', () {
        const config = ScannerConfig(disableDownload: true);
        final args = config.toCommandLineArgs();

        expect(args, contains('-disable-download'));
      });

      test('excludes optional flags when disabled', () {
        const config = ScannerConfig(
          httpingMode: false,
          disableDownload: false,
        );
        final args = config.toCommandLineArgs();

        expect(args, isNot(contains('-httping')));
        expect(args, isNot(contains('-disable-download')));
      });
    });

    group('Preset Configurations', () {
      test('mobile() creates mobile-optimized config', () {
        final config = ScannerConfig.mobile();

        expect(config.threads, equals(100));
        expect(config.testCount, equals(3));
        expect(config.downloadCount, equals(5));
        expect(config.downloadTestTime, equals(5));
      });

      test('desktop() creates desktop-optimized config', () {
        final config = ScannerConfig.desktop();

        expect(config.threads, equals(300));
        expect(config.testCount, equals(5));
        expect(config.downloadCount, equals(15));
        expect(config.downloadTestTime, equals(15));
      });

      test('fast() creates fast config', () {
        final config = ScannerConfig.fast();

        expect(config.threads, equals(400));
        expect(config.testCount, equals(2));
        expect(config.downloadCount, equals(5));
        expect(config.downloadTestTime, equals(5));
      });

      test('thorough() creates thorough config', () {
        final config = ScannerConfig.thorough();

        expect(config.threads, equals(200));
        expect(config.testCount, equals(10));
        expect(config.downloadCount, equals(20));
        expect(config.downloadTestTime, equals(20));
      });
    });

    group('validate', () {
      test('returns empty list for valid config', () {
        const config = ScannerConfig();
        final errors = config.validate();

        expect(errors, isEmpty);
      });

      test('validates threads range', () {
        const config1 = ScannerConfig(threads: 0);
        expect(config1.validate(), isNotEmpty);

        const config2 = ScannerConfig(threads: 1001);
        expect(config2.validate(), isNotEmpty);

        const config3 = ScannerConfig(threads: 1);
        expect(config3.validate(), isEmpty);

        const config4 = ScannerConfig(threads: 1000);
        expect(config4.validate(), isEmpty);
      });

      test('validates test count range', () {
        const config1 = ScannerConfig(testCount: 0);
        expect(config1.validate(), isNotEmpty);

        const config2 = ScannerConfig(testCount: 11);
        expect(config2.validate(), isNotEmpty);

        const config3 = ScannerConfig(testCount: 1);
        expect(config3.validate(), isEmpty);

        const config4 = ScannerConfig(testCount: 10);
        expect(config4.validate(), isEmpty);
      });

      test('validates latency limits', () {
        const config1 = ScannerConfig(
          latencyLowerLimit: 100,
          latencyLimit: 50,
        );
        expect(
          config1.validate(),
          contains('Latency lower limit must be less than latency limit'),
        );

        const config2 = ScannerConfig(
          latencyLowerLimit: 50,
          latencyLimit: 100,
        );
        expect(config2.validate(), isEmpty);
      });

      test('validates port range', () {
        const config1 = ScannerConfig(testPort: 0);
        expect(config1.validate(), isNotEmpty);

        const config2 = ScannerConfig(testPort: 65536);
        expect(config2.validate(), isNotEmpty);

        const config3 = ScannerConfig(testPort: 1);
        expect(config3.validate(), isEmpty);

        const config4 = ScannerConfig(testPort: 65535);
        expect(config4.validate(), isEmpty);
      });

      test('validates test URL', () {
        const config = ScannerConfig(testUrl: '');
        expect(
          config.validate(),
          contains('Test URL cannot be empty'),
        );
      });

      test('validates download test time', () {
        const config1 = ScannerConfig(downloadTestTime: 0);
        expect(config1.validate(), isNotEmpty);

        const config2 = ScannerConfig(downloadTestTime: 61);
        expect(config2.validate(), isNotEmpty);

        const config3 = ScannerConfig(downloadTestTime: 1);
        expect(config3.validate(), isEmpty);

        const config4 = ScannerConfig(downloadTestTime: 60);
        expect(config4.validate(), isEmpty);
      });
    });

    group('isValid', () {
      test('returns true for valid config', () {
        const config = ScannerConfig();
        expect(config.isValid(), isTrue);
      });

      test('returns false for invalid config', () {
        const config = ScannerConfig(threads: 0);
        expect(config.isValid(), isFalse);
      });
    });

    group('copyWith', () {
      test('creates new instance with updated values', () {
        const original = ScannerConfig(
          threads: 200,
          testCount: 4,
        );

        final updated = original.copyWith(
          threads: 300,
          testCount: 5,
        );

        expect(updated.threads, equals(300));
        expect(updated.testCount, equals(5));
      });

      test('preserves unchanged values', () {
        const original = ScannerConfig(
          threads: 200,
          testCount: 4,
          speedLimit: 10,
        );

        final updated = original.copyWith(threads: 300);

        expect(updated.threads, equals(300));
        expect(updated.testCount, equals(4)); // Preserved
        expect(updated.speedLimit, equals(10)); // Preserved
      });

      test('does not modify original instance', () {
        const original = ScannerConfig(threads: 200);
        original.copyWith(threads: 300);

        expect(original.threads, equals(200));
      });
    });

    group('toString', () {
      test('returns formatted string', () {
        const config = ScannerConfig(
          threads: 200,
          testCount: 4,
          downloadCount: 10,
          latencyLimit: 200,
          speedLimit: 5,
        );

        final str = config.toString();

        expect(str, contains('200')); // threads
        expect(str, contains('4')); // testCount
        expect(str, contains('10')); // downloadCount
        expect(str, contains('200ms')); // latencyLimit
        expect(str, contains('5MB/s')); // speedLimit
      });
    });

    group('Equality', () {
      test('equal instances are equal', () {
        const config1 = ScannerConfig(
          threads: 200,
          testCount: 4,
          speedLimit: 10,
        );

        const config2 = ScannerConfig(
          threads: 200,
          testCount: 4,
          speedLimit: 10,
        );

        expect(config1, equals(config2));
        expect(config1.hashCode, equals(config2.hashCode));
      });

      test('different instances are not equal', () {
        const config1 = ScannerConfig(threads: 200);
        const config2 = ScannerConfig(threads: 300);

        expect(config1, isNot(equals(config2)));
      });
    });
  });
}
