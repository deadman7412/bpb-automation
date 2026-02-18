import 'package:flutter/material.dart';
import 'dart:async';
import '../services/storage_service.dart';
import '../services/log_service.dart';
import '../services/dart_scanner_service.dart';

/// Screen for config-based IP scanning
///
/// Allows users to:
/// - Enter BPB Panel subscription URL
/// - Configure scan parameters (IP count, test depth)
/// - Run 2-phase scanning (TLS + Proxy testing)
/// - View and export results
class ConfigScanScreen extends StatefulWidget {
  const ConfigScanScreen({super.key});

  @override
  State<ConfigScanScreen> createState() => _ConfigScanScreenState();
}

class _ConfigScanScreenState extends State<ConfigScanScreen> {
  final StorageService _storage = StorageService.instance;
  final LogService _log = LogService.instance;
  final DartScannerService _scanner = DartScannerService.instance;

  final TextEditingController _urlController = TextEditingController();
  bool _isScanning = false;
  bool _saveUrl = false;

  // Scan parameters
  int _desiredIPCount = 5;
  int _phase2TestDepth = 50;

  // Progress tracking
  String _statusMessage = 'Ready to scan';

  @override
  void initState() {
    super.initState();
    _loadSavedUrl();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedUrl() async {
    final url = await _storage.getSubscriptionUrl();
    if (url != null && url.isNotEmpty) {
      setState(() {
        _urlController.text = url;
        _saveUrl = true;
      });
      _log.logInfo('[INFO] Loaded saved subscription URL');
    }
  }

  Future<void> _startConfigScan() async {
    final url = _urlController.text.trim();

    if (url.isEmpty) {
      _showError('Please enter a subscription URL');
      return;
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      _showError('URL must start with http:// or https://');
      return;
    }

    setState(() {
      _isScanning = true;
      _statusMessage = 'Starting config scan...';
    });

    _log.logInfo('[INFO] Starting config scan with URL: $url');

    try {
      // Save URL if requested
      if (_saveUrl) {
        await _storage.saveSubscriptionUrl(url);
        _log.logInfo('[INFO] Saved subscription URL to storage');
      }

      // Get scanner config
      final config = await _storage.getScannerConfig();

      // Execute config scan
      final result = await _scanner.executeConfigScan(
        subscriptionUrl: url,
        desiredIPCount: _desiredIPCount,
        config: config,
        phase2TestDepth: _phase2TestDepth,
      );

      if (!mounted) return;

      // Check if we found any working IPs
      if (result.workingIPCount > 0) {
        setState(() {
          _statusMessage =
              'Scan complete - ${result.workingIPCount} working IPs found';
          _isScanning = false;
        });

        _log.logOk('[OK] Config scan completed successfully');

        // Navigate to results screen with config scan result
        Navigator.pushNamed(context, '/config-results', arguments: result);
      } else {
        setState(() {
          _statusMessage = 'Scan complete - No working IPs found';
          _isScanning = false;
        });

        _showError('No working IPs found. Try increasing Phase 2 test depth.');
      }
    } catch (e, stackTrace) {
      _log.logError('[ERROR] Config scan error: $e\n$stackTrace');

      if (!mounted) return;

      setState(() {
        _statusMessage = 'Error: $e';
        _isScanning = false;
      });

      _showError('Scan error: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Config-Based Scan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Help',
            onPressed: _showHelp,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
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
                                'Config-Based Scanning',
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
                            'This mode fetches configs from your BPB Panel subscription, '
                            'tests IPs with real proxy connections, and generates working configs.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.blue[900]),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Subscription URL Input
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Subscription URL',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _urlController,
                            decoration: const InputDecoration(
                              hintText: 'https://your-bpb-panel.com/sub/...',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.link),
                            ),
                            enabled: !_isScanning,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                          ),
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            value: _saveUrl,
                            onChanged: _isScanning
                                ? null
                                : (value) {
                                    setState(() {
                                      _saveUrl = value ?? false;
                                    });
                                  },
                            title: const Text('Save URL for future scans'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Scan Parameters
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Scan Parameters',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),

                          // Desired IP Count
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Working IPs to find:'),
                              Text(
                                '$_desiredIPCount',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Theme.of(context).primaryColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _desiredIPCount.toDouble(),
                            min: 1,
                            max: 20,
                            divisions: 19,
                            label: '$_desiredIPCount IPs',
                            onChanged: _isScanning
                                ? null
                                : (value) {
                                    setState(() {
                                      _desiredIPCount = value.round();
                                    });
                                  },
                          ),
                          const SizedBox(height: 8),

                          // Phase 2 Test Depth
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Phase 2 test depth:'),
                              Text(
                                '$_phase2TestDepth IPs',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Theme.of(context).primaryColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _phase2TestDepth.toDouble(),
                            min: 20,
                            max: 100,
                            divisions: 8,
                            label: '$_phase2TestDepth IPs',
                            onChanged: _isScanning
                                ? null
                                : (value) {
                                    setState(() {
                                      _phase2TestDepth = value.round();
                                    });
                                  },
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Higher values increase chances of finding working IPs but take longer',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Progress Display
                  if (_isScanning) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _statusMessage,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Start Scan Button
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isScanning ? null : _startConfigScan,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: _isScanning
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Scanning...'),
                              ],
                            )
                          : const Text(
                              'Start Config Scan',
                              style: TextStyle(fontSize: 18),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Config-Based Scanning Help'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'What is config-based scanning?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'This mode downloads your actual Xray configs from BPB Panel, '
                'tests them with real proxy connections, and generates working configs.',
              ),
              SizedBox(height: 16),
              Text(
                'How it works:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('1. Fetches configs from your subscription URL'),
              Text('2. Phase 1: Fast TLS testing on many IPs'),
              Text('3. Phase 2: Real proxy testing on best IPs'),
              Text('4. Generates working configs for download'),
              SizedBox(height: 16),
              Text(
                'Parameters:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Working IPs to find: How many working IPs you want in the final result.',
              ),
              SizedBox(height: 8),
              Text(
                'Phase 2 test depth: How many top IPs from Phase 1 to test with proxy. '
                'Higher = more likely to find working IPs, but slower.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
