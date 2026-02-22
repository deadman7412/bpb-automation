import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/credentials.dart';
import '../models/panel_credentials.dart';
import '../models/update_mode.dart';
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
  static const String _keyPanelBaseUrl = 'panel_base_url';
  static const String _keyPanelPassword = 'panel_password';
  static const String _keyPanelUseProxyForUpdate = 'panel_use_proxy_for_update';
  static const String _keyPanelForceCleanIpsForUpdate =
      'panel_force_clean_ips_for_update';
  static const String _keyPanelEnableProxyDiagnostics =
      'panel_enable_proxy_diagnostics';
  static const String _keyUpdateMode = 'update_mode';
  static const String _keyLastScanTime = 'last_scan_time';
  static const String _keyAutoUpdateEnabled = 'auto_update_enabled';
  static const String _keyAutoUpdateInterval = 'auto_update_interval_hours';
  static const String _keyAutoApplyAfterScan = 'auto_apply_after_scan';
  static const String _keyCloudflareTryEchViaProxy =
      'cloudflare_try_ech_via_proxy';
  static const String _keyCloudflareTryEchViaDirectResolvers =
      'cloudflare_try_ech_via_direct_resolvers';
  static const String _keyCloudflareTryEchViaPanelDoh =
      'cloudflare_try_ech_via_panel_doh';
  static const String _keyCloudflareBypassEchHandlingForPanelV413Plus =
      'cloudflare_bypass_ech_handling_for_panel_v413_plus';
  static const String _keyCloudflareUseCachedEchFallback =
      'cloudflare_use_cached_ech_fallback';
  static const String _keyCloudflareLastSuccessfulEchConfig =
      'cloudflare_last_successful_ech_config';
  static const String _keyCloudflareLastSuccessfulEchSource =
      'cloudflare_last_successful_ech_source';
  static const String _keyCloudflareLastSuccessfulEchAtMs =
      'cloudflare_last_successful_ech_at_ms';
  static const String _keyCloudflarePanelDohUrlOverride =
      'cloudflare_panel_doh_url_override';
  static const String _keyDebugRunProxyConnectivityOnApply =
      'debug_run_proxy_connectivity_on_apply';
  static const String _keyNumIpsToUse = 'num_ips_to_use';
  static const String _keySubscriptionUrl = 'subscription_url';
  static const String _keyCachedConfigs = 'cached_configs';
  static const String _keyDesiredIPCount = 'desired_ip_count';
  static const String _keyPhase2TestDepth = 'phase2_test_depth';
  static const String _keyEnableIPv6 = 'enable_ipv6';
  static const String _keyMaxSamplesPerCIDR = 'max_samples_per_cidr'; // legacy
  static const String _keyIpPoolSize = 'ip_pool_size';
  static const String _keyScanBatchSize = 'scan_batch_size';
  static const String _keyLastScanResult = 'last_scan_result';
  static const String _keyFullScan = 'full_scan';
  static const String _keyUseServerBackend = 'use_server_backend';
  static const String _keyServerBackendBaseUrl = 'server_backend_base_url';
  static const String _keyServerBackendToken = 'server_backend_token';
  static const String _keyServerBackendWebUsername =
      'server_backend_web_username';
  static const String _keyServerBackendJwt = 'server_backend_jwt';

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
    _logService.logInfo('Account ID length: ${credentials.accountId.length}');
    _logService.logInfo(
      'KV Namespace ID length: ${credentials.kvNamespaceId.length}',
    );

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
      _logService.logInfo('  API Token present: ${apiToken != null}');
      _logService.logInfo(
        '  API Token length: ${apiToken != null ? apiToken.length : 0}',
      );
      _logService.logInfo(
        '  Account ID present: ${accountId != null}, length: ${accountId?.length ?? 0}',
      );
      _logService.logInfo(
        '  KV Namespace ID present: ${kvNamespaceId != null}, length: ${kvNamespaceId?.length ?? 0}',
      );
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
      _logService.logInfo('  API Token present: ${apiToken != null}');
      _logService.logInfo(
        '  API Token length: ${apiToken != null ? apiToken.length : 0}',
      );
      _logService.logInfo(
        '  Account ID present: ${accountId != null}, length: ${accountId?.length ?? 0}',
      );
      _logService.logInfo(
        '  KV Namespace ID present: ${kvNamespaceId != null}, length: ${kvNamespaceId?.length ?? 0}',
      );
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

  /// Saves BPB panel API credentials securely.
  Future<void> savePanelCredentials(PanelCredentials credentials) async {
    _logService.logInfo('Saving panel credentials to secure storage');
    _logService.logInfo('Panel base URL: ${credentials.baseUrl}');

    try {
      await _secureStorage.write(
        key: _keyPanelBaseUrl,
        value: credentials.baseUrl,
      );
      await _secureStorage.write(
        key: _keyPanelPassword,
        value: credentials.password,
      );
      _logService.logOk(
        'Panel credentials written to secure storage successfully',
      );
    } catch (e) {
      _logService.logWarn(
        'Failed to write panel credentials to secure storage, using SharedPreferences fallback: $e',
      );
      await _prefs.setString(
        '${_keyPanelBaseUrl}_fallback',
        credentials.baseUrl,
      );
      await _prefs.setString(
        '${_keyPanelPassword}_fallback',
        credentials.password,
      );
      _logService.logOk(
        'Panel credentials saved to SharedPreferences fallback',
      );
    }
  }

  /// Retrieves stored panel API credentials.
  Future<PanelCredentials?> getPanelCredentials() async {
    _logService.logInfo(
      'Attempting to load panel credentials from secure storage',
    );
    String? baseUrl;
    String? password;

    try {
      baseUrl = await _secureStorage.read(key: _keyPanelBaseUrl);
      password = await _secureStorage.read(key: _keyPanelPassword);
    } catch (e) {
      _logService.logWarn(
        'Exception reading panel credentials from secure storage: $e',
      );
    }

    if (baseUrl == null || password == null) {
      _logService.logInfo(
        'Panel secure storage empty, checking SharedPreferences fallback',
      );
      baseUrl = _prefs.getString('${_keyPanelBaseUrl}_fallback');
      password = _prefs.getString('${_keyPanelPassword}_fallback');
    }

    if (baseUrl == null || password == null) {
      _logService.logWarn('Panel credentials incomplete - returning null');
      return null;
    }

    final credentials = PanelCredentials(baseUrl: baseUrl, password: password);
    if (!credentials.isValid()) {
      _logService.logWarn(
        'Stored panel credentials are invalid - returning null',
      );
      return null;
    }

    _logService.logOk('Panel credentials loaded successfully');
    return credentials;
  }

  /// Clears stored panel credentials.
  Future<void> clearPanelCredentials() async {
    try {
      await _secureStorage.delete(key: _keyPanelBaseUrl);
      await _secureStorage.delete(key: _keyPanelPassword);
    } catch (e) {
      // Silent fail for secure storage
    }

    await _prefs.remove('${_keyPanelBaseUrl}_fallback');
    await _prefs.remove('${_keyPanelPassword}_fallback');
  }

  /// Returns true if panel credentials are stored.
  Future<bool> hasPanelCredentials() async {
    final creds = await getPanelCredentials();
    return creds != null && creds.isValid();
  }

  /// Saves which update mode should be used for panel updates.
  Future<void> saveUpdateMode(UpdateMode mode) async {
    await _prefs.setString(_keyUpdateMode, mode.storageValue);
  }

  /// Returns the configured update mode. Defaults to Cloudflare API.
  Future<UpdateMode> getUpdateMode() async {
    final value = _prefs.getString(_keyUpdateMode);
    return UpdateModeX.fromStorageValue(value);
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

  /// Saves whether completed scans should auto-apply working IPs.
  Future<void> saveAutoApplyAfterScan(bool enabled) async {
    await _prefs.setBool(_keyAutoApplyAfterScan, enabled);
  }

  /// Returns whether completed scans should auto-apply working IPs.
  ///
  /// Defaults to false if not set.
  Future<bool> getAutoApplyAfterScan() async {
    return _prefs.getBool(_keyAutoApplyAfterScan) ?? false;
  }

  /// Saves whether Panel API updates should be sent via Xray proxy.
  ///
  /// Defaults to false for predictable behavior.
  Future<void> savePanelUseProxyForUpdate(bool enabled) async {
    await _prefs.setBool(_keyPanelUseProxyForUpdate, enabled);
  }

  /// Returns whether Panel API updates should be sent via Xray proxy.
  ///
  /// Defaults to false if not set.
  Future<bool> getPanelUseProxyForUpdate() async {
    return _prefs.getBool(_keyPanelUseProxyForUpdate) ?? false;
  }

  /// Saves whether Panel API updates should use direct forced clean IP routing
  /// when proxy mode is disabled.
  ///
  /// Defaults to false.
  Future<void> savePanelForceCleanIpsForUpdate(bool enabled) async {
    await _prefs.setBool(_keyPanelForceCleanIpsForUpdate, enabled);
  }

  /// Returns whether Panel API updates should use forced clean IP routing
  /// when proxy mode is disabled.
  ///
  /// Defaults to false if not set.
  Future<bool> getPanelForceCleanIpsForUpdate() async {
    return _prefs.getBool(_keyPanelForceCleanIpsForUpdate) ?? false;
  }

  /// Saves whether verbose panel proxy diagnostics are enabled.
  ///
  /// Defaults to false to avoid noisy logs.
  Future<void> savePanelEnableProxyDiagnostics(bool enabled) async {
    await _prefs.setBool(_keyPanelEnableProxyDiagnostics, enabled);
  }

  /// Returns whether verbose panel proxy diagnostics are enabled.
  ///
  /// Defaults to false if not set.
  Future<bool> getPanelEnableProxyDiagnostics() async {
    return _prefs.getBool(_keyPanelEnableProxyDiagnostics) ?? false;
  }

  /// Saves whether Cloudflare API mode should try ECH refresh via Xray proxy.
  ///
  /// Defaults to false for predictable/fast updates.
  Future<void> saveCloudflareTryEchViaProxy(bool enabled) async {
    await _prefs.setBool(_keyCloudflareTryEchViaProxy, enabled);
  }

  /// Returns whether Cloudflare API mode should try ECH refresh via Xray proxy.
  ///
  /// Defaults to false if not set.
  Future<bool> getCloudflareTryEchViaProxy() async {
    return _prefs.getBool(_keyCloudflareTryEchViaProxy) ?? false;
  }

  /// Saves whether Cloudflare API mode should try ECH refresh via direct DoH
  /// resolvers (dns.google/cloudflare-dns.com).
  ///
  /// Defaults to true for maximum compatibility.
  Future<void> saveCloudflareTryEchViaDirectResolvers(bool enabled) async {
    await _prefs.setBool(_keyCloudflareTryEchViaDirectResolvers, enabled);
  }

  /// Returns whether Cloudflare API mode should try ECH refresh via direct DoH
  /// resolvers (dns.google/cloudflare-dns.com).
  ///
  /// Defaults to true if not set.
  Future<bool> getCloudflareTryEchViaDirectResolvers() async {
    return _prefs.getBool(_keyCloudflareTryEchViaDirectResolvers) ?? true;
  }

  /// Saves whether Cloudflare API mode should try ECH refresh via panel DoH.
  ///
  /// Defaults to true.
  Future<void> saveCloudflareTryEchViaPanelDoh(bool enabled) async {
    await _prefs.setBool(_keyCloudflareTryEchViaPanelDoh, enabled);
  }

  /// Returns whether Cloudflare API mode should try ECH refresh via panel DoH.
  ///
  /// Defaults to true if not set.
  Future<bool> getCloudflareTryEchViaPanelDoh() async {
    return _prefs.getBool(_keyCloudflareTryEchViaPanelDoh) ?? true;
  }

  /// Saves whether app-side ECH handling should be bypassed for
  /// BPB Panel versions 4.1.3+.
  ///
  /// Defaults to true.
  Future<void> saveCloudflareBypassEchHandlingForPanelV413Plus(
    bool enabled,
  ) async {
    await _prefs.setBool(
      _keyCloudflareBypassEchHandlingForPanelV413Plus,
      enabled,
    );
  }

  /// Returns whether app-side ECH handling should be bypassed for
  /// BPB Panel versions 4.1.3+.
  ///
  /// Defaults to true if not set.
  Future<bool> getCloudflareBypassEchHandlingForPanelV413Plus() async {
    return _prefs.getBool(_keyCloudflareBypassEchHandlingForPanelV413Plus) ??
        true;
  }

  /// Saves whether Cloudflare API mode may use cached ECH fallback when live
  /// refresh fails.
  ///
  /// Defaults to true.
  Future<void> saveCloudflareUseCachedEchFallback(bool enabled) async {
    await _prefs.setBool(_keyCloudflareUseCachedEchFallback, enabled);
  }

  /// Returns whether Cloudflare API mode may use cached ECH fallback when live
  /// refresh fails.
  ///
  /// Defaults to true if not set.
  Future<bool> getCloudflareUseCachedEchFallback() async {
    return _prefs.getBool(_keyCloudflareUseCachedEchFallback) ?? true;
  }

  /// Saves the last successful ECH config plus metadata.
  Future<void> saveCloudflareLastSuccessfulEch({
    required String echConfig,
    required String source,
  }) async {
    await _prefs.setString(_keyCloudflareLastSuccessfulEchConfig, echConfig);
    await _prefs.setString(_keyCloudflareLastSuccessfulEchSource, source);
    await _prefs.setInt(
      _keyCloudflareLastSuccessfulEchAtMs,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Returns last successful ECH config, or null if unavailable.
  Future<String?> getCloudflareLastSuccessfulEchConfig() async {
    final value = _prefs.getString(_keyCloudflareLastSuccessfulEchConfig);
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  /// Returns metadata for last successful ECH cache, if available.
  Future<Map<String, dynamic>?> getCloudflareLastSuccessfulEchMeta() async {
    final source = _prefs.getString(_keyCloudflareLastSuccessfulEchSource);
    final atMs = _prefs.getInt(_keyCloudflareLastSuccessfulEchAtMs);
    if ((source == null || source.isEmpty) && atMs == null) return null;
    return <String, dynamic>{'source': source ?? '', 'atMs': atMs};
  }

  /// Saves optional manual panel DoH URL override used for ECH lookup.
  ///
  /// Empty value clears the override.
  Future<void> saveCloudflarePanelDohUrlOverride(String url) async {
    final normalized = url.trim();
    if (normalized.isEmpty) {
      await _prefs.remove(_keyCloudflarePanelDohUrlOverride);
      return;
    }
    await _prefs.setString(_keyCloudflarePanelDohUrlOverride, normalized);
  }

  /// Returns manual panel DoH URL override used for ECH lookup.
  Future<String?> getCloudflarePanelDohUrlOverride() async {
    final value = _prefs.getString(_keyCloudflarePanelDohUrlOverride);
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  /// Saves whether Apply should run proxy connectivity diagnostics first.
  ///
  /// Defaults to false to avoid slowing normal apply flow.
  Future<void> saveDebugRunProxyConnectivityOnApply(bool enabled) async {
    await _prefs.setBool(_keyDebugRunProxyConnectivityOnApply, enabled);
  }

  /// Returns whether Apply should run proxy connectivity diagnostics first.
  ///
  /// Defaults to false if not set.
  Future<bool> getDebugRunProxyConnectivityOnApply() async {
    return _prefs.getBool(_keyDebugRunProxyConnectivityOnApply) ?? false;
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

  /// Saves scan parameters.
  Future<void> saveScanParameters({
    int? desiredIPCount,
    int? phase2TestDepth,
    int? enableIPv6,
    int? ipPoolSize,
    int? scanBatchSize,
    bool? fullScan,
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
    if (ipPoolSize != null) {
      await _prefs.setInt(_keyIpPoolSize, ipPoolSize);
    }
    if (scanBatchSize != null) {
      await _prefs.setInt(_keyScanBatchSize, scanBatchSize);
    }
    if (fullScan != null) {
      await _prefs.setBool(_keyFullScan, fullScan);
    }
    _logService.logInfo('Saved scan parameters');
  }

  /// Retrieves whether full scan mode is enabled.
  ///
  /// When true, Phase 2 tests all Phase 1 survivors rather than just the top N.
  Future<bool> getFullScan() async {
    return _prefs.getBool(_keyFullScan) ?? false;
  }

  /// Retrieves scan parameters.
  ///
  /// Returns a map with all scan settings.
  /// Defaults: desiredIPCount=5, phase2TestDepth=50, enableIPv6=0,
  ///           ipPoolSize=1000, scanBatchSize=200
  ///
  /// Migrates legacy maxSamplesPerCIDR: if ipPoolSize was never saved but the
  /// old key exists, the old value is converted (×10, clamped to 100–5000).
  Future<Map<String, int>> getScanParameters() async {
    int ipPoolSize;
    final saved = _prefs.getInt(_keyIpPoolSize);
    if (saved != null) {
      ipPoolSize = saved;
    } else {
      // Migrate from legacy key if present.
      final legacy = _prefs.getInt(_keyMaxSamplesPerCIDR);
      ipPoolSize = legacy != null ? (legacy * 10).clamp(100, 5000) : 1000;
    }

    return {
      'desiredIPCount': _prefs.getInt(_keyDesiredIPCount) ?? 5,
      'phase2TestDepth': _prefs.getInt(_keyPhase2TestDepth) ?? 50,
      'enableIPv6': _prefs.getInt(_keyEnableIPv6) ?? 0,
      'ipPoolSize': ipPoolSize,
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

  /// Enables/disables server backend mode.
  Future<void> saveUseServerBackend(bool enabled) async {
    await _prefs.setBool(_keyUseServerBackend, enabled);
  }

  /// Returns true when app should use server-side API/history mode.
  Future<bool> getUseServerBackend() async {
    return _prefs.getBool(_keyUseServerBackend) ?? false;
  }

  /// Saves server backend base URL.
  Future<void> saveServerBackendBaseUrl(String baseUrl) async {
    await _prefs.setString(_keyServerBackendBaseUrl, baseUrl);
  }

  /// Returns configured server backend base URL or null.
  Future<String?> getServerBackendBaseUrl() async {
    return _prefs.getString(_keyServerBackendBaseUrl);
  }

  /// Saves server backend internal token for trigger endpoint.
  Future<void> saveServerBackendToken(String token) async {
    await _secureStorage.write(key: _keyServerBackendToken, value: token);
    // Remove legacy plaintext value if present.
    await _prefs.remove(_keyServerBackendToken);
  }

  /// Returns stored server backend token or null.
  Future<String?> getServerBackendToken() async {
    try {
      final secure = await _secureStorage.read(key: _keyServerBackendToken);
      if (secure != null) return secure;
    } catch (_) {}
    // Legacy fallback migration path.
    final legacy = _prefs.getString(_keyServerBackendToken);
    if (legacy != null && legacy.isNotEmpty) {
      await _secureStorage.write(key: _keyServerBackendToken, value: legacy);
      await _prefs.remove(_keyServerBackendToken);
      return legacy;
    }
    return null;
  }

  Future<void> clearServerBackendToken() async {
    try {
      await _secureStorage.delete(key: _keyServerBackendToken);
    } catch (_) {}
    await _prefs.remove(_keyServerBackendToken);
  }

  Future<void> saveServerBackendWebUsername(String username) async {
    await _prefs.setString(_keyServerBackendWebUsername, username);
  }

  Future<String?> getServerBackendWebUsername() async {
    return _prefs.getString(_keyServerBackendWebUsername);
  }

  Future<void> saveServerBackendJwt(String token) async {
    await _secureStorage.write(key: _keyServerBackendJwt, value: token);
    if (kIsWeb) {
      await _prefs.remove(_keyServerBackendJwt);
    }
  }

  Future<String?> getServerBackendJwt() async {
    try {
      final secure = await _secureStorage.read(key: _keyServerBackendJwt);
      if (secure != null && secure.isNotEmpty) return secure;
    } catch (_) {}
    if (!kIsWeb) {
      final legacy = _prefs.getString(_keyServerBackendJwt);
      if (legacy != null && legacy.isNotEmpty) {
        await _secureStorage.write(key: _keyServerBackendJwt, value: legacy);
        await _prefs.remove(_keyServerBackendJwt);
        return legacy;
      }
    }
    return null;
  }

  Future<void> clearServerBackendJwt() async {
    try {
      await _secureStorage.delete(key: _keyServerBackendJwt);
    } catch (_) {}
    await _prefs.remove(_keyServerBackendJwt);
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
    await clearPanelCredentials();
    await clearServerBackendToken();
    await clearServerBackendJwt();
    await clearPreferences();
  }

  /// Returns true if the service is initialized.
  bool get isInitialized => _preferences != null;
}
