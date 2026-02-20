import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'worker_app.dart';

class ApiServerApp {
  static const _defaultStateDir = '/var/lib/bpb-automation';
  static const _defaultLogDir = '/var/log/bpb-automation';
  static const _defaultRetentionDays = 7;
  static const _defaultHost = '127.0.0.1';
  static const _defaultPort = 8787;
  Future<int>? _activeRunFuture;

  Future<int> run(List<String> args) async {
    if (args.contains('--help') || args.contains('-h')) {
      _printUsage();
      return 0;
    }

    final opts = _parseOptions(args);
    final host = opts['host'] ?? _defaultHost;
    final port = int.tryParse(opts['port'] ?? '$_defaultPort') ?? _defaultPort;
    final stateDir = Directory(opts['state-dir'] ?? _defaultStateDir);
    final logDir = Directory(opts['log-dir'] ?? _defaultLogDir);
    final scanCmd = opts['scan-cmd'];
    final applyCmd = opts['apply-cmd'];
    final applyEnabled = opts['apply'] == 'true';
    final updateMode = opts['update-mode'] ?? 'command';
    final scanRetries = opts['scan-retries'] ?? '3';
    final applyRetries = opts['apply-retries'] ?? '3';
    final minWorkingIps = opts['min-working-ips'] ?? '1';
    final initialRetryDelayMs = opts['initial-retry-delay-ms'] ?? '1000';
    final maxRetryDelayMs = opts['max-retry-delay-ms'] ?? '60000';
    final hostLabel = opts['host-label'] ?? 'server-host';
    final token =
        opts['internal-token'] ?? Platform.environment['BPB_INTERNAL_TOKEN'];
    final retentionDays =
        int.tryParse(opts['retention-days'] ?? '$_defaultRetentionDays') ??
        _defaultRetentionDays;
    final allowedTriggerIps = _parseIpCsv(
      opts['allowed-trigger-ips'] ??
          Platform.environment['BPB_ALLOWED_TRIGGER_IPS'] ??
          '127.0.0.1,::1',
    );
    final trustForwardedFor =
        (opts['trust-forwarded-for'] ??
                Platform.environment['BPB_TRUST_FORWARDED_FOR'] ??
                'false')
            .toLowerCase() ==
        'true';
    final trustedProxyIps = _parseIpCsv(
      opts['trusted-proxy-ips'] ??
          Platform.environment['BPB_TRUSTED_PROXY_IPS'] ??
          '127.0.0.1,::1',
    );
    final corsAllowedOrigins = _parseCsv(
      opts['cors-allowed-origins'] ??
          Platform.environment['BPB_CORS_ALLOWED_ORIGINS'] ??
          '',
    );

    await _ensureDirectory(stateDir);
    await _ensureDirectory(logDir);
    final worker = WorkerApp();
    final audit = AuditLogger(stateDir: stateDir);

    final server = await HttpServer.bind(host, port);
    stdout.writeln('API server listening on http://$host:$port');

    await for (final req in server) {
      unawaited(
        _handle(
          req,
          stateDir: stateDir,
          logDir: logDir,
          worker: worker,
          scanCmd: scanCmd,
          applyCmd: applyCmd,
          applyEnabled: applyEnabled,
          updateMode: updateMode,
          scanRetries: scanRetries,
          applyRetries: applyRetries,
          minWorkingIps: minWorkingIps,
          initialRetryDelayMs: initialRetryDelayMs,
          maxRetryDelayMs: maxRetryDelayMs,
          hostLabel: hostLabel,
          token: token,
          retentionDays: retentionDays,
          audit: audit,
          allowedTriggerIps: allowedTriggerIps,
          trustForwardedFor: trustForwardedFor,
          trustedProxyIps: trustedProxyIps,
          corsAllowedOrigins: corsAllowedOrigins,
        ),
      );
    }
    return 0;
  }

  Future<void> _handle(
    HttpRequest req, {
    required Directory stateDir,
    required Directory logDir,
    required WorkerApp worker,
    required String? scanCmd,
    required String? applyCmd,
    required bool applyEnabled,
    required String updateMode,
    required String scanRetries,
    required String applyRetries,
    required String minWorkingIps,
    required String initialRetryDelayMs,
    required String maxRetryDelayMs,
    required String hostLabel,
    required String? token,
    required int retentionDays,
    required AuditLogger audit,
    required Set<String> allowedTriggerIps,
    required bool trustForwardedFor,
    required Set<String> trustedProxyIps,
    required Set<String> corsAllowedOrigins,
  }) async {
    try {
      _addCors(req, req.response, corsAllowedOrigins: corsAllowedOrigins);
      if (req.method == 'OPTIONS') {
        req.response.statusCode = HttpStatus.noContent;
        await req.response.close();
        return;
      }

      final path = req.uri.path;
      if (req.method == 'GET' && path == '/health') {
        await _json(req.response, HttpStatus.ok, {'ok': true});
        return;
      }

      if (req.method == 'GET' && path == '/api/status') {
        final status =
            await _readJsonFile(File('${stateDir.path}/status.json')) ??
            {'running': false};
        await _json(req.response, HttpStatus.ok, status);
        return;
      }

      if (req.method == 'GET' && path == '/api/results/latest') {
        final latest = await _readJsonFile(
          File('${stateDir.path}/latest.json'),
        );
        if (latest == null) {
          await _json(req.response, HttpStatus.notFound, {
            'error': 'no results',
          });
          return;
        }
        await _json(req.response, HttpStatus.ok, latest);
        return;
      }

      if (req.method == 'GET' && path == '/api/results') {
        final page = int.tryParse(req.uri.queryParameters['page'] ?? '1') ?? 1;
        final pageSize =
            int.tryParse(req.uri.queryParameters['page_size'] ?? '20') ?? 20;
        final payload = await _readRunsIndexPage(
          stateDir,
          page: page,
          pageSize: pageSize,
        );
        await _json(req.response, HttpStatus.ok, payload);
        return;
      }

      if (req.method == 'GET' && path.startsWith('/api/results/')) {
        final runId = path.substring('/api/results/'.length);
        if (runId.isEmpty || runId == 'latest' || !_isSafeRunId(runId)) {
          await _json(req.response, HttpStatus.badRequest, {
            'error': 'invalid run id',
          });
          return;
        }
        final run = await _readJsonFile(
          File('${stateDir.path}/runs/$runId.json'),
        );
        if (run == null) {
          await _json(req.response, HttpStatus.notFound, {
            'error': 'run not found',
          });
          return;
        }
        await _json(req.response, HttpStatus.ok, run);
        return;
      }

      if (req.method == 'GET' && path == '/api/logs/latest') {
        final lines =
            int.tryParse(req.uri.queryParameters['lines'] ?? '200') ?? 200;
        final logs = await _readRecentLogs(logDir, lines.clamp(1, 2000));
        await _json(req.response, HttpStatus.ok, {'lines': logs});
        return;
      }

      if (req.method == 'GET' && path == '/api/logs') {
        final page = int.tryParse(req.uri.queryParameters['page'] ?? '1') ?? 1;
        final pageSize =
            int.tryParse(req.uri.queryParameters['page_size'] ?? '200') ?? 200;
        final payload = await _readPaginatedLogs(
          logDir: logDir,
          page: page,
          pageSize: pageSize.clamp(1, 1000),
        );
        await _json(req.response, HttpStatus.ok, payload);
        return;
      }

      if (req.method == 'GET' && path == '/api/maintenance/log-retention') {
        final status =
            await _readJsonFile(File('${stateDir.path}/cleanup_status.json')) ??
            {'error': 'cleanup status not available yet', 'compliant': false};
        await _json(req.response, HttpStatus.ok, status);
        return;
      }

      if (req.method == 'POST' && path == '/internal/scheduler/run') {
        final clientIp = _clientIp(
          req,
          trustForwardedFor: trustForwardedFor,
          trustedProxyIps: trustedProxyIps,
        );
        if (!_isSourceAllowed(
          clientIp: clientIp,
          allowedIps: allowedTriggerIps,
        )) {
          await audit.log(
            event: 'trigger_run',
            outcome: 'denied_ip',
            method: req.method,
            path: path,
            clientIp: clientIp,
            details: {'trigger': req.uri.queryParameters['trigger'] ?? 'api'},
          );
          await _json(req.response, HttpStatus.forbidden, {
            'error': 'forbidden source ip',
          });
          return;
        }
        if (!_isAuthorized(req, token)) {
          await audit.log(
            event: 'trigger_run',
            outcome: 'unauthorized',
            method: req.method,
            path: path,
            clientIp: clientIp,
            details: {'trigger': req.uri.queryParameters['trigger'] ?? 'api'},
          );
          await _json(req.response, HttpStatus.unauthorized, {
            'error': 'unauthorized',
          });
          return;
        }
        final status = await _readJsonFile(
          File('${stateDir.path}/status.json'),
        );
        final running = (status?['running'] == true);
        if (running || _activeRunFuture != null) {
          await audit.log(
            event: 'trigger_run',
            outcome: 'conflict_running',
            method: req.method,
            path: path,
            clientIp: clientIp,
            details: {'trigger': req.uri.queryParameters['trigger'] ?? 'api'},
          );
          await _json(req.response, HttpStatus.conflict, {
            'error': 'run already active',
          });
          return;
        }

        final trigger = req.uri.queryParameters['trigger'] ?? 'api';
        final workerArgs = <String>[
          'run-once',
          '--state-dir',
          stateDir.path,
          '--log-dir',
          logDir.path,
          '--retention-days',
          '$retentionDays',
          '--trigger',
          trigger,
          '--host-label',
          hostLabel,
          '--update-mode',
          updateMode,
          '--scan-retries',
          scanRetries,
          '--apply-retries',
          applyRetries,
          '--min-working-ips',
          minWorkingIps,
          '--initial-retry-delay-ms',
          initialRetryDelayMs,
          '--max-retry-delay-ms',
          maxRetryDelayMs,
          '--requested-by',
          'api',
          '--request-ip',
          clientIp,
        ];
        if (scanCmd != null && scanCmd.trim().isNotEmpty) {
          workerArgs.addAll(['--scan-cmd', scanCmd]);
        }
        if (applyEnabled) {
          workerArgs.add('--apply');
          if (applyCmd != null && applyCmd.trim().isNotEmpty) {
            workerArgs.addAll(['--apply-cmd', applyCmd]);
          }
        }
        final runFuture = worker.run(workerArgs);
        _activeRunFuture = runFuture;
        unawaited(
          runFuture.whenComplete(() {
            if (identical(_activeRunFuture, runFuture)) {
              _activeRunFuture = null;
            }
          }),
        );
        await audit.log(
          event: 'trigger_run',
          outcome: 'accepted',
          method: req.method,
          path: path,
          clientIp: clientIp,
          details: {'trigger': trigger},
        );
        await _json(req.response, HttpStatus.accepted, {
          'accepted': true,
          'trigger': trigger,
        });
        return;
      }

      if (req.method == 'POST' && path == '/internal/scheduler/rollback') {
        final clientIp = _clientIp(
          req,
          trustForwardedFor: trustForwardedFor,
          trustedProxyIps: trustedProxyIps,
        );
        if (!_isSourceAllowed(
          clientIp: clientIp,
          allowedIps: allowedTriggerIps,
        )) {
          await audit.log(
            event: 'rollback',
            outcome: 'denied_ip',
            method: req.method,
            path: path,
            clientIp: clientIp,
          );
          await _json(req.response, HttpStatus.forbidden, {
            'error': 'forbidden source ip',
          });
          return;
        }
        if (!_isAuthorized(req, token)) {
          await audit.log(
            event: 'rollback',
            outcome: 'unauthorized',
            method: req.method,
            path: path,
            clientIp: clientIp,
          );
          await _json(req.response, HttpStatus.unauthorized, {
            'error': 'unauthorized',
          });
          return;
        }

        final rollbackArgs = <String>[
          'rollback',
          '--state-dir',
          stateDir.path,
          '--log-dir',
          logDir.path,
          '--update-mode',
          updateMode,
          '--apply-retries',
          applyRetries,
          '--initial-retry-delay-ms',
          initialRetryDelayMs,
          '--max-retry-delay-ms',
          maxRetryDelayMs,
          '--requested-by',
          'api',
          '--request-ip',
          clientIp,
        ];
        if (applyCmd != null && applyCmd.trim().isNotEmpty) {
          rollbackArgs.addAll(['--apply-cmd', applyCmd]);
        }

        final code = await worker.run(rollbackArgs);
        if (code == 0) {
          await audit.log(
            event: 'rollback',
            outcome: 'success',
            method: req.method,
            path: path,
            clientIp: clientIp,
          );
          await _json(req.response, HttpStatus.ok, {'rolled_back': true});
          return;
        }
        await audit.log(
          event: 'rollback',
          outcome: 'failed',
          method: req.method,
          path: path,
          clientIp: clientIp,
        );
        await _json(req.response, HttpStatus.badRequest, {
          'rolled_back': false,
          'error': 'rollback failed',
        });
        return;
      }

      await _json(req.response, HttpStatus.notFound, {'error': 'not found'});
    } catch (e) {
      await _json(req.response, HttpStatus.internalServerError, {
        'error': '$e',
      });
    }
  }

  Future<Map<String, dynamic>> _readRunsIndexPage(
    Directory stateDir, {
    required int page,
    required int pageSize,
  }) async {
    final f = File('${stateDir.path}/runs_index.jsonl');
    if (!await f.exists()) {
      return {
        'page': page,
        'page_size': pageSize,
        'total': 0,
        'items': const [],
      };
    }
    final lines = await f.readAsLines();
    final nonEmpty = lines.where((e) => e.trim().isNotEmpty).toList();
    final total = nonEmpty.length;
    final start = (page - 1) * pageSize;
    if (start < 0 || start >= total) {
      return {
        'page': page,
        'page_size': pageSize,
        'total': total,
        'items': const <Map<String, dynamic>>[],
      };
    }

    final out = <Map<String, dynamic>>[];
    var seen = 0;
    for (var i = nonEmpty.length - 1; i >= 0; i--) {
      if (seen < start) {
        seen++;
        continue;
      }
      if (out.length >= pageSize) break;
      try {
        out.add(jsonDecode(nonEmpty[i]) as Map<String, dynamic>);
      } catch (_) {}
      seen++;
    }
    return {'page': page, 'page_size': pageSize, 'total': total, 'items': out};
  }

  Future<Map<String, dynamic>?> _readJsonFile(File file) async {
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    return jsonDecode(content) as Map<String, dynamic>;
  }

  Future<List<String>> _readRecentLogs(Directory logDir, int maxLines) async {
    final payload = await _readPaginatedLogs(
      logDir: logDir,
      page: 1,
      pageSize: maxLines,
    );
    final items = payload['items'] as List<dynamic>? ?? const [];
    return items.map((e) => e.toString()).toList();
  }

  Future<Map<String, dynamic>> _readPaginatedLogs({
    required Directory logDir,
    required int page,
    required int pageSize,
  }) async {
    if (!await logDir.exists()) {
      return {
        'page': page,
        'page_size': pageSize,
        'total': 0,
        'items': const [],
      };
    }
    final files = await logDir
        .list()
        .where((e) => e is File)
        .cast<File>()
        .where((f) {
          final name = f.uri.pathSegments.last;
          return name.startsWith('app-') && name.endsWith('.log');
        })
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));

    final start = (page - 1) * pageSize;
    final endExclusive = start + pageSize;
    var total = 0;
    final paged = <String>[];
    for (final file in files) {
      final lines = await file.readAsLines();
      for (final line in lines.reversed) {
        if (total >= start && total < endExclusive) {
          paged.add(_redactLogLine(line));
        }
        total++;
      }
    }
    return {
      'page': page,
      'page_size': pageSize,
      'total': total,
      // keep newest first for log browsing UX
      'items': paged,
    };
  }

  String _redactLogLine(String line) {
    var out = line;
    out = _replaceWithPrefix(
      out,
      RegExp(
        r'(authorization:\s*bearer\s+)[A-Za-z0-9\._\-]+',
        caseSensitive: false,
      ),
    );
    out = _replaceWithPrefix(
      out,
      RegExp(
        r'(api[_\- ]?token[=:]\s*)[A-Za-z0-9\._\-]+',
        caseSensitive: false,
      ),
    );
    out = _replaceWithPrefix(
      out,
      RegExp(
        r'((?:x[_\-])?auth[_\- ]?token\s*:\s*)[^\s]+',
        caseSensitive: false,
      ),
    );
    out = _replaceWithPrefix(
      out,
      RegExp(r'((?:cf[_\-])?api[_\- ]?key\s*:\s*)[^\s]+', caseSensitive: false),
    );
    out = _replaceWithPrefix(
      out,
      RegExp(r'(password[=:]\s*)[^\s]+', caseSensitive: false),
    );
    out = _replaceWithPrefix(
      out,
      RegExp(r'(account[_\- ]?id[=:]\s*)[A-Za-z0-9\-_]+', caseSensitive: false),
    );
    out = _replaceWithPrefix(
      out,
      RegExp(
        r'(kv[_\- ]?namespace[_\- ]?id[=:]\s*)[A-Za-z0-9\-_]+',
        caseSensitive: false,
      ),
    );
    return out;
  }

  String _replaceWithPrefix(String input, RegExp pattern) {
    return input.replaceAllMapped(pattern, (m) {
      return '${m.group(1)}[REDACTED]';
    });
  }

  bool _isAuthorized(HttpRequest req, String? token) {
    if (token == null || token.isEmpty) return false;
    final auth = req.headers.value(HttpHeaders.authorizationHeader);
    if (auth != null && auth.trim() == 'Bearer $token') return true;
    final header = req.headers.value('x-internal-token');
    return header != null && header == token;
  }

  String _clientIp(
    HttpRequest req, {
    required bool trustForwardedFor,
    required Set<String> trustedProxyIps,
  }) {
    final remoteRaw = req.connectionInfo?.remoteAddress.address ?? '-';
    final remoteIp = _normalizeIp(remoteRaw);
    if (trustForwardedFor && trustedProxyIps.contains(remoteIp)) {
      final forwardedFor = req.headers.value('x-forwarded-for');
      if (forwardedFor != null && forwardedFor.trim().isNotEmpty) {
        for (final candidate in forwardedFor.split(',')) {
          final normalized = _normalizeIp(candidate.trim());
          if (normalized != '-') {
            return normalized;
          }
        }
      }
    }
    return remoteIp;
  }

  bool _isSourceAllowed({
    required String clientIp,
    required Set<String> allowedIps,
  }) {
    if (allowedIps.isEmpty) return false;
    return allowedIps.contains(clientIp);
  }

  Future<void> _json(
    HttpResponse response,
    int statusCode,
    Map<String, dynamic> body,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  bool _isSafeRunId(String runId) {
    return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(runId);
  }

  String _normalizeIp(String value) {
    final parsed = InternetAddress.tryParse(value.trim());
    return parsed?.address ?? '-';
  }

  void _addCors(
    HttpRequest req,
    HttpResponse response, {
    required Set<String> corsAllowedOrigins,
  }) {
    final origin = req.headers.value('origin');
    if (origin != null && corsAllowedOrigins.contains(origin)) {
      response.headers.set('Access-Control-Allow-Origin', origin);
      response.headers.set('Vary', 'Origin');
    }
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization, X-Internal-Token',
    );
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  }

  Future<void> _ensureDirectory(Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  Map<String, String> _parseOptions(List<String> args) {
    final out = <String, String>{};
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (!arg.startsWith('--')) continue;
      final key = arg.substring(2);
      if (key.contains('=')) {
        final parts = key.split('=');
        out[parts[0]] = parts.sublist(1).join('=');
        continue;
      }
      final next = (i + 1 < args.length) ? args[i + 1] : null;
      if (next == null || next.startsWith('--')) {
        out[key] = 'true';
      } else {
        out[key] = next;
        i++;
      }
    }
    return out;
  }

  Set<String> _parseCsv(String input) {
    return input
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  Set<String> _parseIpCsv(String input) {
    return input
        .split(',')
        .map((e) => _normalizeIp(e))
        .where((e) => e != '-')
        .toSet();
  }

  void _printUsage() {
    stdout.writeln('''
BPB autoscan API server

Usage:
  dart run bin/bpb_api.dart [options]

Options:
  --host <addr>             bind host (default: $_defaultHost)
  --port <n>                bind port (default: $_defaultPort)
  --state-dir <path>        state dir (default: $_defaultStateDir)
  --log-dir <path>          log dir (default: $_defaultLogDir)
  --retention-days <n>      log retention days (default: $_defaultRetentionDays)
  --host-label <name>       host/device label for run history
  --update-mode <name>      update mode label passed to run metadata
  --scan-retries <n>        scan retries with backoff (default: 3)
  --apply-retries <n>       apply retries with backoff (default: 3)
  --min-working-ips <n>     minimum working IPs before apply (default: 1)
  --initial-retry-delay-ms  initial retry delay in milliseconds
  --max-retry-delay-ms <n>  retry backoff cap in milliseconds (default: 60000)
  --scan-cmd <cmd>          scan command used by POST /internal/scheduler/run
  --apply                   enable apply step after scan
  --apply-cmd <cmd>         apply command
  --internal-token <token>  required token for POST /internal/scheduler/run
  --allowed-trigger-ips <csv> allowed source IPs for /internal endpoints (default: 127.0.0.1,::1)
  --trust-forwarded-for    trust x-forwarded-for for source IP checks
  --trusted-proxy-ips <csv> proxies allowed to supply x-forwarded-for (default: 127.0.0.1,::1)
  --cors-allowed-origins <csv> allowed browser origins for CORS reads (default: disabled)

Endpoints:
  GET  /health
  GET  /api/status
  GET  /api/results
  GET  /api/results/latest
  GET  /api/results/{run_id}
  GET  /api/maintenance/log-retention
  GET  /api/logs?page=1&page_size=200
  GET  /api/logs/latest?lines=200
  POST /internal/scheduler/run?trigger=api
  POST /internal/scheduler/rollback
''');
  }
}

class AuditLogger {
  AuditLogger({required this.stateDir});

  final Directory stateDir;

  Future<void> log({
    required String event,
    required String outcome,
    required String method,
    required String path,
    required String clientIp,
    Map<String, dynamic>? details,
  }) async {
    final file = File('${stateDir.path}/audit.jsonl');
    final payload = {
      'ts': DateTime.now().toUtc().toIso8601String(),
      'event': event,
      'outcome': outcome,
      'method': method,
      'path': path,
      'client_ip': clientIp,
      'details': details ?? const <String, dynamic>{},
    };
    await file.writeAsString('${jsonEncode(payload)}\n', mode: FileMode.append);
  }
}
