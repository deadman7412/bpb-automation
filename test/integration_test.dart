import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/clean_ip.dart';
import 'package:bpb_automation/models/proxy_settings.dart';
import 'package:bpb_automation/models/scanner_config.dart';
import 'package:bpb_automation/models/credentials.dart';

/// Integration test to verify all models work together
void main() {
  test('All models can be imported and instantiated', () {
    // CleanIP
    final cleanIP = CleanIP(
      ip: '1.1.1.1',
      packetsSent: 10,
      packetsReceived: 10,
      lossRate: 0.0,
      avgLatency: 45.2,
      downloadSpeed: 12.5,
    );
    expect(cleanIP.isAcceptable(), isTrue);

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

    // ScannerConfig
    const scannerConfig = ScannerConfig();
    expect(scannerConfig.validate(), isNull);

    // Credentials
    const credentials = Credentials(
      apiToken: 'test_token_1234567890123456789012',
      accountId: 'test_account_1234567890123456789012',
      kvNamespaceId: 'test_namespace_1234567890123456789012',
    );
    expect(credentials.isValid(), isTrue);

    // Verify JSON serialization works
    final cleanIPJson = cleanIP.toJson();
    final cleanIPRestored = CleanIP.fromJson(cleanIPJson);
    expect(cleanIPRestored, equals(cleanIP));

    final settingsJson = proxySettings.toJson();
    final settingsRestored = ProxySettings.fromJson(settingsJson);
    expect(settingsRestored, equals(proxySettings));

    final configJson = scannerConfig.toJson();
    final configRestored = ScannerConfig.fromJson(configJson);
    expect(configRestored, equals(scannerConfig));

    final credsJson = credentials.toJson();
    final credsRestored = Credentials.fromJson(credsJson);
    expect(credsRestored, equals(credentials));

    // ignore: avoid_print
    print('[OK] All models verified successfully!');
  });
}
