import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bpb_automation/services/cloudflare_api_service.dart';
import 'package:bpb_automation/services/log_service.dart';
import 'package:bpb_automation/models/credentials.dart';
import 'package:bpb_automation/models/proxy_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CloudflareApiService apiService;
  late LogService logService;
  late Credentials testCredentials;

  setUp(() {
    apiService = CloudflareApiService.instance;
    logService = LogService.instance;
    logService.clearLogs();

    testCredentials = Credentials(
      apiToken: 'test_token_1234567890abcdefghijklmnopqrstuvwxyz',
      accountId: 'account_1234567890abcdefghij',
      kvNamespaceId: 'namespace_1234567890abcdefghij',
    );
  });

  group('CloudflareApiService', () {
    group('Singleton', () {
      test('returns same instance', () {
        final instance1 = CloudflareApiService.instance;
        final instance2 = CloudflareApiService.instance;

        expect(instance1, equals(instance2));
        expect(identical(instance1, instance2), isTrue);
      });
    });

    group('Authentication', () {
      test('buildHeaders creates correct authorization header', () async {
        final mockClient = MockClient((request) async {
          // Verify headers
          expect(request.headers['Authorization'], contains('Bearer test_token_'));
          expect(request.headers['Content-Type'], equals('application/json'));

          return http.Response('{"success":true}', 200);
        });

        apiService.setClient(mockClient);

        // Trigger a request to check headers
        await apiService.validateCredentials(testCredentials);
      });

      test('validateCredentials returns true for valid credentials', () async {
        final mockClient = MockClient((request) async {
          if (request.url.path.contains('/storage/kv/namespaces/')) {
            return http.Response('{"success":true}', 200);
          }
          return http.Response('Not found', 404);
        });

        apiService.setClient(mockClient);

        final result = await apiService.validateCredentials(testCredentials);

        expect(result, isTrue);
      });

      test('validateCredentials returns false for 401 unauthorized', () async {
        final mockClient = MockClient((request) async {
          return http.Response('{"success":false,"errors":[{"message":"Invalid token"}]}', 401);
        });

        apiService.setClient(mockClient);

        final result = await apiService.validateCredentials(testCredentials);

        expect(result, isFalse);
      });

      test('validateCredentials returns false for 403 forbidden', () async {
        final mockClient = MockClient((request) async {
          return http.Response('{"success":false,"errors":[{"message":"Forbidden"}]}', 403);
        });

        apiService.setClient(mockClient);

        final result = await apiService.validateCredentials(testCredentials);

        expect(result, isFalse);
      });

      test('validateCredentials returns false for 404 not found', () async {
        final mockClient = MockClient((request) async {
          return http.Response('{"success":false,"errors":[{"message":"Not found"}]}', 404);
        });

        apiService.setClient(mockClient);

        final result = await apiService.validateCredentials(testCredentials);

        expect(result, isFalse);
      });

      test('validateCredentials returns false for invalid credential format', () async {
        final invalidCredentials = Credentials(
          apiToken: '', // Empty token
          accountId: 'account_123',
          kvNamespaceId: 'namespace_456',
        );

        final result = await apiService.validateCredentials(invalidCredentials);

        expect(result, isFalse);
      });

      test('validateCredentials handles network errors', () async {
        final mockClient = MockClient((request) async {
          throw Exception('Network error');
        });

        apiService.setClient(mockClient);

        final result = await apiService.validateCredentials(testCredentials);

        expect(result, isFalse);
      });
    });

    group('KV Read Operations', () {
      test('getProxySettings returns settings for valid response', () async {
        final testSettings = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {'cloudflare-dns.com': '104.16.132.229'},
          localDNS: '8.8.8.8,8.8.4.4',
          cleanIPs: ['1.1.1.1', '1.0.0.1'],
          proxyIPs: [],
          outProxyParams: {},
        );

        final mockClient = MockClient((request) async {
          if (request.url.path.contains('/values/proxySettings')) {
            return http.Response(jsonEncode(testSettings.toJson()), 200);
          }
          return http.Response('Not found', 404);
        });

        apiService.setClient(mockClient);

        final result = await apiService.getProxySettings(testCredentials);

        expect(result, isNotNull);
        expect(result!.cleanIPs.length, equals(2));
        expect(result.cleanIPs[0], equals('1.1.1.1'));
      });

      test('getProxySettings returns null for 404', () async {
        final mockClient = MockClient((request) async {
          return http.Response('{"success":false}', 404);
        });

        apiService.setClient(mockClient);

        final result = await apiService.getProxySettings(testCredentials);

        expect(result, isNull);
      });

      test('getProxySettings throws CloudflareApiException for 401', () async {
        final mockClient = MockClient((request) async {
          return http.Response('{"success":false}', 401);
        });

        apiService.setClient(mockClient);

        expect(
          () => apiService.getProxySettings(testCredentials),
          throwsA(isA<CloudflareApiException>()),
        );
      });

      test('getProxySettings throws CloudflareApiException for 403', () async {
        final mockClient = MockClient((request) async {
          return http.Response('{"success":false}', 403);
        });

        apiService.setClient(mockClient);

        expect(
          () => apiService.getProxySettings(testCredentials),
          throwsA(isA<CloudflareApiException>()),
        );
      });

      test('getProxySettings throws exception for invalid JSON', () async {
        final mockClient = MockClient((request) async {
          return http.Response('invalid json', 200);
        });

        apiService.setClient(mockClient);

        expect(
          () => apiService.getProxySettings(testCredentials),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('KV Write Operations', () {
      test('updateCleanIPs successfully updates IPs', () async {
        final testSettings = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {'cloudflare-dns.com': '104.16.132.229'},
          localDNS: '8.8.8.8,8.8.4.4',
          cleanIPs: ['1.1.1.1'],
          proxyIPs: [],
          outProxyParams: {},
        );

        final mockClient = MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(jsonEncode(testSettings.toJson()), 200);
          } else if (request.method == 'PUT') {
            // Verify the updated settings
            final body = jsonDecode(request.body);
            expect(body['cleanIPs'], equals(['2.2.2.2', '3.3.3.3']));
            return http.Response('{"success":true}', 200);
          }
          return http.Response('Not found', 404);
        });

        apiService.setClient(mockClient);

        final result = await apiService.updateCleanIPs(
          testCredentials,
          ['2.2.2.2', '3.3.3.3'],
        );

        expect(result, isTrue);
      });

      test('updateCleanIPs preserves other fields', () async {
        final testSettings = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {'cloudflare-dns.com': '104.16.132.229'},
          localDNS: '8.8.8.8,8.8.4.4',
          cleanIPs: ['1.1.1.1'],
          proxyIPs: ['5.5.5.5'],
          outProxyParams: {'key': 'value'},
        );

        final mockClient = MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(jsonEncode(testSettings.toJson()), 200);
          } else if (request.method == 'PUT') {
            final body = jsonDecode(request.body);
            // Verify other fields are preserved
            expect(body['remoteDNS'], equals('https://8.8.8.8/dns-query'));
            expect(body['localDNS'], equals('8.8.8.8,8.8.4.4'));
            expect(body['proxyIPs'], equals(['5.5.5.5']));
            expect(body['outProxyParams'], equals({'key': 'value'}));
            return http.Response('{"success":true}', 200);
          }
          return http.Response('Not found', 404);
        });

        apiService.setClient(mockClient);

        final result = await apiService.updateCleanIPs(
          testCredentials,
          ['2.2.2.2'],
        );

        expect(result, isTrue);
      });

      test('updateCleanIPs throws exception if settings not found', () async {
        final mockClient = MockClient((request) async {
          return http.Response('{"success":false}', 404);
        });

        apiService.setClient(mockClient);

        expect(
          () => apiService.updateCleanIPs(testCredentials, ['1.1.1.1']),
          throwsA(isA<CloudflareApiException>()),
        );
      });

      test('updateCleanIPs throws exception for PUT failure', () async {
        final testSettings = ProxySettings(
          remoteDNS: 'https://8.8.8.8/dns-query',
          remoteDnsHost: {},
          localDNS: '8.8.8.8',
          cleanIPs: ['1.1.1.1'],
          proxyIPs: [],
          outProxyParams: {},
        );

        final mockClient = MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(jsonEncode(testSettings.toJson()), 200);
          } else if (request.method == 'PUT') {
            return http.Response('{"success":false}', 500);
          }
          return http.Response('Not found', 404);
        });

        apiService.setClient(mockClient);

        expect(
          () => apiService.updateCleanIPs(testCredentials, ['2.2.2.2']),
          throwsA(isA<CloudflareApiException>()),
        );
      });
    });

    group('Connection Testing', () {
      test('testConnection returns true for reachable API', () async {
        final mockClient = MockClient((request) async {
          return http.Response('{"success":true}', 200);
        });

        apiService.setClient(mockClient);

        final result = await apiService.testConnection();

        expect(result, isTrue);
      });

      test('testConnection returns true even for 401 (proves connectivity)', () async {
        final mockClient = MockClient((request) async {
          return http.Response('{"success":false}', 401);
        });

        apiService.setClient(mockClient);

        final result = await apiService.testConnection();

        expect(result, isTrue);
      });

      test('testConnection returns false for network error', () async {
        final mockClient = MockClient((request) async {
          throw Exception('Network unreachable');
        });

        apiService.setClient(mockClient);

        final result = await apiService.testConnection();

        expect(result, isFalse);
      });
    });

    group('Error Handling', () {
      test('CloudflareApiException has correct message and status code', () {
        final exception = CloudflareApiException('Test error', 500);

        expect(exception.message, equals('Test error'));
        expect(exception.statusCode, equals(500));
        expect(
          exception.toString(),
          equals('CloudflareApiException: Test error (status: 500)'),
        );
      });
    });

    group('Service Structure', () {
      test('service has correct type', () {
        expect(apiService, isA<CloudflareApiService>());
      });

      test('service instance is not null', () {
        expect(apiService, isNotNull);
      });

      test('singleton pattern works correctly', () {
        final instance = CloudflareApiService.instance;
        expect(instance, same(apiService));
      });
    });
  });
}
