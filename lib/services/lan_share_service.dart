import 'dart:io';

class LanShareService {
  static final LanShareService _instance = LanShareService._internal();
  static LanShareService get instance => _instance;
  LanShareService._internal();

  /// Returns the first non-loopback IPv4 address on a local network interface,
  /// or null if none can be found.
  Future<String?> getLocalNetworkIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String formatSocksProxy(String ip, int port) => 'socks5://$ip:$port';
  String formatHttpProxy(String ip, int port) => 'http://$ip:$port';
  String formatAddress(String ip, int port) => '$ip:$port';
}
