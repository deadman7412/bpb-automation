import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/services/xray_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Mock PathProvider for testing
class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('XrayService', () {
    late XrayService xrayService;

    setUp(() {
      xrayService = XrayService.instance;

      // Set up mock path provider
      PathProviderPlatform.instance = MockPathProviderPlatform();
    });

    tearDown(() async {
      // Clean up after each test
      await xrayService.cleanup();
    });

    test('should be a singleton', () {
      final instance1 = XrayService.instance;
      final instance2 = XrayService.instance;
      expect(instance1, same(instance2));
    });

    test('should have correct xray version', () {
      expect(XrayService.xrayVersion, 'v26.3.27');
    });

    test('should have correct binary file name based on platform', () {
      if (Platform.isWindows) {
        expect(xrayService.binaryFileName, 'xray.exe');
      } else {
        expect(xrayService.binaryFileName, 'xray');
      }
    });

    test('should not be initialized by default', () {
      expect(xrayService.isInitialized, false);
      expect(xrayService.binaryPath, null);
    });

    test('cleanup should reset initialization state', () async {
      await xrayService.cleanup();
      expect(xrayService.isInitialized, false);
      expect(xrayService.binaryPath, null);
    });

    // Note: Full initialization test would require mocking rootBundle
    // which is complex in unit tests. Integration tests would be better
    // for testing the full initialization flow.

    test('getBinaryVersion should return null when not initialized', () async {
      await xrayService.cleanup();
      final version = await xrayService.getBinaryVersion();
      expect(version, null);
    });
  });

  group('XrayService Platform Detection', () {
    test('should detect platform correctly', () {
      // Just verify the platform detection logic compiles and runs
      // Actual platform will vary based on test environment
      expect(
        Platform.isAndroid ||
            Platform.isIOS ||
            Platform.isMacOS ||
            Platform.isLinux ||
            Platform.isWindows,
        true,
      );
    });
  });

  group('XrayService Constants', () {
    test('version file name should be correct', () {
      expect(XrayService.versionFileName, '.xray_version');
    });
  });
}
