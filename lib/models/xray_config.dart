import 'outbound.dart';
import 'stream_settings.dart';

/// Represents a complete Xray configuration.
///
/// This model handles the full Xray config JSON structure including:
/// - Log settings
/// - Inbound proxies (SOCKS5, HTTP)
/// - Outbound proxies (VLESS, VMess, Trojan, etc.)
/// - Routing rules
/// - DNS settings
class XrayConfig {
  /// Log configuration
  final Map<String, dynamic>? log;

  /// Inbound proxy configurations
  final List<Map<String, dynamic>>? inbounds;

  /// Outbound proxy configurations
  final List<Outbound>? outbounds;

  /// Routing rules
  final Map<String, dynamic>? routing;

  /// DNS settings
  final Map<String, dynamic>? dns;

  /// Policy settings
  final Map<String, dynamic>? policy;

  /// Stats settings
  final Map<String, dynamic>? stats;

  /// API settings
  final Map<String, dynamic>? api;

  /// Original remarks/name from subscription
  final String? remarks;

  /// Creates an XrayConfig instance.
  const XrayConfig({
    this.log,
    this.inbounds,
    this.outbounds,
    this.routing,
    this.dns,
    this.policy,
    this.stats,
    this.api,
    this.remarks,
  });

  /// Creates an XrayConfig instance from a JSON map.
  ///
  /// This handles both:
  /// 1. Full Xray config JSON (with log, inbounds, outbounds, etc.)
  /// 2. BPB subscription format (may include 'remarks' field)
  factory XrayConfig.fromJson(Map<String, dynamic> json) {
    return XrayConfig(
      log: json['log'] as Map<String, dynamic>?,
      inbounds: json['inbounds'] != null
          ? (json['inbounds'] as List)
                .map((e) => e as Map<String, dynamic>)
                .toList()
          : null,
      outbounds: json['outbounds'] != null
          ? (json['outbounds'] as List)
                .map((e) => Outbound.fromJson(e as Map<String, dynamic>))
                .toList()
          : null,
      routing: json['routing'] as Map<String, dynamic>?,
      dns: json['dns'] as Map<String, dynamic>?,
      policy: json['policy'] as Map<String, dynamic>?,
      stats: json['stats'] as Map<String, dynamic>?,
      api: json['api'] as Map<String, dynamic>?,
      remarks: json['remarks'] as String?,
    );
  }

  /// Converts this XrayConfig instance to a JSON map.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (log != null) json['log'] = log;
    if (inbounds != null) json['inbounds'] = inbounds;
    if (outbounds != null) {
      json['outbounds'] = outbounds!.map((e) => e.toJson()).toList();
    }
    if (routing != null) json['routing'] = routing;
    if (dns != null) json['dns'] = dns;
    if (policy != null) json['policy'] = policy;
    if (stats != null) json['stats'] = stats;
    if (api != null) json['api'] = api;
    if (remarks != null) json['remarks'] = remarks;

    return json;
  }

  /// Gets the primary outbound (first outbound that's not 'direct' or 'block').
  ///
  /// Returns null if no proxy outbound is found.
  Outbound? getPrimaryOutbound() {
    if (outbounds == null || outbounds!.isEmpty) return null;

    // Find first outbound that's not direct/block
    for (final outbound in outbounds!) {
      if (outbound.protocol != 'freedom' && outbound.protocol != 'blackhole') {
        return outbound;
      }
    }

    // Fallback to first outbound
    return outbounds!.first;
  }

  /// Extracts the server address from the primary outbound.
  ///
  /// Returns null if no primary outbound is configured.
  String? getServerAddress() {
    return getPrimaryOutbound()?.getAddress();
  }

  /// Extracts the server port from the primary outbound.
  ///
  /// Returns null if no primary outbound is configured.
  int? getServerPort() {
    return getPrimaryOutbound()?.getPort();
  }

  /// Returns true if the config uses an IP address (not a domain).
  bool isIpBased() {
    return getPrimaryOutbound()?.isIpBased() ?? false;
  }

  /// Returns true if the config uses a domain name.
  bool isDomainBased() {
    return getPrimaryOutbound()?.isDomainBased() ?? false;
  }

  /// Returns the protocol of the primary outbound.
  String? getProtocol() {
    return getPrimaryOutbound()?.protocol;
  }

  /// Returns the stream settings of the primary outbound.
  StreamSettings? getStreamSettings() {
    return getPrimaryOutbound()?.streamSettings;
  }

  /// Extracts SNI (Server Name Indication) for TLS testing.
  String? getSni() {
    return getStreamSettings()?.getSni();
  }

  /// Returns true if TLS/Reality security is enabled.
  bool isSecure() {
    return getStreamSettings()?.isSecure() ?? false;
  }

  /// Creates a copy of this config with the primary outbound's address replaced.
  ///
  /// This is used during IP testing to replace the server address
  /// with candidate IPs while preserving all other settings.
  XrayConfig copyWithAddress(String newAddress) {
    if (outbounds == null || outbounds!.isEmpty) return this;

    // Find index of primary outbound
    int primaryIndex = 0;
    for (int i = 0; i < outbounds!.length; i++) {
      if (outbounds![i].protocol != 'freedom' &&
          outbounds![i].protocol != 'blackhole') {
        primaryIndex = i;
        break;
      }
    }

    // Create new outbounds list with replaced address
    final newOutbounds = List<Outbound>.from(outbounds!);
    newOutbounds[primaryIndex] = outbounds![primaryIndex].copyWithAddress(
      newAddress,
    );

    return XrayConfig(
      log: log,
      inbounds: inbounds,
      outbounds: newOutbounds,
      routing: routing,
      dns: dns,
      policy: policy,
      stats: stats,
      api: api,
      remarks: remarks,
    );
  }

  /// Creates a standardized SOCKS5 inbound for testing.
  ///
  /// This replaces any existing inbounds with a simple SOCKS5 proxy
  /// on 127.0.0.1:10808 for testing purposes.
  XrayConfig withTestInbound() {
    final testInbound = {
      'port': 10808,
      'listen': '127.0.0.1',
      'protocol': 'socks',
      'settings': {'auth': 'noauth', 'udp': true},
      'tag': 'socks-in',
    };

    return XrayConfig(
      log: log,
      inbounds: [testInbound],
      outbounds: outbounds,
      routing: routing,
      dns: dns,
      policy: policy,
      stats: stats,
      api: api,
      remarks: remarks,
    );
  }

  /// Returns a brief description for logging/display.
  ///
  /// Example: "VLESS (1.1.1.1:443) TLS - My Config"
  String getDescription() {
    final protocol = getProtocol()?.toUpperCase() ?? 'Unknown';
    final address = getServerAddress() ?? 'unknown';
    final port = getServerPort()?.toString() ?? '?';
    final security = isSecure() ? 'TLS' : 'Plain';
    final name = remarks ?? '';

    if (name.isNotEmpty) {
      return '$protocol ($address:$port) $security - $name';
    } else {
      return '$protocol ($address:$port) $security';
    }
  }

  @override
  String toString() {
    return 'XrayConfig(${getDescription()})';
  }

  /// Validates that the config has required fields for testing.
  ///
  /// Returns true if:
  /// - Has at least one outbound
  /// - Primary outbound has valid address and port
  bool isValid() {
    final outbound = getPrimaryOutbound();
    if (outbound == null) return false;

    final address = outbound.getAddress();
    final port = outbound.getPort();

    return address != null &&
        address.isNotEmpty &&
        port != null &&
        port > 0 &&
        port <= 65535;
  }

  /// Returns validation errors as a list of strings.
  ///
  /// Returns empty list if valid.
  List<String> getValidationErrors() {
    final errors = <String>[];

    if (outbounds == null || outbounds!.isEmpty) {
      errors.add('No outbounds configured');
      return errors;
    }

    final outbound = getPrimaryOutbound();
    if (outbound == null) {
      errors.add('No proxy outbound found (only direct/block)');
      return errors;
    }

    final address = outbound.getAddress();
    if (address == null || address.isEmpty) {
      errors.add('Outbound has no address configured');
    }

    final port = outbound.getPort();
    if (port == null) {
      errors.add('Outbound has no port configured');
    } else if (port <= 0 || port > 65535) {
      errors.add('Outbound port is invalid: $port');
    }

    return errors;
  }
}
