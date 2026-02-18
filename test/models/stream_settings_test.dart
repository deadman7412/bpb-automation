import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/stream_settings.dart';

void main() {
  group('StreamSettings', () {
    group('Constructor and JSON', () {
      test('creates instance with all fields', () {
        final tlsSettings = TlsSettings(
          serverName: 'example.com',
          alpn: ['h2', 'http/1.1'],
          fingerprint: 'chrome',
        );

        final wsSettings = WsSettings(
          path: '/ws',
          headers: {'Host': 'example.com'},
        );

        final settings = StreamSettings(
          network: 'ws',
          security: 'tls',
          tlsSettings: tlsSettings,
          wsSettings: wsSettings,
        );

        expect(settings.network, equals('ws'));
        expect(settings.security, equals('tls'));
        expect(settings.tlsSettings?.serverName, equals('example.com'));
        expect(settings.wsSettings?.path, equals('/ws'));
      });

      test('creates instance from JSON', () {
        final json = {
          'network': 'ws',
          'security': 'tls',
          'tlsSettings': {
            'serverName': 'example.com',
            'alpn': ['h2', 'http/1.1'],
          },
          'wsSettings': {
            'path': '/ws',
            'headers': {'Host': 'example.com'},
          },
        };

        final settings = StreamSettings.fromJson(json);

        expect(settings.network, equals('ws'));
        expect(settings.security, equals('tls'));
        expect(settings.tlsSettings?.serverName, equals('example.com'));
        expect(settings.tlsSettings?.alpn, equals(['h2', 'http/1.1']));
        expect(settings.wsSettings?.path, equals('/ws'));
      });

      test('converts to JSON', () {
        final settings = StreamSettings(
          network: 'tcp',
          security: 'tls',
          tlsSettings: TlsSettings(serverName: 'example.com'),
        );

        final json = settings.toJson();

        expect(json['network'], equals('tcp'));
        expect(json['security'], equals('tls'));
        expect(json['tlsSettings']['serverName'], equals('example.com'));
      });

      test('handles null fields in JSON', () {
        final json = {'network': 'tcp', 'security': 'none'};

        final settings = StreamSettings.fromJson(json);

        expect(settings.network, equals('tcp'));
        expect(settings.security, equals('none'));
        expect(settings.tlsSettings, isNull);
        expect(settings.wsSettings, isNull);
      });
    });

    group('getSni', () {
      test('returns SNI from TLS settings', () {
        final settings = StreamSettings(
          security: 'tls',
          tlsSettings: TlsSettings(serverName: 'example.com'),
        );

        expect(settings.getSni(), equals('example.com'));
      });

      test('returns null when no TLS settings', () {
        final settings = StreamSettings(network: 'tcp');

        expect(settings.getSni(), isNull);
      });
    });

    group('isSecure', () {
      test('returns true for TLS', () {
        final settings = StreamSettings(security: 'tls');

        expect(settings.isSecure(), isTrue);
      });

      test('returns true for Reality', () {
        final settings = StreamSettings(security: 'reality');

        expect(settings.isSecure(), isTrue);
      });

      test('returns false for none', () {
        final settings = StreamSettings(security: 'none');

        expect(settings.isSecure(), isFalse);
      });

      test('returns false when security is null', () {
        final settings = StreamSettings(network: 'tcp');

        expect(settings.isSecure(), isFalse);
      });
    });
  });

  group('TlsSettings', () {
    test('creates instance from JSON with all fields', () {
      final json = {
        'serverName': 'example.com',
        'alpn': ['h2', 'http/1.1'],
        'fingerprint': 'chrome',
        'publicKey': 'abcd1234',
        'shortId': 'abc',
        'spiderX': '/spider',
      };

      final tls = TlsSettings.fromJson(json);

      expect(tls.serverName, equals('example.com'));
      expect(tls.alpn, equals(['h2', 'http/1.1']));
      expect(tls.fingerprint, equals('chrome'));
      expect(tls.publicKey, equals('abcd1234'));
      expect(tls.shortId, equals('abc'));
      expect(tls.spiderX, equals('/spider'));
    });

    test('converts to JSON', () {
      final tls = TlsSettings(serverName: 'example.com', alpn: ['h2']);

      final json = tls.toJson();

      expect(json['serverName'], equals('example.com'));
      expect(json['alpn'], equals(['h2']));
      expect(json.containsKey('fingerprint'), isFalse);
    });
  });

  group('WsSettings', () {
    test('creates instance from JSON', () {
      final json = {
        'path': '/ws',
        'headers': {'Host': 'example.com'},
      };

      final ws = WsSettings.fromJson(json);

      expect(ws.path, equals('/ws'));
      expect(ws.headers?['Host'], equals('example.com'));
    });

    test('converts to JSON', () {
      final ws = WsSettings(path: '/ws');

      final json = ws.toJson();

      expect(json['path'], equals('/ws'));
    });
  });

  group('GrpcSettings', () {
    test('creates instance from JSON', () {
      final json = {'serviceName': 'MyService', 'multiMode': true};

      final grpc = GrpcSettings.fromJson(json);

      expect(grpc.serviceName, equals('MyService'));
      expect(grpc.multiMode, isTrue);
    });

    test('converts to JSON', () {
      final grpc = GrpcSettings(serviceName: 'MyService', multiMode: false);

      final json = grpc.toJson();

      expect(json['serviceName'], equals('MyService'));
      expect(json['multiMode'], isFalse);
    });
  });

  group('HttpUpgradeSettings', () {
    test('creates instance from JSON', () {
      final json = {'path': '/upgrade', 'host': 'example.com'};

      final httpUpgrade = HttpUpgradeSettings.fromJson(json);

      expect(httpUpgrade.path, equals('/upgrade'));
      expect(httpUpgrade.host, equals('example.com'));
    });

    test('converts to JSON', () {
      final httpUpgrade = HttpUpgradeSettings(path: '/upgrade');

      final json = httpUpgrade.toJson();

      expect(json['path'], equals('/upgrade'));
    });
  });
}
