import 'dart:math';
import 'package:flutter/services.dart';
import 'log_service.dart';

/// Service for loading and managing IP addresses for scanning
class IPLoader {
  final LogService _logService = LogService.instance;

  /// Load IPv4 addresses from assets
  Future<List<String>> loadIPv4Addresses({int maxSamplesPerCIDR = 200}) async {
    try {
      _logService.logInfo('Loading IPv4 addresses from assets (max $maxSamplesPerCIDR per CIDR)');
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
      _logService.logInfo('Loading IPv6 addresses from assets (max $maxSamplesPerCIDR per CIDR)');
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
      _logService.logInfo('Loading all IP addresses (max $maxSamplesPerCIDR per CIDR)');
      final ipv4 = await loadIPv4Addresses(maxSamplesPerCIDR: maxSamplesPerCIDR);
      final ipv6 = await loadIPv6Addresses(maxSamplesPerCIDR: maxSamplesPerCIDR);
      final all = [...ipv4, ...ipv6];
      _logService.logOk('Loaded ${all.length} total IP addresses (${ipv4.length} IPv4, ${ipv6.length} IPv6)');
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
          _logService.logInfo('Expanded CIDR $trimmed to ${rangeIPs.length} IPs');
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
  List<String> _expandCIDR(String cidr, {int maxSamples = 200}) {
    try {
      final parts = cidr.split('/');
      if (parts.length != 2) return [];

      final baseIP = parts[0];
      final prefix = int.tryParse(parts[1]);
      if (prefix == null) return [];

      // Only handle IPv4 for now
      if (!baseIP.contains('.')) {
        _logService.logWarn('IPv6 CIDR expansion not implemented: $cidr');
        return [];
      }

      // Parse base IP
      final octets = baseIP.split('.').map(int.tryParse).toList();
      if (octets.length != 4 || octets.any((o) => o == null || o < 0 || o > 255)) {
        return [];
      }

      // Calculate range size
      final hostBits = 32 - prefix;
      final totalIPs = hostBits < 31 ? (1 << hostBits) : 2147483648; // Cap at 2^31

      // If range is small enough, expand all
      if (totalIPs <= maxSamples) {
        return _expandCIDRFull(octets.cast<int>(), prefix);
      }

      // Otherwise, randomly sample
      return _sampleCIDRRange(octets.cast<int>(), prefix, maxSamples);
    } catch (e) {
      _logService.logWarn('Failed to expand CIDR $cidr: $e');
      return [];
    }
  }

  /// Expand small CIDR range completely
  List<String> _expandCIDRFull(List<int> baseOctets, int prefix) {
    final ips = <String>[];
    final hostBits = 32 - prefix;
    final totalIPs = 1 << hostBits;

    for (var i = 0; i < totalIPs; i++) {
      final ip = _ipFromOffset(baseOctets, i);
      ips.add(ip);
    }

    return ips;
  }

  /// Sample random IPs from large CIDR range
  List<String> _sampleCIDRRange(List<int> baseOctets, int prefix, int samples) {
    final ips = <String>{};  // Use Set to avoid duplicates
    final random = Random();
    final hostBits = 32 - prefix;
    final maxOffset = hostBits < 31 ? (1 << hostBits) : 2147483647;

    while (ips.length < samples) {
      final offset = random.nextInt(maxOffset);
      final ip = _ipFromOffset(baseOctets, offset);
      ips.add(ip);
    }

    return ips.toList();
  }

  /// Calculate IP address from base octets + offset
  String _ipFromOffset(List<int> baseOctets, int offset) {
    // Convert base to 32-bit integer
    int ipInt = (baseOctets[0] << 24) |
                (baseOctets[1] << 16) |
                (baseOctets[2] << 8) |
                baseOctets[3];

    // Add offset
    ipInt += offset;

    // Convert back to octets
    final o1 = (ipInt >> 24) & 0xFF;
    final o2 = (ipInt >> 16) & 0xFF;
    final o3 = (ipInt >> 8) & 0xFF;
    final o4 = ipInt & 0xFF;

    return '$o1.$o2.$o3.$o4';
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
      _logService.logInfo('Selecting all ${ips.length} IPs (requested: $count)');
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
enum IPType {
  ipv4,
  ipv6,
  both,
}
