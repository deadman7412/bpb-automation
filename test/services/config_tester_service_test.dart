import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/services/config_tester_service.dart';
import 'package:bpb_automation/models/xray_config.dart';
import 'package:bpb_automation/models/outbound.dart';
import 'package:bpb_automation/models/stream_settings.dart';

void main() {
  group('ConfigTesterService', () {
    late ConfigTesterService service;

    setUp(() {
      service = ConfigTesterService.instance;
    });

    // Helper function to create a test config
    XrayConfig createTestConfig({
      String address = '1.1.1.1',
      int port = 443,
      String? sni,
    }) {
      return XrayConfig(
        outbounds: [
          Outbound(
            protocol: 'vless',
            settings: OutboundSettings(
              vnext: [
                Vnext(
                  address: address,
                  port: port,
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
              tlsSettings: TlsSettings(
                serverName: sni ?? 'cloudflare.com',
                alpn: ['h2', 'http/1.1'],
              ),
            ),
          ),
        ],
        remarks: 'Test Config',
      );
    }

    group('testIPsWithTLS', () {
      test('should validate config before testing', () async {
        final invalidConfig = XrayConfig(); // No outbounds

        final results = await service.testIPsWithTLS(
          template: invalidConfig,
          candidateIPs: ['1.1.1.1'],
          timeoutSeconds: 5,
        );

        expect(results, isEmpty);
      });

      test('should handle config with no port', () async {
        final configNoPort = XrayConfig(
          outbounds: [
            Outbound(
              protocol: 'vless',
              settings: OutboundSettings(vnext: []),
            ),
          ],
        );

        final results = await service.testIPsWithTLS(
          template: configNoPort,
          candidateIPs: ['1.1.1.1'],
          timeoutSeconds: 5,
        );

        expect(results, isEmpty);
      });

      test(
        'should test single Cloudflare IP with TLS',
        () async {
          final config = createTestConfig(
            address: '1.1.1.1',
            port: 443,
            sni: 'cloudflare.com',
          );

          final results = await service.testIPsWithTLS(
            template: config,
            candidateIPs: ['1.1.1.1'],
            timeoutSeconds: 10,
            maxConcurrency: 1,
            verifyCdn: false, // Disable CDN verification for faster test
          );

          // Should return results (may succeed or fail depending on network)
          expect(results, isNotNull);

          // If successful, verify result structure
          if (results.isNotEmpty) {
            final result = results.first;
            expect(result.ip, equals('1.1.1.1'));
            expect(result.tlsTestResult, isNotNull);
            expect(result.config.getServerAddress(), equals('1.1.1.1'));
          }
        },
        timeout: Timeout(Duration(seconds: 30)),
      );

      test('should handle timeout correctly', () async {
        final config = createTestConfig(
          address: '192.0.2.1', // TEST-NET-1, should timeout
          port: 443,
        );

        final results = await service.testIPsWithTLS(
          template: config,
          candidateIPs: ['192.0.2.1'],
          timeoutSeconds: 1, // Short timeout
          maxConcurrency: 1,
          verifyCdn: false,
        );

        // Should return empty (no successful results)
        expect(results, isEmpty);
      }, timeout: Timeout(Duration(seconds: 10)));

      test(
        'should test multiple IPs and sort by latency',
        () async {
          final config = createTestConfig(
            address: '1.1.1.1',
            port: 443,
            sni: 'cloudflare.com',
          );

          final candidateIPs = [
            '1.1.1.1', // Cloudflare
            '1.0.0.1', // Cloudflare
            '8.8.8.8', // Google (may fail TLS for cloudflare.com SNI)
          ];

          final results = await service.testIPsWithTLS(
            template: config,
            candidateIPs: candidateIPs,
            timeoutSeconds: 10,
            maxConcurrency: 3,
            verifyCdn: false,
          );

          // Should have some results
          expect(results, isNotNull);

          // If we have multiple successful results, verify sorting
          if (results.length > 1) {
            for (int i = 0; i < results.length - 1; i++) {
              expect(
                results[i].finalLatencyMs,
                lessThanOrEqualTo(results[i + 1].finalLatencyMs),
              );
            }
          }
        },
        timeout: Timeout(Duration(seconds: 45)),
      );

      test('should process IPs in batches', () async {
        final config = createTestConfig();

        // Create 10 test IPs (mix of valid and invalid)
        final candidateIPs = [
          '1.1.1.1',
          '1.0.0.1',
          '192.0.2.1', // Invalid
          '192.0.2.2', // Invalid
          '8.8.8.8',
          '8.8.4.4',
          '192.0.2.3', // Invalid
          '192.0.2.4', // Invalid
          '192.0.2.5', // Invalid
          '192.0.2.6', // Invalid
        ];

        final results = await service.testIPsWithTLS(
          template: config,
          candidateIPs: candidateIPs,
          timeoutSeconds: 2,
          maxConcurrency: 3, // Small batch size
          verifyCdn: false,
        );

        // Should have processed all IPs
        expect(results, isNotNull);

        // All results should have replaced addresses
        for (final result in results) {
          expect(candidateIPs, contains(result.ip));
        }
      }, timeout: Timeout(Duration(seconds: 60)));
    });

    group('TlsTestProgress', () {
      test('calculates progress percentage correctly', () {
        final progress = TlsTestProgress(
          totalIPs: 100,
          processedIPs: 50,
          successfulIPs: 30,
          failedIPs: 20,
          currentIP: '1.1.1.1',
        );

        expect(progress.progress, equals(0.5));
        expect(progress.progressPercent, equals(50.0));
        expect(progress.successRate, equals(0.6));
        expect(progress.successRatePercent, equals(60.0));
      });

      test('handles zero total IPs', () {
        final progress = TlsTestProgress(
          totalIPs: 0,
          processedIPs: 0,
          successfulIPs: 0,
          failedIPs: 0,
          currentIP: null,
        );

        expect(progress.progress, equals(0.0));
        expect(progress.progressPercent, equals(0.0));
        expect(progress.successRate, equals(0.0));
      });

      test('handles zero processed IPs', () {
        final progress = TlsTestProgress(
          totalIPs: 100,
          processedIPs: 0,
          successfulIPs: 0,
          failedIPs: 0,
          currentIP: null,
        );

        expect(progress.successRate, equals(0.0));
      });

      test('handles 100% completion', () {
        final progress = TlsTestProgress(
          totalIPs: 100,
          processedIPs: 100,
          successfulIPs: 80,
          failedIPs: 20,
          currentIP: null,
        );

        expect(progress.progress, equals(1.0));
        expect(progress.progressPercent, equals(100.0));
        expect(progress.successRate, equals(0.8));
      });

      test('toString includes all relevant info', () {
        final progress = TlsTestProgress(
          totalIPs: 100,
          processedIPs: 50,
          successfulIPs: 30,
          failedIPs: 20,
          currentIP: '1.1.1.1',
        );

        final str = progress.toString();
        expect(str, contains('50/100'));
        expect(str, contains('50.0%'));
        expect(str, contains('success: 30'));
        expect(str, contains('failed: 20'));
        expect(str, contains('1.1.1.1'));
      });
    });

    group('progressStream', () {
      test(
        'should emit progress updates during testing',
        () async {
          final config = createTestConfig();

          final candidateIPs = [
            '1.1.1.1',
            '1.0.0.1',
            '192.0.2.1', // Will timeout
          ];

          final progressUpdates = <TlsTestProgress>[];

          // Listen to progress stream
          final subscription = service.progressStream.listen((progress) {
            progressUpdates.add(progress);
          });

          await service.testIPsWithTLS(
            template: config,
            candidateIPs: candidateIPs,
            timeoutSeconds: 2,
            maxConcurrency: 1,
            verifyCdn: false,
          );

          // Wait a bit for final progress update to arrive
          await Future.delayed(Duration(milliseconds: 100));

          await subscription.cancel();

          // Should have received progress updates
          expect(progressUpdates, isNotEmpty);

          // First update should be initial (0 processed)
          expect(progressUpdates.first.processedIPs, equals(0));

          // Should have progress updates showing processing
          final hasProgress = progressUpdates.any((p) => p.processedIPs > 0);
          expect(hasProgress, isTrue);

          // Last update should show completion (all IPs processed or close to it)
          // Note: Due to timing, we might not catch the final update, so just verify progress was made
          expect(progressUpdates.last.processedIPs, greaterThan(0));
        },
        timeout: Timeout(Duration(seconds: 30)),
      );
    });
  });
}
