import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/xray_config.dart';
import 'package:bpb_automation/models/outbound.dart';
import 'package:bpb_automation/models/stream_settings.dart';

void main() {
  group('XrayConfig', () {
    group('Constructor and JSON', () {
      test('creates instance from JSON with full config', () {
        final json = {
          'log': {'loglevel': 'warning'},
          'inbounds': [
            {'port': 10808, 'protocol': 'socks'},
          ],
          'outbounds': [
            {
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': '1.1.1.1',
                    'port': 443,
                    'users': [
                      {'id': '12345678-1234-1234-1234-123456789012'},
                    ],
                  },
                ],
              },
              'streamSettings': {
                'network': 'tcp',
                'security': 'tls',
                'tlsSettings': {'serverName': 'example.com'},
              },
            },
          ],
          'remarks': 'Test Config',
        };

        final config = XrayConfig.fromJson(json);

        expect(config.log?['loglevel'], equals('warning'));
        expect(config.inbounds?.length, equals(1));
        expect(config.outbounds?.length, equals(1));
        expect(config.remarks, equals('Test Config'));
      });

      test('converts to JSON', () {
        final config = XrayConfig(
          log: {'loglevel': 'warning'},
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(
                vnext: [Vnext(address: '1.1.1.1', port: 443)],
              ),
            ),
          ],
          remarks: 'Test',
        );

        final json = config.toJson();

        expect(json['log']['loglevel'], equals('warning'));
        expect(json['outbounds'][0]['protocol'], equals('vless'));
        expect(json['remarks'], equals('Test'));
      });
    });

    group('getPrimaryOutbound', () {
      test('returns first proxy outbound', () {
        final config = XrayConfig(
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(
                vnext: [Vnext(address: '1.1.1.1', port: 443)],
              ),
            ),
            Outbound(protocol: 'freedom'),
          ],
        );

        final primary = config.getPrimaryOutbound();

        expect(primary?.protocol, equals('vless'));
      });

      test('skips direct and block outbounds', () {
        final config = XrayConfig(
          outbounds: [
            Outbound(protocol: 'freedom'),
            Outbound(protocol: 'blackhole'),
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(
                vnext: [Vnext(address: '1.1.1.1', port: 443)],
              ),
            ),
          ],
        );

        final primary = config.getPrimaryOutbound();

        expect(primary?.protocol, equals('vless'));
      });

      test('returns null when no outbounds', () {
        final config = XrayConfig();

        expect(config.getPrimaryOutbound(), isNull);
      });

      test('returns first outbound as fallback', () {
        final config = XrayConfig(outbounds: [Outbound(protocol: 'freedom')]);

        final primary = config.getPrimaryOutbound();

        expect(primary?.protocol, equals('freedom'));
      });
    });

    group('getServerAddress and getServerPort', () {
      test('extracts address and port from primary outbound', () {
        final config = XrayConfig(
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(
                vnext: [Vnext(address: '1.1.1.1', port: 443)],
              ),
            ),
          ],
        );

        expect(config.getServerAddress(), equals('1.1.1.1'));
        expect(config.getServerPort(), equals(443));
      });

      test('returns null when no outbound', () {
        final config = XrayConfig();

        expect(config.getServerAddress(), isNull);
        expect(config.getServerPort(), isNull);
      });
    });

    group('isIpBased and isDomainBased', () {
      test('identifies IP-based config', () {
        final config = XrayConfig(
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(
                vnext: [Vnext(address: '1.1.1.1', port: 443)],
              ),
            ),
          ],
        );

        expect(config.isIpBased(), isTrue);
        expect(config.isDomainBased(), isFalse);
      });

      test('identifies domain-based config', () {
        final config = XrayConfig(
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(
                vnext: [Vnext(address: 'example.com', port: 443)],
              ),
            ),
          ],
        );

        expect(config.isIpBased(), isFalse);
        expect(config.isDomainBased(), isTrue);
      });
    });

    group('getProtocol and getStreamSettings', () {
      test('extracts protocol from primary outbound', () {
        final config = XrayConfig(
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(
                vnext: [Vnext(address: '1.1.1.1', port: 443)],
              ),
            ),
          ],
        );

        expect(config.getProtocol(), equals('vless'));
      });

      test('extracts stream settings from primary outbound', () {
        final config = XrayConfig(
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(
                vnext: [Vnext(address: '1.1.1.1', port: 443)],
              ),
              streamSettings: StreamSettings(
                network: 'tcp',
                security: 'tls',
                tlsSettings: TlsSettings(serverName: 'example.com'),
              ),
            ),
          ],
        );

        expect(config.getStreamSettings()?.network, equals('tcp'));
        expect(config.getSni(), equals('example.com'));
      });
    });

    group('isSecure', () {
      test('returns true when TLS is enabled', () {
        final config = XrayConfig(
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(
                vnext: [Vnext(address: '1.1.1.1', port: 443)],
              ),
              streamSettings: StreamSettings(security: 'tls'),
            ),
          ],
        );

        expect(config.isSecure(), isTrue);
      });

      test('returns false when no security', () {
        final config = XrayConfig(
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(
                vnext: [Vnext(address: '1.1.1.1', port: 443)],
              ),
              streamSettings: StreamSettings(security: 'none'),
            ),
          ],
        );

        expect(config.isSecure(), isFalse);
      });
    });

    group('copyWithAddress', () {
      test('replaces address in primary outbound', () {
        final original = XrayConfig(
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(
                vnext: [Vnext(address: 'example.com', port: 443)],
              ),
              streamSettings: StreamSettings(
                security: 'tls',
                tlsSettings: TlsSettings(serverName: 'example.com'),
              ),
            ),
            Outbound(protocol: 'freedom'),
          ],
          remarks: 'Test',
        );

        final modified = original.copyWithAddress('1.1.1.1');

        expect(modified.getServerAddress(), equals('1.1.1.1'));
        expect(modified.getServerPort(), equals(443));
        expect(modified.getSni(), equals('example.com')); // SNI unchanged
        expect(modified.remarks, equals('Test'));
      });

      test('returns same instance when no outbounds', () {
        final original = XrayConfig(remarks: 'Test');

        final modified = original.copyWithAddress('1.1.1.1');

        expect(modified.remarks, equals('Test'));
      });
    });

    group('withTestInbound', () {
      test('replaces inbounds with SOCKS5 test inbound', () {
        final original = XrayConfig(
          inbounds: [
            {'port': 1080, 'protocol': 'http'},
          ],
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(
                vnext: [Vnext(address: '1.1.1.1', port: 443)],
              ),
            ),
          ],
        );

        final modified = original.withTestInbound();

        expect(modified.inbounds?.length, equals(1));
        expect(modified.inbounds?.first['port'], equals(10808));
        expect(modified.inbounds?.first['protocol'], equals('socks'));
        expect(modified.inbounds?.first['listen'], equals('127.0.0.1'));
      });
    });

    group('getDescription', () {
      test('formats full description with remarks', () {
        final config = XrayConfig(
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(
                vnext: [Vnext(address: '1.1.1.1', port: 443)],
              ),
              streamSettings: StreamSettings(security: 'tls'),
            ),
          ],
          remarks: 'My Config',
        );

        final description = config.getDescription();

        expect(description, contains('VLESS'));
        expect(description, contains('1.1.1.1:443'));
        expect(description, contains('TLS'));
        expect(description, contains('My Config'));
      });

      test('formats description without remarks', () {
        final config = XrayConfig(
          outbounds: [
            Outbound(
              protocol: 'vmess',
              settings: OutboundSettings(
                vnext: [Vnext(address: '2.2.2.2', port: 80)],
              ),
              streamSettings: StreamSettings(security: 'none'),
            ),
          ],
        );

        final description = config.getDescription();

        expect(description, contains('VMESS'));
        expect(description, contains('2.2.2.2:80'));
        expect(description, contains('Plain'));
        expect(description, isNot(contains('-'))); // No remarks separator
      });
    });

    group('isValid and getValidationErrors', () {
      test('validates correct config', () {
        final config = XrayConfig(
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(
                vnext: [Vnext(address: '1.1.1.1', port: 443)],
              ),
            ),
          ],
        );

        expect(config.isValid(), isTrue);
        expect(config.getValidationErrors(), isEmpty);
      });

      test('detects missing outbounds', () {
        final config = XrayConfig();

        expect(config.isValid(), isFalse);
        expect(
          config.getValidationErrors(),
          contains('No outbounds configured'),
        );
      });

      test('detects missing address', () {
        final config = XrayConfig(
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(vnext: []),
            ),
          ],
        );

        expect(config.isValid(), isFalse);
        expect(
          config.getValidationErrors(),
          contains('Outbound has no address configured'),
        );
      });

      test('detects invalid port', () {
        final config = XrayConfig(
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(
                vnext: [Vnext(address: '1.1.1.1', port: 99999)],
              ),
            ),
          ],
        );

        expect(config.isValid(), isFalse);
        final errors = config.getValidationErrors();
        expect(
          errors.any((e) => e.startsWith('Outbound port is invalid')),
          isTrue,
        );
      });

      test('detects only direct/block outbounds', () {
        final config = XrayConfig(
          outbounds: [
            Outbound(protocol: 'freedom'),
            Outbound(protocol: 'blackhole'),
          ],
        );

        expect(config.isValid(), isFalse);
        // Since getPrimaryOutbound falls back to first outbound,
        // it returns freedom which has no address/port
        expect(
          config.getValidationErrors(),
          contains('Outbound has no address configured'),
        );
      });
    });
  });
}
