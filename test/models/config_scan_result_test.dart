import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/config_scan_result.dart';
import 'package:bpb_automation/models/config_test_result.dart';
import 'package:bpb_automation/models/xray_config.dart';
import 'package:bpb_automation/models/outbound.dart';

void main() {
  group('ConfigScanResult', () {
    late XrayConfig testConfig;

    setUp(() {
      testConfig = XrayConfig(
        outbounds: [
          Outbound.fromJson({
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {
                  'address': '1.1.1.1',
                  'port': 443,
                  'users': [
                    {'id': 'test-uuid'},
                  ],
                },
              ],
            },
          }),
        ],
        inbounds: [],
        log: {},
        remarks: 'Test Config',
      );
    });

    group('Factory constructors', () {
      test(
        'success factory creates result with working IPs sorted by latency',
        () {
          final results = [
            ConfigTestResult(
              ip: '1.1.1.1',
              config: testConfig,
              tlsTestResult: TlsTestResult.success(latencyMs: 50),
              proxyTestResult: ProxyTestResult.success(
                latencyMs: 200,
                statusCode: 204,
              ),
              qualityScore: 80,
              timestamp: DateTime.now(),
            ),
            ConfigTestResult(
              ip: '8.8.8.8',
              config: testConfig,
              tlsTestResult: TlsTestResult.success(latencyMs: 30),
              proxyTestResult: ProxyTestResult.success(
                latencyMs: 100,
                statusCode: 204,
              ),
              qualityScore: 90,
              timestamp: DateTime.now(),
            ),
            ConfigTestResult(
              ip: '9.9.9.9',
              config: testConfig,
              tlsTestResult: TlsTestResult.success(latencyMs: 40),
              proxyTestResult: ProxyTestResult.failure(error: 'Failed'),
              qualityScore: 0,
              timestamp: DateTime.now(),
            ),
          ];

          final scanResult = ConfigScanResult.success(
            totalTested: 100,
            phase1Passed: 50,
            phase2Tested: 3,
            allResults: results,
            scanDuration: Duration(seconds: 120),
            templateConfig: testConfig,
          );

          expect(scanResult.totalTested, equals(100));
          expect(scanResult.phase1Passed, equals(50));
          expect(scanResult.phase2Tested, equals(3));
          expect(scanResult.workingIPCount, equals(2));
          expect(scanResult.workingIPs.length, equals(2));
          // Should be sorted by proxy latency: 8.8.8.8 (100ms) before 1.1.1.1 (200ms)
          expect(scanResult.workingIPs[0], equals('8.8.8.8'));
          expect(scanResult.workingIPs[1], equals('1.1.1.1'));
          expect(scanResult.isSuccess, isTrue);
        },
      );

      test('failure factory creates result with no working IPs', () {
        final results = [
          ConfigTestResult(
            ip: '1.1.1.1',
            config: testConfig,
            tlsTestResult: TlsTestResult.failure(error: 'Timeout'),
            qualityScore: 0,
            timestamp: DateTime.now(),
          ),
        ];

        final scanResult = ConfigScanResult.failure(
          totalTested: 100,
          phase1Passed: 0,
          phase2Tested: 0,
          allResults: results,
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        expect(scanResult.totalTested, equals(100));
        expect(scanResult.phase1Passed, equals(0));
        expect(scanResult.phase2Tested, equals(0));
        expect(scanResult.workingIPCount, equals(0));
        expect(scanResult.workingIPs, isEmpty);
        expect(scanResult.isSuccess, isFalse);
      });
    });

    group('Success rates', () {
      test('calculates phase 1 success rate correctly', () {
        final scanResult = ConfigScanResult.success(
          totalTested: 100,
          phase1Passed: 50,
          phase2Tested: 10,
          allResults: [],
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        expect(scanResult.phase1SuccessRate, equals(50.0));
      });

      test('calculates phase 2 success rate correctly', () {
        final results = [
          ConfigTestResult(
            ip: '1.1.1.1',
            config: testConfig,
            tlsTestResult: TlsTestResult.success(latencyMs: 50),
            proxyTestResult: ProxyTestResult.success(
              latencyMs: 200,
              statusCode: 204,
            ),
            qualityScore: 80,
            timestamp: DateTime.now(),
          ),
          ConfigTestResult(
            ip: '8.8.8.8',
            config: testConfig,
            tlsTestResult: TlsTestResult.success(latencyMs: 30),
            proxyTestResult: ProxyTestResult.failure(error: 'Failed'),
            qualityScore: 0,
            timestamp: DateTime.now(),
          ),
        ];

        final scanResult = ConfigScanResult.success(
          totalTested: 100,
          phase1Passed: 50,
          phase2Tested: 2,
          allResults: results,
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        expect(scanResult.phase2SuccessRate, equals(50.0)); // 1 out of 2
        expect(scanResult.workingIPCount, equals(1));
      });

      test('calculates overall success rate correctly', () {
        final results = [
          ConfigTestResult(
            ip: '1.1.1.1',
            config: testConfig,
            tlsTestResult: TlsTestResult.success(latencyMs: 50),
            proxyTestResult: ProxyTestResult.success(
              latencyMs: 200,
              statusCode: 204,
            ),
            qualityScore: 80,
            timestamp: DateTime.now(),
          ),
        ];

        final scanResult = ConfigScanResult.success(
          totalTested: 100,
          phase1Passed: 50,
          phase2Tested: 1,
          allResults: results,
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        expect(scanResult.overallSuccessRate, equals(1.0)); // 1 out of 100
      });

      test('handles zero total tested gracefully', () {
        final scanResult = ConfigScanResult.success(
          totalTested: 0,
          phase1Passed: 0,
          phase2Tested: 0,
          allResults: [],
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        expect(scanResult.phase1SuccessRate, equals(0.0));
        expect(scanResult.overallSuccessRate, equals(0.0));
      });
    });

    group('Average latencies', () {
      test('calculates average TLS latency for successful IPs', () {
        final results = [
          ConfigTestResult(
            ip: '1.1.1.1',
            config: testConfig,
            tlsTestResult: TlsTestResult.success(latencyMs: 100),
            qualityScore: 80,
            timestamp: DateTime.now(),
          ),
          ConfigTestResult(
            ip: '8.8.8.8',
            config: testConfig,
            tlsTestResult: TlsTestResult.success(latencyMs: 200),
            qualityScore: 70,
            timestamp: DateTime.now(),
          ),
          ConfigTestResult(
            ip: '9.9.9.9',
            config: testConfig,
            tlsTestResult: TlsTestResult.failure(error: 'Failed'),
            qualityScore: 0,
            timestamp: DateTime.now(),
          ),
        ];

        final scanResult = ConfigScanResult.success(
          totalTested: 100,
          phase1Passed: 2,
          phase2Tested: 0,
          allResults: results,
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        expect(scanResult.averageTlsLatency, equals(150.0)); // (100 + 200) / 2
      });

      test('calculates average proxy latency for working IPs', () {
        final results = [
          ConfigTestResult(
            ip: '1.1.1.1',
            config: testConfig,
            tlsTestResult: TlsTestResult.success(latencyMs: 50),
            proxyTestResult: ProxyTestResult.success(
              latencyMs: 100,
              statusCode: 204,
            ),
            qualityScore: 80,
            timestamp: DateTime.now(),
          ),
          ConfigTestResult(
            ip: '8.8.8.8',
            config: testConfig,
            tlsTestResult: TlsTestResult.success(latencyMs: 30),
            proxyTestResult: ProxyTestResult.success(
              latencyMs: 200,
              statusCode: 204,
            ),
            qualityScore: 70,
            timestamp: DateTime.now(),
          ),
        ];

        final scanResult = ConfigScanResult.success(
          totalTested: 100,
          phase1Passed: 2,
          phase2Tested: 2,
          allResults: results,
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        expect(
          scanResult.averageProxyLatency,
          equals(150.0),
        ); // (100 + 200) / 2
      });

      test('returns 0 for average latencies when no results', () {
        final scanResult = ConfigScanResult.success(
          totalTested: 0,
          phase1Passed: 0,
          phase2Tested: 0,
          allResults: [],
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        expect(scanResult.averageTlsLatency, equals(0.0));
        expect(scanResult.averageProxyLatency, equals(0.0));
      });
    });

    group('Helper methods', () {
      test('fastestIP returns fastest working IP', () {
        final results = [
          ConfigTestResult(
            ip: '1.1.1.1',
            config: testConfig,
            tlsTestResult: TlsTestResult.success(latencyMs: 50),
            proxyTestResult: ProxyTestResult.success(
              latencyMs: 200,
              statusCode: 204,
            ),
            qualityScore: 80,
            timestamp: DateTime.now(),
          ),
          ConfigTestResult(
            ip: '8.8.8.8',
            config: testConfig,
            tlsTestResult: TlsTestResult.success(latencyMs: 30),
            proxyTestResult: ProxyTestResult.success(
              latencyMs: 100,
              statusCode: 204,
            ),
            qualityScore: 90,
            timestamp: DateTime.now(),
          ),
        ];

        final scanResult = ConfigScanResult.success(
          totalTested: 100,
          phase1Passed: 2,
          phase2Tested: 2,
          allResults: results,
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        expect(scanResult.fastestIP, equals('8.8.8.8')); // 100ms < 200ms
      });

      test('fastestIP returns null when no working IPs', () {
        final scanResult = ConfigScanResult.failure(
          totalTested: 100,
          phase1Passed: 0,
          phase2Tested: 0,
          allResults: [],
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        expect(scanResult.fastestIP, isNull);
      });

      test('getResultForIP returns correct result', () {
        final result1 = ConfigTestResult(
          ip: '1.1.1.1',
          config: testConfig,
          tlsTestResult: TlsTestResult.success(latencyMs: 50),
          qualityScore: 80,
          timestamp: DateTime.now(),
        );

        final scanResult = ConfigScanResult.success(
          totalTested: 100,
          phase1Passed: 1,
          phase2Tested: 0,
          allResults: [result1],
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        final retrievedResult = scanResult.getResultForIP('1.1.1.1');
        expect(retrievedResult, isNotNull);
        expect(retrievedResult?.ip, equals('1.1.1.1'));
      });

      test('getResultForIP returns null for non-existent IP', () {
        final scanResult = ConfigScanResult.success(
          totalTested: 100,
          phase1Passed: 0,
          phase2Tested: 0,
          allResults: [],
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        expect(scanResult.getResultForIP('1.1.1.1'), isNull);
      });
    });

    group('Summary message', () {
      test('generates success summary message', () {
        final results = [
          ConfigTestResult(
            ip: '1.1.1.1',
            config: testConfig,
            tlsTestResult: TlsTestResult.success(latencyMs: 50),
            proxyTestResult: ProxyTestResult.success(
              latencyMs: 200,
              statusCode: 204,
            ),
            qualityScore: 80,
            timestamp: DateTime.now(),
          ),
        ];

        final scanResult = ConfigScanResult.success(
          totalTested: 100,
          phase1Passed: 50,
          phase2Tested: 10,
          allResults: results,
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        final message = scanResult.summaryMessage;
        expect(message, contains('Found 1 working IP'));
        expect(message, contains('100 tested'));
        expect(message, contains('Phase 1: 50/100'));
        expect(message, contains('Phase 2: 1/10'));
      });

      test('generates failure summary message', () {
        final scanResult = ConfigScanResult.failure(
          totalTested: 100,
          phase1Passed: 50,
          phase2Tested: 10,
          allResults: [],
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        final message = scanResult.summaryMessage;
        expect(message, contains('No working IPs found'));
        expect(message, contains('100'));
        expect(message, contains('50 passed TLS'));
        expect(message, contains('10 tested with proxy'));
      });

      test('uses plural form for multiple working IPs', () {
        final results = [
          ConfigTestResult(
            ip: '1.1.1.1',
            config: testConfig,
            proxyTestResult: ProxyTestResult.success(
              latencyMs: 200,
              statusCode: 204,
            ),
            qualityScore: 80,
            timestamp: DateTime.now(),
          ),
          ConfigTestResult(
            ip: '8.8.8.8',
            config: testConfig,
            proxyTestResult: ProxyTestResult.success(
              latencyMs: 100,
              statusCode: 204,
            ),
            qualityScore: 90,
            timestamp: DateTime.now(),
          ),
        ];

        final scanResult = ConfigScanResult.success(
          totalTested: 100,
          phase1Passed: 50,
          phase2Tested: 10,
          allResults: results,
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        expect(scanResult.summaryMessage, contains('2 working IPs'));
      });
    });

    group('toString', () {
      test('returns formatted string representation', () {
        final scanResult = ConfigScanResult.success(
          totalTested: 100,
          phase1Passed: 50,
          phase2Tested: 10,
          allResults: [],
          scanDuration: Duration(seconds: 120),
          templateConfig: testConfig,
        );

        final str = scanResult.toString();
        expect(str, contains('ConfigScanResult'));
        expect(str, contains('totalTested: 100'));
        expect(str, contains('phase1Passed: 50'));
        expect(str, contains('phase2Tested: 10'));
        expect(str, contains('workingIPCount: 0'));
        expect(str, contains('scanDuration'));
      });
    });

    group('Edge cases', () {
      test('counts successful non-204 proxy responses as working', () {
        final results = [
          ConfigTestResult(
            ip: '1.1.1.1',
            config: testConfig,
            tlsTestResult: TlsTestResult.success(latencyMs: 50),
            proxyTestResult: ProxyTestResult.success(
              latencyMs: 200,
              statusCode: 200, // Successful and should count as working
            ),
            qualityScore: 80,
            timestamp: DateTime.now(),
          ),
        ];

        final scanResult = ConfigScanResult.success(
          totalTested: 100,
          phase1Passed: 1,
          phase2Tested: 1,
          allResults: results,
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        // Any successful proxy response now counts as working.
        expect(scanResult.workingIPCount, equals(1));
        expect(scanResult.workingIPs, equals(['1.1.1.1']));
      });

      test('handles mixed success and failure proxy results', () {
        final results = [
          ConfigTestResult(
            ip: '1.1.1.1',
            config: testConfig,
            proxyTestResult: ProxyTestResult.success(
              latencyMs: 200,
              statusCode: 204,
            ),
            qualityScore: 80,
            timestamp: DateTime.now(),
          ),
          ConfigTestResult(
            ip: '8.8.8.8',
            config: testConfig,
            proxyTestResult: ProxyTestResult.failure(error: 'Timeout'),
            qualityScore: 0,
            timestamp: DateTime.now(),
          ),
          ConfigTestResult(
            ip: '9.9.9.9',
            config: testConfig,
            proxyTestResult: ProxyTestResult.success(
              latencyMs: 100,
              statusCode: 204,
            ),
            qualityScore: 90,
            timestamp: DateTime.now(),
          ),
        ];

        final scanResult = ConfigScanResult.success(
          totalTested: 100,
          phase1Passed: 3,
          phase2Tested: 3,
          allResults: results,
          scanDuration: Duration(seconds: 60),
          templateConfig: testConfig,
        );

        expect(scanResult.workingIPCount, equals(2));
        expect(scanResult.workingIPs, containsAll(['1.1.1.1', '9.9.9.9']));
        // Sorted by latency: 9.9.9.9 (100ms) before 1.1.1.1 (200ms)
        expect(scanResult.workingIPs[0], equals('9.9.9.9'));
      });
    });
  });
}
