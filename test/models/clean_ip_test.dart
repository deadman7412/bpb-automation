import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/clean_ip.dart';

void main() {
  group('CleanIP', () {
    group('Constructor', () {
      test('creates instance with valid data', () {
        final ip = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 45.2,
          downloadSpeed: 12.5,
        );

        expect(ip.ip, equals('1.1.1.1'));
        expect(ip.packetsSent, equals(10));
        expect(ip.packetsReceived, equals(10));
        expect(ip.lossRate, equals(0.0));
        expect(ip.avgLatency, equals(45.2));
        expect(ip.downloadSpeed, equals(12.5));
      });
    });

    group('fromJson', () {
      test('creates instance from valid JSON', () {
        final json = {
          'ip': '1.1.1.1',
          'packets_sent': 10,
          'packets_received': 10,
          'loss_rate': 0.0,
          'avg_latency': 45.2,
          'download_speed': 12.5,
        };

        final ip = CleanIP.fromJson(json);

        expect(ip.ip, equals('1.1.1.1'));
        expect(ip.packetsSent, equals(10));
        expect(ip.packetsReceived, equals(10));
        expect(ip.lossRate, equals(0.0));
        expect(ip.avgLatency, equals(45.2));
        expect(ip.downloadSpeed, equals(12.5));
      });

      test('handles integer values for double fields', () {
        final json = {
          'ip': '1.1.1.1',
          'packets_sent': 10,
          'packets_received': 10,
          'loss_rate': 0, // int instead of double
          'avg_latency': 45, // int instead of double
          'download_speed': 12, // int instead of double
        };

        final ip = CleanIP.fromJson(json);

        expect(ip.lossRate, equals(0.0));
        expect(ip.avgLatency, equals(45.0));
        expect(ip.downloadSpeed, equals(12.0));
      });

      test('handles IPv6 addresses', () {
        final json = {
          'ip': '2606:4700:4700::1111',
          'packets_sent': 10,
          'packets_received': 10,
          'loss_rate': 0.0,
          'avg_latency': 45.2,
          'download_speed': 12.5,
        };

        final ip = CleanIP.fromJson(json);
        expect(ip.ip, equals('2606:4700:4700::1111'));
      });
    });

    group('toJson', () {
      test('converts instance to JSON correctly', () {
        final ip = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 45.2,
          downloadSpeed: 12.5,
        );

        final json = ip.toJson();

        expect(json['ip'], equals('1.1.1.1'));
        expect(json['packets_sent'], equals(10));
        expect(json['packets_received'], equals(10));
        expect(json['loss_rate'], equals(0.0));
        expect(json['avg_latency'], equals(45.2));
        expect(json['download_speed'], equals(12.5));
      });

      test('round-trip JSON serialization preserves data', () {
        final original = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 9,
          lossRate: 10.0,
          avgLatency: 45.2,
          downloadSpeed: 12.5,
        );

        final json = original.toJson();
        final restored = CleanIP.fromJson(json);

        expect(restored, equals(original));
      });
    });

    group('fromCsvRow', () {
      test('parses valid CSV row', () {
        final row = ['1.1.1.1', '10', '10', '0%', '45.2ms', '12.5MB/s'];
        final ip = CleanIP.fromCsvRow(row);

        expect(ip.ip, equals('1.1.1.1'));
        expect(ip.packetsSent, equals(10));
        expect(ip.packetsReceived, equals(10));
        expect(ip.lossRate, equals(0.0));
        expect(ip.avgLatency, equals(45.2));
        expect(ip.downloadSpeed, equals(12.5));
      });

      test('handles CSV row with whitespace', () {
        final row = [
          ' 1.1.1.1 ',
          ' 10 ',
          ' 10 ',
          ' 0% ',
          ' 45.2ms ',
          ' 12.5MB/s '
        ];
        final ip = CleanIP.fromCsvRow(row);

        expect(ip.ip, equals('1.1.1.1'));
        expect(ip.packetsSent, equals(10));
      });

      test('parses row with packet loss', () {
        final row = ['1.1.1.1', '10', '9', '10%', '45.2ms', '12.5MB/s'];
        final ip = CleanIP.fromCsvRow(row);

        expect(ip.packetsReceived, equals(9));
        expect(ip.lossRate, equals(10.0));
      });

      test('throws on invalid row length', () {
        final row = ['1.1.1.1', '10', '10']; // Too few columns

        expect(
          () => CleanIP.fromCsvRow(row),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws on invalid number format', () {
        final row = ['1.1.1.1', 'invalid', '10', '0%', '45.2ms', '12.5MB/s'];

        expect(
          () => CleanIP.fromCsvRow(row),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('isAcceptable', () {
      test('returns true for good quality IP', () {
        final ip = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 45.2,
          downloadSpeed: 12.5,
        );

        expect(ip.isAcceptable(), isTrue);
      });

      test('returns false for high packet loss', () {
        final ip = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 5,
          lossRate: 50.0,
          avgLatency: 45.2,
          downloadSpeed: 12.5,
        );

        expect(ip.isAcceptable(), isFalse);
      });

      test('returns false for high latency', () {
        final ip = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 350.0,
          downloadSpeed: 12.5,
        );

        expect(ip.isAcceptable(), isFalse);
      });

      test('returns true for edge case (4.9% loss, 299ms latency)', () {
        final ip = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 9,
          lossRate: 4.9,
          avgLatency: 299.0,
          downloadSpeed: 12.5,
        );

        expect(ip.isAcceptable(), isTrue);
      });
    });

    group('isPerfect', () {
      test('returns true for zero packet loss', () {
        final ip = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 45.2,
          downloadSpeed: 12.5,
        );

        expect(ip.isPerfect(), isTrue);
      });

      test('returns false for any packet loss', () {
        final ip = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 9,
          lossRate: 10.0,
          avgLatency: 45.2,
          downloadSpeed: 12.5,
        );

        expect(ip.isPerfect(), isFalse);
      });
    });

    group('compareQuality', () {
      test('prefers lower latency', () {
        final ip1 = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 40.0,
          downloadSpeed: 10.0,
        );

        final ip2 = CleanIP(
          ip: '1.1.1.2',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 50.0,
          downloadSpeed: 15.0, // Higher speed but higher latency
        );

        expect(ip1.compareQuality(ip2), lessThan(0)); // ip1 is better
      });

      test('prefers lower loss rate when latency is equal', () {
        final ip1 = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 40.0,
          downloadSpeed: 10.0,
        );

        final ip2 = CleanIP(
          ip: '1.1.1.2',
          packetsSent: 10,
          packetsReceived: 9,
          lossRate: 10.0,
          avgLatency: 40.0,
          downloadSpeed: 15.0,
        );

        expect(ip1.compareQuality(ip2), lessThan(0)); // ip1 is better
      });

      test('prefers higher speed when latency and loss are equal', () {
        final ip1 = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 40.0,
          downloadSpeed: 15.0,
        );

        final ip2 = CleanIP(
          ip: '1.1.1.2',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 40.0,
          downloadSpeed: 10.0,
        );

        expect(ip1.compareQuality(ip2), lessThan(0)); // ip1 is better
      });

      test('returns 0 for identical quality', () {
        final ip1 = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 40.0,
          downloadSpeed: 10.0,
        );

        final ip2 = CleanIP(
          ip: '1.1.1.2', // Different IP but same quality
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 40.0,
          downloadSpeed: 10.0,
        );

        expect(ip1.compareQuality(ip2), equals(0));
      });
    });

    group('getQualityDescription', () {
      test('returns Excellent for perfect IP', () {
        final ip = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 40.0,
          downloadSpeed: 15.0,
        );

        expect(ip.getQualityDescription(), equals('Excellent'));
      });

      test('returns Very Good for low loss and latency', () {
        final ip = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.5,
          avgLatency: 80.0,
          downloadSpeed: 12.0,
        );

        expect(ip.getQualityDescription(), equals('Very Good'));
      });

      test('returns Good for moderate quality', () {
        final ip = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 2.0,
          avgLatency: 120.0,
          downloadSpeed: 10.0,
        );

        expect(ip.getQualityDescription(), equals('Good'));
      });

      test('returns Fair for acceptable quality', () {
        final ip = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 9,
          lossRate: 4.0,
          avgLatency: 180.0,
          downloadSpeed: 8.0,
        );

        expect(ip.getQualityDescription(), equals('Fair'));
      });

      test('returns Poor for low quality', () {
        final ip = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 8,
          lossRate: 20.0,
          avgLatency: 250.0,
          downloadSpeed: 5.0,
        );

        expect(ip.getQualityDescription(), equals('Poor'));
      });
    });

    group('toString', () {
      test('returns formatted string without sensitive data', () {
        final ip = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 45.2,
          downloadSpeed: 12.5,
        );

        final str = ip.toString();

        expect(str, contains('1.1.1.1'));
        expect(str, contains('0.0%'));
        expect(str, contains('45.2ms'));
        expect(str, contains('12.5MB/s'));
      });
    });

    group('Equality', () {
      test('equal instances are equal', () {
        final ip1 = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 45.2,
          downloadSpeed: 12.5,
        );

        final ip2 = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 45.2,
          downloadSpeed: 12.5,
        );

        expect(ip1, equals(ip2));
        expect(ip1.hashCode, equals(ip2.hashCode));
      });

      test('different instances are not equal', () {
        final ip1 = CleanIP(
          ip: '1.1.1.1',
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 45.2,
          downloadSpeed: 12.5,
        );

        final ip2 = CleanIP(
          ip: '1.1.1.2', // Different IP
          packetsSent: 10,
          packetsReceived: 10,
          lossRate: 0.0,
          avgLatency: 45.2,
          downloadSpeed: 12.5,
        );

        expect(ip1, isNot(equals(ip2)));
      });
    });
  });
}
