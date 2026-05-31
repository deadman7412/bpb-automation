class XrayTrafficStats {
  final int uplinkBytes;
  final int downlinkBytes;
  final double? uplinkBytesPerSec;
  final double? downlinkBytesPerSec;
  final DateTime measuredAt;

  const XrayTrafficStats({
    required this.uplinkBytes,
    required this.downlinkBytes,
    this.uplinkBytesPerSec,
    this.downlinkBytesPerSec,
    required this.measuredAt,
  });

  String get formattedUpload => formatBytes(uplinkBytes);
  String get formattedDownload => formatBytes(downlinkBytes);

  String get formattedUploadSpeed =>
      uplinkBytesPerSec != null ? '${formatBytes(uplinkBytesPerSec!.toInt())}/s' : '';
  String get formattedDownloadSpeed =>
      downlinkBytesPerSec != null ? '${formatBytes(downlinkBytesPerSec!.toInt())}/s' : '';

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
