import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bpb_automation/models/xray_config.dart';
import 'package:bpb_automation/services/log_service.dart';
import 'package:bpb_automation/services/storage_service.dart';
import 'package:bpb_automation/services/xray_service.dart';
import 'package:bpb_automation/utils/socks5_helper.dart';

class EchProxyService {
  EchProxyService._();
  static final EchProxyService instance = EchProxyService._();

  final LogService _log = LogService.instance;
  final StorageService _storage = StorageService.instance;
  final XrayService _xray = XrayService.instance;

  Future<String?> fetchEchViaCleanIPs({
    required String hostName,
    required List<String> candidateIPs,
    List<String> resolverHosts = const ['dns.google', 'cloudflare-dns.com'],
  }) async {
    final config = await _loadTemplateConfig();
    if (config == null) {
      _log.logWarn('No cached Xray config available for SOCKS ECH fallback');
      return null;
    }

    final candidates = candidateIPs.where((e) => e.trim().isNotEmpty).toList();
    if (candidates.isEmpty) {
      _log.logWarn('No clean IP candidates for SOCKS ECH fallback');
      return null;
    }

    final resolvers = resolverHosts
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (resolvers.isEmpty) {
      _log.logWarn('No DNS resolvers configured for SOCKS ECH fallback');
      return null;
    }

    for (final resolver in resolvers) {
      for (int i = 0; i < candidates.length; i++) {
        final ip = candidates[i];
        try {
          _log.logInfo(
            'Trying ECH lookup via SOCKS resolver $resolver, '
            'candidate ${i + 1}/${candidates.length}: $ip',
          );
          final ech = await _xray.runWithSocksProxy<String>(
            config: config,
            candidateIP: ip,
            action: (socksPort) => _queryEchViaSocks(
              socksPort: socksPort,
              hostName: hostName,
              resolverHost: resolver,
            ),
          );
          if (ech.isNotEmpty) {
            _log.logOk(
              'ECH lookup via SOCKS succeeded using resolver $resolver and candidate $ip',
            );
            return ech;
          }
        } catch (e, stackTrace) {
          _log.logWarn(
            'SOCKS ECH lookup failed via resolver $resolver, candidate $ip: $e',
          );
          _log.logError('SOCKS ECH candidate failure stack', e, stackTrace);
        }
      }
    }

    return null;
  }

  Future<XrayConfig?> _loadTemplateConfig() async {
    final cached = await _storage.getCachedConfigs();
    if (cached == null || cached.isEmpty) {
      return null;
    }

    final first = cached.first;
    if (first is! Map<String, dynamic>) {
      return null;
    }

    try {
      return XrayConfig.fromJson(first);
    } catch (_) {
      return null;
    }
  }

  Future<String> _queryEchViaSocks({
    required int socksPort,
    required String hostName,
    required String resolverHost,
  }) async {
    Socks5Connection? conn;
    SecureSocket? tlsSocket;
    try {
      conn = await Socks5Helper.connectViaSocks5(
        socksHost: '127.0.0.1',
        socksPort: socksPort,
        targetHost: resolverHost,
        targetPort: 443,
        timeout: 12,
      );

      tlsSocket = await conn.secure(host: resolverHost);

      final path =
          '/resolve?name=${Uri.encodeQueryComponent(hostName)}&type=HTTPS';
      tlsSocket.write(
        'GET $path HTTP/1.1\r\n'
        'Host: $resolverHost\r\n'
        'Accept: application/dns-json\r\n'
        'Connection: close\r\n'
        '\r\n',
      );
      await tlsSocket.flush();

      final raw = await utf8.decoder
          .bind(tlsSocket)
          .join()
          .timeout(const Duration(seconds: 18));

      final status = _extractStatus(raw);
      if (status != 200) {
        throw Exception('DNS-over-SOCKS request failed: HTTP $status');
      }

      final body = _extractBody(raw);
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) {
        throw Exception('Invalid DNS JSON payload');
      }

      final answers = json['Answer'];
      if (answers is! List) {
        throw Exception('DNS JSON missing Answer');
      }

      for (final answer in answers) {
        if (answer is! Map) continue;
        final data = answer['data']?.toString() ?? '';
        final ech = RegExp(r'ech=([^ ]+)').firstMatch(data)?.group(1);
        if (ech != null && ech.isNotEmpty) {
          return ech;
        }
      }

      throw Exception('ECH record not found in DNS response');
    } finally {
      try {
        await tlsSocket?.close();
      } catch (_) {}
      try {
        await conn?.close();
      } catch (_) {}
    }
  }

  int _extractStatus(String response) {
    final line = response.split('\r\n').first;
    final match = RegExp(r'^HTTP/\S+\s+(\d{3})').firstMatch(line);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  String _extractBody(String response) {
    final sep = response.indexOf('\r\n\r\n');
    if (sep < 0) return '';
    return response.substring(sep + 4);
  }
}
