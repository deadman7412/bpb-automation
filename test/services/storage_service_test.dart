import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bpb_automation/services/storage_service.dart';
import 'package:bpb_automation/models/credentials.dart';
import 'package:bpb_automation/models/scanner_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageService', () {
    late StorageService storage;

    setUp(() async {
      // Initialize SharedPreferences with empty data
      SharedPreferences.setMockInitialValues({});
      storage = StorageService.instance;
      await storage.initialize();
    });

    tearDown(() async {
      // Clean up after each test
      await storage.clearAll();
    });

    group('Initialization', () {
      test('singleton returns same instance', () {
        final instance1 = StorageService.instance;
        final instance2 = StorageService.instance;

        expect(identical(instance1, instance2), isTrue);
      });

      test('isInitialized returns true after initialize()', () async {
        expect(storage.isInitialized, isTrue);
      });
    });

    group('Credentials', () {
      const testCreds = Credentials(
        apiToken: 'test_token_1234567890123456789012',
        accountId: 'test_account_1234567890123456789012',
        kvNamespaceId: 'test_namespace_1234567890123456789012',
      );

      test('saveCredentials and getCredentials work', () async {
        await storage.saveCredentials(testCreds);
        final retrieved = await storage.getCredentials();

        expect(retrieved, isNotNull);
        expect(retrieved!.apiToken, equals(testCreds.apiToken));
        expect(retrieved.accountId, equals(testCreds.accountId));
        expect(retrieved.kvNamespaceId, equals(testCreds.kvNamespaceId));
      });

      test('getCredentials returns null when no credentials saved', () async {
        final retrieved = await storage.getCredentials();
        expect(retrieved, isNull);
      });

      test('clearCredentials removes all credentials', () async {
        await storage.saveCredentials(testCreds);
        await storage.clearCredentials();
        final retrieved = await storage.getCredentials();

        expect(retrieved, isNull);
      });

      test(
        'hasCredentials returns true when valid credentials exist',
        () async {
          await storage.saveCredentials(testCreds);
          final hasCredsResult = await storage.hasCredentials();

          expect(hasCredsResult, isTrue);
        },
      );

      test('hasCredentials returns false when no credentials exist', () async {
        final hasCredsResult = await storage.hasCredentials();
        expect(hasCredsResult, isFalse);
      });

      test('credentials persist across multiple retrievals', () async {
        await storage.saveCredentials(testCreds);

        final retrieved1 = await storage.getCredentials();
        final retrieved2 = await storage.getCredentials();

        expect(retrieved1, equals(testCreds));
        expect(retrieved2, equals(testCreds));
      });
    });

    group('Scanner Config', () {
      const testConfig = ScannerConfig(
        threads: 300,
        testCount: 5,
        maxLatency: 200,
        minDownloadSpeed: 10.0,
      );

      test('saveScannerConfig and getScannerConfig work', () async {
        await storage.saveScannerConfig(testConfig);
        final retrieved = await storage.getScannerConfig();

        expect(retrieved, equals(testConfig));
      });

      test('getScannerConfig uses platform default on first launch', () async {
        // Should return platform-appropriate preset (mobile or desktop)
        final config = await storage.getScannerConfig();

        // Should match either mobile or desktop preset
        expect(
          config == ScannerConfig.mobile || config == ScannerConfig.desktop,
          isTrue,
        );
      });

      test('isFirstTimeConfig returns true when no config saved', () async {
        final isFirstTime = await storage.isFirstTimeConfig();
        expect(isFirstTime, isTrue);
      });

      test('isFirstTimeConfig returns false after config saved', () async {
        const config = ScannerConfig(targetCleanIPs: 15);
        await storage.saveScannerConfig(config);

        final isFirstTime = await storage.isFirstTimeConfig();
        expect(isFirstTime, isFalse);
      });

      test('scanner config persists across multiple retrievals', () async {
        await storage.saveScannerConfig(testConfig);

        final retrieved1 = await storage.getScannerConfig();
        final retrieved2 = await storage.getScannerConfig();

        expect(retrieved1, equals(testConfig));
        expect(retrieved2, equals(testConfig));
      });

      test('overwrites previous config when saving new one', () async {
        const config1 = ScannerConfig(threads: 100);
        const config2 = ScannerConfig(threads: 200);

        await storage.saveScannerConfig(config1);
        await storage.saveScannerConfig(config2);

        final retrieved = await storage.getScannerConfig();
        expect(retrieved.threads, equals(200));
      });
    });

    group('Last Scan Time', () {
      test('saveLastScanTime and getLastScanTime work', () async {
        final now = DateTime.now();
        await storage.saveLastScanTime(now);
        final retrieved = await storage.getLastScanTime();

        expect(retrieved, isNotNull);
        expect(retrieved!.difference(now).inSeconds, lessThan(1));
      });

      test('getLastScanTime returns null when not set', () async {
        final retrieved = await storage.getLastScanTime();
        expect(retrieved, isNull);
      });

      test('preserves exact timestamp', () async {
        final timestamp = DateTime(2026, 2, 15, 14, 30, 45);
        await storage.saveLastScanTime(timestamp);
        final retrieved = await storage.getLastScanTime();

        expect(retrieved, equals(timestamp));
      });
    });

    group('Auto Update Settings', () {
      test('saveAutoUpdateEnabled and getAutoUpdateEnabled work', () async {
        await storage.saveAutoUpdateEnabled(true);
        final retrieved = await storage.getAutoUpdateEnabled();

        expect(retrieved, isTrue);
      });

      test('getAutoUpdateEnabled returns false by default', () async {
        final retrieved = await storage.getAutoUpdateEnabled();
        expect(retrieved, isFalse);
      });

      test('saveAutoUpdateInterval and getAutoUpdateInterval work', () async {
        await storage.saveAutoUpdateInterval(12);
        final retrieved = await storage.getAutoUpdateInterval();

        expect(retrieved, equals(12));
      });

      test('getAutoUpdateInterval returns 24 by default', () async {
        final retrieved = await storage.getAutoUpdateInterval();
        expect(retrieved, equals(24));
      });
    });

    group('Num IPs To Use', () {
      test('saveNumIpsToUse and getNumIpsToUse work', () async {
        await storage.saveNumIpsToUse(10);
        final retrieved = await storage.getNumIpsToUse();

        expect(retrieved, equals(10));
      });

      test('getNumIpsToUse returns 5 by default', () async {
        final retrieved = await storage.getNumIpsToUse();
        expect(retrieved, equals(5));
      });
    });

    group('Generic Preferences', () {
      test('saveString and getString work', () async {
        await storage.saveString('test_key', 'test_value');
        final retrieved = await storage.getString('test_key');

        expect(retrieved, equals('test_value'));
      });

      test('getString returns null for non-existent key', () async {
        final retrieved = await storage.getString('non_existent');
        expect(retrieved, isNull);
      });

      test('saveInt and getInt work', () async {
        await storage.saveInt('test_int', 42);
        final retrieved = await storage.getInt('test_int');

        expect(retrieved, equals(42));
      });

      test('getInt returns null for non-existent key', () async {
        final retrieved = await storage.getInt('non_existent');
        expect(retrieved, isNull);
      });

      test('saveBool and getBool work', () async {
        await storage.saveBool('test_bool', true);
        final retrieved = await storage.getBool('test_bool');

        expect(retrieved, isTrue);
      });

      test('getBool returns null for non-existent key', () async {
        final retrieved = await storage.getBool('non_existent');
        expect(retrieved, isNull);
      });

      test('saveDouble and getDouble work', () async {
        await storage.saveDouble('test_double', 3.14);
        final retrieved = await storage.getDouble('test_double');

        expect(retrieved, equals(3.14));
      });

      test('getDouble returns null for non-existent key', () async {
        final retrieved = await storage.getDouble('non_existent');
        expect(retrieved, isNull);
      });

      test('remove deletes preference', () async {
        await storage.saveString('test_key', 'test_value');
        await storage.remove('test_key');
        final retrieved = await storage.getString('test_key');

        expect(retrieved, isNull);
      });
    });

    group('Clear Operations', () {
      test('clearPreferences removes all preferences', () async {
        await storage.saveScannerConfig(const ScannerConfig(threads: 100));
        await storage.saveString('test_key', 'test_value');
        await storage.saveAutoUpdateEnabled(true);

        await storage.clearPreferences();

        final config = await storage.getScannerConfig();
        final str = await storage.getString('test_key');
        final autoUpdate = await storage.getAutoUpdateEnabled();

        // Should return defaults
        expect(config, equals(const ScannerConfig()));
        expect(str, isNull);
        expect(autoUpdate, isFalse);
      });

      test('clearAll removes credentials and preferences', () async {
        const testCreds = Credentials(
          apiToken: 'test_token_1234567890123456789012',
          accountId: 'test_account_1234567890123456789012',
          kvNamespaceId: 'test_namespace_1234567890123456789012',
        );

        await storage.saveCredentials(testCreds);
        await storage.saveString('test_key', 'test_value');

        await storage.clearAll();

        final creds = await storage.getCredentials();
        final str = await storage.getString('test_key');

        expect(creds, isNull);
        expect(str, isNull);
      });
    });

    group('Edge Cases', () {
      test('handles empty string values', () async {
        await storage.saveString('empty', '');
        final retrieved = await storage.getString('empty');

        expect(retrieved, equals(''));
      });

      test('handles zero values', () async {
        await storage.saveInt('zero', 0);
        final retrieved = await storage.getInt('zero');

        expect(retrieved, equals(0));
      });

      test('handles negative values', () async {
        await storage.saveInt('negative', -42);
        final retrieved = await storage.getInt('negative');

        expect(retrieved, equals(-42));
      });

      test('handles very large numbers', () async {
        await storage.saveInt('large', 999999999);
        final retrieved = await storage.getInt('large');

        expect(retrieved, equals(999999999));
      });

      test('handles special characters in strings', () async {
        const special = 'Test!@#\$%^&*()_+-=[]{}|;:\'",.<>?/`~';
        await storage.saveString('special', special);
        final retrieved = await storage.getString('special');

        expect(retrieved, equals(special));
      });
    });
  });
}
