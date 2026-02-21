import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../utils/socks5_helper.dart';

class ProxyConnectivityCheckResult {
  final String name;
  final bool success;
  final int? statusCode;
  final String? error;

  const ProxyConnectivityCheckResult({
    required this.name,
    required this.success,
    this.statusCode,
    this.error,
  });
}

class ProxyConnectivityDebugService {
  ProxyConnectivityDebugService._();
  static final ProxyConnectivityDebugService instance =
      ProxyConnectivityDebugService._();

  static const Duration _timeout = Duration(seconds: 8);

  Future<List<ProxyConnectivityCheckResult>> runSuite({
    required int socksPort,
    required String dohQueryHost,
  }) async {
    return [
      await _checkHttp(
        socksPort: socksPort,
        name: 'HTTP connectivitycheck',
        uri: Uri.http('connectivitycheck.gstatic.com', '/generate_204'),
      ),
      await _checkHttp(
        socksPort: socksPort,
        name: 'HTTPS example.com',
        uri: Uri.https('example.com', '/'),
      ),
      await _checkHttp(
        socksPort: socksPort,
        name: 'DoH dns.google',
        uri: Uri.https('dns.google', '/resolve', {
          'name': dohQueryHost,
          'type': 'HTTPS',
        }),
        headers: const {'Accept': 'application/dns-json'},
      ),
      await _checkHttp(
        socksPort: socksPort,
        name: 'DoH cloudflare-dns.com',
        uri: Uri.https('cloudflare-dns.com', '/dns-query', {
          'name': dohQueryHost,
          'type': 'HTTPS',
        }),
        headers: const {'Accept': 'application/dns-json'},
      ),
    ];
  }

  Future<ProxyConnectivityCheckResult> _checkHttp({
    required int socksPort,
    required String name,
    required Uri uri,
    Map<String, String> headers = const {},
  }) async {
    Socks5Connection? conn;
    SecureSocket? tlsSocket;
    try {
      final isHttps = uri.scheme.toLowerCase() == 'https';
      final port = uri.hasPort ? uri.port : (isHttps ? 443 : 80);

      conn = await Socks5Helper.connectViaSocks5(
        socksHost: '127.0.0.1',
        socksPort: socksPort,
        targetHost: uri.host,
        targetPort: port,
        timeout: _timeout.inSeconds,
      );

      if (isHttps) {
        tlsSocket = await conn.secure(host: uri.host, timeout: _timeout);
      }

      final path = uri.path.isEmpty ? '/' : uri.path;
      final target = uri.hasQuery ? '$path?${uri.query}' : path;
      final request = StringBuffer()
        ..write('GET $target HTTP/1.1\r\n')
        ..write('Host: ${uri.host}\r\n')
        ..write('Connection: close\r\n')
        ..write('Accept: */*\r\n')
        ..write('Accept-Encoding: identity\r\n');
      headers.forEach((k, v) => request.write('$k: $v\r\n'));
      request.write('\r\n');

      if (isHttps) {
        tlsSocket!.write(request.toString());
        await tlsSocket.flush();
      } else {
        conn.write(utf8.encode(request.toString()));
        await conn.flush();
      }

      final raw = isHttps
          ? await utf8.decoder.bind(tlsSocket!).join().timeout(_timeout)
          : await _readPlain(conn);

      if (raw.trim().isEmpty) {
        return ProxyConnectivityCheckResult(
          name: name,
          success: false,
          error: 'Empty reply',
        );
      }

      final status = _extractStatus(raw);
      if (status >= 200 && status < 400) {
        return ProxyConnectivityCheckResult(
          name: name,
          success: true,
          statusCode: status,
        );
      }
      return ProxyConnectivityCheckResult(
        name: name,
        success: false,
        statusCode: status,
        error: 'HTTP $status',
      );
    } catch (e) {
      return ProxyConnectivityCheckResult(
        name: name,
        success: false,
        error: e.toString(),
      );
    } finally {
      try {
        await tlsSocket?.close();
      } catch (_) {}
      try {
        await conn?.close();
      } catch (_) {}
    }
  }

  Future<String> _readPlain(Socks5Connection conn) async {
    final bytes = <int>[];
    final deadline = DateTime.now().add(_timeout);
    while (DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) break;
      List<int> chunk;
      try {
        chunk = await conn.readAvailable(remaining);
      } on TimeoutException {
        break;
      }
      if (chunk.isEmpty) break;
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) break;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  int _extractStatus(String response) {
    final firstLine = response.split('\r\n').first;
    final match = RegExp(r'^HTTP/\S+\s+(\d{3})').firstMatch(firstLine);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }
}
