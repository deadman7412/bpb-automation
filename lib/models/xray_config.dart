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
  ///
  /// Geo routing rules (geosite:/geoip:) are always stripped for test configs
  /// because the bundled Xray binary does not include geosite.dat/geoip.dat.
  ///
  /// FUTURE: When VPN mode is added, geosite.dat and geoip.dat can be
  /// downloaded from https://github.com/v2fly/domain-list-community/releases
  /// and cached next to the binary. At that point, withStrippedGeoRules()
  /// can be made optional and skipped when the .dat files are present.
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
    ).withStrippedGeoRules();
  }

  /// Returns a copy of this config stripped for proxy connectivity testing.
  ///
  /// The BPB subscription configs contain geosite:/geoip: references in
  /// three places:
  ///
  ///   dns.hosts     - keys like "geosite:category-ads-all" (ad blocking)
  ///   dns.servers   - objects with geosite: domain filters and geoip: IPs
  ///                   (split DNS for IR/CN/RU)
  ///   routing.rules - domain/ip fields with geosite:/geoip: entries
  ///
  /// All three require geosite.dat/geoip.dat on disk, which the bundled
  /// Xray binary does not ship with. For connectivity testing none of this
  /// is needed - system DNS resolves fine and all traffic goes through the
  /// outbound regardless of geo rules.
  ///
  /// Strategy:
  /// - dns: dropped entirely (system DNS is sufficient for testing)
  /// - routing: geosite:/geoip: entries stripped from rules; rules that
  ///   become empty after stripping are dropped; rules with inboundTag /
  ///   network / port / etc. (non-geo criteria) are kept intact
  ///
  /// FUTURE - Export configs: use the original unmodified config so users
  /// get full split-DNS and ad-blocking in their chosen app (which bundles
  /// its own geo data files).
  ///
  /// FUTURE - VPN mode: download geosite.dat + geoip.dat from the official
  /// v2fly releases and cache them next to the binary. Once present, this
  /// stripping can be skipped and the full config passed through unchanged.
  XrayConfig withStrippedGeoRules() {
    // --- Drop DNS entirely ---
    // The dns section uses geosite: as map keys in dns.hosts AND as domain
    // filters in dns.servers - both require geosite.dat. For testing,
    // system DNS is sufficient.

    // --- Strip routing rules ---
    Map<String, dynamic>? strippedRouting = routing;
    if (routing != null) {
      final rules = routing!['rules'];
      if (rules is List) {
        final strippedRules = <Map<String, dynamic>>[];

        for (final rule in rules) {
          if (rule is! Map<String, dynamic>) {
            strippedRules.add(rule as Map<String, dynamic>);
            continue;
          }

          final updatedRule = Map<String, dynamic>.from(rule);

          // Strip geosite: entries from domain field
          if (updatedRule['domain'] is List) {
            final filtered = (updatedRule['domain'] as List)
                .where((d) => d is! String || !d.startsWith('geosite:'))
                .toList();
            if (filtered.isEmpty) {
              updatedRule.remove('domain');
            } else {
              updatedRule['domain'] = filtered;
            }
          }

          // Strip geoip: entries from ip field
          if (updatedRule['ip'] is List) {
            final filtered = (updatedRule['ip'] as List)
                .where((ip) => ip is! String || !ip.startsWith('geoip:'))
                .toList();
            if (filtered.isEmpty) {
              updatedRule.remove('ip');
            } else {
              updatedRule['ip'] = filtered;
            }
          }

          // Drop the rule entirely if it has no matching criteria left.
          // Rules that rely only on inboundTag (dns-in, remote-dns, etc.)
          // are also safe to keep - those inbounds don't exist in the test
          // config so the rules simply never match.
          final hasMatchCriteria = updatedRule.containsKey('domain') ||
              updatedRule.containsKey('ip') ||
              updatedRule.containsKey('port') ||
              updatedRule.containsKey('network') ||
              updatedRule.containsKey('source') ||
              updatedRule.containsKey('user') ||
              updatedRule.containsKey('inboundTag') ||
              updatedRule.containsKey('protocol') ||
              updatedRule.containsKey('attrs');

          if (hasMatchCriteria) {
            strippedRules.add(updatedRule);
          }
        }

        strippedRouting = Map<String, dynamic>.from(routing!);
        strippedRouting['rules'] = strippedRules;
      }
    }

    return XrayConfig(
      log: log,
      inbounds: inbounds,
      outbounds: outbounds,
      routing: strippedRouting,
      dns: null, // dropped - see comment above
      policy: policy,
      stats: stats,
      api: api,
      remarks: remarks,
    );
  }

  /// Creates inbounds for a persistent proxy connection.
  ///
  /// [bindAddress] is '127.0.0.1' for local-only or '0.0.0.0' for LAN sharing.
  /// [socksPort] is the SOCKS5 listen port (default 10808).
  /// [httpPort] optionally adds an HTTP proxy inbound.
  XrayConfig withConnectionInbounds({
    required String bindAddress,
    required int socksPort,
    int? httpPort,
  }) {
    final inboundsList = <Map<String, dynamic>>[
      {
        'port': socksPort,
        'listen': bindAddress,
        'protocol': 'socks',
        'settings': {'auth': 'noauth', 'udp': true},
        'tag': 'socks-in',
      },
    ];
    if (httpPort != null) {
      inboundsList.add({
        'port': httpPort,
        'listen': bindAddress,
        'protocol': 'http',
        'tag': 'http-in',
      });
    }
    return XrayConfig(
      log: log,
      inbounds: inboundsList,
      outbounds: outbounds,
      routing: routing,
      dns: dns,
      policy: policy,
      stats: stats,
      api: api,
      remarks: remarks,
    );
  }

  /// Adds xray's built-in stats/API monitoring to the config.
  ///
  /// This enables the xray StatsService on an internal gRPC endpoint at
  /// [apiPort] (typically 10811) so traffic bytes can be queried externally.
  ///
  /// Must be called AFTER [withConnectionInbounds] and [withStrippedGeoRules]
  /// so the API inbound and routing rule are not stripped.
  XrayConfig withStatsMonitoring({required int apiPort}) {
    final apiInbound = <String, dynamic>{
      'port': apiPort,
      'listen': '127.0.0.1',
      'protocol': 'dokodemo-door',
      'settings': {'address': '127.0.0.1'},
      'tag': 'api-in',
    };

    final apiRoutingRule = <String, dynamic>{
      'inboundTag': ['api-in'],
      'outboundTag': 'api',
      'type': 'field',
    };

    // Prepend API rule so it takes priority, preserve all stripped rules.
    final Map<String, dynamic> updatedRouting;
    if (routing != null) {
      final existingRules =
          List<dynamic>.from(routing!['rules'] as List? ?? []);
      updatedRouting = {
        ...routing!,
        'rules': [apiRoutingRule, ...existingRules],
      };
    } else {
      updatedRouting = {
        'rules': [apiRoutingRule],
      };
    }

    final existingSystem = policy?['system'];
    final systemMap = existingSystem is Map
        ? Map<String, dynamic>.from(existingSystem)
        : <String, dynamic>{};
    final updatedPolicy = <String, dynamic>{
      ...(policy ?? {}),
      'system': <String, dynamic>{
        ...systemMap,
        'statsInboundUplink': true,
        'statsInboundDownlink': true,
      },
    };

    return XrayConfig(
      log: log,
      inbounds: [...(inbounds ?? []), apiInbound],
      outbounds: outbounds,
      routing: updatedRouting,
      dns: dns,
      policy: updatedPolicy,
      stats: const <String, dynamic>{},
      api: const <String, dynamic>{
        'tag': 'api',
        'services': ['StatsService'],
      },
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
