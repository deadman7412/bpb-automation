import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/models/credentials.dart';

void main() {
  group('Credentials', () {
    const testApiToken = 'abcdefghijklmnopqrstuvwxyz123456';
    const testAccountId = '1234567890abcdefghijklmnopqrstuvwxyz';
    const testNamespaceId = 'abcd1234efgh5678ijkl9012mnop3456';

    group('Constructor', () {
      test('creates instance with valid data', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        expect(creds.apiToken, equals(testApiToken));
        expect(creds.accountId, equals(testAccountId));
        expect(creds.kvNamespaceId, equals(testNamespaceId));
      });
    });

    group('fromJson', () {
      test('creates instance from valid JSON', () {
        final json = {
          'api_token': testApiToken,
          'account_id': testAccountId,
          'kv_namespace_id': testNamespaceId,
        };

        final creds = Credentials.fromJson(json);

        expect(creds.apiToken, equals(testApiToken));
        expect(creds.accountId, equals(testAccountId));
        expect(creds.kvNamespaceId, equals(testNamespaceId));
      });

      test('uses empty strings for missing fields', () {
        final json = <String, dynamic>{};
        final creds = Credentials.fromJson(json);

        expect(creds.apiToken, equals(''));
        expect(creds.accountId, equals(''));
        expect(creds.kvNamespaceId, equals(''));
      });

      test('handles null values gracefully', () {
        final json = {
          'api_token': null,
          'account_id': null,
          'kv_namespace_id': null,
        };

        final creds = Credentials.fromJson(json);

        expect(creds.apiToken, equals(''));
        expect(creds.accountId, equals(''));
        expect(creds.kvNamespaceId, equals(''));
      });
    });

    group('toJson', () {
      test('converts instance to JSON correctly', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        final json = creds.toJson();

        expect(json['api_token'], equals(testApiToken));
        expect(json['account_id'], equals(testAccountId));
        expect(json['kv_namespace_id'], equals(testNamespaceId));
      });

      test('round-trip JSON serialization preserves data', () {
        const original = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        final json = original.toJson();
        final restored = Credentials.fromJson(json);

        expect(restored, equals(original));
      });
    });

    group('isValid', () {
      test('returns true when all fields are non-empty', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        expect(creds.isValid(), isTrue);
      });

      test('returns false when api token is empty', () {
        const creds = Credentials(
          apiToken: '',
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        expect(creds.isValid(), isFalse);
      });

      test('returns false when account id is empty', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: '',
          kvNamespaceId: testNamespaceId,
        );

        expect(creds.isValid(), isFalse);
      });

      test('returns false when namespace id is empty', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: '',
        );

        expect(creds.isValid(), isFalse);
      });
    });

    group('isEmpty', () {
      test('returns true when all fields are empty', () {
        const creds = Credentials(
          apiToken: '',
          accountId: '',
          kvNamespaceId: '',
        );

        expect(creds.isEmpty(), isTrue);
      });

      test('returns true when any field is empty', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: '',
          kvNamespaceId: testNamespaceId,
        );

        expect(creds.isEmpty(), isTrue);
      });

      test('returns false when all fields are non-empty', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        expect(creds.isEmpty(), isFalse);
      });
    });

    group('isNotEmpty', () {
      test('returns true when all fields are non-empty', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        expect(creds.isNotEmpty(), isTrue);
      });

      test('returns false when any field is empty', () {
        const creds = Credentials(
          apiToken: '',
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        expect(creds.isNotEmpty(), isFalse);
      });
    });

    group('validate', () {
      test('returns empty list for valid credentials', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        final errors = creds.validate();
        expect(errors, isEmpty);
      });

      test('detects missing api token', () {
        const creds = Credentials(
          apiToken: '',
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        final errors = creds.validate();
        expect(
          errors,
          contains('API token is required'),
        );
      });

      test('detects too short api token', () {
        const creds = Credentials(
          apiToken: 'short',
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        final errors = creds.validate();
        expect(
          errors,
          contains('API token appears to be too short'),
        );
      });

      test('detects missing account id', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: '',
          kvNamespaceId: testNamespaceId,
        );

        final errors = creds.validate();
        expect(
          errors,
          contains('Account ID is required'),
        );
      });

      test('detects missing namespace id', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: '',
        );

        final errors = creds.validate();
        expect(
          errors,
          contains('KV Namespace ID is required'),
        );
      });

      test('returns multiple errors for multiple issues', () {
        const creds = Credentials(
          apiToken: '',
          accountId: 'short',
          kvNamespaceId: '',
        );

        final errors = creds.validate();
        expect(errors.length, greaterThan(1));
      });
    });

    group('copyWith', () {
      test('creates new instance with updated values', () {
        const original = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        final updated = original.copyWith(
          apiToken: 'new_token_123456789012345678',
        );

        expect(updated.apiToken, equals('new_token_123456789012345678'));
        expect(updated.accountId, equals(testAccountId));
        expect(updated.kvNamespaceId, equals(testNamespaceId));
      });

      test('preserves unchanged values', () {
        const original = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        final updated = original.copyWith(
          accountId: 'new_account_id_12345678901234567890',
        );

        expect(updated.apiToken, equals(testApiToken));
        expect(updated.accountId, equals('new_account_id_12345678901234567890'));
        expect(updated.kvNamespaceId, equals(testNamespaceId));
      });

      test('does not modify original instance', () {
        const original = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        original.copyWith(apiToken: 'new_token');

        expect(original.apiToken, equals(testApiToken));
      });
    });

    group('empty', () {
      test('creates credentials with all empty fields', () {
        final creds = Credentials.empty();

        expect(creds.apiToken, equals(''));
        expect(creds.accountId, equals(''));
        expect(creds.kvNamespaceId, equals(''));
        expect(creds.isEmpty(), isTrue);
      });
    });

    group('maskedApiToken', () {
      test('masks long token correctly', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        final masked = creds.maskedApiToken;
        expect(masked, equals('abcd...3456'));
        expect(masked, isNot(contains(testApiToken)));
      });

      test('returns empty string for empty token', () {
        const creds = Credentials(
          apiToken: '',
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        expect(creds.maskedApiToken, equals(''));
      });

      test('masks short token completely', () {
        const creds = Credentials(
          apiToken: 'short',
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        expect(creds.maskedApiToken, equals('****'));
      });
    });

    group('maskedAccountId', () {
      test('masks long account id correctly', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        final masked = creds.maskedAccountId;
        expect(masked, equals('1234...wxyz'));
        expect(masked, isNot(contains(testAccountId)));
      });

      test('returns empty string for empty account id', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: '',
          kvNamespaceId: testNamespaceId,
        );

        expect(creds.maskedAccountId, equals(''));
      });
    });

    group('maskedKvNamespaceId', () {
      test('masks long namespace id correctly', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        final masked = creds.maskedKvNamespaceId;
        expect(masked, equals('abcd...3456'));
        expect(masked, isNot(contains(testNamespaceId)));
      });

      test('returns empty string for empty namespace id', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: '',
        );

        expect(creds.maskedKvNamespaceId, equals(''));
      });
    });

    group('toString', () {
      test('does not expose actual credentials', () {
        const creds = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        final str = creds.toString();

        // Should NOT contain actual credentials
        expect(str, isNot(contains(testApiToken)));
        expect(str, isNot(contains(testAccountId)));
        expect(str, isNot(contains(testNamespaceId)));

        // Should contain masked versions
        expect(str, contains('abcd...3456')); // masked token
        expect(str, contains('1234...wxyz')); // masked account id
      });

      test('is safe for logging', () {
        const creds = Credentials(
          apiToken: 'super_secret_token_12345678901234567890',
          accountId: 'secret_account_12345678901234567890',
          kvNamespaceId: 'secret_namespace_12345678901234567890',
        );

        final str = creds.toString();

        // Verify no secrets are leaked
        expect(str, isNot(contains('super_secret')));
        expect(str, isNot(contains('secret_account')));
        expect(str, isNot(contains('secret_namespace')));
      });
    });

    group('Equality', () {
      test('equal instances are equal', () {
        const creds1 = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        const creds2 = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        expect(creds1, equals(creds2));
        expect(creds1.hashCode, equals(creds2.hashCode));
      });

      test('different instances are not equal', () {
        const creds1 = Credentials(
          apiToken: testApiToken,
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        const creds2 = Credentials(
          apiToken: 'different_token_12345678901234567890',
          accountId: testAccountId,
          kvNamespaceId: testNamespaceId,
        );

        expect(creds1, isNot(equals(creds2)));
      });
    });
  });
}
