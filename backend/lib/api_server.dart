import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
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
    final scanCmd = opts['scan-cmd'] ?? Platform.environment['BPB_SCAN_CMD'];
    final applyCmd = opts['apply-cmd'] ?? Platform.environment['BPB_APPLY_CMD'];
    final applyEnabled =
        opts['apply'] == 'true' ||
        (Platform.environment['BPB_ENABLE_APPLY'] ?? '').toLowerCase() ==
            'true';
    final updateMode =
        opts['update-mode'] ??
        Platform.environment['BPB_UPDATE_MODE'] ??
        'command';
    final scanRetries =
        opts['scan-retries'] ?? Platform.environment['BPB_SCAN_RETRIES'] ?? '3';
    final applyRetries =
        opts['apply-retries'] ??
        Platform.environment['BPB_APPLY_RETRIES'] ??
        '3';
    final minWorkingIps =
        opts['min-working-ips'] ??
        Platform.environment['BPB_MIN_WORKING_IPS'] ??
        '1';
    final initialRetryDelayMs =
        opts['initial-retry-delay-ms'] ??
        Platform.environment['BPB_INITIAL_RETRY_DELAY_MS'] ??
        '1000';
    final maxRetryDelayMs =
        opts['max-retry-delay-ms'] ??
        Platform.environment['BPB_MAX_RETRY_DELAY_MS'] ??
        '60000';
    final hostLabel =
        opts['host-label'] ??
        Platform.environment['BPB_HOST_LABEL'] ??
        'server-host';
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
    final webAuthUsername =
        opts['web-auth-username'] ??
        Platform.environment['BPB_WEB_AUTH_USERNAME'];
    final webAuthPassword =
        opts['web-auth-password'] ??
        Platform.environment['BPB_WEB_AUTH_PASSWORD'];
    final jwtSecret =
        opts['jwt-secret'] ?? Platform.environment['BPB_JWT_SECRET'];
    final jwtTtlSeconds =
        int.tryParse(
          opts['jwt-ttl-seconds'] ??
              Platform.environment['BPB_JWT_TTL_SECONDS'] ??
              '86400',
        ) ??
        86400;

    await _ensureDirectory(stateDir);
    await _ensureDirectory(logDir);
    final webAuth = await _loadOrInitWebAuth(
      stateDir: stateDir,
      username: webAuthUsername,
      password: webAuthPassword,
    );
    JwtService? jwtService;
    if (webAuth != null) {
      if (jwtSecret == null || jwtSecret.trim().isEmpty) {
        stderr.writeln(
          'Web auth credentials are configured, but JWT secret is missing. Set BPB_JWT_SECRET or --jwt-secret.',
        );
        return 1;
      }
      jwtService = JwtService(
        secret: jwtSecret.trim(),
        ttlSeconds: jwtTtlSeconds.clamp(300, 7 * 24 * 3600),
      );
      stdout.writeln(
        'Web JWT auth enabled for user "${webAuth.username}" (ttl: ${jwtService.ttlSeconds}s).',
      );
    }
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
          webAuth: webAuth,
          jwtService: jwtService,
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
    required WebAuthConfig? webAuth,
    required JwtService? jwtService,
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

      if (req.method == 'GET' && path == '/api/auth/status') {
        await _json(req.response, HttpStatus.ok, {
          'enabled': webAuth != null && jwtService != null,
        });
        return;
      }

      if (req.method == 'POST' && path == '/api/auth/login') {
        if (webAuth == null || jwtService == null) {
          await _json(req.response, HttpStatus.notFound, {
            'error': 'web auth not configured',
          });
          return;
        }
        final clientIp = _clientIp(
          req,
          trustForwardedFor: trustForwardedFor,
          trustedProxyIps: trustedProxyIps,
        );
        final body = await utf8.decodeStream(req);
        Map<String, dynamic> payload;
        try {
          payload = jsonDecode(body) as Map<String, dynamic>;
        } catch (_) {
          await _json(req.response, HttpStatus.badRequest, {
            'error': 'invalid json body',
          });
          return;
        }
        final username = (payload['username'] as String? ?? '').trim();
        final password = payload['password'] as String? ?? '';
        if (username.isEmpty || password.isEmpty) {
          await _json(req.response, HttpStatus.badRequest, {
            'error': 'username and password are required',
          });
          return;
        }
        final passwordHash = _hashPassword(
          password: password,
          salt: webAuth.salt,
          iterations: webAuth.iterations,
        );
        final valid =
            username == webAuth.username &&
            passwordHash == webAuth.passwordHash;
        if (!valid) {
          await audit.log(
            event: 'web_login',
            outcome: 'failed',
            method: req.method,
            path: path,
            clientIp: clientIp,
            details: {'username': username},
          );
          await _json(req.response, HttpStatus.unauthorized, {
            'error': 'invalid credentials',
          });
          return;
        }
        final token = jwtService.issueToken(subject: webAuth.username);
        await audit.log(
          event: 'web_login',
          outcome: 'success',
          method: req.method,
          path: path,
          clientIp: clientIp,
          details: {'username': username},
        );
        await _json(req.response, HttpStatus.ok, {
          'token': token,
          'token_type': 'Bearer',
          'expires_in': jwtService.ttlSeconds,
        });
        return;
      }

      if (path.startsWith('/api/') &&
          path != '/api/auth/status' &&
          path != '/api/auth/login') {
        if (webAuth != null && jwtService != null) {
          final authResult = _authorizeRequest(
            req,
            internalToken: token,
            jwtService: jwtService,
          );
          if (!authResult.authorized) {
            await _json(req.response, HttpStatus.unauthorized, {
              'error': 'unauthorized',
            });
            return;
          }
        }
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
        if (!_authorizeRequest(
          req,
          internalToken: token,
          jwtService: jwtService,
        ).authorized) {
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
        if (!_authorizeRequest(
          req,
          internalToken: token,
          jwtService: jwtService,
        ).authorized) {
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
        final status = await _readJsonFile(
          File('${stateDir.path}/status.json'),
        );
        final running = (status?['running'] == true);
        if (running || _activeRunFuture != null) {
          await audit.log(
            event: 'rollback',
            outcome: 'conflict_running',
            method: req.method,
            path: path,
            clientIp: clientIp,
          );
          await _json(req.response, HttpStatus.conflict, {
            'error': 'run already active',
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

        final rollbackFuture = worker.run(rollbackArgs);
        _activeRunFuture = rollbackFuture;
        int code;
        try {
          code = await rollbackFuture;
        } finally {
          if (identical(_activeRunFuture, rollbackFuture)) {
            _activeRunFuture = null;
          }
        }
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

  _AuthorizationResult _authorizeRequest(
    HttpRequest req, {
    required String? internalToken,
    required JwtService? jwtService,
  }) {
    final auth = req.headers.value(HttpHeaders.authorizationHeader)?.trim();
    final bearer = _extractBearerToken(auth);
    if (bearer != null &&
        internalToken != null &&
        internalToken.isNotEmpty &&
        bearer == internalToken) {
      return const _AuthorizationResult(authorized: true, subject: 'internal');
    }

    final header = req.headers.value('x-internal-token');
    if (header != null &&
        internalToken != null &&
        internalToken.isNotEmpty &&
        header == internalToken) {
      return const _AuthorizationResult(authorized: true, subject: 'internal');
    }

    if (bearer != null && jwtService != null) {
      final claims = jwtService.verifyToken(bearer);
      if (claims != null) {
        return _AuthorizationResult(
          authorized: true,
          subject: claims['sub']?.toString(),
        );
      }
    }

    return const _AuthorizationResult(authorized: false);
  }

  String? _extractBearerToken(String? authHeader) {
    if (authHeader == null || authHeader.isEmpty) return null;
    const prefix = 'Bearer ';
    if (!authHeader.startsWith(prefix) || authHeader.length <= prefix.length) {
      return null;
    }
    return authHeader.substring(prefix.length).trim();
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

  Future<WebAuthConfig?> _loadOrInitWebAuth({
    required Directory stateDir,
    required String? username,
    required String? password,
  }) async {
    final file = File('${stateDir.path}/web_auth.json');
    final existing = await _readJsonFile(file);
    if (existing != null) {
      final parsed = WebAuthConfig.fromJson(existing);
      if (parsed != null) return parsed;
      stderr.writeln(
        'Invalid ${file.path}. Expected username/password_hash/salt/iterations.',
      );
      return null;
    }

    final normalizedUser = (username ?? '').trim();
    final rawPassword = password ?? '';
    if (normalizedUser.isEmpty || rawPassword.isEmpty) {
      return null;
    }
    final salt = _randomBase64Url(16);
    final iterations = 120000;
    final passwordHash = _hashPassword(
      password: rawPassword,
      salt: salt,
      iterations: iterations,
    );
    final created = WebAuthConfig(
      username: normalizedUser,
      passwordHash: passwordHash,
      salt: salt,
      iterations: iterations,
    );
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(created.toJson(includeMeta: true)),
    );
    stdout.writeln('Created hashed web auth credentials at ${file.path}.');
    return created;
  }

  String _hashPassword({
    required String password,
    required String salt,
    required int iterations,
  }) {
    final key = utf8.encode(password);
    final saltBytes = utf8.encode(salt);
    final block = <int>[0, 0, 0, 1];
    var u = Hmac(sha256, key).convert([...saltBytes, ...block]).bytes;
    final output = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = Hmac(sha256, key).convert(u).bytes;
      for (var j = 0; j < output.length; j++) {
        output[j] ^= u[j];
      }
    }
    return _base64UrlNoPad(output);
  }

  String _randomBase64Url(int bytes) {
    final rnd = Random.secure();
    final data = List<int>.generate(bytes, (_) => rnd.nextInt(256));
    return _base64UrlNoPad(data);
  }

  String _base64UrlNoPad(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
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
  --web-auth-username <user> bootstrap web login username (saved hashed in state dir)
  --web-auth-password <pass> bootstrap web login password (saved hashed in state dir)
  --jwt-secret <secret>   HMAC secret used for JWT signing/verification
  --jwt-ttl-seconds <n>   JWT lifetime in seconds (default: 86400)

Endpoints:
  GET  /health
  GET  /api/auth/status
  POST /api/auth/login
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

class _AuthorizationResult {
  const _AuthorizationResult({required this.authorized, this.subject});

  final bool authorized;
  final String? subject;
}

class WebAuthConfig {
  const WebAuthConfig({
    required this.username,
    required this.passwordHash,
    required this.salt,
    required this.iterations,
  });

  final String username;
  final String passwordHash;
  final String salt;
  final int iterations;

  static WebAuthConfig? fromJson(Map<String, dynamic> json) {
    final username = (json['username'] as String? ?? '').trim();
    final passwordHash = (json['password_hash'] as String? ?? '').trim();
    final salt = (json['salt'] as String? ?? '').trim();
    final iterations = (json['iterations'] as num?)?.toInt() ?? 0;
    if (username.isEmpty ||
        passwordHash.isEmpty ||
        salt.isEmpty ||
        iterations < 1000) {
      return null;
    }
    return WebAuthConfig(
      username: username,
      passwordHash: passwordHash,
      salt: salt,
      iterations: iterations,
    );
  }

  Map<String, dynamic> toJson({bool includeMeta = false}) {
    return {
      'username': username,
      'password_hash': passwordHash,
      'salt': salt,
      'iterations': iterations,
      if (includeMeta) 'algorithm': 'PBKDF2-HMAC-SHA256',
      if (includeMeta) 'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

class JwtService {
  JwtService({required this.secret, required this.ttlSeconds})
    : _hmac = Hmac(sha256, utf8.encode(secret));

  final String secret;
  final int ttlSeconds;
  final Hmac _hmac;

  String issueToken({required String subject}) {
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final header = _base64UrlNoPad(
      utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})),
    );
    final payload = _base64UrlNoPad(
      utf8.encode(
        jsonEncode({
          'sub': subject,
          'iat': nowSeconds,
          'exp': nowSeconds + ttlSeconds,
          'iss': 'bpb-api',
        }),
      ),
    );
    final signingInput = '$header.$payload';
    final signature = _base64UrlNoPad(
      _hmac.convert(utf8.encode(signingInput)).bytes,
    );
    return '$signingInput.$signature';
  }

  Map<String, dynamic>? verifyToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final signingInput = '${parts[0]}.${parts[1]}';
    final expected = _base64UrlNoPad(
      _hmac.convert(utf8.encode(signingInput)).bytes,
    );
    if (!_constantTimeEquals(expected, parts[2])) return null;

    Map<String, dynamic> payload;
    try {
      final payloadJson = utf8.decode(_base64UrlDecode(parts[1]));
      payload = jsonDecode(payloadJson) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final exp = (payload['exp'] as num?)?.toInt();
    final sub = payload['sub']?.toString();
    if (exp == null || sub == null || sub.isEmpty) return null;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (exp <= nowSeconds) return null;
    return payload;
  }

  String _base64UrlNoPad(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  List<int> _base64UrlDecode(String input) {
    final padded = input.padRight(
      input.length + ((4 - input.length % 4) % 4),
      '=',
    );
    return base64Url.decode(padded);
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var mismatch = 0;
    for (var i = 0; i < a.length; i++) {
      mismatch |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return mismatch == 0;
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
