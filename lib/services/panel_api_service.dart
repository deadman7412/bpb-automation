import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/panel_credentials.dart';
import '../models/xray_config.dart';
import '../utils/socks5_helper.dart';
import 'log_service.dart';
import 'storage_service.dart';
import 'xray_service.dart';

/// Service for interacting with BPB Panel API endpoints.
class PanelApiService {
  static final PanelApiService _instance = PanelApiService._internal();
  static PanelApiService get instance => _instance;

  PanelApiService._internal();

  final LogService _logService = LogService.instance;
  final StorageService _storageService = StorageService.instance;
  final XrayService _xrayService = XrayService.instance;

  static const Duration _defaultTimeout = Duration(seconds: 30);

  http.Client _client = http.Client();
  String? _sessionCookie;

  void setClient(http.Client client) {
    _client = client;
  }

  void clearSession() {
    _sessionCookie = null;
  }

  bool isConnectivityError(Object error) {
    if (error is TimeoutException || error is http.ClientException) {
      return true;
    }

    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('connection refused') ||
        message.contains('network is unreachable') ||
        message.contains('connection reset') ||
        message.contains('timed out');
  }

  Future<void> verifyCredentials(PanelCredentials credentials) async {
    final validationErrors = credentials.validate();
    if (validationErrors.isNotEmpty) {
      throw PanelApiException(
        'Panel credential validation failed: ${validationErrors.join(", ")}',
        400,
      );
    }

    await _login(credentials);
    await _getSettings(credentials.baseUrl);
  }

  Future<bool> validateCredentials(PanelCredentials credentials) async {
    try {
      await verifyCredentials(credentials);
      _logService.logOk('Panel credentials validated successfully');
      return true;
    } catch (e, stackTrace) {
      _logService.logError(
        'Failed to validate panel credentials',
        e,
        stackTrace,
      );
      return false;
    }
  }

  Future<bool> updateCleanIPs(
    PanelCredentials credentials,
    List<String> cleanIPs,
  ) async {
    _logService.logInfo(
      'Updating cleanIPs via panel API (${cleanIPs.length} IPs)',
    );

    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        await _ensureLoggedIn(credentials);

        final settingsResponse = await _getSettings(credentials.baseUrl);
        final proxySettingsRaw = settingsResponse['proxySettings'];
        if (proxySettingsRaw is! Map<String, dynamic>) {
          throw PanelApiException(
            'Panel /settings response missing proxySettings object',
            500,
          );
        }

        final updatedSettings = Map<String, dynamic>.from(proxySettingsRaw);
        updatedSettings['cleanIPs'] = cleanIPs;

        await _updateSettings(credentials.baseUrl, updatedSettings);
        _logService.logOk('CleanIPs updated successfully via panel API');
        return true;
      } on PanelApiException catch (e) {
        if (e.statusCode == 401 && attempt == 1) {
          _logService.logWarn(
            'Panel session expired, re-authenticating and retrying once',
          );
          _sessionCookie = null;
          continue;
        }
        rethrow;
      }
    }

    return false;
  }

  Future<bool> updateCleanIPsViaXrayProxy(
    PanelCredentials credentials,
    List<String> cleanIPs, {
    bool enableDiagnostics = false,
    XrayConfig? templateConfig,
  }) async {
    final validationErrors = credentials.validate();
    if (validationErrors.isNotEmpty) {
      throw PanelApiException(
        'Panel credential validation failed: ${validationErrors.join(", ")}',
        400,
      );
    }

    final config = templateConfig ?? await _loadTemplateConfig();
    if (config == null) {
      throw PanelApiException(
        'No cached Xray config available for panel proxy update',
        500,
      );
    }

    final candidates = cleanIPs.where((ip) => ip.trim().isNotEmpty).toList();
    if (candidates.isEmpty) {
      throw PanelApiException(
        'No clean IP candidates available for proxy',
        400,
      );
    }

    _logService.logInfo(
      'Updating cleanIPs via panel API through Xray proxy (${candidates.length} proxy candidate(s), ${cleanIPs.length} clean IPs)',
    );

    Object? lastError;
    for (int i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      try {
        _logService.logInfo(
          'Trying proxied panel update via candidate ${i + 1}/${candidates.length}: $candidate',
        );
        await _xrayService.runWithSocksProxy<void>(
          config: config,
          candidateIP: candidate,
          action: (socksPort) async {
            _sessionCookie = null;
            if (enableDiagnostics) {
              await _runProxyDiagnostics(
                credentials: credentials,
                socksPort: socksPort,
              );
            }
            await _applyCleanIPsUpdateViaSocks(
              credentials: credentials,
              cleanIPs: cleanIPs,
              socksPort: socksPort,
            );
          },
        );
        _logService.logOk(
          'Proxied panel update succeeded via candidate $candidate',
        );
        return true;
      } catch (e, stackTrace) {
        lastError = e;
        _logService.logWarn(
          'Proxied update failed via candidate $candidate: $e',
        );
        _logService.logError(
          'Proxy candidate failure stack trace',
          e,
          stackTrace,
        );
      }
    }

    throw PanelApiException(
      'All proxy candidates failed for panel update. Last error: $lastError',
      503,
    );
  }

  Future<bool> updateCleanIPsViaForcedCleanIPs(
    PanelCredentials credentials,
    List<String> cleanIPs, {
    required List<String> candidateIPs,
  }) async {
    final validationErrors = credentials.validate();
    if (validationErrors.isNotEmpty) {
      throw PanelApiException(
        'Panel credential validation failed: ${validationErrors.join(", ")}',
        400,
      );
    }

    final candidates = candidateIPs
        .map((ip) => ip.trim())
        .where((ip) => ip.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (candidates.isEmpty) {
      throw PanelApiException(
        'No clean IP candidates available for forced panel routing',
        400,
      );
    }

    _logService.logInfo(
      'Updating cleanIPs via panel API through forced clean IP routing (${candidates.length} candidate(s), ${cleanIPs.length} clean IPs)',
    );

    Object? lastError;
    for (int i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      try {
        _logService.logInfo(
          'Trying forced panel update via candidate ${i + 1}/${candidates.length}: $candidate',
        );
        _sessionCookie = null;
        await _applyCleanIPsUpdateViaForcedIp(
          credentials: credentials,
          cleanIPs: cleanIPs,
          forcedIp: candidate,
        );
        _logService.logOk(
          'Forced panel update succeeded via candidate $candidate',
        );
        return true;
      } catch (e, stackTrace) {
        lastError = e;
        _logService.logWarn(
          'Forced panel update failed via candidate $candidate: $e',
        );
        _logService.logError(
          'Forced panel candidate failure stack trace',
          e,
          stackTrace,
        );
      }
    }

    throw PanelApiException(
      'All forced clean IP candidates failed for panel update. Last error: $lastError',
      503,
    );
  }

  /// Fetches the panel normal subscription URL using the current [subPath].
  ///
  /// Returns null when subPath is unavailable in panel settings.
  Future<String?> fetchNormalSubscriptionUrl(
    PanelCredentials credentials,
  ) async {
    _logService.logInfo('Fetching normal subscription URL via panel API');

    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        await _ensureLoggedIn(credentials);
        final settingsResponse = await _getSettings(credentials.baseUrl);
        final subPath = settingsResponse['subPath'];

        if (subPath is! String || subPath.trim().isEmpty) {
          _logService.logWarn(
            'Panel settings did not include a usable subPath; skipping auto subscription URL population',
          );
          return null;
        }

        final normalizedBase = credentials.baseUrl.trim().replaceFirst(
          RegExp(r'/*$'),
          '',
        );
        final rawPath = subPath.trim();
        final path = rawPath.startsWith('/sub/')
            ? rawPath
            : '/sub/normal/$rawPath';
        final uri = Uri.parse('$normalizedBase$path');
        final query = Map<String, String>.from(uri.queryParameters);
        query.putIfAbsent('app', () => 'xray');
        final normalizedUrl = uri.replace(queryParameters: query).toString();

        _logService.logOk('Fetched normal subscription URL from panel API');
        return normalizedUrl;
      } on PanelApiException catch (e) {
        if (e.statusCode == 401 && attempt == 1) {
          _logService.logWarn(
            'Panel session expired while fetching subscription URL, re-authenticating and retrying once',
          );
          _sessionCookie = null;
          continue;
        }
        rethrow;
      }
    }

    return null;
  }

  Future<void> _applyCleanIPsUpdateViaSocks({
    required PanelCredentials credentials,
    required List<String> cleanIPs,
    required int socksPort,
  }) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        await _ensureLoggedInViaSocks(credentials, socksPort);
        final settingsResponse = await _getSettingsViaSocks(
          credentials.baseUrl,
          socksPort,
        );
        final proxySettingsRaw = settingsResponse['proxySettings'];
        if (proxySettingsRaw is! Map<String, dynamic>) {
          throw PanelApiException(
            'Panel /settings response missing proxySettings object',
            500,
          );
        }

        final updatedSettings = Map<String, dynamic>.from(proxySettingsRaw);
        updatedSettings['cleanIPs'] = cleanIPs;
        await _updateSettingsViaSocks(
          credentials.baseUrl,
          updatedSettings,
          socksPort,
        );
        return;
      } on PanelApiException catch (e) {
        if (e.statusCode == 401 && attempt == 1) {
          _logService.logWarn(
            'Panel proxy session expired, re-authenticating and retrying once',
          );
          _sessionCookie = null;
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _applyCleanIPsUpdateViaForcedIp({
    required PanelCredentials credentials,
    required List<String> cleanIPs,
    required String forcedIp,
  }) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        _logService.logInfo(
          '[Forced panel][$forcedIp] Attempt $attempt: ensuring authenticated session',
        );
        await _ensureLoggedInViaForcedIp(credentials, forcedIp);
        _logService.logInfo(
          '[Forced panel][$forcedIp] Attempt $attempt: fetching /panel/settings',
        );
        final settingsResponse = await _getSettingsViaForcedIp(
          credentials.baseUrl,
          forcedIp,
        );
        final proxySettingsRaw = settingsResponse['proxySettings'];
        if (proxySettingsRaw is! Map<String, dynamic>) {
          throw PanelApiException(
            'Panel /settings response missing proxySettings object',
            500,
          );
        }

        final updatedSettings = Map<String, dynamic>.from(proxySettingsRaw);
        updatedSettings['cleanIPs'] = cleanIPs;
        _logService.logInfo(
          '[Forced panel][$forcedIp] Attempt $attempt: sending /panel/update-settings with ${cleanIPs.length} clean IPs',
        );
        await _updateSettingsViaForcedIp(
          credentials.baseUrl,
          updatedSettings,
          forcedIp,
        );
        _logService.logOk(
          '[Forced panel][$forcedIp] Attempt $attempt: update path completed',
        );
        return;
      } on PanelApiException catch (e) {
        if (e.statusCode == 401 && attempt == 1) {
          _logService.logWarn(
            '[Forced panel][$forcedIp] Session expired (401), re-authenticating and retrying once',
          );
          _sessionCookie = null;
          continue;
        }
        _logService.logWarn(
          '[Forced panel][$forcedIp] Attempt $attempt failed: $e',
        );
        rethrow;
      }
    }
  }

  Future<void> _ensureLoggedInViaSocks(
    PanelCredentials credentials,
    int socksPort,
  ) async {
    if (_sessionCookie != null) return;
    await _loginViaSocks(credentials, socksPort);
  }

  Future<void> _ensureLoggedInViaForcedIp(
    PanelCredentials credentials,
    String forcedIp,
  ) async {
    if (_sessionCookie != null) return;
    await _loginViaForcedIp(credentials, forcedIp);
  }

  Future<void> _loginViaSocks(
    PanelCredentials credentials,
    int socksPort,
  ) async {
    _logService.logInfo('Authenticating with panel API');
    final url = _buildUri(credentials.baseUrl, '/login/authenticate');
    final response = await _sendViaSocks(
      socksPort: socksPort,
      method: 'POST',
      uri: url,
      headers: const {'Content-Type': 'text/plain'},
      body: credentials.password,
    );

    final decoded = _decodeJsonBodyOrThrow(
      body: response.body,
      statusCode: response.statusCode,
    );
    if (response.statusCode != 200 || decoded['success'] != true) {
      throw PanelApiException(
        'Panel login failed: ${decoded['message'] ?? 'Unknown error'}',
        response.statusCode,
      );
    }

    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) {
      throw PanelApiException(
        'Panel login succeeded but no session cookie returned',
        500,
      );
    }
    final cookiePair = setCookie.split(';').first.trim();
    if (!cookiePair.startsWith('jwtToken=')) {
      throw PanelApiException(
        'Panel login returned invalid session cookie',
        500,
      );
    }

    _sessionCookie = cookiePair;
    _logService.logOk('Panel authentication successful');
  }

  Future<void> _loginViaForcedIp(
    PanelCredentials credentials,
    String forcedIp,
  ) async {
    _logService.logInfo(
      'Authenticating with panel API via forced IP $forcedIp',
    );
    final url = _buildUri(credentials.baseUrl, '/login/authenticate');
    final response = await _sendViaForcedIp(
      forcedIp: forcedIp,
      method: 'POST',
      uri: url,
      headers: const {'Content-Type': 'text/plain'},
      body: credentials.password,
    );

    final decoded = _decodeJsonBodyOrThrow(
      body: response.body,
      statusCode: response.statusCode,
    );
    if (response.statusCode != 200 || decoded['success'] != true) {
      throw PanelApiException(
        'Panel login failed: ${decoded['message'] ?? 'Unknown error'}',
        response.statusCode,
      );
    }

    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) {
      throw PanelApiException(
        'Panel login succeeded but no session cookie returned',
        500,
      );
    }
    final cookiePair = setCookie.split(';').first.trim();
    if (!cookiePair.startsWith('jwtToken=')) {
      throw PanelApiException(
        'Panel login returned invalid session cookie',
        500,
      );
    }

    _sessionCookie = cookiePair;
    _logService.logOk(
      'Panel authentication successful via forced IP $forcedIp',
    );
  }

  Future<Map<String, dynamic>> _getSettingsViaSocks(
    String baseUrl,
    int socksPort,
  ) async {
    final url = _buildUri(baseUrl, '/panel/settings');
    final sessionCookie = _sessionCookie;
    final cookieHeader = sessionCookie == null
        ? const <String, String>{}
        : <String, String>{'Cookie': sessionCookie};
    final response = await _sendViaSocks(
      socksPort: socksPort,
      method: 'GET',
      uri: url,
      headers: {'Content-Type': 'application/json', ...cookieHeader},
    );
    final decoded = _decodeJsonBodyOrThrow(
      body: response.body,
      statusCode: response.statusCode,
    );
    _throwIfErrorDecoded(
      responseStatusCode: response.statusCode,
      decoded: decoded,
      action: 'read panel settings',
    );
    final body = decoded['body'];
    if (body is! Map<String, dynamic>) {
      throw PanelApiException(
        'Panel /settings returned invalid body payload',
        500,
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> _getSettingsViaForcedIp(
    String baseUrl,
    String forcedIp,
  ) async {
    final url = _buildUri(baseUrl, '/panel/settings');
    final sessionCookie = _sessionCookie;
    final cookieHeader = sessionCookie == null
        ? const <String, String>{}
        : <String, String>{'Cookie': sessionCookie};
    final response = await _sendViaForcedIp(
      forcedIp: forcedIp,
      method: 'GET',
      uri: url,
      headers: {'Content-Type': 'application/json', ...cookieHeader},
    );
    final decoded = _decodeJsonBodyOrThrow(
      body: response.body,
      statusCode: response.statusCode,
    );
    _throwIfErrorDecoded(
      responseStatusCode: response.statusCode,
      decoded: decoded,
      action: 'read panel settings',
    );
    final body = decoded['body'];
    if (body is! Map<String, dynamic>) {
      throw PanelApiException(
        'Panel /settings returned invalid body payload',
        500,
      );
    }
    return body;
  }

  Future<void> _updateSettingsViaSocks(
    String baseUrl,
    Map<String, dynamic> settings,
    int socksPort,
  ) async {
    final url = _buildUri(baseUrl, '/panel/update-settings');
    final sessionCookie = _sessionCookie;
    final cookieHeader = sessionCookie == null
        ? const <String, String>{}
        : <String, String>{'Cookie': sessionCookie};
    final response = await _sendViaSocks(
      socksPort: socksPort,
      method: 'PUT',
      uri: url,
      headers: {'Content-Type': 'application/json', ...cookieHeader},
      body: jsonEncode(settings),
    );
    final decoded = _decodeJsonBodyOrThrow(
      body: response.body,
      statusCode: response.statusCode,
    );
    _throwIfErrorDecoded(
      responseStatusCode: response.statusCode,
      decoded: decoded,
      action: 'update panel settings',
    );
  }

  Future<void> _updateSettingsViaForcedIp(
    String baseUrl,
    Map<String, dynamic> settings,
    String forcedIp,
  ) async {
    final url = _buildUri(baseUrl, '/panel/update-settings');
    final sessionCookie = _sessionCookie;
    final cookieHeader = sessionCookie == null
        ? const <String, String>{}
        : <String, String>{'Cookie': sessionCookie};
    final response = await _sendViaForcedIp(
      forcedIp: forcedIp,
      method: 'PUT',
      uri: url,
      headers: {'Content-Type': 'application/json', ...cookieHeader},
      body: jsonEncode(settings),
    );
    final decoded = _decodeJsonBodyOrThrow(
      body: response.body,
      statusCode: response.statusCode,
    );
    _throwIfErrorDecoded(
      responseStatusCode: response.statusCode,
      decoded: decoded,
      action: 'update panel settings',
    );
  }

  Future<_RawHttpResponse> _sendViaSocks({
    required int socksPort,
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
    String body = '',
  }) async {
    Socks5Connection? conn;
    SecureSocket? tlsSocket;

    try {
      final targetPort = uri.hasPort
          ? uri.port
          : (uri.scheme.toLowerCase() == 'https' ? 443 : 80);

      conn = await Socks5Helper.connectViaSocks5(
        socksHost: '127.0.0.1',
        socksPort: socksPort,
        targetHost: uri.host,
        targetPort: targetPort,
        timeout: 12,
      );

      final isHttps = uri.scheme.toLowerCase() == 'https';
      if (uri.scheme.toLowerCase() == 'https') {
        _logService.logInfo(
          'Upgrading SOCKS tunnel to TLS for ${uri.host}:$targetPort',
        );
        tlsSocket = await conn.secure(host: uri.host);
      }

      final normalizedPath = uri.path.isEmpty ? '/' : uri.path;
      final requestTarget = uri.hasQuery
          ? '$normalizedPath?${uri.query}'
          : normalizedPath;

      final requestHeaders = <String, String>{
        'Host': uri.host,
        'Connection': 'close',
        'Accept': 'application/json',
        'Accept-Encoding': 'identity',
        ...headers,
      };
      if (body.isNotEmpty) {
        requestHeaders['Content-Length'] = utf8.encode(body).length.toString();
      }

      final buffer = StringBuffer();
      buffer.write('$method $requestTarget HTTP/1.1\r\n');
      requestHeaders.forEach((k, v) => buffer.write('$k: $v\r\n'));
      buffer.write('\r\n');
      if (body.isNotEmpty) {
        buffer.write(body);
      }

      if (isHttps) {
        tlsSocket!.write(buffer.toString());
        await tlsSocket.flush();
      } else {
        conn.write(utf8.encode(buffer.toString()));
        await conn.flush();
      }

      final raw = isHttps
          ? await utf8.decoder.bind(tlsSocket!).join().timeout(_defaultTimeout)
          : await _readHttpFromPlainSocks(conn);
      if (raw.trim().isEmpty) {
        throw PanelApiException('Empty response via SOCKS proxy', 503);
      }

      return _RawHttpResponse.parse(raw);
    } on PanelApiException {
      rethrow;
    } catch (e) {
      throw PanelApiException('SOCKS request failed: $e', 503);
    } finally {
      try {
        await tlsSocket?.close();
      } catch (_) {}
      try {
        await conn?.close();
      } catch (_) {}
    }
  }

  Future<_RawHttpResponse> _sendViaForcedIp({
    required String forcedIp,
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
    String body = '',
  }) async {
    final client = HttpClient();
    try {
      final targetPort = uri.hasPort
          ? uri.port
          : (uri.scheme.toLowerCase() == 'https' ? 443 : 80);
      _logService.logInfo(
        'Connecting directly via forced IP $forcedIp to ${uri.host}:$targetPort',
      );
      client.findProxy = (url) => 'DIRECT';
      client.connectionTimeout = const Duration(seconds: 12);
      client.connectionFactory = (url, proxyHost, proxyPort) {
        final isHttps = url.scheme.toLowerCase() == 'https';
        return Future.value(
          ConnectionTask.fromSocket(
            () async {
              final baseSocket = await Socket.connect(
                forcedIp,
                targetPort,
                timeout: const Duration(seconds: 12),
              );
              if (!isHttps) {
                return baseSocket;
              }
              _logService.logInfo(
                'Upgrading forced-IP tunnel to TLS for ${url.host}:$targetPort (ip: $forcedIp)',
              );
              return await SecureSocket.secure(
                baseSocket,
                host: url.host,
              ).timeout(const Duration(seconds: 12));
            }(),
            () {},
          ),
        );
      };

      _logService.logInfo(
        'Using HttpClient forced-IP transport for ${uri.host}:$targetPort (ip: $forcedIp)',
      );
      final request = await client.openUrl(method, uri).timeout(_defaultTimeout);
      request.headers.set(HttpHeaders.hostHeader, uri.host);
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      );
      final origin = '${uri.scheme}://${uri.host}';
      request.headers.set('origin', origin);
      request.headers.set('referer', '$origin/panel');
      request.headers.set('sec-fetch-site', 'same-origin');
      request.headers.set('sec-fetch-mode', 'cors');
      request.headers.set('sec-fetch-dest', 'empty');
      headers.forEach((k, v) => request.headers.set(k, v));

      if (body.isNotEmpty) {
        final bodyBytes = utf8.encode(body);
        request.contentLength = bodyBytes.length;
        request.add(bodyBytes);
      }

      final response = await request.close().timeout(_defaultTimeout);
      final responseBody = await utf8.decoder
          .bind(response)
          .join()
          .timeout(_defaultTimeout);

      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values.join(', ');
      });

      if (response.statusCode == 0 &&
          responseBody.trim().isEmpty &&
          responseHeaders.isEmpty) {
        _logService.logWarn(
          '[Forced panel][$forcedIp] $method ${uri.path.isEmpty ? "/" : uri.path} returned empty response',
        );
        throw PanelApiException('Empty response via forced clean IP', 503);
      }

      final parsed = _RawHttpResponse(
        statusCode: response.statusCode,
        headers: responseHeaders,
        body: responseBody,
      );
      _logService.logInfo(
        '[Forced panel][$forcedIp] $method ${uri.path.isEmpty ? "/" : uri.path} -> HTTP ${parsed.statusCode}',
      );
      return parsed;
    } on PanelApiException {
      rethrow;
    } catch (e) {
      _logService.logWarn(
        '[Forced panel][$forcedIp] $method ${uri.path.isEmpty ? "/" : uri.path} threw: $e',
      );
      throw PanelApiException('Forced-IP request failed: $e', 503);
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _readHttpFromPlainSocks(Socks5Connection conn) async {
    final bytes = <int>[];
    final deadline = DateTime.now().add(_defaultTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) break;
      List<int> chunk;
      try {
        chunk = await conn.readAvailable(remaining);
      } on TimeoutException {
        break;
      }
      if (chunk.isEmpty) break;
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) break;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> _runProxyDiagnostics({
    required PanelCredentials credentials,
    required int socksPort,
  }) async {
    _logService.logInfo(
      'Panel proxy diagnostics enabled: probing GET /, GET /panel, POST /login/authenticate',
    );
    final endpoints =
        <
          ({
            String method,
            String path,
            String body,
            Map<String, String> headers,
          })
        >[
          (method: 'GET', path: '/', body: '', headers: const {}),
          (method: 'GET', path: '/panel', body: '', headers: const {}),
          (
            method: 'POST',
            path: '/login/authenticate',
            body: credentials.password,
            headers: const {'Content-Type': 'text/plain'},
          ),
        ];

    for (final endpoint in endpoints) {
      try {
        final uri = _buildUri(credentials.baseUrl, endpoint.path);
        final response = await _sendViaSocks(
          socksPort: socksPort,
          method: endpoint.method,
          uri: uri,
          headers: endpoint.headers,
          body: endpoint.body,
        );
        final preview = _singleLinePreview(response.body);
        _logService.logInfo(
          '[Panel proxy debug] ${endpoint.method} ${endpoint.path} -> HTTP ${response.statusCode}, body: $preview',
        );
      } catch (e) {
        _logService.logWarn(
          '[Panel proxy debug] ${endpoint.method} ${endpoint.path} failed: $e',
        );
      }
    }
  }

  String _singleLinePreview(String body) {
    final line = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (line.isEmpty) return '<empty>';
    if (line.length <= 120) return line;
    return '${line.substring(0, 120)}...';
  }

  Future<XrayConfig?> _loadTemplateConfig() async {
    final cached = await _storageService.getCachedConfigs();
    if (cached == null || cached.isEmpty) return null;
    final first = cached.first;
    if (first is! Map<String, dynamic>) return null;
    try {
      return XrayConfig.fromJson(first);
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureLoggedIn(PanelCredentials credentials) async {
    if (_sessionCookie != null) {
      return;
    }
    await _login(credentials);
  }

  Uri _buildUri(String baseUrl, String path) {
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/*$'), '');
    return Uri.parse('$normalized$path');
  }

  Future<void> _login(PanelCredentials credentials) async {
    _logService.logInfo('Authenticating with panel API');
    final url = _buildUri(credentials.baseUrl, '/login/authenticate');

    final response = await _client
        .post(
          url,
          headers: {'Content-Type': 'text/plain'},
          body: credentials.password,
        )
        .timeout(_defaultTimeout);

    final decoded = _decodeJsonResponse(response);
    if (response.statusCode != 200 || decoded['success'] != true) {
      throw PanelApiException(
        'Panel login failed: ${decoded['message'] ?? 'Unknown error'}',
        response.statusCode,
      );
    }

    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) {
      throw PanelApiException(
        'Panel login succeeded but no session cookie returned',
        500,
      );
    }

    final cookiePair = setCookie.split(';').first.trim();
    if (!cookiePair.startsWith('jwtToken=')) {
      throw PanelApiException(
        'Panel login returned invalid session cookie',
        500,
      );
    }

    _sessionCookie = cookiePair;
    _logService.logOk('Panel authentication successful');
  }

  Future<Map<String, dynamic>> _getSettings(String baseUrl) async {
    final url = _buildUri(baseUrl, '/panel/settings');

    final headers = <String, String?>{
      'Content-Type': 'application/json',
      'Cookie': _sessionCookie,
    }..removeWhere((_, value) => value == null);

    final response = await _client
        .get(url, headers: headers.cast<String, String>())
        .timeout(_defaultTimeout);

    final decoded = _decodeJsonResponse(response);
    _throwIfErrorResponse(response, decoded, action: 'read panel settings');

    final body = decoded['body'];
    if (body is! Map<String, dynamic>) {
      throw PanelApiException(
        'Panel /settings returned invalid body payload',
        500,
      );
    }

    return body;
  }

  Future<void> _updateSettings(
    String baseUrl,
    Map<String, dynamic> settings,
  ) async {
    final url = _buildUri(baseUrl, '/panel/update-settings');

    final headers = <String, String?>{
      'Content-Type': 'application/json',
      'Cookie': _sessionCookie,
    }..removeWhere((_, value) => value == null);

    final response = await _client
        .put(
          url,
          headers: headers.cast<String, String>(),
          body: jsonEncode(settings),
        )
        .timeout(_defaultTimeout);

    final decoded = _decodeJsonResponse(response);
    _throwIfErrorResponse(response, decoded, action: 'update panel settings');
  }

  Map<String, dynamic> _decodeJsonResponse(http.Response response) {
    return _decodeJsonBodyOrThrow(
      body: response.body,
      statusCode: response.statusCode,
    );
  }

  Map<String, dynamic> _decodeJsonBodyOrThrow({
    required String body,
    required int statusCode,
  }) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw PanelApiException(
        'Invalid JSON response from panel API: $body',
        statusCode,
      );
    }
  }

  void _throwIfErrorResponse(
    http.Response response,
    Map<String, dynamic> decoded, {
    required String action,
  }) {
    _throwIfErrorDecoded(
      responseStatusCode: response.statusCode,
      decoded: decoded,
      action: action,
    );
  }

  void _throwIfErrorDecoded({
    required int responseStatusCode,
    required Map<String, dynamic> decoded,
    required String action,
  }) {
    if (responseStatusCode == 401 || decoded['status'] == 401) {
      throw PanelApiException('Unauthorized or expired panel session', 401);
    }

    if (responseStatusCode != 200 || decoded['success'] != true) {
      throw PanelApiException(
        'Failed to $action: ${decoded['message'] ?? jsonEncode(decoded)}',
        responseStatusCode,
      );
    }
  }
}

class _RawHttpResponse {
  final int statusCode;
  final Map<String, String> headers;
  final String body;

  const _RawHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  static _RawHttpResponse parse(String raw) {
    final separatorIndex = raw.indexOf('\r\n\r\n');
    final headerPart = separatorIndex >= 0
        ? raw.substring(0, separatorIndex)
        : raw;
    var bodyPart = separatorIndex >= 0 ? raw.substring(separatorIndex + 4) : '';

    final headerLines = headerPart.split('\r\n');
    if (headerLines.isEmpty) {
      throw PanelApiException('Invalid HTTP response via SOCKS proxy', 503);
    }

    final statusMatch = RegExp(
      r'^HTTP/\S+\s+(\d{3})',
    ).firstMatch(headerLines.first);
    if (statusMatch == null) {
      throw PanelApiException(
        'Invalid HTTP status line via SOCKS proxy: ${headerLines.first}',
        503,
      );
    }
    final statusCode = int.tryParse(statusMatch.group(1) ?? '') ?? 0;

    final headers = <String, String>{};
    for (final line in headerLines.skip(1)) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim().toLowerCase();
      final value = line.substring(idx + 1).trim();
      headers[key] = value;
    }

    if ((headers['transfer-encoding'] ?? '').toLowerCase().contains(
      'chunked',
    )) {
      bodyPart = _decodeChunkedBody(bodyPart);
    }

    return _RawHttpResponse(
      statusCode: statusCode,
      headers: headers,
      body: bodyPart,
    );
  }

  static String _decodeChunkedBody(String chunked) {
    final out = StringBuffer();
    var cursor = 0;

    while (cursor < chunked.length) {
      final sizeEnd = chunked.indexOf('\r\n', cursor);
      if (sizeEnd < 0) break;

      final sizeLine = chunked.substring(cursor, sizeEnd).trim();
      final hexPart = sizeLine.split(';').first.trim();
      final chunkSize = int.tryParse(hexPart, radix: 16);
      if (chunkSize == null) break;

      cursor = sizeEnd + 2;
      if (chunkSize == 0) {
        break;
      }

      final chunkEnd = cursor + chunkSize;
      if (chunkEnd > chunked.length) break;
      out.write(chunked.substring(cursor, chunkEnd));
      cursor = chunkEnd;

      if (cursor + 2 <= chunked.length &&
          chunked.substring(cursor, cursor + 2) == '\r\n') {
        cursor += 2;
      }
    }

    return out.toString();
  }
}

class PanelApiException implements Exception {
  final String message;
  final int statusCode;

  PanelApiException(this.message, this.statusCode);

  @override
  String toString() => 'PanelApiException: $message (status: $statusCode)';
}
