import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/credentials.dart';
import '../models/proxy_settings.dart';
import 'log_service.dart';

/// Service for interacting with Cloudflare Workers KV API
class CloudflareApiService {
  static final CloudflareApiService _instance = CloudflareApiService._internal();
  static CloudflareApiService get instance => _instance;

  CloudflareApiService._internal();

  final LogService _logService = LogService.instance;

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

  /// Validate credentials by making a test API call
  Future<bool> validateCredentials(Credentials credentials) async {
    try {
      _logService.logInfo('Validating Cloudflare credentials');

      // Validate credential format first
      final validationErrors = credentials.validate();
      if (validationErrors.isNotEmpty) {
        _logService.logWarn('Credential validation failed: ${validationErrors.join(", ")}');
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
        _logService.logWarn('Unexpected response: ${response.statusCode} ${response.body}');
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
  Future<ProxySettings?> _getProxySettingsInternal(Credentials credentials) async {
    try {
      _logService.logInfo('Fetching proxySettings from Cloudflare KV');

      final url = Uri.parse(
        '$_baseUrl/accounts/${credentials.accountId}/storage/kv/namespaces/${credentials.kvNamespaceId}/values/proxySettings',
      );

      _logService.logInfo('GET $url');

      final response = await _client
          .get(url, headers: _buildHeaders(credentials))
          .timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        _logService.logOk('ProxySettings fetched successfully');

        // Parse JSON response
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        final settings = ProxySettings.fromJson(jsonData);

        _logService.logInfo('Current cleanIPs count: ${settings.cleanIPs.length}');

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
  Future<bool> updateCleanIPs(Credentials credentials, List<String> cleanIPs) async {
    return await _retryOperation(() => _updateCleanIPsInternal(credentials, cleanIPs));
  }

  /// Internal method to update clean IPs (without retry logic)
  Future<bool> _updateCleanIPsInternal(
    Credentials credentials,
    List<String> cleanIPs,
  ) async {
    try {
      _logService.logInfo('Updating cleanIPs in Cloudflare KV (${cleanIPs.length} IPs)');

      // Step 1: Read current settings
      _logService.logInfo('Step 1: Reading current proxySettings');
      final currentSettings = await _getProxySettingsInternal(credentials);

      if (currentSettings == null) {
        throw CloudflareApiException('proxySettings not found in KV', 404);
      }

      // Step 2: Update only cleanIPs field
      _logService.logInfo('Step 2: Updating cleanIPs field');
      final updatedSettings = currentSettings.copyWithCleanIPs(cleanIPs);

      // Step 3: Write back to KV
      _logService.logInfo('Step 3: Writing updated settings to KV');
      final url = Uri.parse(
        '$_baseUrl/accounts/${credentials.accountId}/storage/kv/namespaces/${credentials.kvNamespaceId}/values/proxySettings',
      );

      _logService.logInfo('PUT $url');

      final response = await _client
          .put(
            url,
            headers: _buildHeaders(credentials),
            body: jsonEncode(updatedSettings.toJson()),
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

      final response = await _client
          .get(url)
          .timeout(_defaultTimeout);

      // This endpoint should return 401 without auth, which proves connectivity
      if (response.statusCode == 401 || response.statusCode == 200) {
        _logService.logOk('Cloudflare API is reachable');
        return true;
      }

      _logService.logWarn('Unexpected response from API: ${response.statusCode}');
      return false;
    } catch (e, stackTrace) {
      _logService.logError('Failed to connect to Cloudflare API', e, stackTrace);
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
