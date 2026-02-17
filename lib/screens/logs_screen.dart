import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../services/log_service.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final LogService _log = LogService.instance;
  LogLevel? _filterLevel;
  bool _autoScroll = true;
  final ScrollController _scrollController = ScrollController();
  int _previousLogCount = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_autoScroll && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  Color _getLogColor(LogLevel level) {
    switch (level) {
      case LogLevel.ok:
        return Colors.green;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warn:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }

  IconData _getLogIcon(LogLevel level) {
    switch (level) {
      case LogLevel.ok:
        return Icons.check_circle;
      case LogLevel.info:
        return Icons.info;
      case LogLevel.warn:
        return Icons.warning;
      case LogLevel.error:
        return Icons.error;
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Logs'),
        content: const Text('Are you sure you want to clear all logs?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _log.clearLogs();
      setState(() {});

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Logs cleared')));
    }
  }

  Future<void> _exportLogs() async {
    try {
      final exported = _log.exportLogs();

      // Get the appropriate directory based on platform
      final Directory directory;
      if (Platform.isAndroid) {
        // On Android, use external storage directory
        directory = (await getExternalStorageDirectory())!;
      } else if (Platform.isIOS) {
        // On iOS, use documents directory
        directory = await getApplicationDocumentsDirectory();
      } else {
        // On desktop (macOS, Windows, Linux), use downloads directory
        directory =
            await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      }

      // Create filename with timestamp
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')[0];
      final filename = 'bpb_automation_logs_$timestamp.txt';
      final file = File('${directory.path}/$filename');

      // Write logs to file
      await file.writeAsString(exported);

      if (!mounted) return;

      // Show success message with file path
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logs exported to:\n${file.path}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Copy Path',
            textColor: Colors.white,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: file.path));
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export logs: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _copyLogsToClipboard() async {
    final exported = _log.exportLogs();
    await Clipboard.setData(ClipboardData(text: exported));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs copied to clipboard'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logs = _filterLevel != null
        ? _log.getLogsByLevel(_filterLevel!)
        : _log.getLogs();

    // Auto-scroll to bottom when new logs arrive
    if (logs.length != _previousLogCount) {
      _previousLogCount = logs.length;
      _scrollToBottom();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter',
            onPressed: () => _showFilterDialog(),
          ),
          IconButton(
            icon: Icon(
              _autoScroll
                  ? Icons.arrow_downward
                  : Icons.arrow_downward_outlined,
            ),
            tooltip: 'Auto-scroll',
            onPressed: () {
              setState(() => _autoScroll = !_autoScroll);
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
            onSelected: (value) {
              switch (value) {
                case 'export':
                  _exportLogs();
                  break;
                case 'copy':
                  _copyLogsToClipboard();
                  break;
                case 'clear':
                  _clearLogs();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.save_alt),
                    SizedBox(width: 12),
                    Text('Export to File'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy),
                    SizedBox(width: 12),
                    Text('Copy to Clipboard'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline),
                    SizedBox(width: 12),
                    Text('Clear Logs'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          if (_filterLevel != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  const Text('Filter: '),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(_filterLevel!.tag),
                    backgroundColor: _getLogColor(
                      _filterLevel!,
                    ).withValues(alpha: 0.2),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () => setState(() => _filterLevel = null),
                  ),
                ],
              ),
            ),

          // Log Count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${logs.length} log entries',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (_autoScroll)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.autorenew,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Auto-scroll',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Logs List
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No logs yet',
                          style: TextStyle(color: Colors.grey, fontSize: 18),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: logs.length,
                    padding: const EdgeInsets.all(8),
                    itemBuilder: (context, index) {
                      final log = logs[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 8,
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            _getLogIcon(log.level),
                            color: _getLogColor(log.level),
                            size: 20,
                          ),
                          title: Text(
                            log.message,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_formatTime(log.timestamp)} - ${log.level.tag}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              if (log.error != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Error: ${log.error}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.red,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: log.format()),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Log entry copied'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFilterDialog() async {
    final result = await showDialog<LogLevel?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Logs'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.filter_none),
              title: const Text('All Logs'),
              onTap: () => Navigator.pop(context, null),
            ),
            ...LogLevel.values.map((level) {
              return ListTile(
                leading: Icon(_getLogIcon(level), color: _getLogColor(level)),
                title: Text(level.tag),
                onTap: () => Navigator.pop(context, level),
              );
            }),
          ],
        ),
      ),
    );

    if (result != null || result == null && _filterLevel != null) {
      setState(() => _filterLevel = result);
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}
