import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/proxy_settings.dart';
import 'package:bpb_automation/models/credentials.dart';

/// Integration test to verify core models work together
///
/// Note: This test validates the most commonly used models.
/// Config-based scanner models (ConfigTestResult, ConfigScanResult, XrayConfig)
/// are tested separately in their respective test files.
void main() {
  test('Core models can be imported and instantiated', () {
    // ProxySettings
    final proxySettings = ProxySettings(
      remoteDNS: 'https://8.8.8.8/dns-query',
      remoteDnsHost: {},
      localDNS: '8.8.8.8',
      cleanIPs: ['1.1.1.1'],
      proxyIPs: [],
      outProxyParams: {},
    );
    expect(proxySettings.isValid(), isTrue);
    expect(proxySettings.cleanIPs, ['1.1.1.1']);

    // Credentials
    const credentials = Credentials(
      apiToken: 'test_token_1234567890123456789012',
      accountId: 'test_account_1234567890123456789012',
      kvNamespaceId: 'test_namespace_1234567890123456789012',
    );
    expect(credentials.isValid(), isTrue);
    expect(credentials.apiToken.length, greaterThanOrEqualTo(20));

    // Verify JSON serialization works
    final settingsJson = proxySettings.toJson();
    final settingsRestored = ProxySettings.fromJson(settingsJson);
    expect(settingsRestored, equals(proxySettings));

    final credsJson = credentials.toJson();
    final credsRestored = Credentials.fromJson(credsJson);
    expect(credsRestored, equals(credentials));

    // ignore: avoid_print
    print('[OK] All core models verified successfully!');
  });
}
