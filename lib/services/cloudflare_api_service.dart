import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/credentials.dart';
import '../models/proxy_settings.dart';
import 'ech_proxy_service_stub.dart'
    if (dart.library.io) 'ech_proxy_service.dart';
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
  final EchProxyService _echProxyService = EchProxyService.instance;

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
    final existingEchConfig = settingsPayload['echConfig']?.toString() ?? '';
    try {
      final echConfig = await _extractEchConfig(
        enableEch: enableEch,
        cleanIpCandidates: _toStringList(settingsPayload['cleanIPs']),
      );
      settingsPayload['echConfig'] = echConfig;
    } catch (e) {
      if (enableEch && _isLikelyBase64(existingEchConfig)) {
        _logService.logWarn(
          'ECH refresh failed; preserving existing echConfig. Error: $e',
        );
        settingsPayload['echConfig'] = existingEchConfig;
      } else {
        throw _DerivedFieldException(
          'Failed to derive ECH config and no valid fallback is available',
          e,
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
    final domain = _getDomain(remoteDns);
    final host = domain['host']?.toString() ?? '';
    if (host.isEmpty) {
      return <String, dynamic>{
        'host': '',
        'isDomain': false,
        'ipv4': <String>[],
        'ipv6': <String>[],
      };
    }

    final isDomain = _asBool(domain['isHostDomain']);
    if (!isDomain) {
      return <String, dynamic>{
        'host': host,
        'isDomain': false,
        'ipv4': <String>[],
        'ipv6': <String>[],
      };
    }

    final records = await _resolveDns(host);
    return <String, dynamic>{
      'host': host,
      'isDomain': true,
      'ipv4': records['ipv4'] ?? <String>[],
      'ipv6': records['ipv6'] ?? <String>[],
    };
  }

  Future<Map<String, List<String>>> _resolveDns(String host) async {
    final base =
        'https://cloudflare-dns.com/dns-query?name=${Uri.encodeQueryComponent(host)}';
    final ipv4 = await _fetchDnsRecords('$base&type=A', 1);
    final ipv6 = await _fetchDnsRecords('$base&type=AAAA', 28);
    return <String, List<String>>{'ipv4': ipv4, 'ipv6': ipv6};
  }

  Future<List<String>> _fetchDnsRecords(String url, int recordType) async {
    final response = await _client
        .get(Uri.parse(url), headers: const {'Accept': 'application/dns-json'})
        .timeout(_defaultTimeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch DNS records: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) return <String>[];
    final answers = data['Answer'];
    if (answers is! List) return <String>[];

    return answers
        .whereType<Map>()
        .where((record) => record['type'] == recordType)
        .map((record) => record['data']?.toString() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic> _extractProxyParams(String outProxy) {
    try {
      final uri = Uri.parse(outProxy);
      final protocol = uri.scheme.toLowerCase();
      if (protocol.isEmpty) return <String, dynamic>{};
      final standardProtocol = protocol == 'ss'
          ? 'ss'
          : protocol.replaceAll('socks5', 'socks');

      if (standardProtocol == 'vmess') {
        return _extractVmessParams(uri);
      }

      final configParams = <String, dynamic>{
        'protocol': standardProtocol,
        'server': uri.host,
        'port': uri.hasPort ? uri.port : 0,
      };
      final userInfoParts = uri.userInfo.split(':');
      final uriUsername = userInfoParts.isNotEmpty ? userInfoParts.first : '';
      final uriPassword = userInfoParts.length > 1
          ? userInfoParts.sublist(1).join(':')
          : '';

      Map<String, dynamic> parseParams(
        bool queryParams,
        Map<String, dynamic> customParams,
      ) {
        final merged = Map<String, dynamic>.from(configParams);
        if (queryParams) {
          for (final entry in uri.queryParameters.entries) {
            merged[entry.key] = entry.value.isEmpty ? null : entry.value;
          }
        }
        merged.addAll(customParams);
        merged.removeWhere((_, value) => value == null);
        return merged;
      }

      switch (standardProtocol) {
        case 'vless':
          return parseParams(true, {'uuid': uriUsername});
        case 'trojan':
          return parseParams(true, {'password': uriUsername});
        case 'ss':
          final auth = _base64DecodeUtf8(uriUsername);
          final authParts = auth.split(':');
          return parseParams(true, {
            'method': authParts.isNotEmpty ? authParts.first : null,
            'password': authParts.length > 1
                ? authParts.sublist(1).join(':')
                : null,
          });
        case 'socks':
        case 'http':
          String? user;
          String? pass;
          try {
            final userInfo = _base64DecodeUtf8(uriUsername);
            if (userInfo.contains(':')) {
              final infoParts = userInfo.split(':');
              user = infoParts.first;
              pass = infoParts.sublist(1).join(':');
            }
          } catch (_) {
            user = uriUsername.isEmpty ? null : uriUsername;
            pass = uriPassword.isEmpty ? null : uriPassword;
          }
          return parseParams(false, {'user': user, 'pass': pass});
        default:
          return {};
      }
    } catch (e) {
      _logService.logWarn('Failed to extract outProxyParams: $e');
      return <String, dynamic>{};
    }
  }

  Map<String, dynamic> _extractVmessParams(Uri uri) {
    try {
      final encoded = uri.host.isNotEmpty ? uri.host : uri.path;
      final decoded = _base64DecodeUtf8(encoded);
      final payload = jsonDecode(decoded);
      if (payload is! Map<String, dynamic>) {
        return <String, dynamic>{'protocol': 'vmess'};
      }

      final config = Map<String, dynamic>.from(payload);
      return <String, dynamic>{
        'protocol': 'vmess',
        'uuid': config['id'],
        'server': config['add'],
        'port': int.tryParse('${config['port']}') ?? config['port'],
        'aid': int.tryParse('${config['aid']}') ?? config['aid'],
        'type': config['net'],
        'headerType': config['type'],
        'serviceName': config['path'],
        'authority': config['authority'],
        if ((config['path']?.toString() ?? '').isNotEmpty)
          'path': config['path'],
        if ((config['host']?.toString() ?? '').isNotEmpty)
          'host': config['host'],
        'security': config['tls'],
        'sni': config['sni'],
        'fp': config['fp'],
        if ((config['alpn']?.toString() ?? '').isNotEmpty)
          'alpn': config['alpn'],
      };
    } catch (_) {
      return <String, dynamic>{'protocol': 'vmess'};
    }
  }

  Future<String> _extractEchConfig({
    required bool enableEch,
    required List<String> cleanIpCandidates,
  }) async {
    if (!enableEch) return '';

    final hostName = await _resolveHostNameForPanelBehavior();
    final directResolvers = const ['dns.google', 'cloudflare-dns.com'];
    Object? lastDirectError;

    for (final resolver in directResolvers) {
      try {
        _logService.logInfo(
          'Trying direct ECH lookup via $resolver for $hostName',
        );
        return await _extractEchConfigDirect(
          hostName: hostName,
          resolverHost: resolver,
        );
      } catch (e) {
        lastDirectError = e;
        _logService.logWarn(
          'Direct ECH lookup failed via $resolver for $hostName: $e',
        );
      }
    }

    final directFailure =
        lastDirectError ??
        Exception('Direct ECH lookup failed for all resolvers');

    final tryViaProxy = await _storageService.getCloudflareTryEchViaProxy();
    if (!tryViaProxy) {
      _logService.logInfo(
        'ECH proxy fallback disabled in settings; skipping Xray ECH retry',
      );
      throw directFailure;
    }

    try {
      final socksEch = await _echProxyService.fetchEchViaCleanIPs(
        hostName: hostName,
        candidateIPs: cleanIpCandidates,
        resolverHosts: directResolvers,
      );
      if (socksEch != null && socksEch.isNotEmpty) {
        _logService.logOk('ECH lookup succeeded through Xray SOCKS fallback');
        return socksEch;
      }
    } catch (e) {
      _logService.logWarn('Proxy ECH lookup failed for $hostName: $e');
    }

    throw directFailure;
  }

  Future<String> _extractEchConfigDirect({
    required String hostName,
    required String resolverHost,
  }) async {
    final url = Uri.https(resolverHost, '/resolve', {
      'name': hostName,
      'type': 'HTTPS',
    });

    final response = await _client
        .get(url, headers: const {'Accept': 'application/dns-json'})
        .timeout(_defaultTimeout);
    if (response.statusCode != 200) {
      throw Exception(
        'ECH extraction failed for $hostName via $resolverHost: DNS status ${response.statusCode}',
      );
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw Exception(
        'ECH extraction failed for $hostName via $resolverHost: invalid response',
      );
    }
    final answers = body['Answer'];
    if (answers is! List) {
      throw Exception(
        'ECH extraction failed for $hostName via $resolverHost: missing Answer',
      );
    }

    for (final item in answers) {
      if (item is! Map) continue;
      final record = item['data']?.toString() ?? '';
      final ech = RegExp(r'ech=([^ ]+)').firstMatch(record)?.group(1);
      if (ech != null && ech.isNotEmpty) {
        return ech;
      }
    }

    throw Exception('ECH record not found via $resolverHost');
  }

  Future<String> _resolveHostNameForPanelBehavior() async {
    try {
      final subscriptionUrl = await _storageService.getSubscriptionUrl();
      if (subscriptionUrl != null && subscriptionUrl.isNotEmpty) {
        final uri = Uri.tryParse(subscriptionUrl);
        if (uri != null && uri.host.isNotEmpty) {
          return uri.host;
        }
      }
    } catch (_) {}

    try {
      final panelCredentials = await _storageService.getPanelCredentials();
      if (panelCredentials != null) {
        final uri = Uri.tryParse(panelCredentials.baseUrl);
        if (uri != null && uri.host.isNotEmpty) {
          return uri.host;
        }
      }
    } catch (_) {}

    throw Exception(
      'Panel hostName unavailable; cannot derive echConfig exactly like BPB panel',
    );
  }

  Map<String, dynamic> _getDomain(String url) {
    try {
      final parsed = Uri.parse(url);
      final host = parsed.host;
      return <String, dynamic>{'host': host, 'isHostDomain': _isDomain(host)};
    } catch (_) {
      return <String, dynamic>{'host': '', 'isHostDomain': false};
    }
  }

  bool _isDomain(String value) {
    if (value.isEmpty) return false;
    final regex = RegExp(r'^(?!-)(?:[A-Za-z0-9-]{1,63}\.)+[A-Za-z]{2,}$');
    return regex.hasMatch(value);
  }

  String _base64DecodeUtf8(String value) {
    final normalized = base64.normalize(value);
    return utf8.decode(base64Decode(normalized));
  }

  bool _isLikelyBase64(String value) {
    if (value.isEmpty) return false;
    try {
      base64Decode(base64.normalize(value));
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

        if (e is _DerivedFieldException) {
          _logService.logError('Derived field error, not retrying');
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

class _DerivedFieldException implements Exception {
  final String message;
  final Object? cause;

  _DerivedFieldException(this.message, [this.cause]);

  @override
  String toString() {
    if (cause == null) return '_DerivedFieldException: $message';
    return '_DerivedFieldException: $message; cause: $cause';
  }
}
