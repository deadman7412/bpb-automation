import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/credentials.dart';
import '../models/proxy_settings.dart';
import 'log_service.dart';
import 'storage_service.dart';

/// Service for interacting with Cloudflare Workers KV API
class CloudflareApiService {
  static final CloudflareApiService _instance =
      CloudflareApiService._internal();
  static CloudflareApiService get instance => _instance;

  CloudflareApiService._internal();

  final LogService _logService = LogService.instance;
  final StorageService _storageService = StorageService.instance;

  /// Base URL for Cloudflare API
  static const String _baseUrl = 'https://api.cloudflare.com/client/v4';

  /// Default timeout for API requests
  static const Duration _defaultTimeout = Duration(seconds: 30);

  /// Maximum retry attempts
  static const int _maxRetries = 3;

  /// Initial retry delay
  static const Duration _initialRetryDelay = Duration(seconds: 1);

  /// HTTP client for making requests (can be injected for testing)
  http.Client _client = http.Client();

  /// Set HTTP client (for testing)
  void setClient(http.Client client) {
    _client = client;
  }

  /// Build authorization headers from credentials
  Map<String, String> _buildHeaders(Credentials credentials) {
    return {
      'Authorization': 'Bearer ${credentials.apiToken}',
      'Content-Type': 'application/json',
    };
  }

  /// Redacted path for safe logging (prevents leaking account/namespace IDs).
  String _redactedKvPath(Credentials credentials) {
    return '/accounts/[redacted:${credentials.accountId.length}]'
        '/storage/kv/namespaces/[redacted:${credentials.kvNamespaceId.length}]'
        '/values/proxySettings';
  }

  /// Validate credentials by making a test API call
  Future<bool> validateCredentials(Credentials credentials) async {
    try {
      _logService.logInfo('Validating Cloudflare credentials');

      // Validate credential format first
      final validationErrors = credentials.validate();
      if (validationErrors.isNotEmpty) {
        _logService.logWarn(
          'Credential validation failed: ${validationErrors.join(", ")}',
        );
        return false;
      }

      // Make a test request to verify the namespace exists
      final url = Uri.parse(
        '$_baseUrl/accounts/${credentials.accountId}/storage/kv/namespaces/${credentials.kvNamespaceId}',
      );

      final response = await _client
          .get(url, headers: _buildHeaders(credentials))
          .timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        _logService.logOk('Credentials validated successfully');
        return true;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _logService.logWarn('Invalid API token (${response.statusCode})');
        return false;
      } else if (response.statusCode == 404) {
        _logService.logWarn('KV namespace not found (${response.statusCode})');
        return false;
      } else {
        _logService.logWarn(
          'Unexpected response: ${response.statusCode} ${response.body}',
        );
        return false;
      }
    } catch (e, stackTrace) {
      _logService.logError('Failed to validate credentials', e, stackTrace);
      return false;
    }
  }

  /// Get proxySettings from Cloudflare Workers KV
  Future<ProxySettings?> getProxySettings(Credentials credentials) async {
    return await _retryOperation(() => _getProxySettingsInternal(credentials));
  }

  /// Internal method to get proxy settings (without retry logic)
  Future<ProxySettings?> _getProxySettingsInternal(
    Credentials credentials,
  ) async {
    try {
      _logService.logInfo('Fetching proxySettings from Cloudflare KV');

      final url = Uri.parse(
        '$_baseUrl/accounts/${credentials.accountId}/storage/kv/namespaces/${credentials.kvNamespaceId}/values/proxySettings',
      );

      _logService.logInfo('GET $_baseUrl${_redactedKvPath(credentials)}');

      final response = await _client
          .get(url, headers: _buildHeaders(credentials))
          .timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        _logService.logOk('ProxySettings fetched successfully');

        // Parse JSON response
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        final settings = ProxySettings.fromJson(jsonData);

        _logService.logInfo(
          'Current cleanIPs count: ${settings.cleanIPs.length}',
        );

        return settings;
      } else if (response.statusCode == 404) {
        _logService.logWarn('proxySettings key not found in KV');
        return null;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw CloudflareApiException(
          'Authentication failed (${response.statusCode})',
          response.statusCode,
        );
      } else {
        throw CloudflareApiException(
          'Failed to fetch proxySettings: ${response.statusCode} ${response.body}',
          response.statusCode,
        );
      }
    } catch (e, stackTrace) {
      if (e is CloudflareApiException) {
        _logService.logError('API error: ${e.message}', e, stackTrace);
        rethrow;
      }
      _logService.logError('Failed to fetch proxySettings', e, stackTrace);
      rethrow;
    }
  }

  /// Update cleanIPs in proxySettings while preserving other fields
  Future<bool> updateCleanIPs(
    Credentials credentials,
    List<String> cleanIPs,
  ) async {
    return await _retryOperation(
      () => _updateCleanIPsInternal(credentials, cleanIPs),
    );
  }

  /// Internal method to update clean IPs (without retry logic)
  Future<bool> _updateCleanIPsInternal(
    Credentials credentials,
    List<String> cleanIPs,
  ) async {
    try {
      _logService.logInfo(
        'Updating cleanIPs in Cloudflare KV (${cleanIPs.length} IPs)',
      );

      // Step 1: Read current settings
      _logService.logInfo('Step 1: Reading current proxySettings');
      final currentSettings = await _getProxySettingsInternal(credentials);

      if (currentSettings == null) {
        throw CloudflareApiException('proxySettings not found in KV', 404);
      }

      // Step 2: Update only cleanIPs field
      _logService.logInfo('Step 2: Updating cleanIPs field');
      final updatedSettings = currentSettings.copyWithCleanIPs(cleanIPs);
      final payload = updatedSettings.toJson();

      // Step 3: Apply BPB panel-compatible derived transforms.
      _logService.logInfo('Step 3: Applying panel-compatible derived fields');
      _logDerivedFieldsSnapshot(stage: 'before', settingsPayload: payload);
      await _applyPanelCompatibleTransforms(payload);
      _logDerivedFieldsSnapshot(stage: 'after', settingsPayload: payload);

      // Step 4: Write back to KV
      _logService.logInfo('Step 4: Writing updated settings to KV');
      final url = Uri.parse(
        '$_baseUrl/accounts/${credentials.accountId}/storage/kv/namespaces/${credentials.kvNamespaceId}/values/proxySettings',
      );

      _logService.logInfo('PUT $_baseUrl${_redactedKvPath(credentials)}');

      final response = await _client
          .put(
            url,
            headers: _buildHeaders(credentials),
            body: jsonEncode(payload),
          )
          .timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        _logService.logOk('CleanIPs updated successfully');
        return true;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw CloudflareApiException(
          'Authentication failed (${response.statusCode})',
          response.statusCode,
        );
      } else {
        throw CloudflareApiException(
          'Failed to update cleanIPs: ${response.statusCode} ${response.body}',
          response.statusCode,
        );
      }
    } catch (e, stackTrace) {
      if (e is CloudflareApiException) {
        _logService.logError('API error: ${e.message}', e, stackTrace);
        rethrow;
      }
      _logService.logError('Failed to update cleanIPs', e, stackTrace);
      rethrow;
    }
  }

  Future<void> _applyPanelCompatibleTransforms(
    Map<String, dynamic> settingsPayload,
  ) async {
    final remoteDnsHost = await _getDnsParams(
      settingsPayload['remoteDNS']?.toString() ?? '',
    );
    settingsPayload['remoteDnsHost'] = remoteDnsHost;

    final outProxy = settingsPayload['outProxy']?.toString() ?? '';
    if (outProxy.isNotEmpty) {
      final outProxyParams = _extractProxyParams(outProxy);
      if (outProxyParams.isNotEmpty) {
        settingsPayload['outProxyParams'] = outProxyParams;
      }
    }

    final enableEch = _asBool(settingsPayload['enableECH']);
    if (enableEch) {
      final echHost = await _resolveEchHost(settingsPayload);
      if (echHost != null && echHost.isNotEmpty) {
        final echConfig = await _extractEchConfig(echHost);
        if (echConfig != null && echConfig.isNotEmpty) {
          settingsPayload['echConfig'] = echConfig;
        } else {
          _logService.logWarn(
            'ECH enabled but no HTTPS ECH record found for host: $echHost',
          );
        }
      } else {
        _logService.logWarn(
          'ECH enabled but no host candidate found for ECH extraction',
        );
      }
    }
  }

  void _logDerivedFieldsSnapshot({
    required String stage,
    required Map<String, dynamic> settingsPayload,
  }) {
    final remoteDnsHost = _castToMap(settingsPayload['remoteDnsHost']);
    final outProxyParams = _castToMap(settingsPayload['outProxyParams']);
    final echConfig = settingsPayload['echConfig']?.toString() ?? '';

    final sanitized = <String, dynamic>{
      'remoteDnsHost': <String, dynamic>{
        'host': remoteDnsHost['host']?.toString() ?? '',
        'isDomain': _asBool(remoteDnsHost['isDomain']),
        'ipv4Count': _toStringList(remoteDnsHost['ipv4']).length,
        'ipv6Count': _toStringList(remoteDnsHost['ipv6']).length,
      },
      'outProxyParams': _sanitizeOutProxyParams(outProxyParams),
      'echConfig': <String, dynamic>{
        'present': echConfig.isNotEmpty,
        'length': echConfig.length,
        'prefix': echConfig.isNotEmpty
            ? echConfig.substring(
                0,
                echConfig.length >= 12 ? 12 : echConfig.length,
              )
            : '',
      },
    };

    _logService.logInfo(
      'Derived fields snapshot ($stage): ${jsonEncode(sanitized)}',
    );
  }

  Future<Map<String, dynamic>> _getDnsParams(String remoteDns) async {
    final host = _extractHost(remoteDns);
    if (host.isEmpty) {
      return <String, dynamic>{
        'host': '',
        'isDomain': false,
        'ipv4': <String>[],
        'ipv6': <String>[],
      };
    }

    final isDomain = !_isIpLiteral(host);
    if (!isDomain) {
      return <String, dynamic>{
        'host': host,
        'isDomain': false,
        'ipv4': <String>[],
        'ipv6': <String>[],
      };
    }

    final ipv4 = await _resolveDnsRecord(host, 'A');
    final ipv6 = await _resolveDnsRecord(host, 'AAAA');
    return <String, dynamic>{
      'host': host,
      'isDomain': true,
      'ipv4': ipv4,
      'ipv6': ipv6,
    };
  }

  Future<List<String>> _resolveDnsRecord(String host, String type) async {
    try {
      final url = Uri.https('dns.google', '/resolve', {
        'name': host,
        'type': type,
      });
      final response = await _client
          .get(url, headers: const {'Accept': 'application/dns-json'})
          .timeout(_defaultTimeout);
      if (response.statusCode != 200) {
        _logService.logWarn(
          'DNS $type resolve failed for $host (status: ${response.statusCode})',
        );
        return <String>[];
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return <String>[];
      final answers = data['Answer'];
      if (answers is! List) return <String>[];

      return answers
          .whereType<Map>()
          .map((item) => item['data']?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      _logService.logWarn('DNS $type resolve error for $host: $e');
      return <String>[];
    }
  }

  Map<String, dynamic> _extractProxyParams(String outProxy) {
    try {
      final uri = Uri.parse(outProxy);
      final protocol = uri.scheme.toLowerCase();
      if (protocol.isEmpty) return <String, dynamic>{};

      if (protocol == 'vmess') {
        return _extractVmessParams(uri);
      }

      final params = <String, dynamic>{'protocol': protocol};

      if (uri.host.isNotEmpty) {
        params['server'] = uri.host;
      }
      final defaultPort = _defaultPortForProtocol(protocol);
      if (uri.hasPort) {
        params['port'] = uri.port;
      } else if (defaultPort != null) {
        params['port'] = defaultPort;
      }

      if (uri.userInfo.isNotEmpty) {
        final userInfoParts = uri.userInfo.split(':');
        if (protocol == 'vless') {
          params['uuid'] = userInfoParts.first;
        } else if (protocol == 'trojan') {
          params['password'] = userInfoParts.first;
        } else if (protocol == 'socks' || protocol == 'http') {
          params['user'] = userInfoParts.first;
          if (userInfoParts.length > 1) {
            params['pass'] = userInfoParts.sublist(1).join(':');
          }
        } else {
          params['userInfo'] = uri.userInfo;
        }
      }

      uri.queryParameters.forEach((key, value) {
        if (value.isEmpty) return;
        if (key == 'port') {
          final parsed = int.tryParse(value);
          if (parsed != null) {
            params[key] = parsed;
            return;
          }
        }
        params[key] = value;
      });

      if (params['path'] is String && (params['path'] as String).isEmpty) {
        params['path'] = '/';
      }

      return params;
    } catch (e) {
      _logService.logWarn('Failed to extract outProxyParams: $e');
      return <String, dynamic>{};
    }
  }

  Map<String, dynamic> _extractVmessParams(Uri uri) {
    try {
      final encoded = uri.host.isNotEmpty ? uri.host : uri.path;
      final normalized = base64.normalize(encoded);
      final decoded = utf8.decode(base64Decode(normalized));
      final payload = jsonDecode(decoded);
      if (payload is! Map<String, dynamic>) {
        return <String, dynamic>{'protocol': 'vmess'};
      }
      final params = Map<String, dynamic>.from(payload);
      params['protocol'] = 'vmess';
      if (params['port'] is String) {
        params['port'] =
            int.tryParse(params['port'] as String) ?? params['port'];
      }
      return params;
    } catch (_) {
      return <String, dynamic>{'protocol': 'vmess'};
    }
  }

  Future<String?> _resolveEchHost(Map<String, dynamic> settingsPayload) async {
    final customCdnHost = settingsPayload['customCdnHost']?.toString() ?? '';
    if (customCdnHost.isNotEmpty && !_isIpLiteral(customCdnHost)) {
      return customCdnHost;
    }

    try {
      final subscriptionUrl = await _storageService.getSubscriptionUrl();
      if (subscriptionUrl != null && subscriptionUrl.isNotEmpty) {
        final uri = Uri.tryParse(subscriptionUrl);
        final host = uri?.host ?? '';
        if (host.isNotEmpty && !_isIpLiteral(host)) {
          return host;
        }
      }
    } catch (e) {
      _logService.logWarn('Failed to read subscription URL for ECH host: $e');
    }

    final remoteDnsHost = _extractHost(
      settingsPayload['remoteDNS']?.toString() ?? '',
    );
    if (remoteDnsHost.isNotEmpty && !_isIpLiteral(remoteDnsHost)) {
      return remoteDnsHost;
    }

    return 'cloudflare-ech.com';
  }

  Future<String?> _extractEchConfig(String hostName) async {
    try {
      final url = Uri.https('dns.google', '/resolve', {
        'name': hostName,
        'type': 'HTTPS',
      });
      final response = await _client
          .get(url, headers: const {'Accept': 'application/dns-json'})
          .timeout(_defaultTimeout);
      if (response.statusCode != 200) {
        _logService.logWarn(
          'DNS HTTPS resolve failed for $hostName (status: ${response.statusCode})',
        );
        return null;
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      final answers = body['Answer'];
      if (answers is! List) return null;

      for (final item in answers) {
        if (item is! Map) continue;
        final record = item['data']?.toString() ?? '';
        if (record.isEmpty) continue;

        final match = RegExp(
          r'(?:ech(?:config)?=)([^,\s"]+)',
        ).firstMatch(record);
        if (match != null) {
          final value = match.group(1) ?? '';
          if (_isLikelyBase64(value)) {
            return value;
          }
        }
      }
      return null;
    } catch (e) {
      _logService.logWarn('ECH extraction failed for $hostName: $e');
      return null;
    }
  }

  String _extractHost(String urlOrHost) {
    final value = urlOrHost.trim();
    if (value.isEmpty) return '';
    final uri = Uri.tryParse(value);
    if (uri != null && uri.host.isNotEmpty) {
      return uri.host;
    }
    return value;
  }

  bool _isIpLiteral(String host) {
    final value = host.trim();
    if (value.isEmpty) return false;
    final ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
    if (ipv4.hasMatch(value)) {
      final parts = value.split('.');
      return parts.every((part) {
        final parsed = int.tryParse(part);
        return parsed != null && parsed >= 0 && parsed <= 255;
      });
    }
    return value.contains(':');
  }

  bool _isLikelyBase64(String value) {
    if (value.isEmpty) return false;
    final normalized = base64.normalize(value);
    try {
      base64Decode(normalized);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    if (value is num) return value != 0;
    return false;
  }

  Map<String, dynamic> _castToMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value.map((entry) => entry.toString()).toList(growable: false);
    }
    return <String>[];
  }

  int? _defaultPortForProtocol(String protocol) {
    switch (protocol) {
      case 'http':
        return 80;
      case 'https':
      case 'vless':
      case 'trojan':
      case 'vmess':
        return 443;
      case 'socks':
        return 1080;
      default:
        return null;
    }
  }

  Map<String, dynamic> _sanitizeOutProxyParams(Map<String, dynamic> params) {
    final sanitized = <String, dynamic>{};
    for (final key in <String>[
      'protocol',
      'server',
      'port',
      'type',
      'security',
      'fp',
      'alpn',
      'path',
      'encryption',
      'host',
    ]) {
      if (params.containsKey(key)) {
        sanitized[key] = params[key];
      }
    }
    sanitized['hasUuid'] = (params['uuid']?.toString().isNotEmpty ?? false);
    sanitized['hasPassword'] =
        (params['password']?.toString().isNotEmpty ?? false);
    sanitized['hasPass'] = (params['pass']?.toString().isNotEmpty ?? false);
    return sanitized;
  }

  /// Retry an operation with exponential backoff
  Future<T> _retryOperation<T>(Future<T> Function() operation) async {
    int attempt = 0;
    Duration delay = _initialRetryDelay;

    while (true) {
      attempt++;

      try {
        return await operation();
      } catch (e) {
        if (attempt >= _maxRetries) {
          _logService.logError('Max retries ($attempt) reached, giving up');
          rethrow;
        }

        // Don't retry authentication errors
        if (e is CloudflareApiException &&
            (e.statusCode == 401 || e.statusCode == 403)) {
          _logService.logError('Authentication error, not retrying');
          rethrow;
        }

        _logService.logWarn(
          'Attempt $attempt failed, retrying in ${delay.inSeconds}s',
          e,
        );

        await Future.delayed(delay);

        // Exponential backoff: double the delay for next retry
        delay *= 2;
      }
    }
  }

  /// Test connection to Cloudflare API
  Future<bool> testConnection() async {
    try {
      _logService.logInfo('Testing Cloudflare API connection');

      final url = Uri.parse('$_baseUrl/user/tokens/verify');

      final response = await _client.get(url).timeout(_defaultTimeout);

      // This endpoint should return 401 without auth, which proves connectivity
      if (response.statusCode == 401 || response.statusCode == 200) {
        _logService.logOk('Cloudflare API is reachable');
        return true;
      }

      _logService.logWarn(
        'Unexpected response from API: ${response.statusCode}',
      );
      return false;
    } catch (e, stackTrace) {
      _logService.logError(
        'Failed to connect to Cloudflare API',
        e,
        stackTrace,
      );
      return false;
    }
  }
}

/// Exception for Cloudflare API errors
class CloudflareApiException implements Exception {
  final String message;
  final int statusCode;

  CloudflareApiException(this.message, this.statusCode);

  @override
  String toString() => 'CloudflareApiException: $message (status: $statusCode)';
}
