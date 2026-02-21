import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/credentials.dart';
import '../models/proxy_settings.dart';
import 'ech_proxy_service_stub.dart'
    if (dart.library.io) 'ech_proxy_service.dart';
import 'panel_doh_forced_ip_service_stub.dart'
    if (dart.library.io) 'panel_doh_forced_ip_service.dart';
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
  final PanelDohForcedIpService _panelDohForcedIpService =
      PanelDohForcedIpService.instance;
  String? _lastEchSource;

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
    _lastEchSource = null;
    try {
      final echConfig = await _extractEchConfig(
        enableEch: enableEch,
        cleanIpCandidates: _toStringList(settingsPayload['cleanIPs']),
      );
      settingsPayload['echConfig'] = echConfig;
      if (echConfig == existingEchConfig) {
        _logService.logInfo(
          'ECH refreshed: $echConfig${_lastEchSource != null ? ' (source: $_lastEchSource)' : ''}',
        );
      } else {
        _logService.logInfo(
          'New ECH received: $echConfig${_lastEchSource != null ? ' (source: $_lastEchSource)' : ''}',
        );
      }
    } catch (e) {
      final useCachedFallback = await _storageService
          .getCloudflareUseCachedEchFallback();
      final cachedEchConfig = useCachedFallback
          ? await _storageService.getCloudflareLastSuccessfulEchConfig()
          : null;
      if (enableEch && _isLikelyBase64(existingEchConfig)) {
        _logService.logWarn(
          'ECH refresh failed; preserving existing echConfig. Error: $e',
        );
        settingsPayload['echConfig'] = existingEchConfig;
      } else if (enableEch && _isLikelyBase64(cachedEchConfig ?? '')) {
        final meta = await _storageService.getCloudflareLastSuccessfulEchMeta();
        final source = meta?['source']?.toString() ?? 'unknown';
        final atMs = meta?['atMs'] is int ? meta!['atMs'] as int : null;
        final atText = atMs == null
            ? 'unknown-time'
            : DateTime.fromMillisecondsSinceEpoch(atMs).toIso8601String();
        _logService.logWarn(
          'ECH refresh failed; using cached ECH fallback (source: $source, fetchedAt: $atText). Error: $e',
        );
        settingsPayload['echConfig'] = cachedEchConfig!;
        _logService.logInfo('ECH refreshed: $cachedEchConfig (source: cached)');
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
    final tryViaDirect = await _storageService
        .getCloudflareTryEchViaDirectResolvers();
    final tryViaPanelDoh = await _storageService.getCloudflareTryEchViaPanelDoh();
    final tryViaProxy = await _storageService.getCloudflareTryEchViaProxy();
    _logService.logInfo(
      'ECH source strategy: direct=$tryViaDirect, panelDoH=$tryViaPanelDoh, proxy=$tryViaProxy',
    );

    final startedAt = DateTime.now();
    const totalBudget = Duration(seconds: 16);
    Duration remainingBudget() {
      final elapsed = DateTime.now().difference(startedAt);
      final remaining = totalBudget - elapsed;
      return remaining.isNegative ? Duration.zero : remaining;
    }

    Object? lastError;

    if (tryViaDirect) {
      for (final resolver in directResolvers) {
        final remaining = remainingBudget();
        if (remaining <= Duration.zero) break;
        try {
          final timeout = remaining < const Duration(seconds: 6)
              ? remaining
              : const Duration(seconds: 6);
          _logService.logInfo(
            'Trying direct ECH lookup via $resolver for $hostName (timeout: ${timeout.inSeconds}s)',
          );
          final ech = await _extractEchConfigDirect(
            hostName: hostName,
            resolverHost: resolver,
            timeout: timeout,
          );
          await _cacheSuccessfulEch(echConfig: ech, source: 'direct:$resolver');
          return ech;
        } catch (e) {
          lastError = e;
          _logService.logWarn(
            'Direct ECH lookup failed via $resolver for $hostName: $e',
          );
        }
      }
    } else {
      _logService.logInfo(
        'Direct ECH lookup disabled in settings; skipping public resolvers',
      );
    }

    if (tryViaPanelDoh) {
      final remaining = remainingBudget();
      if (remaining > Duration.zero) {
        try {
          final timeout = remaining < const Duration(seconds: 8)
              ? remaining
              : const Duration(seconds: 8);
          _logService.logInfo(
            'Trying panel DoH ECH lookup for $hostName (timeout: ${timeout.inSeconds}s)',
          );
          final panelDohEch = await _extractEchConfigViaPanelDoh(
            hostName: hostName,
            timeout: timeout,
          );
          if (panelDohEch.isNotEmpty) {
            _logService.logOk('ECH lookup succeeded through panel DoH route');
            await _cacheSuccessfulEch(
              echConfig: panelDohEch,
              source: 'panel-doh',
            );
            return panelDohEch;
          }
        } catch (e) {
          lastError = e;
          _logService.logWarn('Panel DoH ECH lookup failed for $hostName: $e');
          final remainingAfterPrimary = remainingBudget();
          if (remainingAfterPrimary > Duration.zero &&
              cleanIpCandidates.isNotEmpty) {
            try {
              final forcedTimeout = remainingAfterPrimary <
                      const Duration(seconds: 8)
                  ? remainingAfterPrimary
                  : const Duration(seconds: 8);
              _logService.logInfo(
                'Trying panel DoH ECH lookup via forced clean IP rotation '
                '(${cleanIpCandidates.length} candidate(s), timeout: ${forcedTimeout.inSeconds}s)',
              );
              final forcedEch = await _extractEchConfigViaPanelDohForcedIps(
                hostName: hostName,
                timeout: forcedTimeout,
                candidateIps: cleanIpCandidates,
              );
              if (forcedEch.isNotEmpty) {
                _logService.logOk(
                  'ECH lookup succeeded through panel DoH forced-IP rotation',
                );
                await _cacheSuccessfulEch(
                  echConfig: forcedEch,
                  source: 'panel-doh-forced-ip',
                );
                return forcedEch;
              }
            } catch (forcedError) {
              lastError = forcedError;
              _logService.logWarn(
                'Panel DoH forced-IP ECH lookup failed for $hostName: $forcedError',
              );
            }
          }
        }
      }
    } else {
      _logService.logInfo('Panel DoH ECH lookup disabled in settings; skipping');
    }

    if (!tryViaProxy) {
      _logService.logInfo(
        'ECH proxy fallback disabled in settings; skipping Xray ECH retry',
      );
      throw lastError ?? Exception('ECH lookup failed for all enabled sources');
    }

    try {
      final socksEch = await _echProxyService.fetchEchViaCleanIPs(
        hostName: hostName,
        candidateIPs: cleanIpCandidates,
        resolverHosts: directResolvers,
      );
      if (socksEch != null && socksEch.isNotEmpty) {
        _logService.logOk('ECH lookup succeeded through Xray SOCKS fallback');
        await _cacheSuccessfulEch(echConfig: socksEch, source: 'proxy-socks');
        return socksEch;
      }
    } catch (e) {
      _logService.logWarn('Proxy ECH lookup failed for $hostName: $e');
      lastError = e;
    }

    throw lastError ?? Exception('ECH lookup failed for all enabled sources');
  }

  Future<void> _cacheSuccessfulEch({
    required String echConfig,
    required String source,
  }) async {
    if (!_isLikelyBase64(echConfig)) return;
    _lastEchSource = source;
    await _storageService.saveCloudflareLastSuccessfulEch(
      echConfig: echConfig,
      source: source,
    );
    _logService.logInfo(
      'Saved successful ECH to local cache (source: $source, length: ${echConfig.length})',
    );
  }

  Future<String> _extractEchConfigDirect({
    required String hostName,
    required String resolverHost,
    required Duration timeout,
  }) async {
    final url = Uri.https(resolverHost, '/resolve', {
      'name': hostName,
      'type': 'HTTPS',
    });

    final response = await _client
        .get(url, headers: const {'Accept': 'application/dns-json'})
        .timeout(timeout);
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

    final ech = _extractEchFromAnswers(answers);
    if (ech.isNotEmpty) return ech;

    throw Exception('ECH record not found via $resolverHost');
  }

  Future<String> _extractEchConfigViaPanelDoh({
    required String hostName,
    required Duration timeout,
  }) async {
    final uri = await _resolvePanelDohUriForEch(hostName: hostName);

    final response = await _client
        .get(uri, headers: const {'Accept': 'application/dns-json'})
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception(
        'Panel DoH lookup failed for $hostName: DNS status ${response.statusCode}',
      );
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('Panel DoH lookup returned invalid response');
    }
    final answers = body['Answer'];
    if (answers is! List) {
      throw Exception('Panel DoH lookup missing Answer section');
    }

    final ech = _extractEchFromAnswers(answers);
    if (ech.isNotEmpty) return ech;

    throw Exception('ECH record not found via panel DoH route');
  }

  Future<String> _extractEchConfigViaPanelDohForcedIps({
    required String hostName,
    required Duration timeout,
    required List<String> candidateIps,
  }) async {
    final uri = await _resolvePanelDohUriForEch(hostName: hostName);
    final startedAt = DateTime.now();

    for (var index = 0; index < candidateIps.length; index++) {
      final elapsed = DateTime.now().difference(startedAt);
      final remaining = timeout - elapsed;
      if (remaining <= Duration.zero) {
        break;
      }
      final ip = candidateIps[index];
      final perAttempt = remaining < const Duration(seconds: 4)
          ? remaining
          : const Duration(seconds: 4);
      try {
        _logService.logInfo(
          'Trying panel DoH via forced clean IP candidate ${index + 1}/${candidateIps.length}: '
          '$ip (timeout: ${perAttempt.inSeconds}s)',
        );
        final body = await _panelDohForcedIpService.getViaForcedIp(
          uri: uri,
          ip: ip,
          timeout: perAttempt,
        );
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          throw Exception('Panel DoH forced-IP returned invalid response');
        }
        final answers = decoded['Answer'];
        if (answers is! List) {
          throw Exception('Panel DoH forced-IP response missing Answer section');
        }
        final ech = _extractEchFromAnswers(answers);
        if (ech.isNotEmpty) {
          _logService.logOk(
            'Panel DoH forced-IP candidate $ip returned ECH successfully',
          );
          return ech;
        }
        throw Exception('ECH record not found in forced-IP panel DoH response');
      } catch (e) {
        _logService.logWarn(
          'Panel DoH forced-IP candidate $ip failed: $e',
        );
      }
    }

    throw Exception(
      'All forced clean IP candidates failed for panel DoH ECH lookup',
    );
  }

  Future<Uri> _resolvePanelDohUriForEch({required String hostName}) async {
    final manualOverride = await _storageService.getCloudflarePanelDohUrlOverride();
    if (manualOverride != null && manualOverride.isNotEmpty) {
      final parsed = Uri.tryParse(manualOverride);
      if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
        return parsed.replace(
          queryParameters: {'name': hostName, 'type': 'HTTPS'},
        );
      }
      throw Exception('Configured panel DoH URL override is invalid');
    }

    final panelCredentials = await _storageService.getPanelCredentials();
    if (panelCredentials == null) {
      throw Exception('Panel credentials unavailable for panel DoH lookup');
    }

    final subPath = await _resolveSubPathForPanelDoh();
    if (subPath == null || subPath.isEmpty) {
      throw Exception(
        'Panel DoH requires subscription subPath; unable to resolve it from saved subscription URL',
      );
    }

    final baseUrl = panelCredentials.baseUrl.trim().replaceFirst(
      RegExp(r'/*$'),
      '',
    );
    final baseUri = Uri.parse('$baseUrl/dns-query/$subPath');
    // Auto-populate config input with discovered panel DoH URL so user can see
    // the exact route that works on this network.
    try {
      await _storageService.saveCloudflarePanelDohUrlOverride(baseUri.toString());
      _logService.logInfo(
        '[AUTO SAVE] Panel DoH URL override saved from subscription route',
      );
    } catch (_) {}
    return baseUri.replace(
      queryParameters: {'name': hostName, 'type': 'HTTPS'},
    );
  }

  String _extractEchFromAnswers(List answers) {
    for (final item in answers) {
      if (item is! Map) continue;
      final record = item['data']?.toString() ?? '';
      if (record.isEmpty) continue;

      final textMatch = RegExp(r'ech=([^ ]+)').firstMatch(record)?.group(1);
      if (textMatch != null && textMatch.isNotEmpty) {
        return textMatch;
      }

      final wire = _extractEchFromHttpsWireRecord(record);
      if (wire != null && wire.isNotEmpty) {
        return wire;
      }
    }
    return '';
  }

  String? _extractEchFromHttpsWireRecord(String record) {
    final trimmed = record.trim();
    if (!trimmed.startsWith(r'\#')) return null;

    final tokens = trimmed.split(RegExp(r'\s+'));
    if (tokens.length < 3) return null;
    final declaredLength = int.tryParse(tokens[1]);
    if (declaredLength == null || declaredLength <= 0) return null;

    final bytes = <int>[];
    for (var i = 2; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.isEmpty) continue;
      final value = int.tryParse(token, radix: 16);
      if (value == null || value < 0 || value > 255) return null;
      bytes.add(value);
    }
    if (bytes.length < declaredLength) return null;

    final rdata = bytes.sublist(0, declaredLength);
    if (rdata.length < 3) return null;

    int offset = 0;
    offset += 2; // priority
    final nameLength = rdata[offset];
    offset += 1 + nameLength; // target name (usually root for alias form)
    if (offset >= rdata.length) return null;

    while (offset + 4 <= rdata.length) {
      final key = (rdata[offset] << 8) | rdata[offset + 1];
      final valueLength = (rdata[offset + 2] << 8) | rdata[offset + 3];
      offset += 4;
      if (offset + valueLength > rdata.length) return null;
      if (key == 5) {
        final echBytes = rdata.sublist(offset, offset + valueLength);
        return base64Encode(echBytes);
      }
      offset += valueLength;
    }

    return null;
  }

  Future<String?> _resolveSubPathForPanelDoh() async {
    final subscriptionUrl = await _storageService.getSubscriptionUrl();
    if (subscriptionUrl == null || subscriptionUrl.isEmpty) return null;
    final uri = Uri.tryParse(subscriptionUrl);
    if (uri == null) return null;

    final segments = uri.pathSegments;
    final subIndex = segments.indexOf('sub');
    if (subIndex < 0) return null;
    if (subIndex + 2 < segments.length) {
      final subPath = segments[subIndex + 2].trim();
      return subPath.isEmpty ? null : subPath;
    }
    if (subIndex + 1 < segments.length) {
      final subPath = segments[subIndex + 1].trim();
      return subPath.isEmpty ? null : subPath;
    }
    return null;
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
