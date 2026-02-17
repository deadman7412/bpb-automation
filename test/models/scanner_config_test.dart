import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/scanner_config.dart';

void main() {
  group('ScannerConfig', () {
    group('Constructor', () {
      test('creates instance with default values', () {
        const config = ScannerConfig();

        expect(config.targetCleanIPs, equals(10));
        expect(config.threads, equals(200));
        expect(config.maxLatency, equals(9999));
        expect(config.maxLossRate, equals(1.0));
        expect(config.minDownloadSpeed, equals(0.0));
        expect(config.testCount, equals(4));
        expect(config.testPort, equals(443));
        expect(config.downloadTestTime, equals(10));
        expect(config.downloadBytes, equals(52428800));
        expect(
          config.testUrl,
          equals('https://speed.cloudflare.com/__down?bytes=52428800'),
        );
        expect(config.httpingMode, isFalse);
        expect(config.maxIPsToTest, equals(10000));
      });

      test('creates instance with custom values', () {
        const config = ScannerConfig(
          targetCleanIPs: 20,
          threads: 300,
          maxLatency: 150,
          maxLossRate: 0.05,
          minDownloadSpeed: 10.0,
          testCount: 5,
        );

        expect(config.targetCleanIPs, equals(20));
        expect(config.threads, equals(300));
        expect(config.maxLatency, equals(150));
        expect(config.maxLossRate, equals(0.05));
        expect(config.minDownloadSpeed, equals(10.0));
        expect(config.testCount, equals(5));
      });
    });

    group('fromJson', () {
      test('creates instance from valid JSON', () {
        final json = {
          'target_clean_ips': 20,
          'threads': 300,
          'max_latency': 150,
          'max_loss_rate': 0.05,
          'min_download_speed': 10.0,
          'test_count': 5,
          'test_port': 8443,
          'download_test_time': 15,
          'download_bytes': 10485760,
          'test_url': 'https://example.com/test',
          'httping_mode': true,
          'max_ips_to_test': 15000,
        };

        final config = ScannerConfig.fromJson(json);

        expect(config.targetCleanIPs, equals(20));
        expect(config.threads, equals(300));
        expect(config.maxLatency, equals(150));
        expect(config.maxLossRate, equals(0.05));
        expect(config.minDownloadSpeed, equals(10.0));
        expect(config.testCount, equals(5));
        expect(config.testPort, equals(8443));
        expect(config.downloadTestTime, equals(15));
        expect(config.downloadBytes, equals(10485760));
        expect(config.testUrl, equals('https://example.com/test'));
        expect(config.httpingMode, isTrue);
        expect(config.maxIPsToTest, equals(15000));
      });

      test('uses defaults for missing fields', () {
        final json = <String, dynamic>{};
        final config = ScannerConfig.fromJson(json);

        expect(config.targetCleanIPs, equals(10));
        expect(config.threads, equals(200));
        expect(config.maxLatency, equals(9999));
        expect(config.maxLossRate, equals(1.0));
        expect(config.minDownloadSpeed, equals(0.0));
      });
    });

    group('toJson', () {
      test('converts instance to JSON correctly', () {
        const config = ScannerConfig(
          targetCleanIPs: 20,
          threads: 300,
          maxLatency: 150,
          maxLossRate: 0.05,
          minDownloadSpeed: 10.0,
        );

        final json = config.toJson();

        expect(json['target_clean_ips'], equals(20));
        expect(json['threads'], equals(300));
        expect(json['max_latency'], equals(150));
        expect(json['max_loss_rate'], equals(0.05));
        expect(json['min_download_speed'], equals(10.0));
      });

      test('round-trip JSON serialization preserves data', () {
        const original = ScannerConfig(
          targetCleanIPs: 15,
          threads: 250,
          maxLatency: 180,
          maxLossRate: 0.15,
          minDownloadSpeed: 8.0,
          testCount: 6,
          httpingMode: true,
        );

        final json = original.toJson();
        final restored = ScannerConfig.fromJson(json);

        expect(restored.targetCleanIPs, equals(original.targetCleanIPs));
        expect(restored.threads, equals(original.threads));
        expect(restored.maxLatency, equals(original.maxLatency));
        expect(restored.maxLossRate, equals(original.maxLossRate));
        expect(restored.minDownloadSpeed, equals(original.minDownloadSpeed));
        expect(restored.testCount, equals(original.testCount));
        expect(restored.httpingMode, equals(original.httpingMode));
      });
    });

    group('Preset Configurations', () {
      test('mobile creates mobile-optimized config', () {
        const config = ScannerConfig.mobile;

        expect(config.targetCleanIPs, equals(5));
        expect(config.threads, equals(100));
        expect(config.maxLatency, equals(300));
        expect(config.maxLossRate, equals(0.2));
        expect(config.minDownloadSpeed, equals(2.0));
        expect(config.maxIPsToTest, equals(5000));
      });

      test('desktop creates desktop-optimized config', () {
        const config = ScannerConfig.desktop;

        expect(config.targetCleanIPs, equals(10));
        expect(config.threads, equals(200));
        expect(config.maxLatency, equals(9999));
        expect(config.maxLossRate, equals(1.0));
        expect(config.minDownloadSpeed, equals(0.0));
        expect(config.maxIPsToTest, equals(10000));
      });
    });

    group('validate', () {
      test('returns null for valid config', () {
        const config = ScannerConfig();
        final error = config.validate();

        expect(error, isNull);
      });

      test('validates targetCleanIPs range', () {
        const config1 = ScannerConfig(targetCleanIPs: 0);
        expect(config1.validate(), isNotNull);
        expect(
          config1.validate(),
          contains('Target clean IPs must be between 1 and 50'),
        );

        const config2 = ScannerConfig(targetCleanIPs: 51);
        expect(config2.validate(), isNotNull);

        const config3 = ScannerConfig(targetCleanIPs: 1);
        expect(config3.validate(), isNull);

        const config4 = ScannerConfig(targetCleanIPs: 50);
        expect(config4.validate(), isNull);
      });

      test('validates threads range', () {
        const config1 = ScannerConfig(threads: 49);
        expect(config1.validate(), isNotNull);
        expect(
          config1.validate(),
          contains('Threads must be between 50 and 500'),
        );

        const config2 = ScannerConfig(threads: 501);
        expect(config2.validate(), isNotNull);

        const config3 = ScannerConfig(threads: 50);
        expect(config3.validate(), isNull);

        const config4 = ScannerConfig(threads: 500);
        expect(config4.validate(), isNull);
      });

      test('validates maxLatency range', () {
        const config1 = ScannerConfig(maxLatency: 49);
        expect(config1.validate(), isNotNull);
        expect(
          config1.validate(),
          contains('Max latency must be between 50 and 9999 ms'),
        );

        const config2 = ScannerConfig(maxLatency: 10000);
        expect(config2.validate(), isNotNull);

        const config3 = ScannerConfig(maxLatency: 50);
        expect(config3.validate(), isNull);

        const config4 = ScannerConfig(maxLatency: 9999);
        expect(config4.validate(), isNull);
      });

      test('validates maxLossRate range', () {
        const config1 = ScannerConfig(maxLossRate: -0.1);
        expect(config1.validate(), isNotNull);
        expect(
          config1.validate(),
          contains('Max loss rate must be between 0.0 and 1.0'),
        );

        const config2 = ScannerConfig(maxLossRate: 1.1);
        expect(config2.validate(), isNotNull);

        const config3 = ScannerConfig(maxLossRate: 0.0);
        expect(config3.validate(), isNull);

        const config4 = ScannerConfig(maxLossRate: 1.0);
        expect(config4.validate(), isNull);
      });

      test('validates minDownloadSpeed range', () {
        const config1 = ScannerConfig(minDownloadSpeed: -1.0);
        expect(config1.validate(), isNotNull);
        expect(
          config1.validate(),
          contains('Min download speed must be between 0 and 100 MB/s'),
        );

        const config2 = ScannerConfig(minDownloadSpeed: 101.0);
        expect(config2.validate(), isNotNull);

        const config3 = ScannerConfig(minDownloadSpeed: 0.0);
        expect(config3.validate(), isNull);

        const config4 = ScannerConfig(minDownloadSpeed: 100.0);
        expect(config4.validate(), isNull);
      });

      test('validates testCount range', () {
        const config1 = ScannerConfig(testCount: 0);
        expect(config1.validate(), isNotNull);
        expect(
          config1.validate(),
          contains('Test count must be between 1 and 10'),
        );

        const config2 = ScannerConfig(testCount: 11);
        expect(config2.validate(), isNotNull);

        const config3 = ScannerConfig(testCount: 1);
        expect(config3.validate(), isNull);

        const config4 = ScannerConfig(testCount: 10);
        expect(config4.validate(), isNull);
      });

      test('validates testPort range', () {
        const config1 = ScannerConfig(testPort: 0);
        expect(config1.validate(), isNotNull);
        expect(
          config1.validate(),
          contains('Test port must be between 1 and 65535'),
        );

        const config2 = ScannerConfig(testPort: 65536);
        expect(config2.validate(), isNotNull);

        const config3 = ScannerConfig(testPort: 1);
        expect(config3.validate(), isNull);

        const config4 = ScannerConfig(testPort: 65535);
        expect(config4.validate(), isNull);
      });

      test('validates downloadTestTime range', () {
        const config1 = ScannerConfig(downloadTestTime: 4);
        expect(config1.validate(), isNotNull);
        expect(
          config1.validate(),
          contains('Download test time must be between 5 and 60 seconds'),
        );

        const config2 = ScannerConfig(downloadTestTime: 61);
        expect(config2.validate(), isNotNull);

        const config3 = ScannerConfig(downloadTestTime: 5);
        expect(config3.validate(), isNull);

        const config4 = ScannerConfig(downloadTestTime: 60);
        expect(config4.validate(), isNull);
      });

      test('validates maxIPsToTest range', () {
        const config1 = ScannerConfig(maxIPsToTest: 999);
        expect(config1.validate(), isNotNull);
        expect(
          config1.validate(),
          contains('Max IPs to test must be between 1000 and 20000'),
        );

        const config2 = ScannerConfig(maxIPsToTest: 20001);
        expect(config2.validate(), isNotNull);

        const config3 = ScannerConfig(maxIPsToTest: 1000);
        expect(config3.validate(), isNull);

        const config4 = ScannerConfig(maxIPsToTest: 20000);
        expect(config4.validate(), isNull);
      });

      test('validates testUrl is not empty', () {
        const config = ScannerConfig(testUrl: '');
        expect(config.validate(), isNotNull);
        expect(config.validate(), contains('Test URL cannot be empty'));
      });
    });

    group('toString', () {
      test('returns formatted string', () {
        const config = ScannerConfig(
          targetCleanIPs: 15,
          threads: 250,
          maxLatency: 180,
          maxLossRate: 0.15,
          minDownloadSpeed: 8.0,
        );

        final str = config.toString();

        expect(str, contains('ScannerConfig'));
        expect(str, contains('15')); // targetCleanIPs
        expect(str, contains('250')); // threads
      });
    });
  });
}
