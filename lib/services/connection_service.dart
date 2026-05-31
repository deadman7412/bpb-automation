import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/connection_config.dart';
import '../models/connection_test_result.dart';
import '../models/xray_config.dart';
import '../models/xray_connection_state.dart';
import '../utils/socks5_helper.dart';
import 'android_connection_foreground_service.dart';
import 'log_service.dart';
import 'xray_service.dart';
import 'xray_stats_service.dart';

class ConnectionService {
  static final ConnectionService _instance = ConnectionService._internal();
  static ConnectionService get instance => _instance;
  ConnectionService._internal();

  final XrayService _xray = XrayService.instance;
  final LogService _log = LogService.instance;
  final AndroidConnectionForegroundService _androidFgs =
      AndroidConnectionForegroundService.instance;

  XrayConnectionState _state = XrayConnectionState.disconnected();
  final StreamController<XrayConnectionState> _stateController =
      StreamController.broadcast();
  Timer? _healthTimer;

  XrayConnectionState get currentState => _state;
  Stream<XrayConnectionState> get stateStream => _stateController.stream;
  bool get isConnected => _state.isConnected;

  void _emit(XrayConnectionState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  Future<void> connect({
    required XrayConfig templateConfig,
    required String ip,
    required ConnectionConfig connConfig,
  }) async {
    if (_state.isBusy) {
      throw Exception('Connection operation already in progress');
    }
    if (_xray.isPersistentRunning) {
      throw Exception(
        'A proxy is already active. Disconnect first.',
      );
    }

    _emit(XrayConnectionState.connecting(ip: ip));
    _log.logInfo('[Proxy] Connecting to $ip...');

    try {
      if (!_xray.isInitialized) {
        final ok = await _xray.initialize();
        if (!ok) throw Exception('Xray binary initialization failed');
      }

      final connectionConfig = templateConfig
          .copyWithAddress(ip)
          .withConnectionInbounds(
            bindAddress: connConfig.effectiveBindAddress,
            socksPort: connConfig.socksPort,
            httpPort: connConfig.httpPort,
          )
          .withStrippedGeoRules()
          .withStatsMonitoring(apiPort: XrayStatsService.kApiPort);

      await _xray.startPersistent(connectionConfig);

      final ready = await _waitForPort(
        connConfig.socksPort,
        maxSeconds: 10,
      );
      if (!ready) {
        await _xray.stopPersistent();
        throw Exception(
          'Xray did not bind port ${connConfig.socksPort} within 10 seconds',
        );
      }

      await _androidFgs.start(
        socksPort: connConfig.socksPort,
        httpPort: connConfig.httpPort,
        ip: ip,
      );

      XrayStatsService.instance.start();

      _log.logOk(
        '[Proxy] Connected via $ip '
        '(SOCKS5: ${connConfig.effectiveBindAddress}:${connConfig.socksPort})',
      );

      _emit(XrayConnectionState.connected(
        ip: ip,
        configName: templateConfig.remarks,
        socksPort: connConfig.socksPort,
        httpPort: connConfig.httpPort,
        bindAddress: connConfig.effectiveBindAddress,
      ));

      _startHealthWatch();
    } catch (e) {
      _log.logError('[Proxy] Connection failed: $e');
      _emit(XrayConnectionState.error(message: e.toString()));
      rethrow;
    }
  }

  void _startHealthWatch() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_state.isConnected) {
        timer.cancel();
        return;
      }
      if (!_xray.isPersistentRunning) {
        timer.cancel();
        _log.logError('[Proxy] Xray process died unexpectedly');
        XrayStatsService.instance.stop();
        _androidFgs.stop();
        _emit(XrayConnectionState.error(
          message: 'Xray process exited unexpectedly',
        ));
      }
    });
  }

  Future<void> disconnect() async {
    if (_state.isDisconnected) return;
    _healthTimer?.cancel();
    _emit(XrayConnectionState.disconnecting());
    _log.logInfo('[Proxy] Disconnecting...');

    try {
      XrayStatsService.instance.stop();
      await _androidFgs.stop();
      await _xray.stopPersistent();
    } catch (e) {
      _log.logWarn('[Proxy] Error during disconnect: $e');
    }

    _log.logOk('[Proxy] Disconnected');
    _emit(XrayConnectionState.disconnected());
  }

  /// Send an HTTP request through the active SOCKS5 proxy to an external
  /// IP-checking service and return the observed public IP + latency.
  ///
  /// The returned IP will typically be a Cloudflare edge IP, confirming that
  /// traffic is routed correctly through the Cloudflare Worker.
  Future<ConnectionTestResult> testConnection() async {
    if (!_state.isConnected) {
      return ConnectionTestResult(
        success: false,
        error: 'Proxy is not connected. Connect first.',
        testedAt: DateTime.now(),
      );
    }

    final socksPort = _state.socksPort ?? 10808;
    final start = DateTime.now();
    Socks5Connection? conn;

    try {
      conn = await Socks5Helper.connectViaSocks5(
        socksHost: '127.0.0.1',
        socksPort: socksPort,
        targetHost: 'api.ipify.org',
        targetPort: 80,
        timeout: 10,
      );

      conn.write(utf8.encode(
        'GET /?format=json HTTP/1.1\r\n'
        'Host: api.ipify.org\r\n'
        'Connection: close\r\n'
        '\r\n',
      ));
      await conn.flush();

      final buf = StringBuffer();
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        final remaining = deadline.difference(DateTime.now()).inSeconds.clamp(1, 10);
        List<int> chunk;
        try {
          chunk = await conn.readAvailable(remaining);
        } on TimeoutException {
          break;
        }
        if (chunk.isEmpty) break; // server closed connection
        buf.write(utf8.decode(chunk, allowMalformed: true));
      }

      final latencyMs = DateTime.now().difference(start).inMilliseconds;
      final response = buf.toString();

      // Strip HTTP headers — body starts after the blank line
      final bodyStart = response.indexOf('\r\n\r\n');
      final body = bodyStart >= 0
          ? response.substring(bodyStart + 4).trim()
          : response.trim();

      String? ip;
      // Try JSON: {"ip":"1.2.3.4"}
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        ip = json['ip'] as String?;
      } catch (_) {
        // Fall back to plain text or regex extraction
        ip = RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}').firstMatch(body)?.group(0);
      }

      if (ip != null && ip.isNotEmpty) {
        _log.logOk('[Test] External IP: $ip  latency: ${latencyMs}ms');
        return ConnectionTestResult(
          success: true,
          externalIP: ip,
          latencyMs: latencyMs,
          testedAt: DateTime.now(),
        );
      }

      _log.logWarn('[Test] Could not parse IP from response (${body.length} bytes)');
      return ConnectionTestResult(
        success: false,
        error: 'Could not parse IP from response',
        testedAt: DateTime.now(),
      );
    } on Socks5Exception catch (e) {
      _log.logError('[Test] SOCKS5 error: ${e.message}');
      return ConnectionTestResult(
        success: false,
        error: 'SOCKS5 error: ${e.message}',
        testedAt: DateTime.now(),
      );
    } on TimeoutException {
      _log.logWarn('[Test] Connection test timed out');
      return ConnectionTestResult(
        success: false,
        error: 'Timed out — proxy may not be routing traffic',
        testedAt: DateTime.now(),
      );
    } catch (e) {
      _log.logError('[Test] $e');
      return ConnectionTestResult(
        success: false,
        error: e.toString(),
        testedAt: DateTime.now(),
      );
    } finally {
      await conn?.close();
    }
  }

  Future<bool> _waitForPort(int port, {required int maxSeconds}) async {
    final deadline = DateTime.now().add(Duration(seconds: maxSeconds));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final s = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 300),
        );
        await s.close();
        return true;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    return false;
  }
}
