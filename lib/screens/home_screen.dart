import 'package:flutter/material.dart';
import 'dart:async';
import '../services/storage_service.dart';
import '../services/log_service.dart';
import '../services/dart_scanner_service.dart';
import '../models/scan_progress.dart';
import '../models/scan_result.dart';
import '../models/clean_ip.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final StorageService _storage = StorageService.instance;
  final LogService _log = LogService.instance;
  final DartScannerService _scanner = DartScannerService.instance;

  bool _isScanning = false;
  DateTime? _lastScanTime;
  int _lastIPCount = 0;
  String _statusMessage = 'Ready to scan';
  ScanProgress? _currentProgress;
  StreamSubscription<ScanProgress>? _progressSubscription;

  @override
  void initState() {
    super.initState();
    _loadLastScanInfo();
  }

  Future<void> _loadLastScanInfo() async {
    final lastScan = await _storage.getLastScanTime();
    final count = await _storage.getNumIpsToUse();

    setState(() {
      _lastScanTime = lastScan;
      _lastIPCount = count;
    });
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _statusMessage = 'Initializing scanner...';
      _currentProgress = null;
    });

    _log.logInfo('User initiated scan from home screen');

    try {
      // Step 1: Get scanner configuration
      final config = await _storage.getScannerConfig();
      _log.logInfo('Using scanner config: ${config.threads} threads, ${config.testCount} tests');

      // Step 2: Start progress stream
      final progressStream = _scanner.startProgressStream();
      _progressSubscription = progressStream.listen((progress) {
        if (!mounted) return;
        setState(() {
          _currentProgress = progress;
          _statusMessage = progress.message ?? _getStatusForStage(progress.stage);
        });
      });

      // Step 3: Execute scan
      final scanResult = await _scanner.executeScan(config);

      _log.logOk('Scan completed: ${scanResult.successful} successful, ${scanResult.failed} failed');

      // Step 4: Save scan results and statistics
      final scanTime = DateTime.now();
      await _storage.saveLastScanTime(scanTime);

      setState(() {
        _isScanning = false;
        _statusMessage = 'Scan completed';
        _lastScanTime = scanTime;
        _lastIPCount = scanResult.results.length;
      });

      // Step 5: Show success message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scan completed! Found ${scanResult.results.length} clean IPs'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      // Navigate to results screen after brief delay
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      // Convert ScanResult list to CleanIP list for compatibility
      final cleanIPs = scanResult.results.map((r) {
        return _convertToCleanIP(r);
      }).toList();

      Navigator.pushNamed(context, '/results', arguments: cleanIPs);

    } catch (e, stackTrace) {
      _log.logError('Scan failed', e, stackTrace);

      setState(() {
        _isScanning = false;
        _statusMessage = 'Scan failed';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scan failed: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      _progressSubscription?.cancel();
      _scanner.stopProgressStream();
    }
  }

  String _getStatusForStage(ScanStage stage) {
    switch (stage) {
      case ScanStage.initializing:
        return 'Initializing...';
      case ScanStage.loadingIPs:
        return 'Loading IP addresses...';
      case ScanStage.latencyTesting:
        return 'Testing latency...';
      case ScanStage.speedTesting:
        return 'Testing download speed...';
      case ScanStage.sorting:
        return 'Sorting results...';
      case ScanStage.completed:
        return 'Completed!';
      case ScanStage.failed:
        return 'Failed';
    }
  }

  // Helper to convert ScanResult to CleanIP for compatibility
  CleanIP _convertToCleanIP(ScanResult scanResult) {
    final latency = scanResult.latencyResult;
    final speed = scanResult.speedResult;

    return CleanIP(
      ip: scanResult.ip,
      packetsSent: latency.totalAttempts,
      packetsReceived: latency.successCount,
      lossRate: 100 - latency.successRatePercent,
      avgLatency: latency.averageLatencyMs,
      downloadSpeed: speed?.speedMBps ?? 0, // MB/s
    );
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _scanner.stopProgressStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BPB Automation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.assignment),
            tooltip: 'Logs',
            onPressed: () => Navigator.pushNamed(context, '/logs'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Status Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Icon(
                          _isScanning
                              ? Icons.sync
                              : _lastScanTime != null
                                  ? Icons.check_circle
                                  : Icons.cloud_sync,
                          size: 64,
                          color: _isScanning
                              ? Colors.blue
                              : _lastScanTime != null
                                  ? Colors.green
                                  : Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _statusMessage,
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        if (_lastScanTime != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Last scan: ${_formatDateTime(_lastScanTime!)}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Progress Indicator
                if (_isScanning && _currentProgress != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LinearProgressIndicator(
                            value: _currentProgress!.progress,
                            minHeight: 8,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${_currentProgress!.processedIPs}/${_currentProgress!.totalIPs} IPs processed',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Text(
                                '✓ ${_currentProgress!.successfulIPs}',
                                style: const TextStyle(color: Colors.green),
                              ),
                              Text(
                                '✗ ${_currentProgress!.failedIPs}',
                                style: const TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                if (_isScanning && _currentProgress != null)
                  const SizedBox(height: 24),

                // Scan Button
                SizedBox(
                  width: 200,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isScanning ? null : _startScan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: _isScanning
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Start Scan',
                            style: TextStyle(fontSize: 18),
                          ),
                  ),
                ),

                const SizedBox(height: 48),

                // Quick Stats
                if (_lastScanTime != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(
                            context,
                            'Clean IPs Found',
                            _lastIPCount.toString(),
                            Icons.check,
                          ),
                          _buildStatItem(
                            context,
                            'Status',
                            'Ready',
                            Icons.thumb_up,
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // Quick Actions
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildActionButton(
                      context,
                      'Settings',
                      Icons.settings_outlined,
                      () => Navigator.pushNamed(context, '/settings'),
                    ),
                    _buildActionButton(
                      context,
                      'Configuration',
                      Icons.tune,
                      () => Navigator.pushNamed(context, '/config'),
                    ),
                    _buildActionButton(
                      context,
                      'Results',
                      Icons.list_alt,
                      () => Navigator.pushNamed(context, '/results'),
                    ),
                    _buildActionButton(
                      context,
                      'Logs',
                      Icons.assignment_outlined,
                      () => Navigator.pushNamed(context, '/logs'),
                    ),
                    _buildActionButton(
                      context,
                      'About',
                      Icons.info_outline,
                      () => Navigator.pushNamed(context, '/about'),
                    ),
                    _buildActionButton(
                      context,
                      'Debug',
                      Icons.bug_report,
                      () => Navigator.pushNamed(context, '/debug'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Column(
      children: [
        Icon(icon, color: Colors.green),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} hours ago';
    } else {
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
          '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}
