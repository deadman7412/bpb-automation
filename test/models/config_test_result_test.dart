import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/config_test_result.dart';
import 'package:bpb_automation/models/xray_config.dart';
import 'package:bpb_automation/models/outbound.dart';

void main() {
  // Helper function to create a simple valid config
  XrayConfig createTestConfig({String address = '1.1.1.1'}) {
    return XrayConfig(
      outbounds: [
        Outbound(
          protocol: 'vless',
          settings: OutboundSettings(
            vnext: [Vnext(address: address, port: 443)],
          ),
        ),
      ],
      remarks: 'Test Config',
    );
  }

  group('TlsTestResult', () {
    test('creates successful result', () {
      final result = TlsTestResult.success(
        latencyMs: 50.0,
        cloudflareVerified: true,
      );

      expect(result.success, isTrue);
      expect(result.latencyMs, equals(50.0));
      expect(result.cloudflareVerified, isTrue);
      expect(result.error, isNull);
    });

    test('creates failure result', () {
      final result = TlsTestResult.failure(
        error: 'Connection timeout',
        latencyMs: 5000.0,
      );

      expect(result.success, isFalse);
      expect(result.error, equals('Connection timeout'));
      expect(result.latencyMs, equals(5000.0));
    });

    test('converts to and from JSON', () {
      final result = TlsTestResult.success(
        latencyMs: 50.0,
        cloudflareVerified: true,
      );

      final json = result.toJson();
      final restored = TlsTestResult.fromJson(json);

      expect(restored.success, equals(result.success));
      expect(restored.latencyMs, equals(result.latencyMs));
      expect(restored.cloudflareVerified, equals(result.cloudflareVerified));
    });
  });

  group('ProxyTestResult', () {
    test('creates successful result', () {
      final result = ProxyTestResult.success(
        latencyMs: 150.0,
        statusCode: 204,
        speedMbps: 50.0,
      );

      expect(result.success, isTrue);
      expect(result.latencyMs, equals(150.0));
      expect(result.statusCode, equals(204));
      expect(result.speedMbps, equals(50.0));
      expect(result.error, isNull);
    });

    test('creates failure result', () {
      final result = ProxyTestResult.failure(
        error: 'Proxy connection failed',
        statusCode: 500,
      );

      expect(result.success, isFalse);
      expect(result.error, equals('Proxy connection failed'));
      expect(result.statusCode, equals(500));
    });

    test('converts to and from JSON', () {
      final result = ProxyTestResult.success(
        latencyMs: 150.0,
        statusCode: 204,
        speedMbps: 50.0,
      );

      final json = result.toJson();
      final restored = ProxyTestResult.fromJson(json);

      expect(restored.success, equals(result.success));
      expect(restored.latencyMs, equals(result.latencyMs));
      expect(restored.statusCode, equals(result.statusCode));
      expect(restored.speedMbps, equals(result.speedMbps));
    });
  });

  group('ConfigTestResult', () {
    group('fromTlsTest', () {
      test('creates result from successful TLS test', () {
        final config = createTestConfig();
        final tlsResult = TlsTestResult.success(latencyMs: 50.0);

        final result = ConfigTestResult.fromTlsTest(
          ip: '1.1.1.1',
          config: config,
          tlsTestResult: tlsResult,
        );

        expect(result.ip, equals('1.1.1.1'));
        expect(result.tlsPassed, isTrue);
        expect(result.proxyPassed, isFalse);
        expect(result.qualityScore, greaterThan(0));
        expect(result.qualityScore, lessThanOrEqualTo(50));
      });

      test('creates result from failed TLS test', () {
        final config = createTestConfig();
        final tlsResult = TlsTestResult.failure(error: 'Timeout');

        final result = ConfigTestResult.fromTlsTest(
          ip: '1.1.1.1',
          config: config,
          tlsTestResult: tlsResult,
        );

        expect(result.tlsPassed, isFalse);
        expect(result.qualityScore, equals(0));
      });

      test('calculates quality score based on latency', () {
        final config = createTestConfig();

        final fastTls = TlsTestResult.success(latencyMs: 10.0);
        final slowTls = TlsTestResult.success(latencyMs: 450.0);

        final fastResult = ConfigTestResult.fromTlsTest(
          ip: '1.1.1.1',
          config: config,
          tlsTestResult: fastTls,
        );

        final slowResult = ConfigTestResult.fromTlsTest(
          ip: '2.2.2.2',
          config: config,
          tlsTestResult: slowTls,
        );

        expect(fastResult.qualityScore, greaterThan(slowResult.qualityScore));
      });
    });

    group('fromBothTests', () {
      test('creates result from both successful tests', () {
        final config = createTestConfig();
        final tlsResult = TlsTestResult.success(latencyMs: 50.0);
        final proxyResult = ProxyTestResult.success(latencyMs: 150.0);

        final result = ConfigTestResult.fromBothTests(
          ip: '1.1.1.1',
          config: config,
          tlsTestResult: tlsResult,
          proxyTestResult: proxyResult,
        );

        expect(result.tlsPassed, isTrue);
        expect(result.proxyPassed, isTrue);
        expect(result.isFullyTested, isTrue);
        expect(result.qualityScore, greaterThan(50));
      });

      test('creates result from TLS success, proxy fail', () {
        final config = createTestConfig();
        final tlsResult = TlsTestResult.success(latencyMs: 50.0);
        final proxyResult = ProxyTestResult.failure(error: 'Connection failed');

        final result = ConfigTestResult.fromBothTests(
          ip: '1.1.1.1',
          config: config,
          tlsTestResult: tlsResult,
          proxyTestResult: proxyResult,
        );

        expect(result.tlsPassed, isTrue);
        expect(result.proxyPassed, isFalse);
        expect(result.isFullyTested, isFalse);
        expect(result.qualityScore, lessThan(50));
      });

      test('calculates combined quality score', () {
        final config = createTestConfig();

        final fastBoth = ConfigTestResult.fromBothTests(
          ip: '1.1.1.1',
          config: config,
          tlsTestResult: TlsTestResult.success(latencyMs: 10.0),
          proxyTestResult: ProxyTestResult.success(latencyMs: 100.0),
        );

        final slowBoth = ConfigTestResult.fromBothTests(
          ip: '2.2.2.2',
          config: config,
          tlsTestResult: TlsTestResult.success(latencyMs: 400.0),
          proxyTestResult: ProxyTestResult.success(latencyMs: 900.0),
        );

        expect(fastBoth.qualityScore, greaterThan(slowBoth.qualityScore));
      });
    });

    group('isAcceptable', () {
      test('TLS-only result is acceptable when TLS passes', () {
        final result = ConfigTestResult.fromTlsTest(
          ip: '1.1.1.1',
          config: createTestConfig(),
          tlsTestResult: TlsTestResult.success(latencyMs: 50.0),
        );

        expect(result.isAcceptable(), isTrue);
      });

      test('TLS-only result is not acceptable when TLS fails', () {
        final result = ConfigTestResult.fromTlsTest(
          ip: '1.1.1.1',
          config: createTestConfig(),
          tlsTestResult: TlsTestResult.failure(error: 'Timeout'),
        );

        expect(result.isAcceptable(), isFalse);
      });

      test('Full test result is acceptable only when both pass', () {
        final config = createTestConfig();

        final bothPass = ConfigTestResult.fromBothTests(
          ip: '1.1.1.1',
          config: config,
          tlsTestResult: TlsTestResult.success(latencyMs: 50.0),
          proxyTestResult: ProxyTestResult.success(latencyMs: 150.0),
        );

        final proxyFail = ConfigTestResult.fromBothTests(
          ip: '2.2.2.2',
          config: config,
          tlsTestResult: TlsTestResult.success(latencyMs: 50.0),
          proxyTestResult: ProxyTestResult.failure(error: 'Failed'),
        );

        expect(bothPass.isAcceptable(), isTrue);
        expect(proxyFail.isAcceptable(), isFalse);
      });
    });

    group('finalLatencyMs', () {
      test('returns proxy latency when available', () {
        final result = ConfigTestResult.fromBothTests(
          ip: '1.1.1.1',
          config: createTestConfig(),
          tlsTestResult: TlsTestResult.success(latencyMs: 50.0),
          proxyTestResult: ProxyTestResult.success(latencyMs: 150.0),
        );

        expect(result.finalLatencyMs, equals(150.0));
      });

      test('returns TLS latency when proxy not tested', () {
        final result = ConfigTestResult.fromTlsTest(
          ip: '1.1.1.1',
          config: createTestConfig(),
          tlsTestResult: TlsTestResult.success(latencyMs: 50.0),
        );

        expect(result.finalLatencyMs, equals(50.0));
      });

      test('returns infinity when no tests', () {
        final result = ConfigTestResult(
          ip: '1.1.1.1',
          config: createTestConfig(),
          qualityScore: 0,
          timestamp: DateTime.now(),
        );

        expect(result.finalLatencyMs, equals(double.infinity));
      });
    });

    group('compareQuality', () {
      test('prioritizes fully tested over TLS-only', () {
        final config = createTestConfig();

        final fullyTested = ConfigTestResult.fromBothTests(
          ip: '1.1.1.1',
          config: config,
          tlsTestResult: TlsTestResult.success(latencyMs: 100.0),
          proxyTestResult: ProxyTestResult.success(latencyMs: 200.0),
        );

        final tlsOnly = ConfigTestResult.fromTlsTest(
          ip: '2.2.2.2',
          config: config,
          tlsTestResult: TlsTestResult.success(latencyMs: 10.0),
        );

        expect(fullyTested.compareQuality(tlsOnly), lessThan(0));
      });

      test('prioritizes successful over failed', () {
        final config = createTestConfig();

        final success = ConfigTestResult.fromTlsTest(
          ip: '1.1.1.1',
          config: config,
          tlsTestResult: TlsTestResult.success(latencyMs: 100.0),
        );

        final failed = ConfigTestResult.fromTlsTest(
          ip: '2.2.2.2',
          config: config,
          tlsTestResult: TlsTestResult.failure(error: 'Failed'),
        );

        expect(success.compareQuality(failed), lessThan(0));
      });

      test('compares by latency when both same status', () {
        final config = createTestConfig();

        final fast = ConfigTestResult.fromTlsTest(
          ip: '1.1.1.1',
          config: config,
          tlsTestResult: TlsTestResult.success(latencyMs: 10.0),
        );

        final slow = ConfigTestResult.fromTlsTest(
          ip: '2.2.2.2',
          config: config,
          tlsTestResult: TlsTestResult.success(latencyMs: 500.0),
        );

        expect(fast.compareQuality(slow), lessThan(0));
      });
    });

    group('getStatusDescription', () {
      test('returns "Working" for fully tested', () {
        final result = ConfigTestResult.fromBothTests(
          ip: '1.1.1.1',
          config: createTestConfig(),
          tlsTestResult: TlsTestResult.success(latencyMs: 50.0),
          proxyTestResult: ProxyTestResult.success(latencyMs: 150.0),
        );

        expect(result.getStatusDescription(), equals('Working'));
      });

      test('returns appropriate status for TLS-only', () {
        final result = ConfigTestResult.fromTlsTest(
          ip: '1.1.1.1',
          config: createTestConfig(),
          tlsTestResult: TlsTestResult.success(latencyMs: 50.0),
        );

        expect(result.getStatusDescription(), contains('TLS OK'));
      });

      test('returns "Failed" for failed tests', () {
        final result = ConfigTestResult.fromTlsTest(
          ip: '1.1.1.1',
          config: createTestConfig(),
          tlsTestResult: TlsTestResult.failure(error: 'Timeout'),
        );

        expect(result.getStatusDescription(), equals('Failed'));
      });
    });

    group('JSON serialization', () {
      test('converts to and from JSON with full data', () {
        final original = ConfigTestResult.fromBothTests(
          ip: '1.1.1.1',
          config: createTestConfig(),
          tlsTestResult: TlsTestResult.success(latencyMs: 50.0),
          proxyTestResult: ProxyTestResult.success(latencyMs: 150.0),
        );

        final json = original.toJson();
        final restored = ConfigTestResult.fromJson(json);

        expect(restored.ip, equals(original.ip));
        expect(restored.qualityScore, equals(original.qualityScore));
        expect(restored.tlsPassed, equals(original.tlsPassed));
        expect(restored.proxyPassed, equals(original.proxyPassed));
      });
    });
  });
}
