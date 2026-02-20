import 'package:flutter/material.dart';

import '../services/server_backend_service.dart';
import '../services/storage_service.dart';
import '../widgets/logs_action_button.dart';

class ServerLogsScreen extends StatefulWidget {
  const ServerLogsScreen({super.key});

  @override
  State<ServerLogsScreen> createState() => _ServerLogsScreenState();
}

class _ServerLogsScreenState extends State<ServerLogsScreen> {
  final StorageService _storage = StorageService.instance;
  final ServerBackendService _api = ServerBackendService.instance;

  bool _loading = true;
  String? _error;
  String _baseUrl = '';
  int _page = 1;
  int _pageSize = 100;
  int _total = 0;
  List<String> _logs = const [];

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
    if (baseUrl.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Server backend URL not configured in Settings.';
      });
      return;
    }

    try {
      final payload = await _api.getLogsPage(
        baseUrl: baseUrl,
        page: _page,
        pageSize: _pageSize,
      );
      final items = (payload['items'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();
      if (!mounted) return;
      setState(() {
        _baseUrl = baseUrl;
        _total = (payload['total'] as num?)?.toInt() ?? items.length;
        _logs = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = _pageSize > 0
        ? ((_total + _pageSize - 1) ~/ _pageSize)
        : 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Logs'),
        actions: [
          const LogsActionButton(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Source: $_baseUrl',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Total: $_total'),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: (_page > 1 && !_loading)
                              ? () {
                                  setState(() => _page -= 1);
                                  _load();
                                }
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(
                          'Page $_page / ${totalPages == 0 ? 1 : totalPages}',
                        ),
                        IconButton(
                          onPressed: (_page < totalPages && !_loading)
                              ? () {
                                  setState(() => _page += 1);
                                  _load();
                                }
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                        const Spacer(),
                        DropdownButton<int>(
                          value: _pageSize,
                          items: const [50, 100, 200, 500]
                              .map(
                                (n) => DropdownMenuItem<int>(
                                  value: n,
                                  child: Text('$n/page'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _pageSize = v;
                              _page = 1;
                            });
                            _load();
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _logs.isEmpty
                        ? const Center(child: Text('No logs'))
                        : ListView.builder(
                            itemCount: _logs.length,
                            itemBuilder: (context, index) => ListTile(
                              dense: true,
                              title: Text(
                                _logs[index],
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
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
