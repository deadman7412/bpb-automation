import 'dart:math';
import 'package:flutter/services.dart';
import 'log_service.dart';

/// Service for loading and managing IP addresses for scanning.
///
/// Loads exactly the requested number of IPs, distributed proportionally
/// across Cloudflare CIDR ranges based on each range's /24 subnet count.
/// Larger ranges (e.g. /13) receive more IPs proportionally than smaller
/// ones (e.g. /22), ensuring balanced coverage of Cloudflare's network.
class IPLoader {
  final LogService _logService = LogService.instance;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Load exactly [targetCount] IPv4 addresses distributed proportionally
  /// across Cloudflare CIDR ranges.
  ///
  /// Each range's share is proportional to its /24 subnet count. One IP per
  /// /24 subnet is sampled, so the maximum useful [targetCount] is the total
  /// number of /24 subnets across all IPv4 ranges (~5956 for the current
  /// ip.txt). Requests above this cap are silently capped.
  Future<List<String>> loadIPv4AddressesExact({int targetCount = 1000}) async {
    try {
      _logService.logInfo(
        'Loading $targetCount IPv4 addresses (proportional across CIDRs)',
      );
      final content = await rootBundle.loadString('assets/ip_lists/ip.txt');
      final ips = _loadExact(content, targetCount, isIPv6: false);
      _logService.logOk('Loaded ${ips.length} IPv4 addresses');
      return ips;
    } catch (e, stackTrace) {
      _logService.logError('Failed to load IPv4 addresses', e, stackTrace);
      rethrow;
    }
  }

  /// Load exactly [targetCount] IPv6 addresses distributed evenly
  /// across Cloudflare IPv6 CIDR ranges.
  Future<List<String>> loadIPv6AddressesExact({int targetCount = 200}) async {
    try {
      _logService.logInfo(
        'Loading $targetCount IPv6 addresses (proportional across CIDRs)',
      );
      final content = await rootBundle.loadString('assets/ip_lists/ipv6.txt');
      final ips = _loadExact(content, targetCount, isIPv6: true);
      _logService.logOk('Loaded ${ips.length} IPv6 addresses');
      return ips;
    } catch (e, stackTrace) {
      _logService.logError('Failed to load IPv6 addresses', e, stackTrace);
      rethrow;
    }
  }

  /// Returns up to [count] randomly selected IPs from [ips] without duplicates.
  ///
  /// If [count] >= [ips].length, returns a shuffled copy of the full list.
  List<String> selectRandomIPs(List<String> ips, int count) {
    if (count >= ips.length) return List.from(ips)..shuffle(Random());
    final shuffled = List<String>.from(ips)..shuffle(Random());
    return shuffled.take(count).toList();
  }

  /// Filters [ips] to only include addresses matching [type].
  ///
  /// [IPType.ipv4] returns only IPv4 addresses (no colon).
  /// [IPType.ipv6] returns only IPv6 addresses (contains colon).
  /// [IPType.both] returns all addresses unchanged.
  List<String> filterByType(List<String> ips, IPType type) {
    switch (type) {
      case IPType.ipv4:
        return ips.where((ip) => !ip.contains(':')).toList();
      case IPType.ipv6:
        return ips.where((ip) => ip.contains(':')).toList();
      case IPType.both:
        return List.from(ips);
    }
  }

  /// Load [targetCount] addresses total, split 80% IPv4 / 20% IPv6.
  Future<List<String>> loadAllAddressesExact({int targetCount = 1000}) async {
    try {
      _logService.logInfo(
        'Loading $targetCount total addresses (80% IPv4 / 20% IPv6)',
      );
      final ipv4Count = (targetCount * 0.8).round();
      final ipv6Count = targetCount - ipv4Count;

      final ipv4 = await loadIPv4AddressesExact(targetCount: ipv4Count);
      final ipv6 = await loadIPv6AddressesExact(targetCount: ipv6Count);

      final all = [...ipv4, ...ipv6]..shuffle(Random());
      _logService.logOk(
        'Loaded ${all.length} total (${ipv4.length} IPv4, ${ipv6.length} IPv6)',
      );
      return all;
    } catch (e, stackTrace) {
      _logService.logError('Failed to load addresses', e, stackTrace);
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Core loading logic
  // -------------------------------------------------------------------------

  List<String> _loadExact(
    String content,
    int targetCount, {
    required bool isIPv6,
  }) {
    final entries = _parseCidrEntries(
      content,
      isIPv6: isIPv6,
      maxCapacity: targetCount,
    );
    if (entries.isEmpty) return [];

    final weights = entries.map((e) => e.weight).toList();
    final caps = entries.map((e) => e.capacity).toList();
    final allocations = _allocateProportionally(weights, caps, targetCount);

    final ips = <String>[];
    for (int i = 0; i < entries.length; i++) {
      if (allocations[i] <= 0) continue;
      _logService.logInfo(
        '${entries[i].cidr}: allocating ${allocations[i]} IPs',
      );
      ips.addAll(_expandCIDR(entries[i].cidr, maxSamples: allocations[i]));
    }

    ips.shuffle(Random());
    return ips;
  }

  // -------------------------------------------------------------------------
  // CIDR parsing
  // -------------------------------------------------------------------------

  List<_CidrEntry> _parseCidrEntries(
    String content, {
    required bool isIPv6,
    int maxCapacity = 10000,
  }) {
    final entries = <_CidrEntry>[];

    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      if (!trimmed.contains('/')) continue;

      final parts = trimmed.split('/');
      if (parts.length != 2) continue;
      final prefix = int.tryParse(parts[1]);
      if (prefix == null) continue;

      int weight;
      int capacity;

      if (isIPv6) {
        // All IPv6 ranges in our list are /32 — treat them with equal weight.
        // IPv6 ranges contain astronomical numbers of IPs so cap is irrelevant.
        weight = 1;
        capacity = maxCapacity;
      } else {
        if (prefix >= 24) {
          // Range smaller than /24: weight 1, capacity = all IPs in range.
          weight = 1;
          capacity = 1 << (32 - prefix);
        } else {
          // Weight = number of /24 subnets.
          // Capacity = one IP per /24 subnet (routing diversity limit).
          weight = 1 << (24 - prefix);
          capacity = weight;
        }
      }

      entries.add(_CidrEntry(cidr: trimmed, weight: weight, capacity: capacity));
    }

    return entries;
  }

  // -------------------------------------------------------------------------
  // Proportional allocation with cap-and-redistribute
  //
  // Distributes [total] slots across CIDRs proportionally to [weights],
  // never exceeding each CIDR's [caps] entry.  If a CIDR hits its cap,
  // the leftover is redistributed among uncapped CIDRs in further rounds.
  // -------------------------------------------------------------------------

  List<int> _allocateProportionally(
    List<int> weights,
    List<int> caps,
    int total,
  ) {
    final n = weights.length;
    final allocations = List<int>.filled(n, 0);
    final isCapped = List<bool>.filled(n, false);
    int remaining = total;

    while (remaining > 0) {
      // Sum weights of uncapped CIDRs.
      int uncappedWeight = 0;
      int uncappedCount = 0;
      for (int i = 0; i < n; i++) {
        if (!isCapped[i]) {
          uncappedWeight += weights[i];
          uncappedCount++;
        }
      }
      if (uncappedWeight == 0 || uncappedCount == 0) break;

      // Floor pass: compute proportional floor allocation for uncapped CIDRs.
      final proposed = List<int>.filled(n, 0);
      final fractions = List<double>.filled(n, 0.0);
      int floored = 0;

      for (int i = 0; i < n; i++) {
        if (isCapped[i]) continue;
        final exact = remaining * weights[i] / uncappedWeight;
        proposed[i] = exact.floor();
        fractions[i] = exact - proposed[i];
        floored += proposed[i];
      }

      // Largest-remainder pass: distribute leftover 1-slot increments to
      // the CIDRs with the highest fractional parts.
      int leftover = remaining - floored;
      final order = List.generate(n, (i) => i)
        ..sort((a, b) {
          if (isCapped[a] || isCapped[b]) {
            if (isCapped[a]) return 1;
            if (isCapped[b]) return -1;
          }
          return fractions[b].compareTo(fractions[a]);
        });

      for (int k = 0; k < leftover && k < order.length; k++) {
        final i = order[k];
        if (!isCapped[i]) proposed[i]++;
      }

      // Apply proposed allocations; cap any that exceed their limit.
      bool anyCapped = false;
      for (int i = 0; i < n; i++) {
        if (isCapped[i]) continue;
        final newAlloc = allocations[i] + proposed[i];
        if (newAlloc >= caps[i]) {
          // CIDR hits capacity — give it exactly what it can hold.
          remaining -= (caps[i] - allocations[i]);
          allocations[i] = caps[i];
          isCapped[i] = true;
          anyCapped = true;
        } else {
          allocations[i] = newAlloc;
          remaining -= proposed[i];
        }
      }

      // If no cap was hit this round, remaining is fully allocated — stop.
      if (!anyCapped) break;
    }

    return allocations;
  }

  // -------------------------------------------------------------------------
  // CIDR expansion (unchanged from original)
  // -------------------------------------------------------------------------

  List<String> _expandCIDR(String cidr, {int maxSamples = 200}) {
    try {
      final parts = cidr.split('/');
      if (parts.length != 2) return [];

      final baseIP = parts[0];
      final prefix = int.tryParse(parts[1]);
      if (prefix == null) return [];

      if (baseIP.contains(':')) {
        return _expandIPv6CIDR(baseIP, prefix, maxSamples);
      }

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

  /// Expand IPv4 CIDR using /24 subnet-aware sampling.
  ///
  /// For ranges smaller than /24, full expansion is used (all IPs returned).
  /// For larger ranges, one random IP is sampled per /24 subnet up to
  /// [maxSamples].  The full-expansion shortcut is intentionally restricted
  /// to prefix >= 24 only, preventing /22 and larger ranges from being
  /// fully expanded regardless of [maxSamples].
  List<String> _expandIPv4CIDR(
    List<int> baseOctets,
    int prefix,
    int maxSamples,
  ) {
    if (prefix >= 24) {
      // Range is /24 or smaller — full expansion is safe and correct.
      return _expandCIDRFull(baseOctets, prefix);
    }
    // For all larger ranges, always use subnet-aware sampling.
    return _sampleIPv4BySubnet(baseOctets, prefix, maxSamples);
  }

  List<String> _sampleIPv4BySubnet(
    List<int> baseOctets,
    int prefix,
    int maxSamples,
  ) {
    final ips = <String>[];
    final random = Random();

    final baseInt =
        (baseOctets[0] << 24) |
        (baseOctets[1] << 16) |
        (baseOctets[2] << 8) |
        baseOctets[3];

    // Number of /24 subnets in this range.
    final numSubnets = 1 << (24 - prefix);
    final samplesToTake = maxSamples < numSubnets ? maxSamples : numSubnets;

    const subnetSize = 256; // /24 has 256 IPs

    // Randomly select which /24 subnets to sample from.
    final subnetsToSample = <int>{};
    while (subnetsToSample.length < samplesToTake) {
      subnetsToSample.add(random.nextInt(numSubnets));
    }

    // For each selected subnet, pick one random IP.
    for (final subnetIndex in subnetsToSample) {
      final subnetOffset = subnetIndex * subnetSize;
      final ipOffset = subnetOffset + random.nextInt(subnetSize);
      ips.add(_ipFromInt(baseInt + ipOffset));
    }

    return ips;
  }

  List<String> _expandIPv6CIDR(String baseIP, int prefix, int maxSamples) {
    try {
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

  List<int>? _parseIPv6(String ip) {
    try {
      String expanded = ip;
      if (ip.contains('::')) {
        final parts = ip.split('::');
        final leftParts = parts[0].isEmpty ? [] : parts[0].split(':');
        final rightParts =
            parts.length > 1 && parts[1].isNotEmpty
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
        bytes.add((value >> 8) & 0xFF);
        bytes.add(value & 0xFF);
      }

      return bytes;
    } catch (e) {
      return null;
    }
  }

  List<String> _sampleIPv6Range(
    List<int> baseBytes,
    int prefix,
    int maxSamples,
  ) {
    final ips = <String>[];
    final random = Random();
    final seen = <String>{};

    for (var i = 0; i < maxSamples && i < 10000; i++) {
      final ipBytes = List<int>.from(baseBytes);
      final hostBits = 128 - prefix;
      final hostBytes = (hostBits / 8).ceil();

      for (var j = 16 - hostBytes; j < 16; j++) {
        if (j >= 0) ipBytes[j] = random.nextInt(256);
      }

      final ip = _ipv6ToString(ipBytes);
      if (seen.add(ip)) ips.add(ip);
      if (ips.length >= maxSamples) break;
    }

    return ips;
  }

  String _ipv6ToString(List<int> bytes) {
    if (bytes.length != 16) return '';
    final parts = <String>[];
    for (var i = 0; i < 16; i += 2) {
      parts.add(((bytes[i] << 8) | bytes[i + 1]).toRadixString(16));
    }
    return '[${parts.join(':')}]';
  }

  List<String> _expandCIDRFull(List<int> baseOctets, int prefix) {
    final ips = <String>[];
    final hostBits = 32 - prefix;
    final totalIPs = 1 << hostBits;
    final baseInt =
        (baseOctets[0] << 24) |
        (baseOctets[1] << 16) |
        (baseOctets[2] << 8) |
        baseOctets[3];

    for (var i = 0; i < totalIPs; i++) {
      ips.add(_ipFromInt(baseInt + i));
    }
    return ips;
  }

  String _ipFromInt(int ipInt) {
    final o1 = (ipInt >> 24) & 0xFF;
    final o2 = (ipInt >> 16) & 0xFF;
    final o3 = (ipInt >> 8) & 0xFF;
    final o4 = ipInt & 0xFF;
    return '$o1.$o2.$o3.$o4';
  }
}

// ---------------------------------------------------------------------------
// Internal data class
// ---------------------------------------------------------------------------

class _CidrEntry {
  final String cidr;

  /// Proportional weight (number of /24 subnets for IPv4, 1 per range for IPv6).
  final int weight;

  /// Maximum IPs this CIDR can contribute (routing diversity cap).
  final int capacity;

  const _CidrEntry({
    required this.cidr,
    required this.weight,
    required this.capacity,
  });
}

/// IP address type filter (kept for API compatibility).
enum IPType { ipv4, ipv6, both }
