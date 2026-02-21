import 'dart:convert';
import 'dart:io';

class PanelDohForcedIpService {
  static final PanelDohForcedIpService instance =
      PanelDohForcedIpService._internal();

  PanelDohForcedIpService._internal();

  Future<String> getViaForcedIp({
    required Uri uri,
    required String ip,
    required Duration timeout,
  }) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = timeout;
      client.connectionFactory = (targetUri, proxyHost, proxyPort) {
        final targetPort = targetUri.hasPort
            ? targetUri.port
            : (targetUri.scheme == 'https' ? 443 : 80);
        return Future.value(
          ConnectionTask.fromSocket(
            () async {
              final raw = await Socket.connect(ip, targetPort, timeout: timeout);
              return await SecureSocket.secure(
                raw,
                host: targetUri.host,
              ).timeout(timeout);
            }(),
            () {},
          ),
        );
      };

      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      request.headers.set(HttpHeaders.hostHeader, uri.host);
      request.headers.set(HttpHeaders.connectionHeader, 'close');

      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode != 200) {
        throw Exception(
          'Panel DoH forced-IP lookup failed with status ${response.statusCode}',
        );
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }
}
