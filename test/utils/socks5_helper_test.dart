import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/utils/socks5_helper.dart';

void main() {
  group('Socks5Helper', () {
    group('connectViaSocks5', () {
      test(
        'should throw SocketException when proxy is not available',
        () async {
          // Try to connect to a port that's not listening
          await expectLater(
            Socks5Helper.connectViaSocks5(
              socksHost: '127.0.0.1',
              socksPort: 65432, // Random high port, unlikely to be in use
              targetHost: 'www.gstatic.com',
              targetPort: 80,
              timeout: 2,
            ),
            throwsA(isA<SocketException>()),
          );
        },
      );

      test('should throw when connection times out', () async {
        // Try to connect to unreachable host with very short timeout
        await expectLater(
          Socks5Helper.connectViaSocks5(
            socksHost: '192.0.2.1', // TEST-NET-1, guaranteed to not respond
            socksPort: 1080,
            targetHost: 'www.gstatic.com',
            targetPort: 80,
            timeout: 1,
          ),
          throwsA(anyOf(isA<SocketException>(), isA<TimeoutException>())),
        );
      });

      test(
        'should accept valid parameters without throwing immediately',
        () async {
          // Just test that the function accepts valid parameters and throws when connection fails
          // We can't test actual connection without a SOCKS5 proxy running
          await expectLater(
            Socks5Helper.connectViaSocks5(
              socksHost: '127.0.0.1',
              socksPort: 1080,
              targetHost: 'www.gstatic.com',
              targetPort: 80,
              timeout: 1,
            ),
            throwsA(isA<SocketException>()),
          );
        },
      );
    });

    group('Socks5Exception', () {
      test('should have correct message', () {
        final exception = Socks5Exception('Test error');

        expect(exception.message, equals('Test error'));
        expect(exception.toString(), equals('Socks5Exception: Test error'));
      });

      test('should be throwable and catchable', () {
        expect(
          () => throw Socks5Exception('Test error'),
          throwsA(
            isA<Socks5Exception>().having(
              (e) => e.message,
              'message',
              'Test error',
            ),
          ),
        );
      });
    });

    group('Integration scenarios', () {
      test('should handle invalid IPv4 addresses gracefully', () async {
        // This will likely fail at connection time, but shouldn't crash
        await expectLater(
          Socks5Helper.connectViaSocks5(
            socksHost: '999.999.999.999', // Invalid IP
            socksPort: 1080,
            targetHost: 'www.gstatic.com',
            targetPort: 80,
            timeout: 1,
          ),
          throwsA(isA<SocketException>()),
        );
      });

      test('should handle zero timeout gracefully', () async {
        await expectLater(
          Socks5Helper.connectViaSocks5(
            socksHost: '127.0.0.1',
            socksPort: 65432,
            targetHost: 'www.gstatic.com',
            targetPort: 80,
            timeout: 0,
          ),
          throwsA(isA<Exception>()),
        );
      });

      test('should handle various target ports', () async {
        // Test that different ports are accepted
        final results = await Future.wait(
          [80, 443, 8080, 3128].map((port) async {
            try {
              await Socks5Helper.connectViaSocks5(
                socksHost: '127.0.0.1',
                socksPort: 65432,
                targetHost: 'www.gstatic.com',
                targetPort: port,
                timeout: 1,
              );
              return false;
            } catch (e) {
              // Expected to fail since no proxy is running
              return true;
            }
          }),
        );

        // All should throw exceptions
        expect(results.every((failed) => failed), isTrue);
      });
    });
  });
}
