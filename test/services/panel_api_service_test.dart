import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bpb_automation/models/panel_credentials.dart';
import 'package:bpb_automation/services/panel_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PanelApiService service;
  const credentials = PanelCredentials(
    baseUrl: 'https://example.workers.dev',
    password: 'test-password',
  );

  setUp(() {
    service = PanelApiService.instance;
    service.clearSession();
  });

  group('PanelApiService', () {
    test(
      'validateCredentials returns true for valid panel auth and settings',
      () async {
        final mockClient = MockClient((request) async {
          if (request.url.path == '/login/authenticate') {
            return http.Response(
              jsonEncode({'success': true, 'status': 200, 'body': null}),
              200,
              headers: {'set-cookie': 'jwtToken=test123; Path=/; HttpOnly'},
            );
          }

          if (request.url.path == '/panel/settings') {
            expect(
              request.headers['Cookie'] ?? request.headers['cookie'],
              equals('jwtToken=test123'),
            );
            return http.Response(
              jsonEncode({
                'success': true,
                'status': 200,
                'body': {
                  'proxySettings': {
                    'cleanIPs': ['1.1.1.1'],
                  },
                },
              }),
              200,
            );
          }

          return http.Response('not found', 404);
        });

        service.setClient(mockClient);
        final result = await service.validateCredentials(credentials);

        expect(result, isTrue);
      },
    );

    test(
      'updateCleanIPs replaces cleanIPs and calls update endpoint',
      () async {
        int settingsReads = 0;
        bool updateCalled = false;

        final mockClient = MockClient((request) async {
          if (request.url.path == '/login/authenticate') {
            return http.Response(
              jsonEncode({'success': true, 'status': 200, 'body': null}),
              200,
              headers: {'set-cookie': 'jwtToken=test123; Path=/; HttpOnly'},
            );
          }

          if (request.url.path == '/panel/settings') {
            settingsReads++;
            return http.Response(
              jsonEncode({
                'success': true,
                'status': 200,
                'body': {
                  'proxySettings': {
                    'cleanIPs': ['1.1.1.1'],
                    'remoteDNS': 'https://1.1.1.1/dns-query',
                  },
                },
              }),
              200,
            );
          }

          if (request.url.path == '/panel/update-settings') {
            updateCalled = true;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['cleanIPs'], equals(['2.2.2.2', '3.3.3.3']));
            expect(body['remoteDNS'], equals('https://1.1.1.1/dns-query'));
            return http.Response(
              jsonEncode({'success': true, 'status': 200, 'body': body}),
              200,
            );
          }

          return http.Response('not found', 404);
        });

        service.setClient(mockClient);
        final result = await service.updateCleanIPs(credentials, [
          '2.2.2.2',
          '3.3.3.3',
        ]);

        expect(result, isTrue);
        expect(settingsReads, equals(1));
        expect(updateCalled, isTrue);
      },
    );

    test('updateCleanIPs retries once when session is expired', () async {
      int loginCalls = 0;
      int settingsCalls = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/login/authenticate') {
          loginCalls++;
          return http.Response(
            jsonEncode({'success': true, 'status': 200, 'body': null}),
            200,
            headers: {
              'set-cookie': 'jwtToken=test$loginCalls; Path=/; HttpOnly',
            },
          );
        }

        if (request.url.path == '/panel/settings') {
          settingsCalls++;
          if (settingsCalls == 1) {
            return http.Response(
              jsonEncode({
                'success': false,
                'status': 401,
                'message': 'Unauthorized',
              }),
              401,
            );
          }

          return http.Response(
            jsonEncode({
              'success': true,
              'status': 200,
              'body': {
                'proxySettings': {
                  'cleanIPs': ['1.1.1.1'],
                },
              },
            }),
            200,
          );
        }

        if (request.url.path == '/panel/update-settings') {
          return http.Response(
            jsonEncode({'success': true, 'status': 200, 'body': {}}),
            200,
          );
        }

        return http.Response('not found', 404);
      });

      service.setClient(mockClient);
      final result = await service.updateCleanIPs(credentials, ['4.4.4.4']);

      expect(result, isTrue);
      expect(loginCalls, equals(2));
      expect(settingsCalls, equals(2));
    });

    test('fetchNormalSubscriptionUrl returns URL built from subPath', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/login/authenticate') {
          return http.Response(
            jsonEncode({'success': true, 'status': 200, 'body': null}),
            200,
            headers: {'set-cookie': 'jwtToken=test123; Path=/; HttpOnly'},
          );
        }

        if (request.url.path == '/panel/settings') {
          return http.Response(
            jsonEncode({
              'success': true,
              'status': 200,
              'body': {
                'subPath': 'abc123',
                'proxySettings': {
                  'cleanIPs': ['1.1.1.1'],
                },
              },
            }),
            200,
          );
        }

        return http.Response('not found', 404);
      });

      service.setClient(mockClient);
      final url = await service.fetchNormalSubscriptionUrl(credentials);
      expect(
        url,
        equals('https://example.workers.dev/sub/normal/abc123?app=xray'),
      );
    });

    test(
      'fetchNormalSubscriptionUrl returns null when subPath missing',
      () async {
        final mockClient = MockClient((request) async {
          if (request.url.path == '/login/authenticate') {
            return http.Response(
              jsonEncode({'success': true, 'status': 200, 'body': null}),
              200,
              headers: {'set-cookie': 'jwtToken=test123; Path=/; HttpOnly'},
            );
          }

          if (request.url.path == '/panel/settings') {
            return http.Response(
              jsonEncode({
                'success': true,
                'status': 200,
                'body': {
                  'proxySettings': {
                    'cleanIPs': ['1.1.1.1'],
                  },
                },
              }),
              200,
            );
          }

          return http.Response('not found', 404);
        });

        service.setClient(mockClient);
        final url = await service.fetchNormalSubscriptionUrl(credentials);
        expect(url, isNull);
      },
    );
  });
}
