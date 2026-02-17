import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/credentials.dart';
import '../models/scanner_config.dart';
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
  static const String _keyScannerConfig = 'scanner_config';
  static const String _keyLastScanTime = 'last_scan_time';
  static const String _keyAutoUpdateEnabled = 'auto_update_enabled';
  static const String _keyAutoUpdateInterval = 'auto_update_interval_hours';
  static const String _keyNumIpsToUse = 'num_ips_to_use';

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

  // ==================== Scanner Config ====================

  /// Saves scanner configuration.
  Future<void> saveScannerConfig(ScannerConfig config) async {
    final json = jsonEncode(config.toJson());
    await _prefs.setString(_keyScannerConfig, json);
  }

  /// Retrieves scanner configuration.
  ///
  /// - If user has saved a config: Returns their saved preference
  /// - If no config saved (first launch): Auto-detects platform and returns appropriate preset
  ///   - Mobile (Android/iOS): Conservative settings (300ms, 0.2 loss, 2MB/s)
  ///   - Desktop/Web: Unrestricted settings (9999ms, 1.0 loss, 0MB/s)
  Future<ScannerConfig> getScannerConfig() async {
    final json = _prefs.getString(_keyScannerConfig);
    if (json == null) {
      // First launch - auto-detect platform and use appropriate preset
      final config = ScannerConfig.defaultForPlatform();
      final presetName = ScannerConfig.detectedPresetName();
      _logService.logInfo(
        '[INFO] No saved config - auto-detected platform: $presetName',
      );
      _logService.logInfo(
        '[INFO] Using $presetName preset: ${config.threads} threads, ${config.maxLatency}ms latency',
      );
      return config;
    }

    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final config = ScannerConfig.fromJson(map);
      _logService.logInfo('[INFO] Loaded saved scanner config from storage');
      return config;
    } catch (e) {
      // If parsing fails, auto-detect platform
      _logService.logWarn(
        '[WARN] Failed to parse saved config, using platform default: $e',
      );
      return ScannerConfig.defaultForPlatform();
    }
  }

  /// Checks if this is the first time loading scanner config (no saved config exists).
  ///
  /// Used to determine if we should show the platform auto-detection notification.
  /// Returns true if no config has been saved yet, false otherwise.
  Future<bool> isFirstTimeConfig() async {
    final json = _prefs.getString(_keyScannerConfig);
    return json == null;
  }

  // ==================== Scan Results ====================

  static const String _keyLastScanResults = 'last_scan_results';

  /// Saves the last scan results.
  Future<void> saveLastScanResults(List<Map<String, dynamic>> results) async {
    final json = jsonEncode(results);
    await _prefs.setString(_keyLastScanResults, json);
    _logService.logInfo('Saved ${results.length} scan results to storage');
  }

  /// Retrieves the last scan results.
  ///
  /// Returns null if no results are saved.
  Future<List<Map<String, dynamic>>?> getLastScanResults() async {
    final json = _prefs.getString(_keyLastScanResults);
    if (json == null) return null;

    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      _logService.logWarn('Failed to parse last scan results: $e');
      return null;
    }
  }

  /// Clears the last scan results.
  Future<void> clearLastScanResults() async {
    await _prefs.remove(_keyLastScanResults);
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
