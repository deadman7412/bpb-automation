import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/panel_credentials.dart';
import 'log_service.dart';

/// Service for interacting with BPB Panel API endpoints.
class PanelApiService {
  static final PanelApiService _instance = PanelApiService._internal();
  static PanelApiService get instance => _instance;

  PanelApiService._internal();

  final LogService _logService = LogService.instance;

  static const Duration _defaultTimeout = Duration(seconds: 30);

  http.Client _client = http.Client();
  String? _sessionCookie;

  void setClient(http.Client client) {
    _client = client;
  }

  void clearSession() {
    _sessionCookie = null;
  }

  Future<bool> validateCredentials(PanelCredentials credentials) async {
    try {
      final validationErrors = credentials.validate();
      if (validationErrors.isNotEmpty) {
        _logService.logWarn(
          'Panel credential validation failed: ${validationErrors.join(", ")}',
        );
        return false;
      }

      await _login(credentials);
      await _getSettings(credentials.baseUrl);
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
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw PanelApiException(
        'Invalid JSON response from panel API: ${response.body}',
        response.statusCode,
      );
    }
  }

  void _throwIfErrorResponse(
    http.Response response,
    Map<String, dynamic> decoded, {
    required String action,
  }) {
    if (response.statusCode == 401 || decoded['status'] == 401) {
      throw PanelApiException('Unauthorized or expired panel session', 401);
    }

    if (response.statusCode != 200 || decoded['success'] != true) {
      throw PanelApiException(
        'Failed to $action: ${decoded['message'] ?? response.body}',
        response.statusCode,
      );
    }
  }
}

class PanelApiException implements Exception {
  final String message;
  final int statusCode;

  PanelApiException(this.message, this.statusCode);

  @override
  String toString() => 'PanelApiException: $message (status: $statusCode)';
}
