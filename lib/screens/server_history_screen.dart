import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../services/server_backend_service.dart';
import '../services/storage_service.dart';
import '../widgets/experimental_server_banner.dart';
import '../widgets/logs_action_button.dart';

class ServerHistoryScreen extends StatefulWidget {
  const ServerHistoryScreen({super.key});

  @override
  State<ServerHistoryScreen> createState() => _ServerHistoryScreenState();
}

class _ServerHistoryScreenState extends State<ServerHistoryScreen> {
  final StorageService _storage = StorageService.instance;
  final ServerBackendService _api = ServerBackendService.instance;

  bool _loading = true;
  bool _triggering = false;
  String? _error;
  String _baseUrl = '';
  String _token = '';
  Map<String, dynamic>? _status;
  List<Map<String, dynamic>> _runs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final baseUrl = (await _storage.getServerBackendBaseUrl())?.trim() ?? '';
    final token = kIsWeb
        ? (await _storage.getServerBackendJwt())?.trim() ?? ''
        : (await _storage.getServerBackendToken())?.trim() ?? '';
    if (baseUrl.isEmpty) {
      setState(() {
        _loading = false;
        _baseUrl = '';
        _token = token;
        _error = 'Server backend URL not configured in Settings.';
      });
      return;
    }
    if (kIsWeb && token.isEmpty) {
      setState(() {
        _loading = false;
        _baseUrl = baseUrl;
        _token = token;
        _error = 'Web login required. Open Settings and sign in.';
      });
      return;
    }

    try {
      final status = await _api.getStatus(baseUrl: baseUrl, authToken: token);
      final runs = await _api.getResults(
        baseUrl: baseUrl,
        page: 1,
        pageSize: 50,
        authToken: token,
      );
      if (!mounted) return;
      setState(() {
        _baseUrl = baseUrl;
        _token = token;
        _status = status;
        _runs = runs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _baseUrl = baseUrl;
        _token = token;
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _triggerNow() async {
    if (_baseUrl.isEmpty || _token.isEmpty) {
      _show(
        kIsWeb
            ? 'Set server URL and sign in from Settings first.'
            : 'Set server URL + token in Settings first.',
        isError: true,
      );
      return;
    }

    setState(() => _triggering = true);
    try {
      await _api.triggerRun(baseUrl: _baseUrl, token: _token, trigger: 'api');
      if (!mounted) return;
      _show('Run accepted by backend.');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _load();
    } catch (e) {
      _show('Trigger failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _triggering = false);
    }
  }

  Future<void> _rollbackLastApply() async {
    if (_baseUrl.isEmpty || _token.isEmpty) {
      _show(
        kIsWeb
            ? 'Set server URL and sign in from Settings first.'
            : 'Set server URL + token in Settings first.',
        isError: true,
      );
      return;
    }
    final shouldRollback = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rollback Last Apply'),
        content: const Text(
          'This will re-apply the previous snapshot of IPs on the server. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rollback'),
          ),
        ],
      ),
    );
    if (shouldRollback != true) return;

    setState(() => _triggering = true);
    try {
      await _api.rollback(baseUrl: _baseUrl, token: _token);
      if (!mounted) return;
      _show('Rollback applied successfully.');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _load();
    } catch (e) {
      _show('Rollback failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _triggering = false);
    }
  }

  void _show(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Run History (WIP)'),
        actions: [
          const LogsActionButton(currentRoute: '/server-history'),
          IconButton(
            icon: const Icon(Icons.article),
            tooltip: 'Server Logs',
            onPressed: () => Navigator.pushNamed(context, '/server-logs'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const ExperimentalServerBanner(),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Backend Status',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text('URL: $_baseUrl'),
                          Text(
                            'Running: ${_status?['running'] == true ? "Yes" : "No"}',
                          ),
                          Text('Last run: ${_status?['last_run_id'] ?? "-"}'),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _triggering ? null : _triggerNow,
                            icon: _triggering
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow),
                            label: Text(
                              _triggering
                                  ? 'Triggering (WIP)...'
                                  : 'Trigger Run Now (WIP)',
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _triggering ? null : _rollbackLastApply,
                            icon: const Icon(Icons.restore),
                            label: const Text('Rollback Last Apply (WIP)'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Recent Runs',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (_runs.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No runs found yet.'),
                      ),
                    )
                  else
                    ..._runs.map(
                      (run) => Card(
                        child: ListTile(
                          title: Text(run['run_id']?.toString() ?? '-'),
                          subtitle: Text(
                            'Status: ${run['status'] ?? '-'} | '
                            'Working: ${run['working_count'] ?? 0} | '
                            'Trigger: ${run['trigger'] ?? '-'}',
                          ),
                          trailing: Text(run['finished_at']?.toString() ?? '-'),
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/server-run-detail',
                            arguments: {'run_id': run['run_id']?.toString()},
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
