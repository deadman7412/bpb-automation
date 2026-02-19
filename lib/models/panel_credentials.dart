/// BPB Panel authentication credentials for panel API access.
///
/// SECURITY NOTE: toString() intentionally does not expose the password.
class PanelCredentials {
  /// Base URL of the BPB panel worker, e.g. https://example.workers.dev
  final String baseUrl;

  /// Panel login password.
  final String password;

  const PanelCredentials({required this.baseUrl, required this.password});

  factory PanelCredentials.fromJson(Map<String, dynamic> json) {
    return PanelCredentials(
      baseUrl: json['base_url'] as String? ?? '',
      password: json['password'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'base_url': baseUrl, 'password': password};
  }

  bool isValid() {
    final errors = validate();
    return errors.isEmpty;
  }

  List<String> validate() {
    final errors = <String>[];

    if (baseUrl.trim().isEmpty) {
      errors.add('Panel base URL is required');
    } else {
      Uri? uri;
      try {
        uri = Uri.parse(baseUrl.trim());
      } catch (_) {
        uri = null;
      }

      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        errors.add('Panel base URL must be a valid absolute URL');
      } else if (uri.path.isNotEmpty && uri.path != '/') {
        errors.add('Panel base URL must not include a path');
      }
    }

    if (password.trim().isEmpty) {
      errors.add('Panel password is required');
    }

    return errors;
  }

  PanelCredentials copyWith({String? baseUrl, String? password}) {
    return PanelCredentials(
      baseUrl: baseUrl ?? this.baseUrl,
      password: password ?? this.password,
    );
  }

  String get maskedPassword {
    if (password.isEmpty) return '';
    return '********';
  }

  @override
  String toString() {
    return 'PanelCredentials(baseUrl: $baseUrl, password: $maskedPassword)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PanelCredentials &&
        other.baseUrl == baseUrl &&
        other.password == password;
  }

  @override
  int get hashCode => Object.hash(baseUrl, password);
}
