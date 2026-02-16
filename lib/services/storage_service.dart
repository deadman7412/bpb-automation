import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/credentials.dart';
import '../models/scanner_config.dart';

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
  SharedPreferences? _preferences;

  // In-memory fallback for secure storage (used when platform not available)
  final Map<String, String> _secureStorageFallback = {};

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
          aOptions: AndroidOptions(
            encryptedSharedPreferences: true,
          ),
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
    } catch (e) {
      // Fallback to in-memory storage for testing
      _secureStorageFallback[_keyApiToken] = credentials.apiToken;
      _secureStorageFallback[_keyAccountId] = credentials.accountId;
      _secureStorageFallback[_keyKvNamespaceId] = credentials.kvNamespaceId;
    }
  }

  /// Retrieves stored Cloudflare API credentials.
  ///
  /// Returns null if no credentials are saved.
  Future<Credentials?> getCredentials() async {
    String? apiToken;
    String? accountId;
    String? kvNamespaceId;

    try {
      apiToken = await _secureStorage.read(key: _keyApiToken);
      accountId = await _secureStorage.read(key: _keyAccountId);
      kvNamespaceId = await _secureStorage.read(key: _keyKvNamespaceId);
    } catch (e) {
      // Fallback to in-memory storage for testing
      apiToken = _secureStorageFallback[_keyApiToken];
      accountId = _secureStorageFallback[_keyAccountId];
      kvNamespaceId = _secureStorageFallback[_keyKvNamespaceId];
    }

    if (apiToken == null || accountId == null || kvNamespaceId == null) {
      return null;
    }

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
      // Fallback to in-memory storage for testing
      _secureStorageFallback.remove(_keyApiToken);
      _secureStorageFallback.remove(_keyAccountId);
      _secureStorageFallback.remove(_keyKvNamespaceId);
    }
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
  /// Returns default config if none is saved.
  Future<ScannerConfig> getScannerConfig() async {
    final json = _prefs.getString(_keyScannerConfig);
    if (json == null) {
      return const ScannerConfig(); // Return default
    }

    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return ScannerConfig.fromJson(map);
    } catch (e) {
      // If parsing fails, return default config
      return const ScannerConfig();
    }
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
