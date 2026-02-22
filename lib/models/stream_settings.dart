/// Represents Xray stream settings (transport layer configuration).
///
/// This model handles the transport protocol configuration including:
/// - Network type (tcp, ws, grpc, httpupgrade, etc.)
/// - Security settings (TLS, Reality)
/// - Transport-specific parameters (WebSocket path, gRPC service name, etc.)
class StreamSettings {
  /// Network transport type (tcp, ws, grpc, httpupgrade, etc.)
  final String? network;

  /// Security protocol (tls, reality, none)
  final String? security;

  /// TLS/Reality settings
  final TlsSettings? tlsSettings;

  /// WebSocket settings (when network is 'ws')
  final WsSettings? wsSettings;

  /// gRPC settings (when network is 'grpc')
  final GrpcSettings? grpcSettings;

  /// HTTPUpgrade settings (when network is 'httpupgrade')
  final HttpUpgradeSettings? httpUpgradeSettings;

  /// Additional unknown fields preserved during JSON round-trip.
  final Map<String, dynamic> additionalFields;

  /// Creates a StreamSettings instance.
  const StreamSettings({
    this.network,
    this.security,
    this.tlsSettings,
    this.wsSettings,
    this.grpcSettings,
    this.httpUpgradeSettings,
    this.additionalFields = const {},
  });

  /// Creates a StreamSettings instance from a JSON map.
  factory StreamSettings.fromJson(Map<String, dynamic> json) {
    const knownFields = {
      'network',
      'security',
      'tlsSettings',
      'wsSettings',
      'grpcSettings',
      'httpupgradeSettings',
    };
    final additionalFields = <String, dynamic>{};
    json.forEach((key, value) {
      if (!knownFields.contains(key)) {
        additionalFields[key] = value;
      }
    });

    return StreamSettings(
      network: json['network'] as String?,
      security: json['security'] as String?,
      tlsSettings: json['tlsSettings'] != null
          ? TlsSettings.fromJson(json['tlsSettings'] as Map<String, dynamic>)
          : null,
      wsSettings: json['wsSettings'] != null
          ? WsSettings.fromJson(json['wsSettings'] as Map<String, dynamic>)
          : null,
      grpcSettings: json['grpcSettings'] != null
          ? GrpcSettings.fromJson(json['grpcSettings'] as Map<String, dynamic>)
          : null,
      httpUpgradeSettings: json['httpupgradeSettings'] != null
          ? HttpUpgradeSettings.fromJson(
              json['httpupgradeSettings'] as Map<String, dynamic>,
            )
          : null,
      additionalFields: additionalFields,
    );
  }

  /// Converts this StreamSettings instance to a JSON map.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (network != null) json['network'] = network;
    if (security != null) json['security'] = security;
    if (tlsSettings != null) json['tlsSettings'] = tlsSettings!.toJson();
    if (wsSettings != null) json['wsSettings'] = wsSettings!.toJson();
    if (grpcSettings != null) json['grpcSettings'] = grpcSettings!.toJson();
    if (httpUpgradeSettings != null) {
      json['httpupgradeSettings'] = httpUpgradeSettings!.toJson();
    }
    json.addAll(additionalFields);

    return json;
  }

  /// Extracts SNI (Server Name Indication) for TLS testing.
  String? getSni() {
    return tlsSettings?.serverName;
  }

  /// Extracts port for connection testing.
  /// Returns null as port is typically in the vnext address field.
  int? getPort() {
    return null; // Port is in Vnext, not StreamSettings
  }

  /// Returns true if TLS/Reality security is enabled.
  bool isSecure() {
    return security == 'tls' || security == 'reality';
  }

  @override
  String toString() {
    return 'StreamSettings(network: $network, security: $security, sni: ${getSni()})';
  }
}

/// Represents TLS/Reality settings.
class TlsSettings {
  /// Server Name Indication (domain name for TLS)
  final String? serverName;

  /// Application Layer Protocol Negotiation
  final List<String>? alpn;

  /// Fingerprint for Reality protocol
  final String? fingerprint;

  /// Public key for Reality protocol
  final String? publicKey;

  /// Short ID for Reality protocol
  final String? shortId;

  /// Spider X for Reality protocol
  final String? spiderX;

  /// Additional unknown fields preserved during JSON round-trip.
  final Map<String, dynamic> additionalFields;

  /// Creates a TlsSettings instance.
  const TlsSettings({
    this.serverName,
    this.alpn,
    this.fingerprint,
    this.publicKey,
    this.shortId,
    this.spiderX,
    this.additionalFields = const {},
  });

  /// Creates a TlsSettings instance from a JSON map.
  factory TlsSettings.fromJson(Map<String, dynamic> json) {
    const knownFields = {
      'serverName',
      'alpn',
      'fingerprint',
      'publicKey',
      'shortId',
      'spiderX',
    };
    final additionalFields = <String, dynamic>{};
    json.forEach((key, value) {
      if (!knownFields.contains(key)) {
        additionalFields[key] = value;
      }
    });

    return TlsSettings(
      serverName: json['serverName'] as String?,
      alpn: json['alpn'] != null
          ? (json['alpn'] as List).map((e) => e as String).toList()
          : null,
      fingerprint: json['fingerprint'] as String?,
      publicKey: json['publicKey'] as String?,
      shortId: json['shortId'] as String?,
      spiderX: json['spiderX'] as String?,
      additionalFields: additionalFields,
    );
  }

  /// Converts this TlsSettings instance to a JSON map.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (serverName != null) json['serverName'] = serverName;
    if (alpn != null) json['alpn'] = alpn;
    if (fingerprint != null) json['fingerprint'] = fingerprint;
    if (publicKey != null) json['publicKey'] = publicKey;
    if (shortId != null) json['shortId'] = shortId;
    if (spiderX != null) json['spiderX'] = spiderX;
    json.addAll(additionalFields);

    return json;
  }
}

/// Represents WebSocket transport settings.
class WsSettings {
  /// WebSocket path
  final String? path;

  /// HTTP headers
  final Map<String, dynamic>? headers;

  /// Additional unknown fields preserved during JSON round-trip.
  final Map<String, dynamic> additionalFields;

  /// Creates a WsSettings instance.
  const WsSettings({
    this.path,
    this.headers,
    this.additionalFields = const {},
  });

  /// Creates a WsSettings instance from a JSON map.
  factory WsSettings.fromJson(Map<String, dynamic> json) {
    const knownFields = {'path', 'headers'};
    final additionalFields = <String, dynamic>{};
    json.forEach((key, value) {
      if (!knownFields.contains(key)) {
        additionalFields[key] = value;
      }
    });

    return WsSettings(
      path: json['path'] as String?,
      headers: json['headers'] as Map<String, dynamic>?,
      additionalFields: additionalFields,
    );
  }

  /// Converts this WsSettings instance to a JSON map.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (path != null) json['path'] = path;
    if (headers != null) json['headers'] = headers;
    json.addAll(additionalFields);

    return json;
  }
}

/// Represents gRPC transport settings.
class GrpcSettings {
  /// gRPC service name
  final String? serviceName;

  /// Multi-mode setting
  final bool? multiMode;

  /// Additional unknown fields preserved during JSON round-trip.
  final Map<String, dynamic> additionalFields;

  /// Creates a GrpcSettings instance.
  const GrpcSettings({
    this.serviceName,
    this.multiMode,
    this.additionalFields = const {},
  });

  /// Creates a GrpcSettings instance from a JSON map.
  factory GrpcSettings.fromJson(Map<String, dynamic> json) {
    const knownFields = {'serviceName', 'multiMode'};
    final additionalFields = <String, dynamic>{};
    json.forEach((key, value) {
      if (!knownFields.contains(key)) {
        additionalFields[key] = value;
      }
    });

    return GrpcSettings(
      serviceName: json['serviceName'] as String?,
      multiMode: json['multiMode'] as bool?,
      additionalFields: additionalFields,
    );
  }

  /// Converts this GrpcSettings instance to a JSON map.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (serviceName != null) json['serviceName'] = serviceName;
    if (multiMode != null) json['multiMode'] = multiMode;
    json.addAll(additionalFields);

    return json;
  }
}

/// Represents HTTPUpgrade transport settings.
class HttpUpgradeSettings {
  /// HTTPUpgrade path
  final String? path;

  /// HTTP host header
  final String? host;

  /// Additional unknown fields preserved during JSON round-trip.
  final Map<String, dynamic> additionalFields;

  /// Creates an HttpUpgradeSettings instance.
  const HttpUpgradeSettings({
    this.path,
    this.host,
    this.additionalFields = const {},
  });

  /// Creates an HttpUpgradeSettings instance from a JSON map.
  factory HttpUpgradeSettings.fromJson(Map<String, dynamic> json) {
    const knownFields = {'path', 'host'};
    final additionalFields = <String, dynamic>{};
    json.forEach((key, value) {
      if (!knownFields.contains(key)) {
        additionalFields[key] = value;
      }
    });

    return HttpUpgradeSettings(
      path: json['path'] as String?,
      host: json['host'] as String?,
      additionalFields: additionalFields,
    );
  }

  /// Converts this HttpUpgradeSettings instance to a JSON map.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (path != null) json['path'] = path;
    if (host != null) json['host'] = host;
    json.addAll(additionalFields);

    return json;
  }
}
