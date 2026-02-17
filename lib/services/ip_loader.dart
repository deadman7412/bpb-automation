import 'dart:math';
import 'package:flutter/services.dart';
import 'log_service.dart';

/// Service for loading and managing IP addresses for scanning
class IPLoader {
  final LogService _logService = LogService.instance;

  /// Load IPv4 addresses from assets
  Future<List<String>> loadIPv4Addresses({int maxSamplesPerCIDR = 200}) async {
    try {
      _logService.logInfo(
        'Loading IPv4 addresses from assets (max $maxSamplesPerCIDR per CIDR)',
      );
      final content = await rootBundle.loadString('assets/ip_lists/ip.txt');
      final ips = _parseIPList(content, maxSamplesPerCIDR: maxSamplesPerCIDR);
      _logService.logOk('Loaded ${ips.length} IPv4 addresses');
      return ips;
    } catch (e, stackTrace) {
      _logService.logError('Failed to load IPv4 addresses', e, stackTrace);
      rethrow;
    }
  }

  /// Load IPv6 addresses from assets
  Future<List<String>> loadIPv6Addresses({int maxSamplesPerCIDR = 200}) async {
    try {
      _logService.logInfo(
        'Loading IPv6 addresses from assets (max $maxSamplesPerCIDR per CIDR)',
      );
      final content = await rootBundle.loadString('assets/ip_lists/ipv6.txt');
      final ips = _parseIPList(content, maxSamplesPerCIDR: maxSamplesPerCIDR);
      _logService.logOk('Loaded ${ips.length} IPv6 addresses');
      return ips;
    } catch (e, stackTrace) {
      _logService.logError('Failed to load IPv6 addresses', e, stackTrace);
      rethrow;
    }
  }

  /// Load both IPv4 and IPv6 addresses
  Future<List<String>> loadAllAddresses({int maxSamplesPerCIDR = 200}) async {
    try {
      _logService.logInfo(
        'Loading all IP addresses (max $maxSamplesPerCIDR per CIDR)',
      );
      final ipv4 = await loadIPv4Addresses(
        maxSamplesPerCIDR: maxSamplesPerCIDR,
      );
      final ipv6 = await loadIPv6Addresses(
        maxSamplesPerCIDR: maxSamplesPerCIDR,
      );
      final all = [...ipv4, ...ipv6];
      _logService.logOk(
        'Loaded ${all.length} total IP addresses (${ipv4.length} IPv4, ${ipv6.length} IPv6)',
      );
      return all;
    } catch (e, stackTrace) {
      _logService.logError('Failed to load IP addresses', e, stackTrace);
      rethrow;
    }
  }

  /// Parse IP list from text content
  ///
  /// Supports both individual IPs and CIDR ranges.
  /// CIDR ranges are randomly sampled.
  List<String> _parseIPList(String content, {int maxSamplesPerCIDR = 200}) {
    final lines = content.split('\n');
    final ips = <String>[];

    for (var line in lines) {
      final trimmed = line.trim();

      // Skip empty lines and comments
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }

      // Check if CIDR range
      if (trimmed.contains('/')) {
        final rangeIPs = _expandCIDR(trimmed, maxSamples: maxSamplesPerCIDR);
        if (rangeIPs.isNotEmpty) {
          ips.addAll(rangeIPs);
          _logService.logInfo(
            'Expanded CIDR $trimmed to ${rangeIPs.length} IPs',
          );
        } else {
          _logService.logWarn('Skipping invalid CIDR: $trimmed');
        }
      } else {
        // Individual IP
        if (_isValidIP(trimmed)) {
          ips.add(trimmed);
        } else {
          _logService.logWarn('Skipping invalid IP: $trimmed');
        }
      }
    }

    return ips;
  }

  /// Expand CIDR range to individual IPs (with random sampling for large ranges)
  ///
  /// IPv4: Uses subnet-aware sampling (one IP per /24 subnet) to ensure routing diversity
  /// IPv6: Uses pure random sampling across entire range
  List<String> _expandCIDR(String cidr, {int maxSamples = 200}) {
    try {
      final parts = cidr.split('/');
      if (parts.length != 2) return [];

      final baseIP = parts[0];
      final prefix = int.tryParse(parts[1]);
      if (prefix == null) return [];

      // Handle IPv6
      if (baseIP.contains(':')) {
        return _expandIPv6CIDR(baseIP, prefix, maxSamples);
      }

      // Handle IPv4
      final octets = baseIP.split('.').map(int.tryParse).toList();
      if (octets.length != 4 ||
          octets.any((o) => o == null || o < 0 || o > 255)) {
        return [];
      }

      return _expandIPv4CIDR(octets.cast<int>(), prefix, maxSamples);
    } catch (e) {
      _logService.logWarn('Failed to expand CIDR $cidr: $e');
      return [];
    }
  }

  /// Expand IPv4 CIDR using /24 subnet-aware sampling
  /// Matches Go scanner behavior: one random IP per /24 subnet for routing diversity
  List<String> _expandIPv4CIDR(
    List<int> baseOctets,
    int prefix,
    int maxSamples,
  ) {
    final hostBits = 32 - prefix;
    final totalIPs = hostBits < 31 ? (1 << hostBits) : 2147483648;

    // If range is small enough, expand all
    if (totalIPs <= maxSamples) {
      return _expandCIDRFull(baseOctets, prefix);
    }

    // Use subnet-aware sampling for large ranges
    // This matches Go scanner's approach: one random IP per /24 subnet
    return _sampleIPv4BySubnet(baseOctets, prefix, maxSamples);
  }

  /// Sample IPv4 addresses with one random IP per /24 subnet
  /// This ensures routing diversity across Cloudflare's network topology
  List<String> _sampleIPv4BySubnet(
    List<int> baseOctets,
    int prefix,
    int maxSamples,
  ) {
    final ips = <String>[];
    final random = Random();

    // Convert base to 32-bit integer
    int baseInt =
        (baseOctets[0] << 24) |
        (baseOctets[1] << 16) |
        (baseOctets[2] << 8) |
        baseOctets[3];

    final hostBits = 32 - prefix;
    final maxOffset = hostBits < 31 ? (1 << hostBits) : 2147483647;

    // Calculate number of /24 subnets in this range
    int numSubnets;
    if (prefix >= 24) {
      // Smaller than /24, treat as single subnet
      numSubnets = 1;
    } else {
      // Number of /24 subnets = 2^(24-prefix)
      numSubnets = 1 << (24 - prefix);
    }

    // Limit samples to available subnets
    final samplesToTake = maxSamples < numSubnets ? maxSamples : numSubnets;

    if (prefix >= 24) {
      // For /24 or smaller, just do random sampling
      final seen = <String>{};
      while (ips.length < samplesToTake && ips.length < maxOffset) {
        final offset = random.nextInt(maxOffset);
        final ip = _ipFromInt(baseInt + offset);
        if (seen.add(ip)) {
          ips.add(ip);
        }
      }
    } else {
      // For larger than /24, sample one IP from each /24 subnet
      final subnetSize = 256; // /24 has 256 IPs
      final subnetsToSample = <int>{};

      // Randomly select which /24 subnets to sample from
      while (subnetsToSample.length < samplesToTake) {
        subnetsToSample.add(random.nextInt(numSubnets));
      }

      // For each selected subnet, pick one random IP
      for (final subnetIndex in subnetsToSample) {
        final subnetOffset = subnetIndex * subnetSize;
        final ipOffset = subnetOffset + random.nextInt(subnetSize);

        if (ipOffset < maxOffset) {
          final ip = _ipFromInt(baseInt + ipOffset);
          ips.add(ip);
        }
      }
    }

    return ips;
  }

  /// Expand IPv6 CIDR using pure random sampling
  /// Matches Go scanner behavior: random IPs across entire range
  List<String> _expandIPv6CIDR(String baseIP, int prefix, int maxSamples) {
    try {
      // Parse IPv6 address
      final parsed = _parseIPv6(baseIP);
      if (parsed == null) {
        _logService.logWarn('Invalid IPv6 address: $baseIP');
        return [];
      }

      return _sampleIPv6Range(parsed, prefix, maxSamples);
    } catch (e) {
      _logService.logWarn('Failed to expand IPv6 CIDR $baseIP/$prefix: $e');
      return [];
    }
  }

  /// Parse IPv6 address to 16-byte array
  List<int>? _parseIPv6(String ip) {
    try {
      // Handle :: abbreviation expansion
      String expanded = ip;
      if (ip.contains('::')) {
        final parts = ip.split('::');
        final leftParts = parts[0].isEmpty ? [] : parts[0].split(':');
        final rightParts = parts.length > 1 && parts[1].isNotEmpty
            ? parts[1].split(':')
            : [];
        final zerosNeeded = 8 - leftParts.length - rightParts.length;

        final middleZeros = List.filled(zerosNeeded, '0');
        expanded = [...leftParts, ...middleZeros, ...rightParts].join(':');
      }

      final parts = expanded.split(':');
      if (parts.length != 8) return null;

      final bytes = <int>[];
      for (final part in parts) {
        final value = int.tryParse(part, radix: 16);
        if (value == null || value > 0xFFFF) return null;

        // Convert to 2 bytes (big-endian)
        bytes.add((value >> 8) & 0xFF);
        bytes.add(value & 0xFF);
      }

      return bytes;
    } catch (e) {
      return null;
    }
  }

  /// Sample random IPv6 addresses from range
  /// Matches Go scanner's approach: randomize last 2 bytes, increment through range
  List<String> _sampleIPv6Range(
    List<int> baseBytes,
    int prefix,
    int maxSamples,
  ) {
    final ips = <String>[];
    final random = Random();
    final seen = <String>{};

    // For IPv6, we'll use pure random sampling within the prefix
    // This matches the Go scanner's chooseIPv6() behavior

    for (var i = 0; i < maxSamples && i < 10000; i++) {
      // Cap iterations
      final ipBytes = List<int>.from(baseBytes);

      // Randomize the host portion based on prefix
      final hostBits = 128 - prefix;
      final hostBytes = (hostBits / 8).ceil();

      // Randomize last bytes (host portion)
      for (var j = 16 - hostBytes; j < 16; j++) {
        if (j >= 0) {
          ipBytes[j] = random.nextInt(256);
        }
      }

      final ip = _ipv6ToString(ipBytes);
      if (seen.add(ip)) {
        ips.add(ip);
      }

      if (ips.length >= maxSamples) break;
    }

    return ips;
  }

  /// Convert 16-byte array to IPv6 string
  String _ipv6ToString(List<int> bytes) {
    if (bytes.length != 16) return '';

    final parts = <String>[];
    for (var i = 0; i < 16; i += 2) {
      final value = (bytes[i] << 8) | bytes[i + 1];
      parts.add(value.toRadixString(16));
    }

    return parts.join(':');
  }

  /// Convert 32-bit integer to IPv4 string
  String _ipFromInt(int ipInt) {
    final o1 = (ipInt >> 24) & 0xFF;
    final o2 = (ipInt >> 16) & 0xFF;
    final o3 = (ipInt >> 8) & 0xFF;
    final o4 = ipInt & 0xFF;
    return '$o1.$o2.$o3.$o4';
  }

  /// Expand small CIDR range completely
  List<String> _expandCIDRFull(List<int> baseOctets, int prefix) {
    final ips = <String>[];
    final hostBits = 32 - prefix;
    final totalIPs = 1 << hostBits;

    for (var i = 0; i < totalIPs; i++) {
      final ip = _ipFromInt(
        (baseOctets[0] << 24) |
            (baseOctets[1] << 16) |
            (baseOctets[2] << 8) |
            baseOctets[3] + i,
      );
      ips.add(ip);
    }

    return ips;
  }

  /// Basic IP validation (IPv4 or IPv6)
  bool _isValidIP(String ip) {
    // IPv4 pattern: xxx.xxx.xxx.xxx
    final ipv4Pattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');

    // IPv6 pattern: basic check for colons
    final ipv6Pattern = RegExp(r'^[0-9a-fA-F:]+$');

    if (ipv4Pattern.hasMatch(ip)) {
      // Validate IPv4 octets are 0-255
      final parts = ip.split('.');
      return parts.every((part) {
        final num = int.tryParse(part);
        return num != null && num >= 0 && num <= 255;
      });
    } else if (ipv6Pattern.hasMatch(ip) && ip.contains(':')) {
      // Basic IPv6 validation
      return true;
    }

    return false;
  }

  /// Randomly select N IPs from a list
  List<String> selectRandomIPs(List<String> ips, int count) {
    if (count >= ips.length) {
      _logService.logInfo(
        'Selecting all ${ips.length} IPs (requested: $count)',
      );
      return List.from(ips);
    }

    _logService.logInfo('Randomly selecting $count IPs from ${ips.length}');
    final random = Random();
    final selected = <String>[];
    final available = List.from(ips);

    for (var i = 0; i < count; i++) {
      final index = random.nextInt(available.length);
      selected.add(available.removeAt(index));
    }

    return selected;
  }

  /// Filter IPs by type
  List<String> filterByType(List<String> ips, IPType type) {
    switch (type) {
      case IPType.ipv4:
        return ips.where((ip) => ip.contains('.')).toList();
      case IPType.ipv6:
        return ips.where((ip) => ip.contains(':')).toList();
      case IPType.both:
        return ips;
    }
  }
}

/// IP address type filter
enum IPType { ipv4, ipv6, both }
