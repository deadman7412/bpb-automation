import 'package:flutter/material.dart';
import 'dart:async';
import '../models/xray_config.dart';
import '../services/storage_service.dart';
import '../services/log_service.dart';
import '../services/dart_scanner_service.dart';
import '../services/config_tester_service.dart';
import '../services/subscription_service.dart';

/// Real-time scan progress screen
///
/// Features:
/// - Auto-starts scan when screen loads
/// - Intelligently caches subscription configs
/// - Real-time Phase 1 (TLS) and Phase 2 (Proxy) progress tracking
/// - Background scan support - can navigate away
/// - Shows detailed statistics for each phase
class ScanProgressScreen extends StatefulWidget {
  const ScanProgressScreen({super.key});

  @override
  State<ScanProgressScreen> createState() => _ScanProgressScreenState();
}

class _ScanProgressScreenState extends State<ScanProgressScreen> {
  final StorageService _storage = StorageService.instance;
  final LogService _log = LogService.instance;
  final DartScannerService _scanner = DartScannerService.instance;
  final ConfigTesterService _configTester = ConfigTesterService.instance;
  final SubscriptionService _subscription = SubscriptionService.instance;

  bool _isScanning = false;

  // Progress tracking
  String _currentPhase = 'Initializing...';
  int _phase1Tested = 0;
  int _phase1Total = 0;
  int _phase1Success = 0;
  int _phase2Tested = 0;
  int _phase2Total = 0;
  int _phase2Success = 0;
  double _progressPercent = 0.0;

  StreamSubscription<TlsTestProgress>? _progressSubscription;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    // Load configuration from storage
    final url = await _storage.getSubscriptionUrl();
    if (url == null || url.isEmpty) {
      if (!mounted) return;
      _showError(
        'No subscription URL configured',
        'Please enter your BPB Panel URL in Configuration first.',
        showConfigButton: true,
      );
      return;
    }

    final params = await _storage.getScanParameters();
    final desiredIPCount = params['desiredIPCount'] ?? 5;
    final phase2TestDepth = params['phase2TestDepth'] ?? 50;
    final enableIPv6 = params['enableIPv6'] == 1; // 1 = ON, 0 = OFF

    setState(() {
      _isScanning = true;
      _currentPhase = 'Loading configs...';
    });

    // Try to load cached configs first
    List<XrayConfig>? configs;
    final cachedConfigsJson = await _storage.getCachedConfigs();

    if (cachedConfigsJson != null && cachedConfigsJson.isNotEmpty) {
      // Use cached configs
      configs = cachedConfigsJson
          .map((json) => XrayConfig.fromJson(json as Map<String, dynamic>))
          .toList();
      _log.logInfo('Using ${configs.length} cached configs');

      setState(() {
        _currentPhase = 'Using cached configs (${configs!.length} configs)';
      });

      await Future.delayed(const Duration(milliseconds: 500));
    } else {
      // No cache - fetch from network
      setState(() {
        _currentPhase = 'Downloading configs from subscription URL...';
      });

      try {
        _log.logInfo('Fetching subscription from: $url');
        configs = await _subscription.fetchConfigs(url);

        if (configs.isEmpty) {
          if (!mounted) return;
          setState(() {
            _isScanning = false;
            _currentPhase = 'Error';
          });
          _showError(
            'No Valid Configs Found',
            'The subscription URL returned no valid Xray configs.\n\n'
                'Please check your URL in Configuration.',
            showConfigButton: true,
          );
          return;
        }

        // Cache the configs for next time
        await _storage.saveCachedConfigs(configs);
        _log.logOk('Fetched and cached ${configs.length} configs');

        setState(() {
          _currentPhase = 'Configs downloaded (${configs!.length} configs)';
        });

        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        _log.logError('Failed to fetch subscription: $e');

        if (!mounted) return;
        setState(() {
          _isScanning = false;
          _currentPhase = 'Error';
        });

        _showError(
          'Cannot Download Configs',
          'Failed to fetch configs from subscription URL.\n\n'
              'Error: $e\n\n'
              'Please check:\n'
              '• Your internet connection\n'
              '• The subscription URL is correct\n'
              '• The URL is accessible',
          showConfigButton: true,
          showRetryButton: true,
        );
        return;
      }
    }

    // Now we have configs - start the scan
    setState(() {
      _currentPhase = 'Preparing scan...';
      _phase1Tested = 0;
      _phase1Total = 0;
      _phase1Success = 0;
      _phase2Tested = 0;
      _phase2Total = 0;
      _phase2Success = 0;
      _progressPercent = 0.0;
    });

    // Subscribe to Phase 1 progress updates
    _progressSubscription = _configTester.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() {
        _currentPhase = 'Phase 1: TLS Testing';
        _phase1Tested = progress.processedIPs;
        _phase1Total = progress.totalIPs;
        _phase1Success = progress.successfulIPs;
        _progressPercent = progress.progressPercent;
      });
    });

    _log.logInfo('Starting config scan');

    try {
      // Execute config scan with the configs we have
      final result = await _scanner.executeConfigScanWithConfigs(
        configs: configs,
        desiredIPCount: desiredIPCount,
        phase2TestDepth: phase2TestDepth,
        enableIPv6: enableIPv6,
      );

      if (!mounted) return;

      await _progressSubscription?.cancel();
      _progressSubscription = null;

      if (!mounted) return;

      // Check if we found any working IPs
      if (result.workingIPCount > 0) {
        setState(() {
          _currentPhase = 'Complete';
          _isScanning = false;
        });

        _log.logOk('Config scan completed successfully');

        // Navigate to results screen
        // ignore: use_build_context_synchronously
        Navigator.pushReplacementNamed(context, '/results', arguments: result);
      } else {
        setState(() {
          _currentPhase = 'Complete - No working IPs found';
          _isScanning = false;
        });

        _showError(
          'No Working IPs Found',
          'The scan completed but found no working IPs.\n\n'
              'Try:\n'
              '• Increasing scan depth in Configuration\n'
              '• Running the scan again (network conditions vary)',
          showRetryButton: true,
        );
      }
    } catch (e, stackTrace) {
      _log.logError('Config scan error: $e\n$stackTrace');

      await _progressSubscription?.cancel();
      _progressSubscription = null;

      if (!mounted) return;

      setState(() {
        _currentPhase = 'Error';
        _isScanning = false;
      });

      _showError(
        'Scan Error',
        'An error occurred during scanning:\n\n$e',
        showRetryButton: true,
      );
    }
  }

  void _showError(
    String title,
    String message, {
    bool showConfigButton = false,
    bool showRetryButton = false,
  }) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          if (showRetryButton)
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                _startScan(); // Retry scan
              },
              child: const Text('Retry'),
            ),
          if (showConfigButton)
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Close scan screen
                Navigator.pushNamed(context, '/config'); // Go to config
              },
              child: const Text('Open Config'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close scan screen
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _stopScan() {
    // Cancel the scan
    _scanner.cancelScan();

    // Update UI
    setState(() {
      _isScanning = false;
      _currentPhase = 'Scan cancelled by user';
    });

    _log.logWarn('User cancelled scan from progress screen');

    // Show confirmation
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Scan cancelled'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanning'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Logs',
            onPressed: () {
              Navigator.pushNamed(context, '/logs');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Info Card
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              Text(
                                'Scan in Progress',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Colors.blue[900],
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Testing clean Cloudflare IPs with your BPB configs. '
                            'This may take a few minutes.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.blue[900]),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Progress Display
                  Card(
                    color: Colors.green[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Current Phase
                          Row(
                            children: [
                              if (_isScanning)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                Icon(
                                  _currentPhase.contains('Error')
                                      ? Icons.error_outline
                                      : Icons.check_circle_outline,
                                  color: _currentPhase.contains('Error')
                                      ? Colors.red
                                      : Colors.green,
                                ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _currentPhase,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),

                          // Phase 1 Progress
                          if (_phase1Total > 0) ...[
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Phase 1 (TLS):',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '$_phase1Tested / $_phase1Total tested',
                                  style: TextStyle(color: Colors.grey[700]),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: _phase1Total > 0
                                  ? _phase1Tested / _phase1Total
                                  : 0,
                              backgroundColor: Colors.grey[300],
                              color: Colors.green,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Success: $_phase1Success IPs',
                              style: TextStyle(
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],

                          // Phase 2 Progress
                          if (_phase2Total > 0) ...[
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Phase 2 (Proxy):',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '$_phase2Tested / $_phase2Total tested',
                                  style: TextStyle(color: Colors.grey[700]),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: _phase2Total > 0
                                  ? _phase2Tested / _phase2Total
                                  : 0,
                              backgroundColor: Colors.grey[300],
                              color: Colors.blue,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Working: $_phase2Success IPs',
                              style: TextStyle(
                                color: Colors.blue[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Stop Scan Button
                  if (_isScanning) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _stopScan,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text(
                          'Stop Scan',
                          style: TextStyle(fontSize: 16),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red, width: 2),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
