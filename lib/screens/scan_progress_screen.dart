import 'package:flutter/material.dart';
import 'dart:async';
import '../models/xray_config.dart';
import '../models/config_scan_result.dart';
import '../models/update_mode.dart';
import '../services/storage_service.dart';
import '../services/log_service.dart';
import '../services/dart_scanner_service.dart';
import '../services/config_tester_service.dart';
import '../services/subscription_service.dart';
import '../services/cloudflare_api_service.dart';
import '../services/panel_api_service.dart';
import '../widgets/logs_action_button.dart';

/// Real-time scan progress screen
///
/// Features:
/// - Auto-starts scan when screen loads
/// - Intelligently caches subscription configs
/// - Real-time Phase 1 (TCP), Phase 2 (TLS), and Phase 3 (Proxy) progress tracking
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
  final CloudflareApiService _cloudflareApi = CloudflareApiService.instance;
  final PanelApiService _panelApi = PanelApiService.instance;

  bool _isScanning = false;
  bool _isCancelling = false;
  static const String _keyActiveScanStartMs = 'active_scan_start_ms';
  static const String _keyLastScanElapsedMs = 'last_scan_elapsed_ms';

  // Progress tracking
  String _currentPhase = 'Initializing...';
  // Phase 1: TCP pre-filter
  int _phase0Tested = 0;
  int _phase0Total = 0;
  int _phase0Success = 0;
  // Phase 2: TLS handshake
  int _phase1Tested = 0;
  int _phase1Total = 0;
  int _phase1Success = 0;
  String? _phase1PassLabel; // "1/2" or "2/2" during two-pass TLS
  // Phase 3: Proxy test
  int _phase2Tested = 0;
  int _phase2Total = 0;
  int _phase2Success = 0;

  StreamSubscription<TlsTestProgress>? _progressSubscription;
  StreamSubscription<Phase2Progress>? _phase2ProgressSubscription;
  StreamSubscription<ConfigScanResult>? _completionSubscription;

  // Elapsed time tracking
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (_scanner.isScanning) {
      unawaited(_attachToExistingScan());
    } else {
      unawaited(_startScan());
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

  void _startElapsedTimer(DateTime scanStartTime) {
    _elapsed = DateTime.now().difference(scanStartTime);
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(scanStartTime);
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

  void _setStateIfMounted(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
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
    final ipPoolSize = params['ipPoolSize'] ?? 1000;
    final batchSize = params['scanBatchSize'] ?? 200;
    final fullScan = await _storage.getFullScan();

    _setStateIfMounted(() {
      _isScanning = true;
      _currentPhase = 'Loading configs...';
    });
    final scanStartTime = DateTime.now();
    await _storage.saveInt(
      _keyActiveScanStartMs,
      scanStartTime.millisecondsSinceEpoch,
    );
    if (!mounted) return;
    _startElapsedTimer(scanStartTime);

    // Always refresh configs from subscription first.
    List<XrayConfig>? configs;
    final cachedConfigsJson = await _storage.getCachedConfigs();
    final cachedConfigs = (cachedConfigsJson ?? const <dynamic>[])
        .map((json) => XrayConfig.fromJson(json as Map<String, dynamic>))
        .toList();

    _setStateIfMounted(() {
      _currentPhase = 'Refreshing configs from subscription...';
    });

    try {
      _log.logInfo('Fetching latest subscription configs from: $url');
      configs = await _subscription.fetchConfigs(url);

      if (configs.isEmpty) {
        throw Exception('Subscription returned no valid configs');
      }

      await _storage.saveCachedConfigs(configs);
      _log.logOk(
        'Fetched latest ${configs.length} configs and refreshed cache',
      );

      _setStateIfMounted(() {
        _currentPhase = 'Using latest configs (${configs!.length} configs)';
      });
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      _log.logWarn('Failed to refresh subscription configs: $e');

      if (cachedConfigs.isNotEmpty) {
        configs = cachedConfigs;
        _log.logWarn(
          'Falling back to ${configs.length} cached configs for this scan',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not refresh latest configs. Using cached configs for this scan.',
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
            ),
          );
        }

        _setStateIfMounted(() {
          _currentPhase =
              'Using cached configs (refresh failed, ${configs!.length} configs)';
        });
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        _log.logError('No cached configs available and refresh failed: $e');

        _stopElapsedTimer();
        await _storage.remove(_keyActiveScanStartMs);
        _setStateIfMounted(() {
          _isScanning = false;
          _currentPhase = 'Error';
        });
        if (mounted) {
          _showError(
            'Cannot Load Configs',
            'Failed to refresh configs from subscription URL, and no cached configs are available.\n\n'
                'Error: $e\n\n'
                'Please check:\n'
                '• Your internet connection\n'
                '• The subscription URL is correct\n'
                '• The URL is accessible',
            showConfigButton: true,
            showRetryButton: true,
          );
        }
        return;
      }
    }

    // Now we have configs - start the scan
    _setStateIfMounted(() {
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

    // Subscribe to Phase 1 (TCP) + Phase 2 (TLS) progress updates
    _progressSubscription = _configTester.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() {
        if (progress.phase == ScanPhaseType.tcp) {
          _currentPhase = 'Phase 1: TCP Pre-filter';
          _phase0Tested = progress.processedIPs;
          _phase0Total = progress.totalIPs;
          _phase0Success = progress.successfulIPs;
        } else {
          _currentPhase = 'Phase 2: TLS Testing';
          _phase1Tested = progress.processedIPs;
          _phase1Total = progress.totalIPs;
          _phase1Success = progress.successfulIPs;
          _phase1PassLabel = progress.passLabel;
        }
      });
    });

    // Subscribe to Phase 3 progress updates
    _phase2ProgressSubscription = _scanner.phase2ProgressStream.listen((
      progress,
    ) {
      if (!mounted) return;
      setState(() {
        _currentPhase = 'Phase 3: Proxy Testing';
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
        ipPoolSize: ipPoolSize,
        batchSize: batchSize,
        fullScan: fullScan,
      );

      await _handleScanResult(result);
    } catch (e, stackTrace) {
      _log.logError('Config scan error: $e\n$stackTrace');

      await _progressSubscription?.cancel();
      await _phase2ProgressSubscription?.cancel();
      await _completionSubscription?.cancel();
      _progressSubscription = null;
      _phase2ProgressSubscription = null;
      _completionSubscription = null;

      _stopElapsedTimer();
      await _storage.remove(_keyActiveScanStartMs);

      _setStateIfMounted(() {
        _currentPhase = 'Error';
        _isScanning = false;
      });

      if (mounted) {
        _showError(
          'Scan Error',
          'An error occurred during scanning:\n\n$e',
          showRetryButton: true,
        );
      }
    }
  }

  /// Attach to a scan that is already running (navigated back then returned).
  /// Subscribes to progress and completion streams without starting a new scan.
  Future<void> _attachToExistingScan() async {
    _log.logInfo('Attaching to existing scan in progress');

    // Immediately apply last known state for ALL phases so bars appear right away
    String phase = 'Scan in progress...';
    int p0tested = 0, p0total = 0, p0success = 0;
    int p1tested = 0, p1total = 0, p1success = 0;
    int p2tested = 0, p2total = 0, p2success = 0;

    // Phase 1 (TCP) — always show last TCP snapshot if it exists
    final lastTcp = _configTester.lastTcpProgress;
    if (lastTcp != null) {
      p0tested = lastTcp.processedIPs;
      p0total = lastTcp.totalIPs;
      p0success = lastTcp.successfulIPs;
      phase = 'Phase 1: TCP Pre-filter';
    }

    // Phase 2 (TLS) — always show last TLS snapshot if it exists
    final lastTls = _configTester.lastTlsProgress;
    if (lastTls != null) {
      p1tested = lastTls.processedIPs;
      p1total = lastTls.totalIPs;
      p1success = lastTls.successfulIPs;
      phase = 'Phase 2: TLS Testing';
      _phase1PassLabel = lastTls.passLabel;
    }

    // Phase 3 — always show last proxy snapshot if it exists
    final lastP2 = _scanner.lastPhase2Progress;
    if (lastP2 != null) {
      p2tested = lastP2.testedIPs;
      p2total = lastP2.totalIPs;
      p2success = lastP2.workingIPs;
      phase = 'Phase 3: Proxy Testing';
    }

    final activeStartMs = await _storage.getInt(_keyActiveScanStartMs);
    final scanStartTime = activeStartMs != null
        ? DateTime.fromMillisecondsSinceEpoch(activeStartMs)
        : DateTime.now();
    if (activeStartMs == null) {
      await _storage.saveInt(
        _keyActiveScanStartMs,
        scanStartTime.millisecondsSinceEpoch,
      );
    }
    if (!mounted) return;
    _startElapsedTimer(scanStartTime);
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

    // Phase 1 (TCP) + Phase 2 (TLS) progress
    _progressSubscription = _configTester.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() {
        if (progress.phase == ScanPhaseType.tcp) {
          _currentPhase = 'Phase 1: TCP Pre-filter';
          _phase0Tested = progress.processedIPs;
          _phase0Total = progress.totalIPs;
          _phase0Success = progress.successfulIPs;
        } else {
          _currentPhase = 'Phase 2: TLS Testing';
          _phase1Tested = progress.processedIPs;
          _phase1Total = progress.totalIPs;
          _phase1Success = progress.successfulIPs;
          _phase1PassLabel = progress.passLabel;
        }
      });
    });

    // Phase 3 progress
    _phase2ProgressSubscription = _scanner.phase2ProgressStream.listen((
      progress,
    ) {
      if (!mounted) return;
      setState(() {
        _currentPhase = 'Phase 3: Proxy Testing';
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
    final shouldAutoApply = await _storage.getAutoApplyAfterScan();
    var finalResult = result;

    if (shouldAutoApply && result.workingIPs.isNotEmpty) {
      final outcome = await _autoApplyWorkingIPs(result.workingIPs);
      if (outcome.message != null) {
        finalResult = result.copyWith(
          autoApplyStatus: outcome.message,
          autoApplySucceeded: outcome.success,
        );
      }
    } else if (shouldAutoApply && result.workingIPs.isEmpty) {
      finalResult = result.copyWith(
        autoApplyStatus: 'Auto-apply enabled, but no working IPs were found.',
        autoApplySucceeded: false,
      );
    }

    await _storage.saveInt(_keyLastScanElapsedMs, _elapsed.inMilliseconds);
    await _storage.remove(_keyActiveScanStartMs);
    await _storage.saveLastScanResult(finalResult.toJson());
    _stopElapsedTimer();
    await _progressSubscription?.cancel();
    await _phase2ProgressSubscription?.cancel();
    await _completionSubscription?.cancel();
    _progressSubscription = null;
    _phase2ProgressSubscription = null;
    _completionSubscription = null;

    final wasCancelling = _isCancelling;
    _log.logOk(
      wasCancelling
          ? 'Scan cancelled - showing partial results'
          : 'Config scan completed successfully',
    );

    if (finalResult.workingIPCount > 0 || wasCancelling) {
      if (mounted) {
        setState(() {
          _currentPhase = wasCancelling ? 'Cancelled' : 'Complete';
          _isScanning = false;
          _isCancelling = false;
        });

        // ignore: use_build_context_synchronously
        Navigator.pushReplacementNamed(
          context,
          '/results',
          arguments: finalResult,
        );
      }
    } else {
      if (mounted) {
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
  }

  Future<_AutoApplyOutcome> _autoApplyWorkingIPs(
    List<String> workingIPs,
  ) async {
    _log.logInfo(
      'Auto-apply enabled: updating BPB with ${workingIPs.length} working IPs',
    );
    _setStateIfMounted(() {
      _currentPhase = 'Auto-applying updates to BPB panel...';
    });

    final mode = await _storage.getUpdateMode();

    try {
      if (mode == UpdateMode.cloudflareApi) {
        final credentials = await _storage.getCredentials();
        if (credentials == null) {
          _log.logWarn(
            'Auto-apply skipped: Cloudflare API credentials are not configured',
          );
          return const _AutoApplyOutcome(
            message:
                'Auto-apply skipped: Cloudflare API credentials are not configured.',
            success: false,
          );
        }
        await _cloudflareApi.updateCleanIPs(credentials, workingIPs);
      } else {
        final credentials = await _storage.getPanelCredentials();
        if (credentials == null) {
          _log.logWarn(
            'Auto-apply skipped: Panel API credentials are not configured',
          );
          return const _AutoApplyOutcome(
            message:
                'Auto-apply skipped: Panel API credentials are not configured.',
            success: false,
          );
        }
        await _panelApi
            .updateCleanIPs(credentials, workingIPs)
            .timeout(const Duration(seconds: 45));
      }

      _log.logOk('Auto-apply completed successfully');
      return _AutoApplyOutcome(
        message:
            'Auto-apply completed successfully via ${mode.displayName}. New settings may take up to 60 seconds to propagate.',
        success: true,
      );
    } catch (e, stackTrace) {
      if (mode == UpdateMode.panelApi && _panelApi.isConnectivityError(e)) {
        _log.logWarn(
          'Auto-apply failed: panel unreachable from current network. '
          'Switch to Cloudflare API mode for updates.',
        );
        return const _AutoApplyOutcome(
          message:
              'Auto-apply failed: panel is not reachable from this network. Switch Update Method to Cloudflare API.',
          success: false,
        );
      } else {
        _log.logError('Auto-apply failed: $e', e, stackTrace);
        return _AutoApplyOutcome(
          message: 'Auto-apply failed: $e',
          success: false,
        );
      }
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
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Scanner will complete shortly and navigate to results
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanning'),
        actions: const [LogsActionButton(currentRoute: '/scan-progress')],
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
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Scan in Progress',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
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
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                            ],
                          ),

                          // Phase 1: TCP Pre-filter
                          if (_phase0Total > 0) ...[
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Phase 1 (TCP):',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text('$_phase0Tested / $_phase0Total checked'),
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

                          // Phase 2: TLS Handshake
                          if (_phase1Total > 0) ...[
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _phase1PassLabel != null &&
                                          _phase1PassLabel != 'done'
                                      ? 'Phase 2 (TLS, Pass $_phase1PassLabel):'
                                      : 'Phase 2 (TLS):',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text('$_phase1Tested / $_phase1Total tested'),
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

                          // Phase 3 Progress
                          if (_phase2Total > 0) ...[
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Phase 3 (Proxy):',
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

class _AutoApplyOutcome {
  final String? message;
  final bool? success;

  const _AutoApplyOutcome({required this.message, required this.success});
}
