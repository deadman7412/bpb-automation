import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/config_scan_result.dart';
import '../models/update_mode.dart';
import '../services/storage_service.dart';
import '../services/cloudflare_api_service.dart';
import '../services/panel_api_service.dart';
import '../services/config_generator_service.dart';
import '../services/log_service.dart';
import '../services/server_backend_service.dart';
import '../services/xray_service.dart';
import '../services/proxy_connectivity_debug_service.dart';
import '../models/xray_config.dart';
import '../widgets/logs_action_button.dart';

/// Screen for displaying config-based scan results
///
/// Shows Phase 1 (TLS) and Phase 2 (Proxy) test statistics,
/// and provides options to update BPB Panel or download configs.
class ConfigScanResultsScreen extends StatefulWidget {
  const ConfigScanResultsScreen({super.key});

  @override
  State<ConfigScanResultsScreen> createState() =>
      _ConfigScanResultsScreenState();
}

class _ConfigScanResultsScreenState extends State<ConfigScanResultsScreen> {
  final StorageService _storage = StorageService.instance;
  final CloudflareApiService _api = CloudflareApiService.instance;
  final PanelApiService _panelApi = PanelApiService.instance;
  final ConfigGeneratorService _configGenerator =
      ConfigGeneratorService.instance;
  final LogService _log = LogService.instance;
  final ServerBackendService _serverApi = ServerBackendService.instance;
  final XrayService _xrayService = XrayService.instance;
  final ProxyConnectivityDebugService _proxyDebugService =
      ProxyConnectivityDebugService.instance;
  static const String _keyLastScanElapsedMs = 'last_scan_elapsed_ms';

  ConfigScanResult? _result;
  Duration? _displayScanDuration;
  bool _isLoaded = false;
  bool _isUpdating = false;
  bool _isGenerating = false;
  bool _isCopying = false;
  bool _useServerBackend = false;
  bool _isServerLoading = false;
  Map<String, dynamic>? _serverLatest;
  String? _serverError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isLoaded) {
      _loadResults();
      _isLoaded = true;
    }
  }

  Future<void> _loadResults() async {
    final args = ModalRoute.of(context)?.settings.arguments;
    final useServerBackend = await _storage.getUseServerBackend();
    if (useServerBackend) {
      await _loadServerLatest();
      return;
    }
    _useServerBackend = false;
    final savedElapsedMs = await _storage.getInt(_keyLastScanElapsedMs);
    final savedDuration = savedElapsedMs != null
        ? Duration(milliseconds: savedElapsedMs)
        : null;

    if (args != null && args is ConfigScanResult) {
      setState(() {
        _result = args;
        _displayScanDuration = savedDuration;
      });
      _log.logInfo(
        'Loaded config scan result with ${_result!.workingIPCount} working IPs',
      );
    } else {
      _log.logInfo('No route argument — trying persistent storage');
      final resultJson = await _storage.getLastScanResult();
      if (resultJson != null) {
        try {
          setState(() {
            _result = ConfigScanResult.fromJson(resultJson);
            _displayScanDuration = savedDuration;
          });
          _log.logInfo(
            'Loaded saved scan result with ${_result!.workingIPCount} working IPs',
          );
        } catch (e) {
          _log.logWarn('Failed to parse saved scan result: $e');
        }
      } else {
        _log.logWarn('No config scan result available');
      }
    }
  }

  Future<void> _loadServerLatest() async {
    setState(() {
      _useServerBackend = true;
      _isServerLoading = true;
      _serverError = null;
    });

    final baseUrl = (await _storage.getServerBackendBaseUrl())?.trim() ?? '';
    final authToken = kIsWeb
        ? (await _storage.getServerBackendJwt())?.trim() ?? ''
        : '';
    if (baseUrl.isEmpty) {
      setState(() {
        _isServerLoading = false;
        _serverError = 'Server backend URL is not set in Settings.';
      });
      return;
    }
    if (kIsWeb && authToken.isEmpty) {
      setState(() {
        _isServerLoading = false;
        _serverError = 'Web login required. Open Settings and sign in.';
      });
      return;
    }

    try {
      final latest = await _serverApi.getLatestResult(
        baseUrl: baseUrl,
        authToken: authToken,
      );
      if (!mounted) return;
      setState(() {
        _serverLatest = latest;
        _isServerLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isServerLoading = false;
        _serverError = e.toString();
      });
    }
  }

  Duration get _effectiveScanDuration {
    if (_displayScanDuration != null && _displayScanDuration! > Duration.zero) {
      return _displayScanDuration!;
    }
    return _result?.scanDuration ?? Duration.zero;
  }

  Future<void> _updateBPBPanel() async {
    if (_result == null || _result!.workingIPs.isEmpty) {
      _showMessage('No working IPs to update', isError: true);
      return;
    }

    final updateMode = await _storage.getUpdateMode();

    setState(() {
      _isUpdating = true;
    });

    _log.logInfo(
      'Updating BPB Panel with ${_result!.workingIPs.length} working IPs',
    );

    try {
      final runProxyConnectivityDebug = await _storage
          .getDebugRunProxyConnectivityOnApply();
      bool useProxyForPanelUpdate = false;
      bool forceCleanIpsForPanelUpdate = false;
      bool useProxyForCloudflareEch = false;

      if (updateMode == UpdateMode.panelApi) {
        useProxyForPanelUpdate = await _storage.getPanelUseProxyForUpdate();
        forceCleanIpsForPanelUpdate = await _storage
            .getPanelForceCleanIpsForUpdate();
      } else {
        useProxyForCloudflareEch = await _storage.getCloudflareTryEchViaProxy();
      }

      final shouldRunProxyConnectivityDebug =
          runProxyConnectivityDebug &&
          ((updateMode == UpdateMode.panelApi && useProxyForPanelUpdate) ||
              (updateMode == UpdateMode.cloudflareApi &&
                  useProxyForCloudflareEch));

      _log.logInfo(
        '[Apply proxy debug] Setting is ${runProxyConnectivityDebug ? "ON" : "OFF"}',
      );
      if (runProxyConnectivityDebug && !shouldRunProxyConnectivityDebug) {
        if (updateMode == UpdateMode.panelApi) {
          _log.logInfo(
            '[Apply proxy debug] Skipped: panel proxy update is disabled in settings',
          );
        } else {
          _log.logInfo(
            '[Apply proxy debug] Skipped: ECH proxy fallback is disabled in settings',
          );
        }
      }
      if (shouldRunProxyConnectivityDebug) {
        await _runProxyConnectivityDebugOnApply(
          _result!.workingIPs,
          _result!.templateConfig,
        );
      }

      if (updateMode == UpdateMode.cloudflareApi) {
        final credentials = await _storage.getCredentials();
        if (credentials == null) {
          if (mounted) _showNoCredentialsDialog(UpdateMode.cloudflareApi);
          return;
        }
        await _api.updateCleanIPs(credentials, _result!.workingIPs);
      } else {
        final credentials = await _storage.getPanelCredentials();
        if (credentials == null) {
          if (mounted) _showNoCredentialsDialog(UpdateMode.panelApi);
          return;
        }
        final enablePanelProxyDiagnostics = await _storage
            .getPanelEnableProxyDiagnostics();
        if (useProxyForPanelUpdate) {
          _log.logInfo(
            'Panel API update is using Xray proxy mode (diagnostics: ${enablePanelProxyDiagnostics ? "on" : "off"})',
          );
          await _panelApi
              .updateCleanIPsViaXrayProxy(
                credentials,
                _result!.workingIPs,
                enableDiagnostics: enablePanelProxyDiagnostics,
                templateConfig: _result!.templateConfig,
              )
              .timeout(const Duration(seconds: 120));
        } else if (forceCleanIpsForPanelUpdate) {
          _log.logInfo(
            'Panel API update is using forced clean IP routing mode (${_result!.workingIPs.length} candidate(s))',
          );
          await _panelApi
              .updateCleanIPsViaForcedCleanIPs(
                credentials,
                _result!.workingIPs,
                candidateIPs: _result!.workingIPs,
              )
              .timeout(const Duration(seconds: 120));
        } else {
          // Hard timeout so UI never appears stuck forever when panel route is bad.
          await _panelApi
              .updateCleanIPs(credentials, _result!.workingIPs)
              .timeout(const Duration(seconds: 45));
        }
      }

      if (!mounted) return;

      _showMessage(
        'Updated BPB Panel with ${_result!.workingIPs.length} IPs. '
        'Wait ~60s for KV to propagate, then refresh your subscription.',
      );
      _log.logOk('BPB Panel updated successfully');
    } catch (e, stackTrace) {
      _log.logError('Failed to update BPB Panel: $e\n$stackTrace');

      if (!mounted) return;

      setState(() {
        _isUpdating = false;
      });

      final shouldSuggestCloudflare =
          updateMode == UpdateMode.panelApi && _panelApi.isConnectivityError(e);
      if (shouldSuggestCloudflare) {
        _showPanelUnreachableDialog();
      } else {
        _showMessage('Failed to update: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _runProxyConnectivityDebugOnApply(
    List<String> candidateIPs,
    XrayConfig templateConfig,
  ) async {
    final trimmedCandidates = candidateIPs
        .where((ip) => ip.trim().isNotEmpty)
        .take(2)
        .toList();
    if (trimmedCandidates.isEmpty) {
      _log.logWarn(
        '[Apply proxy debug] No candidate IPs available for connectivity diagnostics',
      );
      return;
    }

    final config = templateConfig;

    final dohHost = await _resolveDoHDebugHost();
    _log.logInfo(
      '[Apply proxy debug] Running SOCKS connectivity diagnostics '
      '(target host: $dohHost, candidates: ${trimmedCandidates.join(", ")})',
    );
    var successCount = 0;
    var totalChecks = 0;

    for (final candidate in trimmedCandidates) {
      try {
        _log.logInfo(
          '[Apply proxy debug][$candidate] Starting diagnostics suite',
        );
        final results = await _xrayService
            .runWithSocksProxy<List<ProxyConnectivityCheckResult>>(
              config: config,
              candidateIP: candidate,
              action: (socksPort) => _proxyDebugService.runSuite(
                socksPort: socksPort,
                dohQueryHost: dohHost,
              ),
            );
        for (final r in results) {
          totalChecks += 1;
          if (r.success) {
            successCount += 1;
            _log.logOk(
              '[Apply proxy debug][$candidate] ${r.name}: OK (HTTP ${r.statusCode ?? 0})',
            );
          } else {
            _log.logWarn(
              '[Apply proxy debug][$candidate] ${r.name}: FAIL '
              '${r.statusCode != null ? "(HTTP ${r.statusCode}) " : ""}${r.error ?? ""}',
            );
          }
        }
      } catch (e, stackTrace) {
        _log.logWarn('[Apply proxy debug][$candidate] Diagnostics failed: $e');
        _log.logError('[Apply proxy debug] stack', e, stackTrace);
      }
    }

    _log.logInfo(
      '[Apply proxy debug] Completed: $successCount/$totalChecks checks passed',
    );
  }

  Future<String> _resolveDoHDebugHost() async {
    final panelCredentials = await _storage.getPanelCredentials();
    if (panelCredentials != null) {
      final panelUri = Uri.tryParse(panelCredentials.baseUrl);
      if (panelUri != null && panelUri.host.isNotEmpty) {
        return panelUri.host;
      }
    }
    final subscriptionUrl = await _storage.getSubscriptionUrl();
    if (subscriptionUrl != null && subscriptionUrl.isNotEmpty) {
      final subUri = Uri.tryParse(subscriptionUrl);
      if (subUri != null && subUri.host.isNotEmpty) {
        return subUri.host;
      }
    }
    return 'example.com';
  }

  void _showPanelUnreachableDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Panel Not Reachable'),
        content: const Text(
          'Panel API is not reachable from your current network.\n\n'
          'Use Cloudflare API mode instead:\n'
          '1. Go to Settings\n'
          '2. Choose Update Method: Cloudflare API\n'
          '3. Save/validate Cloudflare credentials\n'
          '4. Return to Results and tap Update BPB Panel again',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/settings');
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showNoCredentialsDialog(UpdateMode mode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Credentials Required'),
        content: Text(
          mode == UpdateMode.cloudflareApi
              ? 'Cloudflare credentials are not configured.\n\n'
                    'Please enter your API token, account ID, and KV namespace ID in Settings.'
              : 'Panel API credentials are not configured.\n\n'
                    'Please enter your panel base URL and panel password in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/settings');
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadConfigs() async {
    if (_result == null || _result!.workingIPs.isEmpty) {
      _showMessage('No working IPs to generate configs', isError: true);
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    _log.logInfo(
      '[INFO] Generating configs for ${_result!.workingIPs.length} working IPs',
    );

    try {
      // Generate configs
      final configs = await _configGenerator.generateConfigsWithIPs(
        template: _result!.templateConfig,
        workingIPs: _result!.workingIPs,
      );

      if (configs.isEmpty) {
        throw Exception('Failed to generate configs');
      }

      // Share configs (download on web, share sheet on mobile/desktop)
      final success = await _configGenerator.shareConfigs(
        configs,
        subject: 'BPB Panel Configs (${configs.length} IPs)',
      );

      if (!mounted) return;

      setState(() {
        _isGenerating = false;
      });

      if (success) {
        _showMessage('Configs generated and shared successfully');
        _log.logOk('${configs.length} configs generated and shared');
      } else {
        _showMessage('Failed to share configs', isError: true);
      }
    } catch (e, stackTrace) {
      _log.logError('Failed to generate configs: $e\n$stackTrace');

      if (!mounted) return;

      setState(() {
        _isGenerating = false;
      });

      _showMessage('Failed to generate configs: $e', isError: true);
    }
  }

  Future<void> _copyConfigs() async {
    if (_result == null || _result!.workingIPs.isEmpty) {
      _showMessage('No working IPs to generate configs', isError: true);
      return;
    }

    setState(() {
      _isCopying = true;
    });

    _log.logInfo(
      'Copying configs for ${_result!.workingIPs.length} working IPs to clipboard',
    );

    try {
      final configs = await _configGenerator.generateConfigsWithIPs(
        template: _result!.templateConfig,
        workingIPs: _result!.workingIPs,
      );

      if (configs.isEmpty) {
        throw Exception('Failed to generate configs');
      }

      final jsonString = _configGenerator.exportConfigsAsJSON(configs);
      await Clipboard.setData(ClipboardData(text: jsonString));

      if (!mounted) return;

      setState(() {
        _isCopying = false;
      });

      _showMessage('${configs.length} configs copied to clipboard');
      _log.logOk('${configs.length} configs copied to clipboard');
    } catch (e, stackTrace) {
      _log.logError('Failed to copy configs: $e\n$stackTrace');

      if (!mounted) return;

      setState(() {
        _isCopying = false;
      });

      _showMessage('Failed to copy configs: $e', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: isError ? 4 : 6),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon, {
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = color ?? cs.onSurfaceVariant;
    final valueColor = color ?? cs.onSurface;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, size: 32, color: iconColor),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerServerRun() async {
    final baseUrl = (await _storage.getServerBackendBaseUrl())?.trim() ?? '';
    final token = kIsWeb
        ? (await _storage.getServerBackendJwt())?.trim() ?? ''
        : (await _storage.getServerBackendToken())?.trim() ?? '';
    if (baseUrl.isEmpty || token.isEmpty) {
      _showMessage(
        kIsWeb
            ? 'Set server backend URL and sign in from Settings first.'
            : 'Set server backend URL and token in Settings first.',
        isError: true,
      );
      return;
    }
    setState(() => _isUpdating = true);
    try {
      await _serverApi.triggerRun(baseUrl: baseUrl, token: token);
      _showMessage('Server run accepted');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _loadServerLatest();
    } catch (e) {
      _showMessage('Failed to trigger run: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  List<String> _serverIps() {
    final list = _serverLatest?['selected_ips'] as List<dynamic>? ?? const [];
    return list.map((e) => e.toString()).toList();
  }

  Widget _buildServerModeBody() {
    if (_isServerLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_serverError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(_serverError!, textAlign: TextAlign.center),
        ),
      );
    }

    if (_serverLatest == null) {
      return const Center(child: Text('No server results available'));
    }

    final status = _serverLatest!['status']?.toString() ?? 'unknown';
    final isPartial = status == 'partial';
    final isSuccess = status == 'success';
    final runId = _serverLatest!['run_id']?.toString() ?? '-';
    final durationMs = (_serverLatest!['duration_ms'] as num?)?.toInt() ?? 0;
    final phase1 = (_serverLatest!['phase1_passed'] as num?)?.toInt() ?? 0;
    final phase2 = (_serverLatest!['phase2_tested'] as num?)?.toInt() ?? 0;
    final working = (_serverLatest!['working_count'] as num?)?.toInt() ?? 0;
    final applied = _serverLatest!['applied'] == true;
    final ips = _serverIps();

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        isSuccess
                            ? Icons.check_circle
                            : (isPartial ? Icons.warning : Icons.error),
                        size: 56,
                        color: isSuccess
                            ? Colors.green
                            : (isPartial ? Colors.orange : Colors.red),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Latest Server Run: $status',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('Run ID: $runId'),
                      Text(
                        'Duration: ${(durationMs / 1000).toStringAsFixed(1)}s',
                      ),
                      Text('Applied: ${applied ? "Yes" : "No"}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  _buildStatCard('Phase 1 Passed', '$phase1', Icons.done),
                  _buildStatCard('Phase 2 Tested', '$phase2', Icons.verified),
                  _buildStatCard('Working IPs', '$working', Icons.cloud_done),
                  _buildStatCard(
                    'Status',
                    status,
                    isSuccess
                        ? Icons.check
                        : (isPartial ? Icons.warning : Icons.error),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isUpdating ? null : _triggerServerRun,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Trigger Server Run'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/server-history'),
                      icon: const Icon(Icons.history),
                      label: const Text('Open Run History'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/server-logs'),
                icon: const Icon(Icons.article),
                label: const Text('Open Server Logs'),
              ),
              const SizedBox(height: 16),
              if (ips.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Selected IPs',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: 'Copy all IPs',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: ips.join('\n')));
                        _showMessage('Copied ${ips.length} IPs');
                      },
                    ),
                  ],
                ),
                Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: ips.length,
                    separatorBuilder: (_, index) => const Divider(),
                    itemBuilder: (context, index) => ListTile(
                      title: Text(
                        ips[index],
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_useServerBackend) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Server Results'),
          actions: [
            const LogsActionButton(),
            IconButton(
              icon: const Icon(Icons.bug_report),
              tooltip: 'Debug & Diagnostics',
              onPressed: () => Navigator.pushNamed(context, '/debug'),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isServerLoading ? null : _loadServerLatest,
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: _buildServerModeBody(),
      );
    }

    if (_result == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Config Scan Results'),
          actions: [
            const LogsActionButton(),
            IconButton(
              icon: const Icon(Icons.bug_report),
              tooltip: 'Debug & Diagnostics',
              onPressed: () => Navigator.pushNamed(context, '/debug'),
            ),
          ],
        ),
        body: const Center(child: Text('No results available')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Config Scan Results'),
        actions: [
          const LogsActionButton(),
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Debug & Diagnostics',
            onPressed: () => Navigator.pushNamed(context, '/debug'),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Info',
            onPressed: _showResultInfo,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                // Summary Card
                Card(
                  color: _result!.workingIPCount > 0
                      ? Colors.green[50]
                      : Colors.orange[50],
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Icon(
                          _result!.workingIPCount > 0
                              ? Icons.check_circle
                              : Icons.warning,
                          size: 64,
                          color: _result!.workingIPCount > 0
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _result!.workingIPCount > 0
                              ? 'Found ${_result!.workingIPCount} Working IPs'
                              : 'No Working IPs Found',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _result!.workingIPCount > 0
                                    ? Colors.green[900]
                                    : Colors.orange[900],
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Scan completed in ${_effectiveScanDuration.inSeconds} seconds',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                if (_result!.autoApplyStatus != null) ...[
                  Builder(
                    builder: (context) {
                      final cs = Theme.of(context).colorScheme;
                      final isSuccess = _result!.autoApplySucceeded == true;
                      final bgColor = isSuccess
                          ? cs.secondaryContainer
                          : cs.tertiaryContainer;
                      final fgColor = isSuccess
                          ? cs.onSecondaryContainer
                          : cs.onTertiaryContainer;
                      final icon = isSuccess
                          ? Icons.check_circle
                          : Icons.info_outline;

                      return Card(
                        color: bgColor,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(icon, color: fgColor),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Auto Apply Status',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: fgColor,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _result!.autoApplyStatus!,
                                      style: TextStyle(color: fgColor),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],

                // Phase Statistics
                Text(
                  'Scan Statistics',
                  style: Theme.of(context).textTheme.titleLarge,
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
                    _buildStatCard(
                      'Phase 1 Tested',
                      '${_result!.totalTested}',
                      Icons.network_check,
                    ),
                    _buildStatCard(
                      'Phase 1 Passed',
                      '${_result!.phase1Passed}',
                      Icons.done,
                      color: Colors.blue,
                    ),
                    _buildStatCard(
                      'Phase 2 Tested',
                      '${_result!.phase2Tested}',
                      Icons.verified_user,
                    ),
                    _buildStatCard(
                      'Working IPs',
                      '${_result!.workingIPCount}',
                      Icons.check_circle,
                      color: Colors.green,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Working IPs List
                if (_result!.workingIPs.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Working IPs',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: 'Copy all IPs',
                        onPressed: _copyAllIPs,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _result!.workingIPs.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final ip = _result!.workingIPs[index];
                        final testResult = _result!.allResults.firstWhere(
                          (r) => r.ip == ip,
                        );

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(
                            ip,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                          subtitle: Text(
                            'Proxy: ${testResult.proxyTestResult?.latencyMs.toStringAsFixed(0) ?? "N/A"} ms',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            tooltip: 'Copy IP',
                            onPressed: () => _copyIP(ip),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Action Buttons
                if (_result!.workingIPCount > 0) ...[
                  Builder(
                    builder: (context) {
                      final alreadyApplied =
                          _result!.autoApplySucceeded == true;
                      final idleLabel = alreadyApplied
                          ? 'Already Applied - Apply Again'
                          : 'Update BPB Panel';
                      final busyLabel = alreadyApplied
                          ? 'Applying Again...'
                          : 'Updating...';
                      final idleIcon = alreadyApplied
                          ? const Icon(Icons.refresh)
                          : const Icon(Icons.cloud_upload);

                      return ElevatedButton.icon(
                        onPressed: _isUpdating ? null : _updateBPBPanel,
                        icon: _isUpdating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : idleIcon,
                        label: Text(_isUpdating ? busyLabel : idleLabel),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isGenerating ? null : _downloadConfigs,
                          icon: _isGenerating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download),
                          label: Text(
                            _isGenerating
                                ? 'Generating...'
                                : 'Download Configs',
                          ),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 50),
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isCopying ? null : _copyConfigs,
                          icon: _isCopying
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.copy),
                          label: Text(
                            _isCopying ? 'Copying...' : 'Copy Configs',
                          ),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 50),
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _copyIP(String ip) {
    Clipboard.setData(ClipboardData(text: ip));
    _showMessage('Copied: $ip');
  }

  void _copyAllIPs() {
    if (_result == null || _result!.workingIPs.isEmpty) return;

    final ipsText = _result!.workingIPs.join('\n');
    Clipboard.setData(ClipboardData(text: ipsText));
    _showMessage('Copied ${_result!.workingIPs.length} IPs to clipboard');
  }

  void _showResultInfo() {
    if (_result == null) return;

    final phase1SuccessRate =
        (_result!.phase1Passed / _result!.totalTested * 100).toStringAsFixed(1);
    final phase2SuccessRate = _result!.phase2Tested > 0
        ? (_result!.workingIPCount / _result!.phase2Tested * 100)
              .toStringAsFixed(1)
        : '0.0';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scan Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Protocol: ${_result!.templateConfig.getProtocol() ?? "Unknown"}',
              ),
              const SizedBox(height: 8),
              Text(
                'Security: ${_result!.templateConfig.isSecure() ? "TLS/Reality" : "None"}',
              ),
              const SizedBox(height: 16),
              const Text(
                'Phase 1 (TLS Testing):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('  Total tested: ${_result!.totalTested}'),
              Text('  Passed: ${_result!.phase1Passed} ($phase1SuccessRate%)'),
              const SizedBox(height: 12),
              const Text(
                'Phase 2 (Proxy Testing):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('  Total tested: ${_result!.phase2Tested}'),
              Text(
                '  Working: ${_result!.workingIPCount} ($phase2SuccessRate%)',
              ),
              const SizedBox(height: 12),
              Text('Duration: ${_effectiveScanDuration.inSeconds}s'),
              Text('Timestamp: ${_formatDateTime(_result!.timestamp)}'),
              if (_result!.autoApplyStatus != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Auto Apply:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('  ${_result!.autoApplyStatus}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
