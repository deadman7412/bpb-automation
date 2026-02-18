import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:bpb_automation/models/xray_config.dart';
import 'package:bpb_automation/services/log_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Conditional import for web-specific functionality
import 'config_generator_service_stub.dart'
    if (dart.library.html) 'config_generator_service_web.dart';

/// Service for generating and exporting Xray configs with working IPs
///
/// Takes a template config and list of working IPs, generates individual
/// configs for each IP, and provides methods to export/share them.
///
/// Usage:
/// ```dart
/// final configs = await configGenerator.generateConfigsWithIPs(
///   template: scanResult.templateConfig,
///   workingIPs: scanResult.workingIPs,
/// );
/// await configGenerator.shareConfigs(configs);
/// ```
class ConfigGeneratorService {
  static final ConfigGeneratorService _instance =
      ConfigGeneratorService._internal();
  static ConfigGeneratorService get instance => _instance;

  ConfigGeneratorService._internal();

  final LogService _logService = LogService.instance;

  /// Generate individual configs for each working IP
  ///
  /// Takes a template config and replaces the outbound address with each
  /// working IP to create individual configs.
  ///
  /// Parameters:
  /// - [template]: The original Xray config from subscription
  /// - [workingIPs]: List of IPs that passed proxy testing
  ///
  /// Returns list of XrayConfig objects, one per IP.
  Future<List<XrayConfig>> generateConfigsWithIPs({
    required XrayConfig template,
    required List<String> workingIPs,
  }) async {
    _logService.logInfo(
      '[INFO] Generating configs for ${workingIPs.length} working IPs',
    );

    if (workingIPs.isEmpty) {
      _logService.logWarn('[WARN] No working IPs to generate configs for');
      return [];
    }

    if (!template.isValid()) {
      final errors = template.getValidationErrors();
      _logService.logError(
        '[ERROR] Invalid template config: ${errors.join(", ")}',
      );
      return [];
    }

    final configs = <XrayConfig>[];

    for (int i = 0; i < workingIPs.length; i++) {
      final ip = workingIPs[i];

      try {
        // Create config with IP replaced
        final config = template.copyWithAddress(ip);

        // Update remarks to include IP
        final originalRemarks = template.remarks ?? 'BPB Config';
        final newRemarks =
            '$originalRemarks - $ip (${i + 1}/${workingIPs.length})';

        // Create final config with updated remarks
        final finalConfig = XrayConfig(
          outbounds: config.outbounds,
          inbounds: config.inbounds,
          log: config.log,
          remarks: newRemarks,
          dns: config.dns,
          routing: config.routing,
        );

        configs.add(finalConfig);

        _logService.logInfo('[INFO] Generated config ${i + 1}: $ip');
      } catch (e) {
        _logService.logError('[ERROR] Failed to generate config for $ip: $e');
      }
    }

    _logService.logOk('[OK] Generated ${configs.length} configs successfully');

    return configs;
  }

  /// Export configs as JSON string
  ///
  /// Serializes the list of configs to a JSON array format that can be
  /// imported into Xray clients.
  ///
  /// Parameters:
  /// - [configs]: List of XrayConfig objects to export
  ///
  /// Returns JSON string representation.
  String exportConfigsAsJSON(List<XrayConfig> configs) {
    _logService.logInfo('[INFO] Exporting ${configs.length} configs as JSON');

    if (configs.isEmpty) {
      _logService.logWarn('[WARN] No configs to export');
      return '[]';
    }

    try {
      // Convert configs to JSON array
      final jsonArray = configs.map((c) => c.toJson()).toList();

      // Pretty print for readability
      const encoder = JsonEncoder.withIndent('  ');
      final jsonString = encoder.convert(jsonArray);

      _logService.logOk(
        '[OK] Exported ${configs.length} configs (${jsonString.length} bytes)',
      );

      return jsonString;
    } catch (e) {
      _logService.logError('[ERROR] Failed to export configs as JSON: $e');
      return '[]';
    }
  }

  /// Save configs to a file
  ///
  /// Writes the configs JSON to a file in the app's documents directory.
  ///
  /// Parameters:
  /// - [configs]: List of XrayConfig objects to save
  /// - [filename]: Optional filename (defaults to 'xray_configs_TIMESTAMP.json')
  ///
  /// Returns the file path if successful, null otherwise.
  Future<String?> saveConfigsToFile(
    List<XrayConfig> configs, {
    String? filename,
  }) async {
    _logService.logInfo('[INFO] Saving ${configs.length} configs to file');

    if (kIsWeb) {
      _logService.logWarn('[WARN] File save not supported on web platform');
      return null;
    }

    try {
      // Generate filename if not provided
      final fileName =
          filename ??
          'xray_configs_${DateTime.now().millisecondsSinceEpoch}.json';

      // Get documents directory
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';

      // Export as JSON
      final jsonString = exportConfigsAsJSON(configs);

      // Write to file
      final file = File(filePath);
      await file.writeAsString(jsonString);

      _logService.logOk('[OK] Saved configs to: $filePath');

      return filePath;
    } catch (e) {
      _logService.logError('[ERROR] Failed to save configs to file: $e');
      return null;
    }
  }

  /// Share configs via platform share sheet
  ///
  /// Uses the platform's native share functionality to share the configs.
  /// On mobile: Opens share sheet with apps that can handle JSON/text.
  /// On desktop: Copies to clipboard or opens system share dialog.
  /// On web: Downloads the file.
  ///
  /// Parameters:
  /// - [configs]: List of XrayConfig objects to share
  /// - [subject]: Optional subject line for the share
  ///
  /// Returns true if share was initiated successfully.
  Future<bool> shareConfigs(List<XrayConfig> configs, {String? subject}) async {
    _logService.logInfo('[INFO] Sharing ${configs.length} configs');

    if (configs.isEmpty) {
      _logService.logWarn('[WARN] No configs to share');
      return false;
    }

    try {
      if (kIsWeb) {
        // Web: Trigger download
        return await _downloadConfigsOnWeb(configs);
      } else {
        // Mobile/Desktop: Use share sheet
        final jsonString = exportConfigsAsJSON(configs);
        final fileName =
            'xray_configs_${DateTime.now().millisecondsSinceEpoch}.json';

        // Save to temp file first
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsString(jsonString);

        // Share the file
        final result = await Share.shareXFiles(
          [XFile(filePath)],
          subject: subject ?? 'Xray Configs (${configs.length} IPs)',
          text: 'Generated Xray configs with ${configs.length} working IPs',
        );

        _logService.logOk('[OK] Share dialog opened: ${result.status}');

        return result.status == ShareResultStatus.success ||
            result.status == ShareResultStatus.dismissed;
      }
    } catch (e) {
      _logService.logError('[ERROR] Failed to share configs: $e');
      return false;
    }
  }

  /// Download configs on web platform
  ///
  /// Triggers a browser download of the configs JSON file.
  Future<bool> _downloadConfigsOnWeb(List<XrayConfig> configs) async {
    try {
      final jsonString = exportConfigsAsJSON(configs);
      final fileName =
          'xray_configs_${DateTime.now().millisecondsSinceEpoch}.json';

      final success = await downloadConfigsOnWeb(jsonString, fileName);

      if (success) {
        _logService.logOk('[OK] Triggered download: $fileName');
      }

      return success;
    } catch (e) {
      _logService.logError('[ERROR] Failed to download on web: $e');
      return false;
    }
  }

  /// Get a summary of generated configs
  ///
  /// Returns a human-readable summary of the configs.
  String getConfigsSummary(List<XrayConfig> configs) {
    if (configs.isEmpty) {
      return 'No configs generated';
    }

    final ipCount = configs.length;
    final protocol = configs.first.getProtocol() ?? 'unknown';
    final isSecure = configs.first.isSecure();

    return '$ipCount config${ipCount > 1 ? 's' : ''} generated '
        '(Protocol: $protocol, Security: ${isSecure ? 'TLS/Reality' : 'None'})';
  }
}
