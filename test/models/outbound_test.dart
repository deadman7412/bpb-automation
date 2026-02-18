import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/outbound.dart';
import 'package:bpb_automation/models/stream_settings.dart';

void main() {
  group('Outbound', () {
    group('Constructor and JSON', () {
      test('creates instance from JSON with VLESS config', () {
        final json = {
          'protocol': 'vless',
          'tag': 'proxy',
          'settings': {
            'vnext': [
              {
                'address': '1.1.1.1',
                'port': 443,
                'users': [
                  {
                    'id': '12345678-1234-1234-1234-123456789012',
                    'encryption': 'none',
                    'flow': 'xtls-rprx-vision',
                  },
                ],
              },
            ],
          },
          'streamSettings': {
            'network': 'tcp',
            'security': 'tls',
            'tlsSettings': {'serverName': 'example.com'},
          },
        };

        final outbound = Outbound.fromJson(json);

        expect(outbound.protocol, equals('vless'));
        expect(outbound.tag, equals('proxy'));
        expect(outbound.getAddress(), equals('1.1.1.1'));
        expect(outbound.getPort(), equals(443));
        expect(outbound.streamSettings?.network, equals('tcp'));
      });

      test('converts to JSON', () {
        final outbound = Outbound(
          protocol: 'vless',
          tag: 'proxy',
          settings: OutboundSettings(
            vnext: [
              Vnext(
                address: '1.1.1.1',
                port: 443,
                users: [
                  VnextUser(
                    id: '12345678-1234-1234-1234-123456789012',
                    encryption: 'none',
                  ),
                ],
              ),
            ],
          ),
        );

        final json = outbound.toJson();

        expect(json['protocol'], equals('vless'));
        expect(json['tag'], equals('proxy'));
        expect(json['settings']['vnext'][0]['address'], equals('1.1.1.1'));
        expect(json['settings']['vnext'][0]['port'], equals(443));
      });
    });

    group('getAddress and getPort', () {
      test('extracts address from vnext', () {
        final outbound = Outbound(
          protocol: 'vless',
          settings: OutboundSettings(
            vnext: [Vnext(address: '1.1.1.1', port: 443)],
          ),
        );

        expect(outbound.getAddress(), equals('1.1.1.1'));
        expect(outbound.getPort(), equals(443));
      });

      test('returns null when no vnext', () {
        final outbound = Outbound(protocol: 'freedom');

        expect(outbound.getAddress(), isNull);
        expect(outbound.getPort(), isNull);
      });

      test('returns null when vnext is empty', () {
        final outbound = Outbound(
          protocol: 'vless',
          settings: OutboundSettings(vnext: []),
        );

        expect(outbound.getAddress(), isNull);
        expect(outbound.getPort(), isNull);
      });
    });

    group('isIpBased and isDomainBased', () {
      test('identifies IPv4 address', () {
        final outbound = Outbound(
          protocol: 'vless',
          settings: OutboundSettings(
            vnext: [Vnext(address: '1.1.1.1', port: 443)],
          ),
        );

        expect(outbound.isIpBased(), isTrue);
        expect(outbound.isDomainBased(), isFalse);
      });

      test('identifies IPv6 address', () {
        final outbound = Outbound(
          protocol: 'vless',
          settings: OutboundSettings(
            vnext: [Vnext(address: '2606:4700:4700::1111', port: 443)],
          ),
        );

        expect(outbound.isIpBased(), isTrue);
        expect(outbound.isDomainBased(), isFalse);
      });

      test('identifies domain name', () {
        final outbound = Outbound(
          protocol: 'vless',
          settings: OutboundSettings(
            vnext: [Vnext(address: 'example.com', port: 443)],
          ),
        );

        expect(outbound.isIpBased(), isFalse);
        expect(outbound.isDomainBased(), isTrue);
      });

      test('handles missing address', () {
        final outbound = Outbound(protocol: 'freedom');

        expect(outbound.isIpBased(), isFalse);
        expect(outbound.isDomainBased(), isFalse);
      });
    });

    group('copyWithAddress', () {
      test('replaces address in vnext', () {
        final original = Outbound(
          protocol: 'vless',
          settings: OutboundSettings(
            vnext: [
              Vnext(
                address: 'example.com',
                port: 443,
                users: [
                  VnextUser(
                    id: '12345678-1234-1234-1234-123456789012',
                    encryption: 'none',
                  ),
                ],
              ),
            ],
          ),
          streamSettings: StreamSettings(
            network: 'tcp',
            security: 'tls',
            tlsSettings: TlsSettings(serverName: 'example.com'),
          ),
        );

        final modified = original.copyWithAddress('1.1.1.1');

        expect(modified.getAddress(), equals('1.1.1.1'));
        expect(modified.getPort(), equals(443));
        expect(modified.streamSettings?.getSni(), equals('example.com'));
        expect(modified.protocol, equals('vless'));
      });

      test('returns same instance when no vnext', () {
        final original = Outbound(protocol: 'freedom');

        final modified = original.copyWithAddress('1.1.1.1');

        expect(modified, equals(original));
      });
    });
  });

  group('Vnext', () {
    test('creates instance from JSON', () {
      final json = {
        'address': '1.1.1.1',
        'port': 443,
        'users': [
          {'id': '12345678-1234-1234-1234-123456789012', 'encryption': 'none'},
        ],
      };

      final vnext = Vnext.fromJson(json);

      expect(vnext.address, equals('1.1.1.1'));
      expect(vnext.port, equals(443));
      expect(vnext.users?.length, equals(1));
      expect(
        vnext.users?.first.id,
        equals('12345678-1234-1234-1234-123456789012'),
      );
    });

    test('converts to JSON', () {
      final vnext = Vnext(
        address: '1.1.1.1',
        port: 443,
        users: [VnextUser(id: '12345678-1234-1234-1234-123456789012')],
      );

      final json = vnext.toJson();

      expect(json['address'], equals('1.1.1.1'));
      expect(json['port'], equals(443));
      expect(
        json['users'][0]['id'],
        equals('12345678-1234-1234-1234-123456789012'),
      );
    });

    test('copyWithAddress creates new instance with updated address', () {
      final original = Vnext(
        address: 'example.com',
        port: 443,
        users: [VnextUser(id: '12345678-1234-1234-1234-123456789012')],
      );

      final modified = original.copyWithAddress('1.1.1.1');

      expect(modified.address, equals('1.1.1.1'));
      expect(modified.port, equals(443));
      expect(modified.users?.length, equals(1));
      expect(original.address, equals('example.com')); // Original unchanged
    });
  });

  group('VnextUser', () {
    test('creates instance from JSON with all fields', () {
      final json = {
        'id': '12345678-1234-1234-1234-123456789012',
        'encryption': 'none',
        'flow': 'xtls-rprx-vision',
        'security': 'auto',
        'alterId': 0,
      };

      final user = VnextUser.fromJson(json);

      expect(user.id, equals('12345678-1234-1234-1234-123456789012'));
      expect(user.encryption, equals('none'));
      expect(user.flow, equals('xtls-rprx-vision'));
      expect(user.security, equals('auto'));
      expect(user.alterId, equals(0));
    });

    test('converts to JSON with optional fields', () {
      final user = VnextUser(
        id: '12345678-1234-1234-1234-123456789012',
        encryption: 'none',
        flow: 'xtls-rprx-vision',
      );

      final json = user.toJson();

      expect(json['id'], equals('12345678-1234-1234-1234-123456789012'));
      expect(json['encryption'], equals('none'));
      expect(json['flow'], equals('xtls-rprx-vision'));
      expect(json.containsKey('security'), isFalse);
      expect(json.containsKey('alterId'), isFalse);
    });
  });

  group('OutboundSettings', () {
    test('creates instance from JSON with vnext', () {
      final json = {
        'vnext': [
          {
            'address': '1.1.1.1',
            'port': 443,
            'users': [
              {'id': '12345678-1234-1234-1234-123456789012'},
            ],
          },
        ],
      };

      final settings = OutboundSettings.fromJson(json);

      expect(settings.vnext?.length, equals(1));
      expect(settings.vnext?.first.address, equals('1.1.1.1'));
    });

    test('creates instance from JSON with servers', () {
      final json = {
        'servers': [
          {'address': '1.1.1.1', 'port': 443},
        ],
      };

      final settings = OutboundSettings.fromJson(json);

      expect(settings.servers?.length, equals(1));
      expect(settings.servers?.first['address'], equals('1.1.1.1'));
    });

    test('converts to JSON', () {
      final settings = OutboundSettings(
        vnext: [Vnext(address: '1.1.1.1', port: 443)],
      );

      final json = settings.toJson();

      expect(json['vnext'][0]['address'], equals('1.1.1.1'));
    });
  });
}
