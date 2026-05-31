import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/xray_traffic_stats.dart';
import 'log_service.dart';
import 'xray_service.dart';

class XrayStatsService {
  static final XrayStatsService instance = XrayStatsService._();
  XrayStatsService._();

  /// Internal gRPC API port xray listens on for stats queries.
  /// Must match the port passed to XrayConfig.withStatsMonitoring().
  static const int kApiPort = 10811;

  final LogService _log = LogService.instance;
  final StreamController<XrayTrafficStats> _controller =
      StreamController.broadcast();
  Timer? _pollTimer;
  XrayTrafficStats? _prev;
  bool _loggedUnavailable = false;
  bool _loggedFormat = false;

  Stream<XrayTrafficStats> get statsStream => _controller.stream;
  XrayTrafficStats? get lastStats => _prev;

  void start() {
    _pollTimer?.cancel();
    _prev = null;
    _loggedUnavailable = false;
    _loggedFormat = false;
    // Wait one cycle before first poll so xray is fully ready.
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _prev = null;
  }

  Future<void> _poll() async {
    final result = await _query();
    if (result == null) return;

    final now = DateTime.now();
    double? upBps, downBps;

    final prev = _prev;
    if (prev != null) {
      final dtSec =
          now.difference(prev.measuredAt).inMilliseconds / 1000.0;
      if (dtSec > 0) {
        upBps = ((result.uplink - prev.uplinkBytes) / dtSec).clamp(0, double.infinity);
        downBps = ((result.downlink - prev.downlinkBytes) / dtSec).clamp(0, double.infinity);
      }
    }

    final stats = XrayTrafficStats(
      uplinkBytes: result.uplink,
      downlinkBytes: result.downlink,
      uplinkBytesPerSec: upBps,
      downlinkBytesPerSec: downBps,
      measuredAt: now,
    );
    _prev = stats;
    if (!_controller.isClosed) _controller.add(stats);
  }

  Future<({int uplink, int downlink})?> _query() async {
    final binary = XrayService.instance.binaryPath;
    if (binary == null) return null;

    try {
      final result = await Process.run(binary, [
        'api',
        'statsquery',
        '--server=127.0.0.1:$kApiPort',
      ]).timeout(const Duration(seconds: 3));

      if (result.exitCode != 0) {
        if (!_loggedUnavailable) {
          _log.logWarn(
            '[Stats] xray stats API unavailable (exit ${result.exitCode}): '
            '${(result.stderr as String).trim()}',
          );
          _loggedUnavailable = true;
        }
        return null;
      }

      final stdout = result.stdout as String;
      if (!_loggedFormat) {
        _loggedFormat = true;
        _log.logInfo('[Stats] first response: ${stdout.length} chars');
        if (stdout.length < 500) _log.logInfo('[Stats] full: $stdout');
      }

      return _parse(stdout);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  ({int uplink, int downlink})? _parse(String output) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) return null;

    // --- Attempt 1: parse entire output as a single JSON document ----------
    // xray v26 outputs multi-line JSON like:
    //   {"stat": [{"name":"inbound>>>...uplink","value":"0"}, ...]}
    // The >>> separator is Unicode-escaped as >>>.
    try {
      final doc = jsonDecode(trimmed);
      if (doc is Map<String, dynamic>) {
        final statList = doc['stat'] as List?;
        if (statList != null) {
          final r = _extractFromStatList(statList);
          if (r != null) return r;
        }
        // Single-stat object: {"name":"...","value":"..."}
        return _statFromObject(doc);
      }
    } catch (_) {}

    // --- Attempt 2: extract the outermost {...} if there's leading noise ----
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final doc = jsonDecode(trimmed.substring(start, end + 1));
        if (doc is Map<String, dynamic>) {
          final statList = doc['stat'] as List?;
          if (statList != null) {
            final r = _extractFromStatList(statList);
            if (r != null) return r;
          }
          return _statFromObject(doc);
        }
      } catch (_) {}
    }

    // --- Attempt 3: concatenated JSON objects, one per line -----------------
    int uplink = 0, downlink = 0;
    bool found = false;
    for (final raw in trimmed.split('\n')) {
      final line = raw.trim();
      if (!line.startsWith('{') || !line.endsWith('}')) continue;
      try {
        final obj = jsonDecode(line) as Map<String, dynamic>;
        final r = _statFromObject(obj);
        if (r != null) {
          if (r.uplink != 0) uplink = r.uplink;
          if (r.downlink != 0) downlink = r.downlink;
          found = true;
        }
      } catch (_) {}
    }
    if (found) return (uplink: uplink, downlink: downlink);

    // --- Attempt 4: protobuf text format ------------------------------------
    //   Name: "inbound>>>socks-in>>>traffic>>>downlink"
    //   Value: 12345
    for (final raw in trimmed.split('\n')) {
      final line = raw.trim();
      final lc = line.toLowerCase();
      if (lc.contains('uplink')) {
        final m = RegExp(r'[Vv]alue[:\s"]+(\d+)').firstMatch(line);
        if (m != null) {
          uplink = int.tryParse(m.group(1)!) ?? 0;
          found = true;
        }
      } else if (lc.contains('downlink')) {
        final m = RegExp(r'[Vv]alue[:\s"]+(\d+)').firstMatch(line);
        if (m != null) {
          downlink = int.tryParse(m.group(1)!) ?? 0;
          found = true;
        }
      }
    }

    return found ? (uplink: uplink, downlink: downlink) : null;
  }

  ({int uplink, int downlink})? _extractFromStatList(List<dynamic> list) {
    int uplink = 0, downlink = 0;
    bool found = false;
    for (final item in list) {
      final r = _statFromObject(item as Map<String, dynamic>);
      if (r != null) {
        uplink += r.uplink;
        downlink += r.downlink;
        found = true;
      }
    }
    return found ? (uplink: uplink, downlink: downlink) : null;
  }

  ({int uplink, int downlink})? _statFromObject(Map<String, dynamic> obj) {
    final name = obj['name']?.toString() ?? '';
    if (name.isEmpty) return null;
    final value = int.tryParse(obj['value']?.toString() ?? '0') ?? 0;
    if (name.contains('uplink')) return (uplink: value, downlink: 0);
    if (name.contains('downlink')) return (uplink: 0, downlink: value);
    return null;
  }
}
