import 'dart:convert';
import '../models/config_scan_result.dart';
import '../models/xray_config.dart';
import 'log_service.dart';

/// Service for exporting working IPs as Xray-compatible config files.
///
/// For each working IP the template config is cloned with:
///   - Outbound address replaced by the clean IP.
///   - DNS section dropped (users may not have geosite.dat/geoip.dat).
///   - geosite:/geoip: routing rules stripped for the same reason.
///   - Original inbounds preserved (SOCKS5 + HTTP on standard ports).
///   - All other settings kept intact (fragmentation, TLS, ECH, etc.).
///
/// Why template substitution instead of building from scratch:
///   The template already contains the full BPB Panel config (UUID, path,
///   fragment settings, ECH, WebSocket, etc.). Substituting only the IP
///   preserves everything automatically without re-parsing.
///
/// Output formats:
///   - JSON array: all working IPs as separate configs. Import directly into
///     v2rayN, NekoBox, or any Xray-based app.
///   - Single config: one clean config with the best (lowest-latency) IP.
class ConfigExportService {
  static final ConfigExportService _instance =
      ConfigExportService._internal();
  static ConfigExportService get instance => _instance;

  ConfigExportService._internal();

  final LogService _logService = LogService.instance;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Builds export-ready configs from a completed scan result.
  ///
  /// Returns one [XrayConfig] per working IP, ordered by proxy latency
  /// (best first). Each config has the clean IP substituted, DNS dropped,
  /// and geo routing rules stripped.
  List<XrayConfig> buildExportConfigs(ConfigScanResult result) {
    if (result.workingIPs.isEmpty) {
      _logService.logWarn('No working IPs in scan result — nothing to export');
      return [];
    }

    _logService.logInfo(
      'Building export configs for ${result.workingIPs.length} working IPs...',
    );

    final configs = <XrayConfig>[];

    for (final ip in result.workingIPs) {
      final exportConfig = _buildSingleExportConfig(
        templateConfig: result.templateConfig,
        ip: ip,
        index: configs.length + 1,
        total: result.workingIPs.length,
      );
      configs.add(exportConfig);
    }

    _logService.logOk(
      'Built ${configs.length} export configs',
    );

    return configs;
  }

  /// Serializes all working IPs as a JSON array for import into v2rayN,
  /// NekoBox, or any Xray-compatible app.
  ///
  /// The returned string is a JSON array where each element is a complete
  /// Xray config object. Import the whole array as a subscription batch,
  /// or paste individual objects into your app.
  String exportToJsonArray(ConfigScanResult result) {
    final configs = buildExportConfigs(result);

    if (configs.isEmpty) {
      _logService.logWarn('No configs to export');
      return '[]';
    }

    final jsonList = configs.map((c) => c.toJson()).toList();
    final output = const JsonEncoder.withIndent('  ').convert(jsonList);

    _logService.logOk(
      'Exported ${configs.length} configs as JSON array '
      '(${output.length} bytes)',
    );

    return output;
  }

  /// Serializes the single best (lowest-latency) working IP as a JSON object.
  ///
  /// Returns null if no working IPs are available.
  String? exportBestConfig(ConfigScanResult result) {
    if (result.workingIPs.isEmpty) {
      _logService.logWarn('No working IPs — cannot export best config');
      return null;
    }

    final bestIP = result.workingIPs.first;
    _logService.logInfo('Exporting best config for IP: $bestIP');

    final config = _buildSingleExportConfig(
      templateConfig: result.templateConfig,
      ip: bestIP,
      index: 1,
      total: 1,
    );

    final output = const JsonEncoder.withIndent('  ').convert(config.toJson());

    _logService.logOk(
      'Exported best config for $bestIP (${output.length} bytes)',
    );

    return output;
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  XrayConfig _buildSingleExportConfig({
    required XrayConfig templateConfig,
    required String ip,
    required int index,
    required int total,
  }) {
    // Step 1: Substitute the candidate IP into the outbound address.
    final withIP = templateConfig.copyWithAddress(ip);

    // Step 2: Drop DNS and strip geo routing rules.
    //
    // DNS and geosite:/geoip: rules require geosite.dat/geoip.dat on disk.
    // These data files are NOT bundled with the app (they would add ~30 MB).
    // Without them, Xray will refuse to start.
    //
    // The user's VPN app (v2rayN, NekoBox, etc.) bundles its own geo data,
    // so importing the stripped config into those apps is safe — the apps
    // simply ignore or re-apply geo rules from their own data.
    final stripped = withIP.withStrippedGeoRules();

    // Step 3: Attach a remarks label for easy identification in VPN apps.
    final label = total > 1
        ? 'BPB-Clean-$index ($ip)'
        : 'BPB-Clean ($ip)';

    return XrayConfig(
      log: stripped.log,
      inbounds: stripped.inbounds,
      outbounds: stripped.outbounds,
      routing: stripped.routing,
      dns: stripped.dns, // already null after withStrippedGeoRules
      policy: stripped.policy,
      stats: stripped.stats,
      api: stripped.api,
      remarks: label,
    );
  }
}
