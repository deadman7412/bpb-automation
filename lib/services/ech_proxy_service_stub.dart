class EchProxyService {
  EchProxyService._();
  static final EchProxyService instance = EchProxyService._();

  Future<String?> fetchEchViaCleanIPs({
    required String hostName,
    required List<String> candidateIPs,
    List<String> resolverHosts = const ['dns.google', 'cloudflare-dns.com'],
  }) async {
    return null;
  }
}
