import 'package:flutter/material.dart';
import 'dart:async';
import '../services/storage_service.dart';
import '../services/log_service.dart';
import '../services/dart_scanner_service.dart';
import '../services/config_tester_service.dart';
import '../services/subscription_service.dart';

/// Main screen for config-based IP scanning
///
/// Features:
/// - Subscription URL input with validation
/// - Manual VLESS config input as fallback
/// - Real-time scan progress tracking
/// - Background scan support
class ConfigScanScreen extends StatefulWidget {
  const ConfigScanScreen({super.key});

  @override
  State<ConfigScanScreen> createState() => _ConfigScanScreenState();
}

class _ConfigScanScreenState extends State<ConfigScanScreen> {
  final StorageService _storage = StorageService.instance;
  final LogService _log = LogService.instance;
  final DartScannerService _scanner = DartScannerService.instance;
  final ConfigTesterService _configTester = ConfigTesterService.instance;
  final SubscriptionService _subscription = SubscriptionService.instance;

  final TextEditingController _urlController = TextEditingController();
  bool _isScanning = false;
  bool _saveUrl = false;
  bool _useManualConfig = false;

  // Scan parameters
  int _desiredIPCount = 5;
  int _phase2TestDepth = 50;

  // Progress tracking
  String _currentPhase = '';
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
    _loadSavedUrl();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _progressSubscription?.cancel();
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

    // Validate input
    if (!_useManualConfig && url.isEmpty) {
      _showError('Please enter a subscription URL or use manual config');
      return;
    }

    if (!_useManualConfig &&
        !url.startsWith('http://') &&
        !url.startsWith('https://')) {
      _showError('URL must start with http:// or https://');
      return;
    }

    // Validate URL accessibility
    if (!_useManualConfig) {
      setState(() {
        _isScanning = true;
        _currentPhase = 'Validating URL...';
      });

      // Test if URL is accessible
      final isValid = await _validateSubscriptionUrl(url);
      if (!isValid) {
        if (!mounted) return;
        setState(() {
          _isScanning = false;
          _currentPhase = '';
        });
        _showError(
          'Could not access subscription URL. Please check the URL or try manual config.',
        );
        return;
      }
    }

    setState(() {
      _isScanning = true;
      _currentPhase = 'Initializing scan...';
      _phase1Tested = 0;
      _phase1Total = 0;
      _phase1Success = 0;
      _phase2Tested = 0;
      _phase2Total = 0;
      _phase2Success = 0;
      _progressPercent = 0.0;
    });

    // Subscribe to progress updates
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

    _log.logInfo('[INFO] Starting config scan with URL: $url');

    try {
      // Save URL if requested
      if (_saveUrl && !_useManualConfig) {
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

      await _progressSubscription?.cancel();
      _progressSubscription = null;

      // Check if we found any working IPs
      if (result.workingIPCount > 0) {
        setState(() {
          _currentPhase = 'Complete';
          _isScanning = false;
        });

        _log.logOk('[OK] Config scan completed successfully');

        // Navigate to results screen
        Navigator.pushNamed(context, '/results', arguments: result);
      } else {
        setState(() {
          _currentPhase = 'Complete - No working IPs found';
          _isScanning = false;
        });

        _showError('No working IPs found. Try increasing Phase 2 test depth.');
      }
    } catch (e, stackTrace) {
      _log.logError('[ERROR] Config scan error: $e\n$stackTrace');

      await _progressSubscription?.cancel();
      _progressSubscription = null;

      if (!mounted) return;

      setState(() {
        _currentPhase = 'Error';
        _isScanning = false;
      });

      _showError('Scan error: $e');
    }
  }

  Future<bool> _validateSubscriptionUrl(String url) async {
    try {
      _log.logInfo('[INFO] Validating subscription URL: $url');
      // Try to fetch configs to validate
      final configs = await _subscription.fetchConfigs(url);
      return configs.isNotEmpty;
    } catch (e) {
      _log.logWarn('[WARN] URL validation failed: $e');
      return false;
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

  void _showManualConfigDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manual VLESS Config'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Manual config input is not yet implemented.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text(
                'This feature will allow you to paste a VLESS:// config directly '
                'instead of using a subscription URL.',
              ),
              SizedBox(height: 12),
              Text('Coming soon in a future update.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BPB Clean IP Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Logs',
            onPressed: () {
              Navigator.pushNamed(context, '/logs');
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
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
                                'How It Works',
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
                            'Tests clean Cloudflare IPs with your actual BPB subscription configs. '
                            'Phase 1: Fast TLS testing. Phase 2: Real proxy connectivity testing.',
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
                            decoration: InputDecoration(
                              hintText: 'https://your-bpb-panel.com/sub/...',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.link),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.edit_note),
                                tooltip: 'Use manual config instead',
                                onPressed: _isScanning
                                    ? null
                                    : _showManualConfigDialog,
                              ),
                            ),
                            enabled: !_isScanning && !_useManualConfig,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            value: _saveUrl,
                            onChanged: _isScanning || _useManualConfig
                                ? null
                                : (value) {
                                    setState(() {
                                      _saveUrl = value ?? false;
                                    });
                                  },
                            title: const Text('Remember URL for next time'),
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
                            'Higher = better chance of success, slower scan',
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
                      color: Colors.green[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Current Phase
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Phase 1 (TLS):',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
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
                                'Success: $_phase1Success IPs (${(_progressPercent).toStringAsFixed(1)}%)',
                                style: TextStyle(
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],

                            // Phase 2 Progress (placeholder for now)
                            if (_phase2Total > 0) ...[
                              const SizedBox(height: 16),
                              const Divider(),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Phase 2 (Proxy):',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
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

                            const SizedBox(height: 12),
                            Text(
                              'Tip: You can navigate away. Scan continues in background.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.grey[600],
                                    fontStyle: FontStyle.italic,
                                  ),
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
                              'Start Scan',
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
        title: const Text('How Config Scanning Works'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Overview', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text(
                'This scanner tests Cloudflare IPs with your actual BPB Panel '
                'subscription configs to find working clean IPs.',
              ),
              SizedBox(height: 16),
              Text(
                'How it works:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('1. Fetches Xray configs from your subscription URL'),
              Text('2. Phase 1: Fast TLS testing on many IPs (pre-filter)'),
              Text('3. Phase 2: Real proxy testing on best candidates'),
              Text('4. Generates working configs for you to use'),
              SizedBox(height: 16),
              Text(
                'Parameters:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Working IPs: How many clean IPs you want in the final result.',
              ),
              SizedBox(height: 8),
              Text(
                'Phase 2 depth: How many top Phase 1 IPs to test with proxy. '
                'Higher = better chance, slower scan.',
              ),
              SizedBox(height: 16),
              Text(
                'Background Scanning:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'You can navigate to other screens while scanning. The scan '
                'continues in the background. Check logs for progress.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }
}
