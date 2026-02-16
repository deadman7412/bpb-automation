/// Represents BPB Panel proxy configuration from Cloudflare Workers KV.
///
/// This model holds the complete proxy settings stored in Workers KV.
/// The primary purpose is to update the [cleanIPs] field while preserving
/// all other configuration settings.
class ProxySettings {
  /// Remote DNS server address
  final String remoteDNS;

  /// Remote DNS host configuration (custom DNS settings)
  final Map<String, dynamic> remoteDnsHost;

  /// Local DNS server address
  final String localDNS;

  /// List of clean Cloudflare IP addresses (THIS IS WHAT WE UPDATE)
  final List<String> cleanIPs;

  /// List of proxy IP addresses
  final List<String> proxyIPs;

  /// Outbound proxy parameters
  final Map<String, dynamic> outProxyParams;

  /// Additional unknown fields from the original JSON
  /// This ensures we don't lose any data when round-tripping
  final Map<String, dynamic> _additionalFields;

  /// Creates a ProxySettings instance.
  ProxySettings({
    required this.remoteDNS,
    required this.remoteDnsHost,
    required this.localDNS,
    required this.cleanIPs,
    required this.proxyIPs,
    required this.outProxyParams,
    Map<String, dynamic>? additionalFields,
  }) : _additionalFields = additionalFields ?? {};

  /// Creates a ProxySettings instance from JSON.
  ///
  /// This method handles all known fields and preserves any unknown fields
  /// in [_additionalFields] to ensure no data is lost during updates.
  ///
  /// Example JSON structure:
  /// ```json
  /// {
  ///   "remoteDNS": "https://8.8.8.8/dns-query",
  ///   "remoteDnsHost": {},
  ///   "localDNS": "8.8.8.8",
  ///   "cleanIPs": ["1.1.1.1", "1.0.0.1"],
  ///   "proxyIPs": [],
  ///   "outProxyParams": {}
  /// }
  /// ```
  factory ProxySettings.fromJson(Map<String, dynamic> json) {
    // Extract known fields
    final knownFields = {
      'remoteDNS',
      'remoteDnsHost',
      'localDNS',
      'cleanIPs',
      'proxyIPs',
      'outProxyParams',
    };

    // Preserve unknown fields
    final additionalFields = <String, dynamic>{};
    json.forEach((key, value) {
      if (!knownFields.contains(key)) {
        additionalFields[key] = value;
      }
    });

    return ProxySettings(
      remoteDNS: json['remoteDNS'] as String? ?? '',
      remoteDnsHost: _castToStringMap(json['remoteDnsHost']),
      localDNS: json['localDNS'] as String? ?? '',
      cleanIPs: (json['cleanIPs'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      proxyIPs: (json['proxyIPs'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      outProxyParams: _castToStringMap(json['outProxyParams']),
      additionalFields: additionalFields,
    );
  }

  /// Converts this ProxySettings instance to JSON.
  ///
  /// Includes both known fields and any additional fields that were
  /// present in the original JSON.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'remoteDNS': remoteDNS,
      'remoteDnsHost': remoteDnsHost,
      'localDNS': localDNS,
      'cleanIPs': cleanIPs,
      'proxyIPs': proxyIPs,
      'outProxyParams': outProxyParams,
    };

    // Add back any additional fields
    json.addAll(_additionalFields);

    return json;
  }

  /// Creates a new ProxySettings with updated clean IPs.
  ///
  /// This is the primary method for updating the settings.
  /// All other fields remain unchanged.
  ProxySettings copyWithCleanIPs(List<String> newCleanIPs) {
    return ProxySettings(
      remoteDNS: remoteDNS,
      remoteDnsHost: Map.from(remoteDnsHost),
      localDNS: localDNS,
      cleanIPs: List.from(newCleanIPs),
      proxyIPs: List.from(proxyIPs),
      outProxyParams: Map.from(outProxyParams),
      additionalFields: Map.from(_additionalFields),
    );
  }

  /// Returns true if this settings object has clean IPs configured.
  bool hasCleanIPs() {
    return cleanIPs.isNotEmpty;
  }

  /// Returns the number of configured clean IPs.
  int get cleanIPCount => cleanIPs.length;

  /// Returns true if this settings object has proxy IPs configured.
  bool hasProxyIPs() {
    return proxyIPs.isNotEmpty;
  }

  /// Returns the number of configured proxy IPs.
  int get proxyIPCount => proxyIPs.length;

  /// Validates that required fields are present.
  ///
  /// Returns true if the settings appear to be valid.
  bool isValid() {
    // At minimum, we should have DNS settings
    return remoteDNS.isNotEmpty || localDNS.isNotEmpty;
  }

  /// Returns a copy of the additional (unknown) fields.
  Map<String, dynamic> get additionalFields =>
      Map.unmodifiable(_additionalFields);

  /// Returns true if there are any additional fields beyond the known ones.
  bool hasAdditionalFields() {
    return _additionalFields.isNotEmpty;
  }

  @override
  String toString() {
    return 'ProxySettings('
        'remoteDNS: $remoteDNS, '
        'localDNS: $localDNS, '
        'cleanIPs: ${cleanIPs.length} IPs, '
        'proxyIPs: ${proxyIPs.length} IPs, '
        'additionalFields: ${_additionalFields.keys.length} fields)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ProxySettings &&
        other.remoteDNS == remoteDNS &&
        _mapEquals(other.remoteDnsHost, remoteDnsHost) &&
        other.localDNS == localDNS &&
        _listEquals(other.cleanIPs, cleanIPs) &&
        _listEquals(other.proxyIPs, proxyIPs) &&
        _mapEquals(other.outProxyParams, outProxyParams) &&
        _mapEquals(other._additionalFields, _additionalFields);
  }

  @override
  int get hashCode {
    return Object.hash(
      remoteDNS,
      _mapHashCode(remoteDnsHost),
      localDNS,
      _listHashCode(cleanIPs),
      _listHashCode(proxyIPs),
      _mapHashCode(outProxyParams),
      _mapHashCode(_additionalFields),
    );
  }

  int _listHashCode(List list) {
    return Object.hashAll(list);
  }

  int _mapHashCode(Map map) {
    return Object.hashAll(map.keys.toList()..sort()) ^
        Object.hashAll(map.values.toList());
  }

  static Map<String, dynamic> _castToStringMap(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return {};
  }

  // Helper methods for deep equality
  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _mapEquals<K, V>(Map<K, V>? a, Map<K, V>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) {
        return false;
      }
    }
    return true;
  }
}
