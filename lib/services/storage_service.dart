import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/credentials.dart';
import 'log_service.dart';

/// Service for managing persistent storage of credentials and preferences.
///
/// Uses:
/// - flutter_secure_storage for sensitive data (credentials)
/// - shared_preferences for non-sensitive app state
///
/// This is a singleton service - use StorageService.instance to access.
class StorageService {
  static final StorageService _instance = StorageService._internal();
  static StorageService get instance => _instance;

  final FlutterSecureStorage _secureStorage;
  final LogService _logService = LogService.instance;
  SharedPreferences? _preferences;

  // Storage keys
  static const String _keyApiToken = 'cf_api_token';
  static const String _keyAccountId = 'cf_account_id';
  static const String _keyKvNamespaceId = 'cf_kv_namespace_id';
  static const String _keyLastScanTime = 'last_scan_time';
  static const String _keyAutoUpdateEnabled = 'auto_update_enabled';
  static const String _keyAutoUpdateInterval = 'auto_update_interval_hours';
  static const String _keyNumIpsToUse = 'num_ips_to_use';
  static const String _keySubscriptionUrl = 'subscription_url';
  static const String _keyCachedConfigs = 'cached_configs';
  static const String _keyDesiredIPCount = 'desired_ip_count';
  static const String _keyPhase2TestDepth = 'phase2_test_depth';
  static const String _keyEnableIPv6 = 'enable_ipv6';
  static const String _keyMaxSamplesPerCIDR = 'max_samples_per_cidr';
  static const String _keyScanBatchSize = 'scan_batch_size';
  static const String _keyLastScanResult = 'last_scan_result';

  StorageService._internal()
    : _secureStorage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );

  /// Initializes the storage service.
  ///
  /// Must be called before using the service.
  /// Typically called once at app startup.
  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
  }

  /// Ensures preferences are initialized.
  ///
  /// Throws if not initialized.
  SharedPreferences get _prefs {
    if (_preferences == null) {
      throw StateError(
        'StorageService not initialized. Call initialize() first.',
      );
    }
    return _preferences!;
  }

  // ==================== Credentials ====================

  /// Saves Cloudflare API credentials securely.
  ///
  /// Credentials are encrypted using platform-specific secure storage.
  Future<void> saveCredentials(Credentials credentials) async {
    _logService.logInfo('Saving credentials to secure storage');
    _logService.logInfo('API Token length: ${credentials.apiToken.length}');
    _logService.logInfo('Account ID: ${credentials.accountId}');
    _logService.logInfo('KV Namespace ID: ${credentials.kvNamespaceId}');

    try {
      await _secureStorage.write(
        key: _keyApiToken,
        value: credentials.apiToken,
      );
      await _secureStorage.write(
        key: _keyAccountId,
        value: credentials.accountId,
      );
      await _secureStorage.write(
        key: _keyKvNamespaceId,
        value: credentials.kvNamespaceId,
      );
      _logService.logOk('Credentials written to secure storage successfully');
    } catch (e) {
      _logService.logWarn(
        'Failed to write to secure storage, using SharedPreferences fallback: $e',
      );
      // Fallback to SharedPreferences (persists across restarts)
      await _prefs.setString('${_keyApiToken}_fallback', credentials.apiToken);
      await _prefs.setString(
        '${_keyAccountId}_fallback',
        credentials.accountId,
      );
      await _prefs.setString(
        '${_keyKvNamespaceId}_fallback',
        credentials.kvNamespaceId,
      );
      _logService.logOk('Credentials saved to SharedPreferences fallback');
    }
  }

  /// Retrieves stored Cloudflare API credentials.
  ///
  /// Returns null if no credentials are saved.
  Future<Credentials?> getCredentials() async {
    _logService.logInfo('Attempting to load credentials from secure storage');
    String? apiToken;
    String? accountId;
    String? kvNamespaceId;

    try {
      apiToken = await _secureStorage.read(key: _keyApiToken);
      accountId = await _secureStorage.read(key: _keyAccountId);
      kvNamespaceId = await _secureStorage.read(key: _keyKvNamespaceId);

      _logService.logInfo('Read from secure storage:');
      _logService.logInfo(
        '  API Token: ${apiToken != null ? "${apiToken.substring(0, 10)}... (${apiToken.length} chars)" : "null"}',
      );
      _logService.logInfo('  Account ID: ${accountId ?? "null"}');
      _logService.logInfo('  KV Namespace ID: ${kvNamespaceId ?? "null"}');
    } catch (e) {
      _logService.logWarn('Exception reading from secure storage: $e');
    }

    // If secure storage returned null, try SharedPreferences fallback
    if (apiToken == null || accountId == null || kvNamespaceId == null) {
      _logService.logInfo(
        'Secure storage empty, checking SharedPreferences fallback',
      );
      apiToken = _prefs.getString('${_keyApiToken}_fallback');
      accountId = _prefs.getString('${_keyAccountId}_fallback');
      kvNamespaceId = _prefs.getString('${_keyKvNamespaceId}_fallback');

      _logService.logInfo('SharedPreferences fallback values:');
      _logService.logInfo(
        '  API Token: ${apiToken != null ? "${apiToken.substring(0, 10)}... (${apiToken.length} chars)" : "null"}',
      );
      _logService.logInfo('  Account ID: ${accountId ?? "null"}');
      _logService.logInfo('  KV Namespace ID: ${kvNamespaceId ?? "null"}');
    }

    if (apiToken == null || accountId == null || kvNamespaceId == null) {
      _logService.logWarn(
        'Credentials incomplete in both storages - returning null',
      );
      return null;
    }

    _logService.logOk('Credentials loaded successfully');
    return Credentials(
      apiToken: apiToken,
      accountId: accountId,
      kvNamespaceId: kvNamespaceId,
    );
  }

  /// Clears all stored credentials.
  Future<void> clearCredentials() async {
    try {
      await _secureStorage.delete(key: _keyApiToken);
      await _secureStorage.delete(key: _keyAccountId);
      await _secureStorage.delete(key: _keyKvNamespaceId);
    } catch (e) {
      // Silent fail for secure storage
    }
    // Also clear SharedPreferences fallback
    await _prefs.remove('${_keyApiToken}_fallback');
    await _prefs.remove('${_keyAccountId}_fallback');
    await _prefs.remove('${_keyKvNamespaceId}_fallback');
  }

  /// Returns true if credentials are stored.
  Future<bool> hasCredentials() async {
    final creds = await getCredentials();
    return creds != null && creds.isValid();
  }

  // ==================== App Preferences ====================

  /// Saves the timestamp of the last scan.
  Future<void> saveLastScanTime(DateTime time) async {
    await _prefs.setString(_keyLastScanTime, time.toIso8601String());
  }

  /// Retrieves the timestamp of the last scan.
  ///
  /// Returns null if no scan has been performed.
  Future<DateTime?> getLastScanTime() async {
    final timeStr = _prefs.getString(_keyLastScanTime);
    if (timeStr == null) return null;

    try {
      return DateTime.parse(timeStr);
    } catch (e) {
      return null;
    }
  }

  /// Saves whether auto-update is enabled.
  Future<void> saveAutoUpdateEnabled(bool enabled) async {
    await _prefs.setBool(_keyAutoUpdateEnabled, enabled);
  }

  /// Retrieves whether auto-update is enabled.
  ///
  /// Defaults to false if not set.
  Future<bool> getAutoUpdateEnabled() async {
    return _prefs.getBool(_keyAutoUpdateEnabled) ?? false;
  }

  /// Saves the auto-update interval in hours.
  Future<void> saveAutoUpdateInterval(int hours) async {
    await _prefs.setInt(_keyAutoUpdateInterval, hours);
  }

  /// Retrieves the auto-update interval in hours.
  ///
  /// Defaults to 24 hours if not set.
  Future<int> getAutoUpdateInterval() async {
    return _prefs.getInt(_keyAutoUpdateInterval) ?? 24;
  }

  /// Saves the number of IPs to use from scan results.
  Future<void> saveNumIpsToUse(int count) async {
    await _prefs.setInt(_keyNumIpsToUse, count);
  }

  /// Retrieves the number of IPs to use from scan results.
  ///
  /// Defaults to 5 if not set.
  Future<int> getNumIpsToUse() async {
    return _prefs.getInt(_keyNumIpsToUse) ?? 5;
  }

  /// Saves the subscription URL for config-based scanning.
  ///
  /// This URL should point to a BPB Panel subscription endpoint.
  Future<void> saveSubscriptionUrl(String url) async {
    await _prefs.setString(_keySubscriptionUrl, url);
    _logService.logInfo('Saved subscription URL');
  }

  /// Retrieves the saved subscription URL.
  ///
  /// Returns null if no URL has been saved.
  Future<String?> getSubscriptionUrl() async {
    return _prefs.getString(_keySubscriptionUrl);
  }

  /// Saves cached XrayConfigs to storage.
  ///
  /// This allows scans to use pre-validated configs without fetching
  /// from the network each time.
  Future<void> saveCachedConfigs(List<dynamic> configs) async {
    final jsonList = configs.map((c) => c.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    await _prefs.setString(_keyCachedConfigs, jsonString);
    _logService.logInfo('Saved ${configs.length} cached configs');
  }

  /// Retrieves cached XrayConfigs from storage.
  ///
  /// Returns null if no configs are cached.
  Future<List<dynamic>?> getCachedConfigs() async {
    final jsonString = _prefs.getString(_keyCachedConfigs);
    if (jsonString == null) return null;

    try {
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      // Import XrayConfig here to avoid circular dependency
      final configs = jsonList.map((json) {
        // Return raw JSON - caller will convert to XrayConfig
        return json as Map<String, dynamic>;
      }).toList();
      return configs;
    } catch (e) {
      _logService.logWarn('Failed to parse cached configs: $e');
      return null;
    }
  }

  /// Clears cached configs from storage.
  Future<void> clearCachedConfigs() async {
    await _prefs.remove(_keyCachedConfigs);
    _logService.logInfo('Cleared cached configs');
  }

  /// Saves scan parameters (desired IP count and Phase 2 test depth).
  Future<void> saveScanParameters({
    int? desiredIPCount,
    int? phase2TestDepth,
    int? enableIPv6,
    int? maxSamplesPerCIDR,
    int? scanBatchSize,
  }) async {
    if (desiredIPCount != null) {
      await _prefs.setInt(_keyDesiredIPCount, desiredIPCount);
    }
    if (phase2TestDepth != null) {
      await _prefs.setInt(_keyPhase2TestDepth, phase2TestDepth);
    }
    if (enableIPv6 != null) {
      await _prefs.setInt(_keyEnableIPv6, enableIPv6);
    }
    if (maxSamplesPerCIDR != null) {
      await _prefs.setInt(_keyMaxSamplesPerCIDR, maxSamplesPerCIDR);
    }
    if (scanBatchSize != null) {
      await _prefs.setInt(_keyScanBatchSize, scanBatchSize);
    }
    _logService.logInfo('Saved scan parameters');
  }

  /// Retrieves scan parameters.
  ///
  /// Returns a map with all scan settings.
  /// Defaults: desiredIPCount=5, phase2TestDepth=50, enableIPv6=0,
  ///           maxSamplesPerCIDR=100, scanBatchSize=200
  Future<Map<String, int>> getScanParameters() async {
    return {
      'desiredIPCount': _prefs.getInt(_keyDesiredIPCount) ?? 5,
      'phase2TestDepth': _prefs.getInt(_keyPhase2TestDepth) ?? 50,
      'enableIPv6': _prefs.getInt(_keyEnableIPv6) ?? 0,
      'maxSamplesPerCIDR': _prefs.getInt(_keyMaxSamplesPerCIDR) ?? 100,
      'scanBatchSize': _prefs.getInt(_keyScanBatchSize) ?? 200,
    };
  }

  /// Saves the last scan result to storage (compact — only working IP results).
  Future<void> saveLastScanResult(Map<String, dynamic> resultJson) async {
    try {
      final jsonString = jsonEncode(resultJson);
      await _prefs.setString(_keyLastScanResult, jsonString);
      _logService.logInfo('Saved last scan result to storage');
    } catch (e) {
      _logService.logWarn('Failed to save last scan result: $e');
    }
  }

  /// Retrieves the last scan result from storage.
  ///
  /// Returns null if no result has been saved or if parsing fails.
  Future<Map<String, dynamic>?> getLastScanResult() async {
    try {
      final jsonString = _prefs.getString(_keyLastScanResult);
      if (jsonString == null) return null;
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      _logService.logWarn('Failed to load last scan result: $e');
      return null;
    }
  }

  // ==================== Generic Preferences ====================

  /// Saves a string preference.
  Future<void> saveString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  /// Retrieves a string preference.
  Future<String?> getString(String key) async {
    return _prefs.getString(key);
  }

  /// Saves an integer preference.
  Future<void> saveInt(String key, int value) async {
    await _prefs.setInt(key, value);
  }

  /// Retrieves an integer preference.
  Future<int?> getInt(String key) async {
    return _prefs.getInt(key);
  }

  /// Saves a boolean preference.
  Future<void> saveBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  /// Retrieves a boolean preference.
  Future<bool?> getBool(String key) async {
    return _prefs.getBool(key);
  }

  /// Saves a double preference.
  Future<void> saveDouble(String key, double value) async {
    await _prefs.setDouble(key, value);
  }

  /// Retrieves a double preference.
  Future<double?> getDouble(String key) async {
    return _prefs.getDouble(key);
  }

  /// Removes a preference.
  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }

  /// Clears all preferences (except credentials).
  Future<void> clearPreferences() async {
    await _prefs.clear();
  }

  /// Clears all data (credentials and preferences).
  Future<void> clearAll() async {
    await clearCredentials();
    await clearPreferences();
  }

  /// Returns true if the service is initialized.
  bool get isInitialized => _preferences != null;
}
