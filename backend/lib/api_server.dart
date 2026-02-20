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
    final hostLabel = opts['host-label'] ?? 'server-host';
    final token =
        opts['internal-token'] ?? Platform.environment['BPB_INTERNAL_TOKEN'];
    final retentionDays =
        int.tryParse(opts['retention-days'] ?? '$_defaultRetentionDays') ??
        _defaultRetentionDays;

    await _ensureDirectory(stateDir);
    await _ensureDirectory(logDir);
    final worker = WorkerApp();

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
          hostLabel: hostLabel,
          token: token,
          retentionDays: retentionDays,
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
    required String hostLabel,
    required String? token,
    required int retentionDays,
  }) async {
    try {
      _addCors(req.response);
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
        final items = await _readRunsIndex(stateDir);
        final total = items.length;
        final start = (page - 1) * pageSize;
        final end = (start + pageSize).clamp(0, total);
        final sliced = (start >= 0 && start < total)
            ? items.sublist(start, end)
            : <Map<String, dynamic>>[];
        await _json(req.response, HttpStatus.ok, {
          'page': page,
          'page_size': pageSize,
          'total': total,
          'items': sliced,
        });
        return;
      }

      if (req.method == 'GET' && path.startsWith('/api/results/')) {
        final runId = path.substring('/api/results/'.length);
        if (runId.isEmpty || runId == 'latest') {
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

      if (req.method == 'POST' && path == '/internal/scheduler/run') {
        if (!_isAuthorized(req, token)) {
          await _json(req.response, HttpStatus.unauthorized, {
            'error': 'unauthorized',
          });
          return;
        }
        final status = await _readJsonFile(
          File('${stateDir.path}/status.json'),
        );
        final running = (status?['running'] == true);
        if (running) {
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

        unawaited(worker.run(workerArgs));
        await _json(req.response, HttpStatus.accepted, {
          'accepted': true,
          'trigger': trigger,
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

  Future<List<Map<String, dynamic>>> _readRunsIndex(Directory stateDir) async {
    final f = File('${stateDir.path}/runs_index.jsonl');
    if (!await f.exists()) return [];
    final lines = await f.readAsLines();
    final items = <Map<String, dynamic>>[];
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) continue;
      try {
        items.add(jsonDecode(t) as Map<String, dynamic>);
      } catch (_) {}
    }
    return items.reversed.toList();
  }

  Future<Map<String, dynamic>?> _readJsonFile(File file) async {
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    return jsonDecode(content) as Map<String, dynamic>;
  }

  Future<List<String>> _readRecentLogs(Directory logDir, int maxLines) async {
    if (!await logDir.exists()) return const [];
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

    final all = <String>[];
    for (final file in files) {
      final lines = await file.readAsLines();
      for (final line in lines.reversed) {
        all.add(line);
        if (all.length >= maxLines) {
          return all.reversed.toList();
        }
      }
    }
    return all.reversed.toList();
  }

  bool _isAuthorized(HttpRequest req, String? token) {
    if (token == null || token.isEmpty) return false;
    final auth = req.headers.value(HttpHeaders.authorizationHeader);
    if (auth != null && auth.trim() == 'Bearer $token') return true;
    final header = req.headers.value('x-internal-token');
    return header != null && header == token;
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

  void _addCors(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
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
  --scan-cmd <cmd>          scan command used by POST /internal/scheduler/run
  --apply                   enable apply step after scan
  --apply-cmd <cmd>         apply command
  --internal-token <token>  required token for POST /internal/scheduler/run

Endpoints:
  GET  /health
  GET  /api/status
  GET  /api/results
  GET  /api/results/latest
  GET  /api/results/{run_id}
  GET  /api/logs/latest?lines=200
  POST /internal/scheduler/run?trigger=api
''');
  }
}
