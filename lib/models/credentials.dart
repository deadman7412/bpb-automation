/// Cloudflare API authentication credentials.
///
/// This model holds the credentials needed to access Cloudflare Workers KV API.
/// These credentials are stored securely using flutter_secure_storage.
///
/// SECURITY NOTE: toString() method intentionally DOES NOT expose sensitive data.
class Credentials {
  /// Cloudflare API token
  /// Get this from: Cloudflare Dashboard > My Profile > API Tokens
  /// Required permissions: Workers KV Edit
  final String apiToken;

  /// Cloudflare Account ID
  /// Found in: Cloudflare Dashboard > Workers & Pages > Overview
  final String accountId;

  /// Workers KV Namespace ID
  /// Found in: Cloudflare Dashboard > Workers & Pages > KV
  final String kvNamespaceId;

  /// Creates a Credentials instance.
  const Credentials({
    required this.apiToken,
    required this.accountId,
    required this.kvNamespaceId,
  });

  /// Creates a Credentials instance from JSON.
  ///
  /// Example JSON:
  /// ```json
  /// {
  ///   "api_token": "your_token_here",
  ///   "account_id": "your_account_id",
  ///   "kv_namespace_id": "your_namespace_id"
  /// }
  /// ```
  factory Credentials.fromJson(Map<String, dynamic> json) {
    return Credentials(
      apiToken: json['api_token'] as String? ?? '',
      accountId: json['account_id'] as String? ?? '',
      kvNamespaceId: json['kv_namespace_id'] as String? ?? '',
    );
  }

  /// Converts this Credentials instance to JSON.
  Map<String, dynamic> toJson() {
    return {
      'api_token': apiToken,
      'account_id': accountId,
      'kv_namespace_id': kvNamespaceId,
    };
  }

  /// Returns true if all required fields are present and non-empty.
  bool isValid() {
    return apiToken.isNotEmpty &&
        accountId.isNotEmpty &&
        kvNamespaceId.isNotEmpty;
  }

  /// Returns true if any of the credentials are empty.
  bool isEmpty() {
    return apiToken.isEmpty || accountId.isEmpty || kvNamespaceId.isEmpty;
  }

  /// Returns true if all credentials are non-empty.
  bool isNotEmpty() {
    return !isEmpty();
  }

  /// Validates the format of the credentials.
  ///
  /// Returns a list of validation errors, or empty list if valid.
  List<String> validate() {
    final errors = <String>[];

    if (apiToken.isEmpty) {
      errors.add('API token is required');
    } else if (apiToken.length < 20) {
      errors.add('API token appears to be too short');
    }

    if (accountId.isEmpty) {
      errors.add('Account ID is required');
    } else if (accountId.length < 20) {
      errors.add('Account ID appears to be too short');
    }

    if (kvNamespaceId.isEmpty) {
      errors.add('KV Namespace ID is required');
    } else if (kvNamespaceId.length < 20) {
      errors.add('KV Namespace ID appears to be too short');
    }

    return errors;
  }

  /// Creates a copy of this credentials with modified values.
  Credentials copyWith({
    String? apiToken,
    String? accountId,
    String? kvNamespaceId,
  }) {
    return Credentials(
      apiToken: apiToken ?? this.apiToken,
      accountId: accountId ?? this.accountId,
      kvNamespaceId: kvNamespaceId ?? this.kvNamespaceId,
    );
  }

  /// Creates an empty Credentials instance.
  factory Credentials.empty() {
    return const Credentials(
      apiToken: '',
      accountId: '',
      kvNamespaceId: '',
    );
  }

  /// Returns a masked version of the API token for display purposes.
  ///
  /// Shows only first 4 and last 4 characters: "abcd...wxyz"
  String get maskedApiToken {
    if (apiToken.isEmpty) return '';
    if (apiToken.length <= 8) return '****';
    final start = apiToken.substring(0, 4);
    final end = apiToken.substring(apiToken.length - 4);
    return '$start...$end';
  }

  /// Returns a masked version of the account ID for display purposes.
  ///
  /// Shows only first 4 and last 4 characters: "abcd...wxyz"
  String get maskedAccountId {
    if (accountId.isEmpty) return '';
    if (accountId.length <= 8) return '****';
    final start = accountId.substring(0, 4);
    final end = accountId.substring(accountId.length - 4);
    return '$start...$end';
  }

  /// Returns a masked version of the namespace ID for display purposes.
  ///
  /// Shows only first 4 and last 4 characters: "abcd...wxyz"
  String get maskedKvNamespaceId {
    if (kvNamespaceId.isEmpty) return '';
    if (kvNamespaceId.length <= 8) return '****';
    final start = kvNamespaceId.substring(0, 4);
    final end = kvNamespaceId.substring(kvNamespaceId.length - 4);
    return '$start...$end';
  }

  /// Returns a string representation WITHOUT exposing sensitive data.
  ///
  /// SECURITY: This method NEVER shows actual credentials, only masked versions.
  @override
  String toString() {
    return 'Credentials('
        'apiToken: $maskedApiToken, '
        'accountId: $maskedAccountId, '
        'kvNamespaceId: $maskedKvNamespaceId)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Credentials &&
        other.apiToken == apiToken &&
        other.accountId == accountId &&
        other.kvNamespaceId == kvNamespaceId;
  }

  @override
  int get hashCode {
    return Object.hash(
      apiToken,
      accountId,
      kvNamespaceId,
    );
  }
}
