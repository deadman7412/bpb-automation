import 'stream_settings.dart';

/// Represents an Xray outbound configuration.
///
/// This model handles outbound proxy settings including:
/// - Protocol (vless, vmess, trojan, etc.)
/// - Server settings (address, port, user ID, encryption)
/// - Stream settings (transport and security)
class Outbound {
  /// Outbound protocol (vless, vmess, trojan, shadowsocks, etc.)
  final String protocol;

  /// Outbound settings containing server configuration
  final OutboundSettings? settings;

  /// Stream settings (transport layer configuration)
  final StreamSettings? streamSettings;

  /// Outbound tag for routing
  final String? tag;

  /// Mux settings
  final Map<String, dynamic>? mux;

  /// Additional unknown fields preserved during JSON round-trip.
  final Map<String, dynamic> additionalFields;

  /// Creates an Outbound instance.
  const Outbound({
    required this.protocol,
    this.settings,
    this.streamSettings,
    this.tag,
    this.mux,
    this.additionalFields = const {},
  });

  /// Creates an Outbound instance from a JSON map.
  factory Outbound.fromJson(Map<String, dynamic> json) {
    const knownFields = {
      'protocol',
      'settings',
      'streamSettings',
      'tag',
      'mux',
    };
    final additionalFields = <String, dynamic>{};
    json.forEach((key, value) {
      if (!knownFields.contains(key)) {
        additionalFields[key] = value;
      }
    });

    return Outbound(
      protocol: json['protocol'] as String,
      settings: json['settings'] != null
          ? OutboundSettings.fromJson(json['settings'] as Map<String, dynamic>)
          : null,
      streamSettings: json['streamSettings'] != null
          ? StreamSettings.fromJson(
              json['streamSettings'] as Map<String, dynamic>,
            )
          : null,
      tag: json['tag'] as String?,
      mux: json['mux'] as Map<String, dynamic>?,
      additionalFields: additionalFields,
    );
  }

  /// Converts this Outbound instance to a JSON map.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'protocol': protocol};

    if (settings != null) json['settings'] = settings!.toJson();
    if (streamSettings != null) {
      json['streamSettings'] = streamSettings!.toJson();
    }
    if (tag != null) json['tag'] = tag;
    if (mux != null) json['mux'] = mux;
    json.addAll(additionalFields);

    return json;
  }

  /// Extracts the server address from vnext settings.
  ///
  /// Returns null if no vnext server is configured.
  String? getAddress() {
    final vnextList = settings?.vnext;
    if (vnextList != null && vnextList.isNotEmpty) {
      return vnextList[0].address;
    }
    final servers = settings?.servers;
    if (servers != null && servers.isNotEmpty) {
      return servers[0]['address']?.toString();
    }
    return null;
  }

  /// Extracts the server port from vnext settings.
  ///
  /// Returns null if no vnext server is configured.
  int? getPort() {
    final vnextList = settings?.vnext;
    if (vnextList != null && vnextList.isNotEmpty) {
      return vnextList[0].port;
    }
    final servers = settings?.servers;
    if (servers != null && servers.isNotEmpty) {
      final rawPort = servers[0]['port'];
      if (rawPort is int) return rawPort;
      if (rawPort is String) return int.tryParse(rawPort);
      if (rawPort is num) return rawPort.toInt();
    }
    return null;
  }

  /// Returns true if the outbound uses an IP address (not a domain).
  bool isIpBased() {
    final address = getAddress();
    if (address == null) return false;

    // Check if address is IPv4
    final ipv4Pattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (ipv4Pattern.hasMatch(address)) return true;

    // Check if address is IPv6 (simplified check)
    if (address.contains(':') && !address.contains('.')) return true;

    return false;
  }

  /// Returns true if the outbound uses a domain name.
  bool isDomainBased() {
    return !isIpBased() && getAddress() != null;
  }

  /// Creates a copy of this outbound with a new address.
  ///
  /// This is used during IP testing to replace the server address
  /// with candidate IPs while preserving all other settings.
  Outbound copyWithAddress(String newAddress) {
    if (settings == null) return this;

    if (settings!.vnext != null && settings!.vnext!.isNotEmpty) {
      final newVnext = settings!.vnext!.map((vnext) {
        // Only replace address of the first vnext entry
        if (vnext == settings!.vnext!.first) {
          return vnext.copyWithAddress(newAddress);
        }
        return vnext;
      }).toList();

      final newSettings = OutboundSettings(
        vnext: newVnext,
        servers: settings!.servers,
        additionalFields: settings!.additionalFields,
      );

      return Outbound(
        protocol: protocol,
        settings: newSettings,
        streamSettings: streamSettings,
        tag: tag,
        mux: mux,
        additionalFields: additionalFields,
      );
    }

    if (settings!.servers == null || settings!.servers!.isEmpty) {
      return this;
    }

    final newServers = List<Map<String, dynamic>>.from(settings!.servers!);
    final firstServer = Map<String, dynamic>.from(newServers.first);
    firstServer['address'] = newAddress;
    newServers[0] = firstServer;

    final newSettings = OutboundSettings(
      vnext: settings!.vnext,
      servers: newServers,
      additionalFields: settings!.additionalFields,
    );

    return Outbound(
      protocol: protocol,
      settings: newSettings,
      streamSettings: streamSettings,
      tag: tag,
      mux: mux,
      additionalFields: additionalFields,
    );
  }

  @override
  String toString() {
    return 'Outbound(protocol: $protocol, address: ${getAddress()}, port: ${getPort()})';
  }
}

/// Represents outbound settings containing server configuration.
class OutboundSettings {
  /// VLESS/VMess server list (vnext)
  final List<Vnext>? vnext;

  /// Trojan/Shadowsocks server list (servers)
  final List<Map<String, dynamic>>? servers;

  /// Additional unknown fields preserved during JSON round-trip.
  final Map<String, dynamic> additionalFields;

  /// Creates an OutboundSettings instance.
  const OutboundSettings({
    this.vnext,
    this.servers,
    this.additionalFields = const {},
  });

  /// Creates an OutboundSettings instance from a JSON map.
  factory OutboundSettings.fromJson(Map<String, dynamic> json) {
    const knownFields = {'vnext', 'servers'};
    final additionalFields = <String, dynamic>{};
    json.forEach((key, value) {
      if (!knownFields.contains(key)) {
        additionalFields[key] = value;
      }
    });

    return OutboundSettings(
      vnext: json['vnext'] != null
          ? (json['vnext'] as List)
                .map((e) => Vnext.fromJson(e as Map<String, dynamic>))
                .toList()
          : null,
      servers: json['servers'] != null
          ? (json['servers'] as List)
                .map((e) => e as Map<String, dynamic>)
                .toList()
          : null,
      additionalFields: additionalFields,
    );
  }

  /// Converts this OutboundSettings instance to a JSON map.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (vnext != null) {
      json['vnext'] = vnext!.map((e) => e.toJson()).toList();
    }
    if (servers != null) json['servers'] = servers;
    json.addAll(additionalFields);

    return json;
  }
}

/// Represents a VLESS/VMess server entry.
class Vnext {
  /// Server address (IP or domain)
  final String address;

  /// Server port
  final int port;

  /// User list
  final List<VnextUser>? users;

  /// Additional unknown fields preserved during JSON round-trip.
  final Map<String, dynamic> additionalFields;

  /// Creates a Vnext instance.
  const Vnext({
    required this.address,
    required this.port,
    this.users,
    this.additionalFields = const {},
  });

  /// Creates a Vnext instance from a JSON map.
  factory Vnext.fromJson(Map<String, dynamic> json) {
    const knownFields = {'address', 'port', 'users'};
    final additionalFields = <String, dynamic>{};
    json.forEach((key, value) {
      if (!knownFields.contains(key)) {
        additionalFields[key] = value;
      }
    });

    return Vnext(
      address: json['address'] as String,
      port: json['port'] as int,
      users: json['users'] != null
          ? (json['users'] as List)
                .map((e) => VnextUser.fromJson(e as Map<String, dynamic>))
                .toList()
          : null,
      additionalFields: additionalFields,
    );
  }

  /// Converts this Vnext instance to a JSON map.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'address': address, 'port': port};

    if (users != null) {
      json['users'] = users!.map((e) => e.toJson()).toList();
    }
    json.addAll(additionalFields);

    return json;
  }

  /// Creates a copy of this vnext with a new address.
  Vnext copyWithAddress(String newAddress) {
    return Vnext(
      address: newAddress,
      port: port,
      users: users,
      additionalFields: additionalFields,
    );
  }
}

/// Represents a VLESS/VMess user configuration.
class VnextUser {
  /// User ID (UUID)
  final String id;

  /// Encryption method (for VLESS: 'none', for VMess: 'auto', 'aes-128-gcm', etc.)
  final String? encryption;

  /// Flow (for VLESS with XTLS)
  final String? flow;

  /// Security (for VMess)
  final String? security;

  /// Alter ID (for VMess)
  final int? alterId;

  /// Additional unknown fields preserved during JSON round-trip.
  final Map<String, dynamic> additionalFields;

  /// Creates a VnextUser instance.
  const VnextUser({
    required this.id,
    this.encryption,
    this.flow,
    this.security,
    this.alterId,
    this.additionalFields = const {},
  });

  /// Creates a VnextUser instance from a JSON map.
  factory VnextUser.fromJson(Map<String, dynamic> json) {
    const knownFields = {'id', 'encryption', 'flow', 'security', 'alterId'};
    final additionalFields = <String, dynamic>{};
    json.forEach((key, value) {
      if (!knownFields.contains(key)) {
        additionalFields[key] = value;
      }
    });

    return VnextUser(
      id: json['id'] as String,
      encryption: json['encryption'] as String?,
      flow: json['flow'] as String?,
      security: json['security'] as String?,
      alterId: json['alterId'] as int?,
      additionalFields: additionalFields,
    );
  }

  /// Converts this VnextUser instance to a JSON map.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'id': id};

    if (encryption != null) json['encryption'] = encryption;
    if (flow != null) json['flow'] = flow;
    if (security != null) json['security'] = security;
    if (alterId != null) json['alterId'] = alterId;
    json.addAll(additionalFields);

    return json;
  }
}
