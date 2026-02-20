import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../services/server_backend_service.dart';
import '../services/storage_service.dart';
import '../widgets/logs_action_button.dart';

class ServerRunDetailScreen extends StatefulWidget {
  const ServerRunDetailScreen({super.key});

  @override
  State<ServerRunDetailScreen> createState() => _ServerRunDetailScreenState();
}

class _ServerRunDetailScreenState extends State<ServerRunDetailScreen> {
  final StorageService _storage = StorageService.instance;
  final ServerBackendService _api = ServerBackendService.instance;

  bool _loading = true;
  bool _loadInFlight = false;
  String? _error;
  Map<String, dynamic>? _run;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && !_loadInFlight) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    final runId = (args is Map<String, dynamic>)
        ? args['run_id']?.toString()
        : null;
    if (runId == null || runId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Missing run ID';
      });
      _loadInFlight = false;
      return;
    }

    final baseUrl = (await _storage.getServerBackendBaseUrl())?.trim() ?? '';
    final authToken = kIsWeb
        ? (await _storage.getServerBackendJwt())?.trim() ?? ''
        : '';
    if (baseUrl.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Server backend URL not configured.';
      });
      _loadInFlight = false;
      return;
    }
    if (kIsWeb && authToken.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Web login required. Open Settings and sign in.';
      });
      _loadInFlight = false;
      return;
    }

    try {
      final run = await _api.getResultById(
        baseUrl: baseUrl,
        runId: runId,
        authToken: authToken,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _run = run;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    } finally {
      _loadInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Run Detail'),
        actions: [
          const LogsActionButton(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading
                ? null
                : () {
                    setState(() => _loading = true);
                    _load();
                  },
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
          : run == null
          ? const Center(child: Text('Run not found'))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Run ${run['run_id']}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text('Status: ${run['status'] ?? '-'}'),
                          Text('Trigger: ${run['trigger'] ?? '-'}'),
                          Text('Host: ${run['host_label'] ?? '-'}'),
                          Text('Started: ${run['started_at'] ?? '-'}'),
                          Text('Finished: ${run['finished_at'] ?? '-'}'),
                          Text('Duration: ${run['duration_ms'] ?? 0} ms'),
                          Text(
                            'Applied: ${run['applied'] == true ? "Yes" : "No"}',
                          ),
                          if (run['error_summary'] != null)
                            Text('Error: ${run['error_summary']}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    children: [
                      _statCard(
                        context,
                        'Phase 1 Passed',
                        '${run['phase1_passed'] ?? 0}',
                        Icons.done,
                      ),
                      _statCard(
                        context,
                        'Phase 2 Tested',
                        '${run['phase2_tested'] ?? 0}',
                        Icons.verified,
                      ),
                      _statCard(
                        context,
                        'Working IPs',
                        '${run['working_count'] ?? 0}',
                        Icons.cloud_done,
                      ),
                      _statCard(
                        context,
                        'Status',
                        '${run['status'] ?? '-'}',
                        Icons.info,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Selected IPs',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: 'Copy all',
                        onPressed: () {
                          final ips =
                              (run['selected_ips'] as List<dynamic>? ??
                                      const [])
                                  .map((e) => e.toString())
                                  .toList();
                          Clipboard.setData(
                            ClipboardData(text: ips.join('\n')),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Copied ${ips.length} IPs'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount:
                          (run['selected_ips'] as List<dynamic>? ?? const [])
                              .length,
                      separatorBuilder: (_, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final ips =
                            run['selected_ips'] as List<dynamic>? ?? const [];
                        final ip = ips[index].toString();
                        return ListTile(
                          title: Text(
                            ip,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _statCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 30),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(title, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
