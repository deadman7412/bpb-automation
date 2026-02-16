/// Represents a scanned Cloudflare IP address with test results.
///
/// This model contains all metrics collected during the IP scanning process,
/// including latency, packet loss, and download speed measurements.
class CleanIP {
  /// The IP address (IPv4 or IPv6)
  final String ip;

  /// Number of packets sent during latency test
  final int packetsSent;

  /// Number of packets received during latency test
  final int packetsReceived;

  /// Packet loss rate as a percentage (0.0 to 100.0)
  final double lossRate;

  /// Average latency in milliseconds
  final double avgLatency;

  /// Download speed in MB/s
  final double downloadSpeed;

  /// Creates a CleanIP instance.
  const CleanIP({
    required this.ip,
    required this.packetsSent,
    required this.packetsReceived,
    required this.lossRate,
    required this.avgLatency,
    required this.downloadSpeed,
  });

  /// Creates a CleanIP instance from a JSON map.
  ///
  /// Example JSON:
  /// ```json
  /// {
  ///   "ip": "1.1.1.1",
  ///   "packets_sent": 10,
  ///   "packets_received": 10,
  ///   "loss_rate": 0.0,
  ///   "avg_latency": 45.2,
  ///   "download_speed": 12.5
  /// }
  /// ```
  factory CleanIP.fromJson(Map<String, dynamic> json) {
    return CleanIP(
      ip: json['ip'] as String,
      packetsSent: json['packets_sent'] as int,
      packetsReceived: json['packets_received'] as int,
      lossRate: (json['loss_rate'] as num).toDouble(),
      avgLatency: (json['avg_latency'] as num).toDouble(),
      downloadSpeed: (json['download_speed'] as num).toDouble(),
    );
  }

  /// Converts this CleanIP instance to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'packets_sent': packetsSent,
      'packets_received': packetsReceived,
      'loss_rate': lossRate,
      'avg_latency': avgLatency,
      'download_speed': downloadSpeed,
    };
  }

  /// Creates a CleanIP instance from CSV row data.
  ///
  /// Expected CSV format:
  /// IP Address,Sent,Received,Loss Rate,Avg Latency,Download Speed
  /// 1.1.1.1,10,10,0%,45.2ms,12.5MB/s
  factory CleanIP.fromCsvRow(List<String> row) {
    if (row.length < 6) {
      throw ArgumentError('CSV row must have at least 6 columns');
    }

    // Parse loss rate (remove % symbol)
    final lossRateStr = row[3].replaceAll('%', '').trim();
    final lossRate = double.parse(lossRateStr);

    // Parse latency (remove 'ms' suffix)
    final latencyStr = row[4].replaceAll('ms', '').trim();
    final avgLatency = double.parse(latencyStr);

    // Parse download speed (remove 'MB/s' suffix)
    final speedStr = row[5].replaceAll('MB/s', '').trim();
    final downloadSpeed = double.parse(speedStr);

    return CleanIP(
      ip: row[0].trim(),
      packetsSent: int.parse(row[1].trim()),
      packetsReceived: int.parse(row[2].trim()),
      lossRate: lossRate,
      avgLatency: avgLatency,
      downloadSpeed: downloadSpeed,
    );
  }

  /// Returns true if this IP has acceptable quality metrics.
  ///
  /// An IP is considered acceptable if:
  /// - Loss rate is below 5%
  /// - Average latency is below 300ms
  bool isAcceptable() {
    return lossRate < 5.0 && avgLatency < 300.0;
  }

  /// Returns true if this IP has zero packet loss.
  bool isPerfect() {
    return lossRate == 0.0;
  }

  /// Compares this IP with another based on quality score.
  ///
  /// Returns negative if this IP is better, positive if worse, 0 if equal.
  /// Quality score prioritizes: low latency > low loss rate > high speed
  int compareQuality(CleanIP other) {
    // First compare latency (lower is better)
    final latencyDiff = avgLatency.compareTo(other.avgLatency);
    if (latencyDiff != 0) return latencyDiff;

    // Then compare loss rate (lower is better)
    final lossDiff = lossRate.compareTo(other.lossRate);
    if (lossDiff != 0) return lossDiff;

    // Finally compare download speed (higher is better)
    return -downloadSpeed.compareTo(other.downloadSpeed);
  }

  /// Returns a formatted string representation for debugging.
  ///
  /// Does not include sensitive information.
  @override
  String toString() {
    return 'CleanIP(ip: $ip, '
        'loss: ${lossRate.toStringAsFixed(1)}%, '
        'latency: ${avgLatency.toStringAsFixed(1)}ms, '
        'speed: ${downloadSpeed.toStringAsFixed(1)}MB/s)';
  }

  /// Returns a human-readable description of the IP quality.
  String getQualityDescription() {
    if (lossRate == 0.0 && avgLatency < 50.0) {
      return 'Excellent';
    } else if (lossRate < 1.0 && avgLatency < 100.0) {
      return 'Very Good';
    } else if (lossRate < 3.0 && avgLatency < 150.0) {
      return 'Good';
    } else if (lossRate < 5.0 && avgLatency < 200.0) {
      return 'Fair';
    } else {
      return 'Poor';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CleanIP &&
        other.ip == ip &&
        other.packetsSent == packetsSent &&
        other.packetsReceived == packetsReceived &&
        other.lossRate == lossRate &&
        other.avgLatency == avgLatency &&
        other.downloadSpeed == downloadSpeed;
  }

  @override
  int get hashCode {
    return Object.hash(
      ip,
      packetsSent,
      packetsReceived,
      lossRate,
      avgLatency,
      downloadSpeed,
    );
  }
}
