import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/xray_config.dart';
import 'log_service.dart';

/// Service for fetching and parsing BPB Panel subscription links.
///
/// This service handles:
/// - Fetching Xray configs from subscription URLs
/// - Parsing JSON array of configs
/// - Filtering configs by type (IP-based vs domain-based)
/// - Auto-selecting best config for scanning
class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._internal();
  static SubscriptionService get instance => _instance;

  SubscriptionService._internal();

  final LogService _logService = LogService.instance;

  /// Default timeout for subscription requests
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

  /// Fetches Xray configs from a BPB Panel subscription URL.
  ///
  /// Returns a list of parsed XrayConfig objects.
  /// Returns empty list on error.
  ///
  /// Example subscription URL:
  /// https://artshop.ecomedgeinnovators.com/sub/normal/AK*%40FX.Kzmj8A3M%2C?app=xray
  Future<List<XrayConfig>> fetchConfigs(String subscriptionUrl) async {
    return await _retryOperation(() => _fetchConfigsInternal(subscriptionUrl));
  }

  /// Internal method to fetch configs (without retry logic).
  Future<List<XrayConfig>> _fetchConfigsInternal(String subscriptionUrl) async {
    try {
      final url = Uri.parse(subscriptionUrl);
      _logService.logInfo(
        'Fetching subscription from host: ${url.host} (query: ${url.query.isNotEmpty ? "present" : "none"})',
      );

      final response = await _client.get(url).timeout(_defaultTimeout);

      if (response.statusCode != 200) {
        _logService.logError(
          'Subscription fetch failed: HTTP ${response.statusCode}',
        );
        return [];
      }

      _logService.logOk(
        'Subscription fetched successfully (${response.body.length} bytes)',
      );

      // Parse JSON array
      final List<dynamic> jsonArray = jsonDecode(response.body) as List;

      _logService.logInfo(
        'Parsing ${jsonArray.length} configs from subscription',
      );

      final configs = <XrayConfig>[];

      for (int i = 0; i < jsonArray.length; i++) {
        try {
          final configJson = jsonArray[i] as Map<String, dynamic>;
          final config = XrayConfig.fromJson(configJson);

          // Validate config
          if (config.isValid()) {
            configs.add(config);
            _logService.logInfo(
              'Config ${i + 1}: ${_sanitizeConfigText(config.getDescription())} - Valid',
            );
          } else {
            final errors = config.getValidationErrors();
            _logService.logWarn(
              'Config ${i + 1}: ${_sanitizeConfigText(config.remarks ?? "Unnamed")} - Invalid: ${errors.join(", ")}',
            );
          }
        } catch (e) {
          _logService.logError('Failed to parse config ${i + 1}', e);
        }
      }

      _logService.logOk('Parsed ${configs.length} valid configs');

      return configs;
    } catch (e, stackTrace) {
      _logService.logError('Failed to fetch subscription', e, stackTrace);
      return [];
    }
  }

  /// Filters configs to only IP-based ones.
  ///
  /// IP-based configs are preferred for clean IP scanning because:
  /// - We're testing IPs, not domains
  /// - IP-based configs don't require DNS resolution
  /// - They're more suitable for direct IP replacement
  List<XrayConfig> filterIpBasedConfigs(List<XrayConfig> configs) {
    final ipBased = configs.where((config) => config.isIpBased()).toList();

    _logService.logInfo(
      'Filtered to ${ipBased.length} IP-based configs (out of ${configs.length} total)',
    );

    return ipBased;
  }

  /// Filters configs to only domain-based ones.
  List<XrayConfig> filterDomainBasedConfigs(List<XrayConfig> configs) {
    final domainBased = configs
        .where((config) => config.isDomainBased())
        .toList();

    _logService.logInfo(
      'Filtered to ${domainBased.length} domain-based configs (out of ${configs.length} total)',
    );

    return domainBased;
  }

  /// Auto-selects the best config for IP scanning.
  ///
  /// Selection priority:
  /// 1. IP-based configs (preferred)
  /// 2. Domain-based configs (fallback)
  /// 3. First valid config
  ///
  /// Returns null if no valid config is found.
  XrayConfig? selectBestConfigForScanning(List<XrayConfig> configs) {
    if (configs.isEmpty) {
      _logService.logWarn('No configs available for selection');
      return null;
    }

    // Priority 1: IP-based configs
    final ipBased = filterIpBasedConfigs(configs);
    if (ipBased.isNotEmpty) {
      final selected = ipBased.first;
      _logService.logOk(
        'Auto-selected IP-based config: ${selected.getDescription()}',
      );
      return selected;
    }

    // Priority 2: Domain-based configs
    final domainBased = filterDomainBasedConfigs(configs);
    if (domainBased.isNotEmpty) {
      final selected = domainBased.first;
      _logService.logOk(
        'Auto-selected domain-based config: ${selected.getDescription()}',
      );
      return selected;
    }

    // Fallback: First config
    final selected = configs.first;
    _logService.logOk(
      'Auto-selected first config: ${selected.getDescription()}',
    );
    return selected;
  }

  /// Fetches configs and auto-selects the best one for scanning.
  ///
  /// This is a convenience method that combines fetching and selection.
  ///
  /// Returns null if fetching fails or no valid config is found.
  Future<XrayConfig?> fetchAndSelectConfig(String subscriptionUrl) async {
    final configs = await fetchConfigs(subscriptionUrl);

    if (configs.isEmpty) {
      _logService.logWarn('No configs fetched from subscription');
      return null;
    }

    return selectBestConfigForScanning(configs);
  }

  /// Validates a subscription URL format.
  ///
  /// Returns true if the URL appears valid (basic check).
  bool isValidSubscriptionUrl(String url) {
    if (url.isEmpty) return false;

    try {
      final uri = Uri.parse(url);

      // Must have http or https scheme
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return false;
      }

      // Must have a host
      if (uri.host.isEmpty) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Gets descriptive information about all configs from a subscription.
  ///
  /// Useful for displaying a list of configs to the user.
  ///
  /// Returns list of strings like:
  /// "1. VLESS (1.1.1.1:443) TLS - My Config"
  Future<List<String>> getConfigDescriptions(String subscriptionUrl) async {
    final configs = await fetchConfigs(subscriptionUrl);

    final descriptions = <String>[];

    for (int i = 0; i < configs.length; i++) {
      final config = configs[i];
      descriptions.add('${i + 1}. ${config.getDescription()}');
    }

    return descriptions;
  }

  /// Retries an operation with exponential backoff.
  Future<T> _retryOperation<T>(Future<T> Function() operation) async {
    int attempt = 0;
    Duration delay = _initialRetryDelay;

    while (true) {
      attempt++;

      try {
        return await operation();
      } catch (e) {
        if (attempt >= _maxRetries) {
          _logService.logError('Operation failed after $attempt attempts', e);
          rethrow;
        }

        _logService.logWarn(
          'Operation failed (attempt $attempt/$_maxRetries), retrying in ${delay.inSeconds}s...',
        );

        await Future.delayed(delay);

        // Exponential backoff
        delay = Duration(seconds: delay.inSeconds * 2);
      }
    }
  }

  /// Disposes resources used by the service.
  void dispose() {
    _client.close();
  }

  String _sanitizeConfigText(String input) {
    return input.replaceAll(
      RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]', unicode: true),
      '',
    );
  }
}
