class PanelDohForcedIpService {
  static final PanelDohForcedIpService instance =
      PanelDohForcedIpService._internal();

  PanelDohForcedIpService._internal();

  Future<String> getViaForcedIp({
    required Uri uri,
    required String ip,
    required Duration timeout,
  }) {
    throw UnsupportedError(
      'Forced-IP panel DoH is not supported on this platform',
    );
  }
}
