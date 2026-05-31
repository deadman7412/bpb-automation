class ConnectionTestResult {
  final bool success;
  final String? externalIP;
  final int? latencyMs;
  final String? error;
  final DateTime testedAt;

  const ConnectionTestResult({
    required this.success,
    this.externalIP,
    this.latencyMs,
    this.error,
    required this.testedAt,
  });
}
