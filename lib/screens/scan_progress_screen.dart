import 'package:flutter/material.dart';
import 'dart:async';
import '../models/xray_config.dart';
import '../models/config_scan_result.dart';
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
  bool _isCancelling = false;

  // Progress tracking
  String _currentPhase = 'Initializing...';
  // Phase 0: TCP pre-filter
  int _phase0Tested = 0;
  int _phase0Total = 0;
  int _phase0Success = 0;
  // Phase 1: TLS handshake
  int _phase1Tested = 0;
  int _phase1Total = 0;
  int _phase1Success = 0;
  // Phase 2: Proxy test
  int _phase2Tested = 0;
  int _phase2Total = 0;
  int _phase2Success = 0;

  StreamSubscription<TlsTestProgress>? _progressSubscription;
  StreamSubscription<Phase2Progress>? _phase2ProgressSubscription;
  StreamSubscription<ConfigScanResult>? _completionSubscription;

  // Elapsed time tracking
  DateTime? _scanStartTime;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (_scanner.isScanning) {
      _attachToExistingScan();
    } else {
      _startScan();
    }
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _phase2ProgressSubscription?.cancel();
    _completionSubscription?.cancel();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  void _startElapsedTimer() {
    _scanStartTime = DateTime.now();
    _elapsed = Duration.zero;
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(_scanStartTime!);
      });
    });
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  String get _elapsedString {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
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
    final maxSamplesPerCIDR = params['maxSamplesPerCIDR'] ?? 100;
    final batchSize = params['scanBatchSize'] ?? 200;

    setState(() {
      _isScanning = true;
      _currentPhase = 'Loading configs...';
    });
    _startElapsedTimer();

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
      _phase0Tested = 0;
      _phase0Total = 0;
      _phase0Success = 0;
      _phase1Tested = 0;
      _phase1Total = 0;
      _phase1Success = 0;
      _phase2Tested = 0;
      _phase2Total = 0;
      _phase2Success = 0;
    });

    // Subscribe to Phase 0 (TCP) + Phase 1 (TLS) progress updates
    _progressSubscription = _configTester.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() {
        if (progress.phase == ScanPhaseType.tcp) {
          _currentPhase = 'Phase 0: TCP Pre-filter';
          _phase0Tested = progress.processedIPs;
          _phase0Total = progress.totalIPs;
          _phase0Success = progress.successfulIPs;
        } else {
          _currentPhase = 'Phase 1: TLS Testing';
          _phase1Tested = progress.processedIPs;
          _phase1Total = progress.totalIPs;
          _phase1Success = progress.successfulIPs;
        }
      });
    });

    // Subscribe to Phase 2 progress updates
    _phase2ProgressSubscription = _scanner.phase2ProgressStream.listen((
      progress,
    ) {
      if (!mounted) return;
      setState(() {
        _currentPhase = 'Phase 2: Proxy Testing';
        _phase2Tested = progress.testedIPs;
        _phase2Total = progress.totalIPs;
        _phase2Success = progress.workingIPs;
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
        maxSamplesPerCIDR: maxSamplesPerCIDR,
        batchSize: batchSize,
      );

      if (!mounted) return;
      await _handleScanResult(result);
    } catch (e, stackTrace) {
      _log.logError('Config scan error: $e\n$stackTrace');

      await _progressSubscription?.cancel();
      await _phase2ProgressSubscription?.cancel();
      await _completionSubscription?.cancel();
      _progressSubscription = null;
      _phase2ProgressSubscription = null;
      _completionSubscription = null;

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

  /// Attach to a scan that is already running (navigated back then returned).
  /// Subscribes to progress and completion streams without starting a new scan.
  void _attachToExistingScan() {
    _log.logInfo('Attaching to existing scan in progress');

    // Immediately apply last known state for ALL phases so bars appear right away
    String phase = 'Scan in progress...';
    int p0tested = 0, p0total = 0, p0success = 0;
    int p1tested = 0, p1total = 0, p1success = 0;
    int p2tested = 0, p2total = 0, p2success = 0;

    // Phase 0 (TCP) — always show last TCP snapshot if it exists
    final lastTcp = _configTester.lastTcpProgress;
    if (lastTcp != null) {
      p0tested = lastTcp.processedIPs;
      p0total = lastTcp.totalIPs;
      p0success = lastTcp.successfulIPs;
      phase = 'Phase 0: TCP Pre-filter';
    }

    // Phase 1 (TLS) — always show last TLS snapshot if it exists
    final lastTls = _configTester.lastTlsProgress;
    if (lastTls != null) {
      p1tested = lastTls.processedIPs;
      p1total = lastTls.totalIPs;
      p1success = lastTls.successfulIPs;
      phase = 'Phase 1: TLS Testing';
    }

    // Phase 2 — always show last proxy snapshot if it exists
    final lastP2 = _scanner.lastPhase2Progress;
    if (lastP2 != null) {
      p2tested = lastP2.testedIPs;
      p2total = lastP2.totalIPs;
      p2success = lastP2.workingIPs;
      phase = 'Phase 2: Proxy Testing';
    }

    _startElapsedTimer();
    setState(() {
      _isScanning = true;
      _currentPhase = phase;
      _phase0Tested = p0tested;
      _phase0Total = p0total;
      _phase0Success = p0success;
      _phase1Tested = p1tested;
      _phase1Total = p1total;
      _phase1Success = p1success;
      _phase2Tested = p2tested;
      _phase2Total = p2total;
      _phase2Success = p2success;
    });

    // Phase 0 (TCP) + Phase 1 (TLS) progress
    _progressSubscription = _configTester.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() {
        if (progress.phase == ScanPhaseType.tcp) {
          _currentPhase = 'Phase 0: TCP Pre-filter';
          _phase0Tested = progress.processedIPs;
          _phase0Total = progress.totalIPs;
          _phase0Success = progress.successfulIPs;
        } else {
          _currentPhase = 'Phase 1: TLS Testing';
          _phase1Tested = progress.processedIPs;
          _phase1Total = progress.totalIPs;
          _phase1Success = progress.successfulIPs;
        }
      });
    });

    // Phase 2 progress
    _phase2ProgressSubscription = _scanner.phase2ProgressStream.listen((
      progress,
    ) {
      if (!mounted) return;
      setState(() {
        _currentPhase = 'Phase 2: Proxy Testing';
        _phase2Tested = progress.testedIPs;
        _phase2Total = progress.totalIPs;
        _phase2Success = progress.workingIPs;
      });
    });

    // Wait for the scan to finish
    _completionSubscription = _scanner.completionStream.listen((result) {
      _handleScanResult(result);
    });
  }

  /// Handle the final scan result — called from both _startScan and _attachToExistingScan.
  Future<void> _handleScanResult(ConfigScanResult result) async {
    _stopElapsedTimer();
    await _progressSubscription?.cancel();
    await _phase2ProgressSubscription?.cancel();
    await _completionSubscription?.cancel();
    _progressSubscription = null;
    _phase2ProgressSubscription = null;
    _completionSubscription = null;

    if (!mounted) return;

    if (result.workingIPCount > 0 || _isCancelling) {
      setState(() {
        _currentPhase = _isCancelling ? 'Cancelled' : 'Complete';
        _isScanning = false;
        _isCancelling = false;
      });

      _log.logOk(
        _isCancelling
            ? 'Scan cancelled - showing partial results'
            : 'Config scan completed successfully',
      );

      // Persist result so results screen can reload it after navigating away
      await _storage.saveLastScanResult(result.toJson());

      // ignore: use_build_context_synchronously
      Navigator.pushReplacementNamed(context, '/results', arguments: result);
    } else {
      setState(() {
        _currentPhase = 'Complete - No IPs found';
        _isScanning = false;
      });

      _showError(
        'No IPs Found',
        'The scan completed but found no usable IPs.\n\n'
            'Try:\n'
            '• Increasing scan depth in Configuration\n'
            '• Running the scan again (network conditions vary)',
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
    // Mark as cancelling
    setState(() {
      _isCancelling = true;
      _currentPhase = 'Stopping scan...';
    });

    // Cancel the scan
    _scanner.cancelScan();

    _log.logWarn('User cancelled scan from progress screen');

    // Show confirmation
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Stopping scan - will show results found so far'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );

    // Scanner will complete shortly and navigate to results
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
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Scan in Progress',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Progress Display
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Current Phase + Elapsed Time
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
                              if (_elapsed > Duration.zero)
                                Text(
                                  _elapsedString,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                            ],
                          ),

                          // Phase 0: TCP Pre-filter
                          if (_phase0Total > 0) ...[
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Phase 0 (TCP):',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '$_phase0Tested / $_phase0Total checked',
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: _phase0Total > 0
                                  ? _phase0Tested / _phase0Total
                                  : 0,
                              backgroundColor: Colors.grey[300],
                              color: Colors.orange,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Reachable: $_phase0Success IPs',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],

                          // Phase 1: TLS Handshake
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
                              'Passed TLS: $_phase1Success IPs',
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
