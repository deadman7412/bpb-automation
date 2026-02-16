import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/proxy_settings.dart';

void main() {
  group('ProxySettings', () {
    group('Constructor', () {
      test('creates instance with valid data', () {
        final settings = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {},
          localDNS: '8.8.8.8',
          cleanIPs: ['1.1.1.1', '1.0.0.1'],
          proxyIPs: [],
          outProxyParams: {},
        );

        expect(settings.remoteDNS, equals('https://8.8.8.8/dns-query'));
        expect(settings.localDNS, equals('8.8.8.8'));
        expect(settings.cleanIPs, equals(['1.1.1.1', '1.0.0.1']));
        expect(settings.proxyIPs, isEmpty);
      });

      test('creates instance with additional fields', () {
        final settings = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {},
          localDNS: '8.8.8.8',
          cleanIPs: ['1.1.1.1'],
          proxyIPs: [],
          outProxyParams: {},
          additionalFields: {'customField': 'value'},
        );

        expect(settings.hasAdditionalFields(), isTrue);
        expect(settings.additionalFields['customField'], equals('value'));
      });
    });

    group('fromJson', () {
      test('creates instance from valid JSON', () {
        final json = {
          'remoteDNS': 'https://8.8.8.8/dns-query',
          'remoteDnsHost': {},
          'localDNS': '8.8.8.8',
          'cleanIPs': ['1.1.1.1', '1.0.0.1'],
          'proxyIPs': [],
          'outProxyParams': {},
        };

        final settings = ProxySettings.fromJson(json);

        expect(settings.remoteDNS, equals('https://8.8.8.8/dns-query'));
        expect(settings.localDNS, equals('8.8.8.8'));
        expect(settings.cleanIPs, equals(['1.1.1.1', '1.0.0.1']));
      });

      test('preserves unknown fields', () {
        final json = {
          'remoteDNS': 'https://8.8.8.8/dns-query',
          'remoteDnsHost': {},
          'localDNS': '8.8.8.8',
          'cleanIPs': ['1.1.1.1'],
          'proxyIPs': [],
          'outProxyParams': {},
          'unknownField1': 'value1',
          'unknownField2': 42,
          'unknownField3': {'nested': 'object'},
        };

        final settings = ProxySettings.fromJson(json);

        expect(settings.hasAdditionalFields(), isTrue);
        expect(settings.additionalFields['unknownField1'], equals('value1'));
        expect(settings.additionalFields['unknownField2'], equals(42));
        expect(
          settings.additionalFields['unknownField3'],
          equals({'nested': 'object'}),
        );
      });

      test('handles missing optional fields with defaults', () {
        final json = <String, dynamic>{};

        final settings = ProxySettings.fromJson(json);

        expect(settings.remoteDNS, equals(''));
        expect(settings.localDNS, equals(''));
        expect(settings.cleanIPs, isEmpty);
        expect(settings.proxyIPs, isEmpty);
        expect(settings.remoteDnsHost, isEmpty);
        expect(settings.outProxyParams, isEmpty);
      });

      test('handles null values gracefully', () {
        final json = {
          'remoteDNS': null,
          'remoteDnsHost': null,
          'localDNS': null,
          'cleanIPs': null,
          'proxyIPs': null,
          'outProxyParams': null,
        };

        final settings = ProxySettings.fromJson(json);

        expect(settings.remoteDNS, equals(''));
        expect(settings.localDNS, equals(''));
        expect(settings.cleanIPs, isEmpty);
        expect(settings.proxyIPs, isEmpty);
      });

      test('handles complex nested structures', () {
        final json = {
          'remoteDNS': 'https://8.8.8.8/dns-query',
          'remoteDnsHost': {
            'server': '8.8.8.8',
            'port': 53,
            'options': ['no-cache', 'trust-ad'],
          },
          'localDNS': '8.8.8.8',
          'cleanIPs': ['1.1.1.1'],
          'proxyIPs': [],
          'outProxyParams': {
            'protocol': 'socks5',
            'address': '127.0.0.1',
            'port': 1080,
          },
        };

        final settings = ProxySettings.fromJson(json);

        expect(settings.remoteDnsHost['server'], equals('8.8.8.8'));
        expect(settings.remoteDnsHost['port'], equals(53));
        expect(settings.outProxyParams['protocol'], equals('socks5'));
      });
    });

    group('toJson', () {
      test('converts instance to JSON correctly', () {
        final settings = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {},
          localDNS: '8.8.8.8',
          cleanIPs: ['1.1.1.1', '1.0.0.1'],
          proxyIPs: [],
          outProxyParams: {},
        );

        final json = settings.toJson();

        expect(json['remoteDNS'], equals('https://8.8.8.8/dns-query'));
        expect(json['localDNS'], equals('8.8.8.8'));
        expect(json['cleanIPs'], equals(['1.1.1.1', '1.0.0.1']));
        expect(json['proxyIPs'], equals([]));
      });

      test('includes additional fields in JSON output', () {
        final settings = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {},
          localDNS: '8.8.8.8',
          cleanIPs: ['1.1.1.1'],
          proxyIPs: [],
          outProxyParams: {},
          additionalFields: {
            'customField': 'value',
            'anotherField': 123,
          },
        );

        final json = settings.toJson();

        expect(json['customField'], equals('value'));
        expect(json['anotherField'], equals(123));
      });

      test('round-trip JSON serialization preserves all data', () {
        final original = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {'key': 'value'},
          localDNS: '8.8.8.8',
          cleanIPs: ['1.1.1.1', '1.0.0.1'],
          proxyIPs: ['2.2.2.2'],
          outProxyParams: {'param': 'value'},
          additionalFields: {'extra': 'field'},
        );

        final json = original.toJson();
        final restored = ProxySettings.fromJson(json);

        expect(restored, equals(original));
      });

      test('round-trip preserves unknown fields from original JSON', () {
        final originalJson = {
          'remoteDNS': 'https://8.8.8.8/dns-query',
          'remoteDnsHost': {},
          'localDNS': '8.8.8.8',
          'cleanIPs': ['1.1.1.1'],
          'proxyIPs': [],
          'outProxyParams': {},
          'unknownField': 'should be preserved',
        };

        final settings = ProxySettings.fromJson(originalJson);
        final restoredJson = settings.toJson();

        expect(restoredJson['unknownField'], equals('should be preserved'));
      });
    });

    group('copyWithCleanIPs', () {
      test('creates new instance with updated clean IPs', () {
        final original = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {},
          localDNS: '8.8.8.8',
          cleanIPs: ['1.1.1.1'],
          proxyIPs: [],
          outProxyParams: {},
        );

        final updated = original.copyWithCleanIPs(['2.2.2.2', '3.3.3.3']);

        expect(updated.cleanIPs, equals(['2.2.2.2', '3.3.3.3']));
        expect(updated.remoteDNS, equals(original.remoteDNS));
        expect(updated.localDNS, equals(original.localDNS));
        expect(updated.proxyIPs, equals(original.proxyIPs));
      });

      test('preserves additional fields', () {
        final original = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {},
          localDNS: '8.8.8.8',
          cleanIPs: ['1.1.1.1'],
          proxyIPs: [],
          outProxyParams: {},
          additionalFields: {'custom': 'value'},
        );

        final updated = original.copyWithCleanIPs(['2.2.2.2']);

        expect(updated.additionalFields['custom'], equals('value'));
      });

      test('does not modify original instance', () {
        final original = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {},
          localDNS: '8.8.8.8',
          cleanIPs: ['1.1.1.1'],
          proxyIPs: [],
          outProxyParams: {},
        );

        final originalCleanIPs = List.from(original.cleanIPs);
        original.copyWithCleanIPs(['2.2.2.2']);

        expect(original.cleanIPs, equals(originalCleanIPs));
      });
    });

    group('hasCleanIPs', () {
      test('returns true when clean IPs exist', () {
        final settings = ProxySettings(
          remoteDNS: '',
          remoteDnsHost: {},
          localDNS: '',
          cleanIPs: ['1.1.1.1'],
          proxyIPs: [],
          outProxyParams: {},
        );

        expect(settings.hasCleanIPs(), isTrue);
      });

      test('returns false when clean IPs list is empty', () {
        final settings = ProxySettings(
          remoteDNS: '',
          remoteDnsHost: {},
          localDNS: '',
          cleanIPs: [],
          proxyIPs: [],
          outProxyParams: {},
        );

        expect(settings.hasCleanIPs(), isFalse);
      });
    });

    group('cleanIPCount', () {
      test('returns correct count of clean IPs', () {
        final settings = ProxySettings(
          remoteDNS: '',
          remoteDnsHost: {},
          localDNS: '',
          cleanIPs: ['1.1.1.1', '1.0.0.1', '8.8.8.8'],
          proxyIPs: [],
          outProxyParams: {},
        );

        expect(settings.cleanIPCount, equals(3));
      });

      test('returns 0 for empty list', () {
        final settings = ProxySettings(
          remoteDNS: '',
          remoteDnsHost: {},
          localDNS: '',
          cleanIPs: [],
          proxyIPs: [],
          outProxyParams: {},
        );

        expect(settings.cleanIPCount, equals(0));
      });
    });

    group('hasProxyIPs', () {
      test('returns true when proxy IPs exist', () {
        final settings = ProxySettings(
          remoteDNS: '',
          remoteDnsHost: {},
          localDNS: '',
          cleanIPs: [],
          proxyIPs: ['1.1.1.1'],
          outProxyParams: {},
        );

        expect(settings.hasProxyIPs(), isTrue);
      });

      test('returns false when proxy IPs list is empty', () {
        final settings = ProxySettings(
          remoteDNS: '',
          remoteDnsHost: {},
          localDNS: '',
          cleanIPs: [],
          proxyIPs: [],
          outProxyParams: {},
        );

        expect(settings.hasProxyIPs(), isFalse);
      });
    });

    group('isValid', () {
      test('returns true when remoteDNS is present', () {
        final settings = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {},
          localDNS: '',
          cleanIPs: [],
          proxyIPs: [],
          outProxyParams: {},
        );

        expect(settings.isValid(), isTrue);
      });

      test('returns true when localDNS is present', () {
        final settings = ProxySettings(
          remoteDNS: '',
          remoteDnsHost: {},
          localDNS: '8.8.8.8',
          cleanIPs: [],
          proxyIPs: [],
          outProxyParams: {},
        );

        expect(settings.isValid(), isTrue);
      });

      test('returns false when no DNS settings present', () {
        final settings = ProxySettings(
          remoteDNS: '',
          remoteDnsHost: {},
          localDNS: '',
          cleanIPs: ['1.1.1.1'],
          proxyIPs: [],
          outProxyParams: {},
        );

        expect(settings.isValid(), isFalse);
      });
    });

    group('toString', () {
      test('returns formatted string without sensitive data', () {
        final settings = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {},
          localDNS: '8.8.8.8',
          cleanIPs: ['1.1.1.1', '1.0.0.1'],
          proxyIPs: [],
          outProxyParams: {},
          additionalFields: {'extra': 'field'},
        );

        final str = settings.toString();

        expect(str, contains('https://8.8.8.8/dns-query'));
        expect(str, contains('8.8.8.8'));
        expect(str, contains('2 IPs')); // cleanIPs count
        expect(str, contains('1 fields')); // additional fields count
      });
    });

    group('Equality', () {
      test('equal instances are equal', () {
        final settings1 = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {'key': 'value'},
          localDNS: '8.8.8.8',
          cleanIPs: ['1.1.1.1'],
          proxyIPs: [],
          outProxyParams: {'param': 'value'},
        );

        final settings2 = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {'key': 'value'},
          localDNS: '8.8.8.8',
          cleanIPs: ['1.1.1.1'],
          proxyIPs: [],
          outProxyParams: {'param': 'value'},
        );

        expect(settings1, equals(settings2));
        expect(settings1.hashCode, equals(settings2.hashCode));
      });

      test('different instances are not equal', () {
        final settings1 = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {},
          localDNS: '8.8.8.8',
          cleanIPs: ['1.1.1.1'],
          proxyIPs: [],
          outProxyParams: {},
        );

        final settings2 = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {},
          localDNS: '8.8.8.8',
          cleanIPs: ['1.0.0.1'], // Different clean IPs
          proxyIPs: [],
          outProxyParams: {},
        );

        expect(settings1, isNot(equals(settings2)));
      });
    });
  });
}
