import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/config_scan_result.dart';
import '../services/storage_service.dart';
import '../services/cloudflare_api_service.dart';
import '../services/config_generator_service.dart';
import '../services/log_service.dart';

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
  final ConfigGeneratorService _configGenerator =
      ConfigGeneratorService.instance;
  final LogService _log = LogService.instance;

  ConfigScanResult? _result;
  bool _isLoaded = false;
  bool _isUpdating = false;
  bool _isGenerating = false;

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
    if (args != null && args is ConfigScanResult) {
      setState(() {
        _result = args;
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

  Future<void> _updateBPBPanel() async {
    if (_result == null || _result!.workingIPs.isEmpty) {
      _showMessage('No working IPs to update', isError: true);
      return;
    }

    // Check credentials before showing loading state
    final credentials = await _storage.getCredentials();
    if (credentials == null) {
      if (mounted) _showNoCredentialsDialog();
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    _log.logInfo(
      'Updating BPB Panel with ${_result!.workingIPs.length} working IPs',
    );

    try {
      await _api.updateCleanIPs(credentials, _result!.workingIPs);

      if (!mounted) return;

      setState(() {
        _isUpdating = false;
      });

      _showMessage('Updated BPB Panel with ${_result!.workingIPs.length} IPs');
      _log.logOk('BPB Panel updated successfully');
    } catch (e, stackTrace) {
      _log.logError('Failed to update BPB Panel: $e\n$stackTrace');

      if (!mounted) return;

      setState(() {
        _isUpdating = false;
      });

      _showMessage('Failed to update: $e', isError: true);
    }
  }

  void _showNoCredentialsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Credentials Required'),
        content: const Text(
          'Cloudflare credentials are not configured.\n\n'
          'Please enter your API token, account ID, and KV namespace ID in Settings.',
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

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: color ?? Theme.of(context).primaryColor,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
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

  @override
  Widget build(BuildContext context) {
    if (_result == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Config Scan Results')),
        body: const Center(child: Text('No results available')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Config Scan Results'),
        actions: [
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
                          'Scan completed in ${_result!.scanDuration.inSeconds} seconds',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

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
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isUpdating ? null : _updateBPBPanel,
                          icon: _isUpdating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_upload),
                          label: Text(
                            _isUpdating ? 'Updating...' : 'Update BPB Panel',
                          ),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 50),
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
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
              Text('Duration: ${_result!.scanDuration.inSeconds}s'),
              Text('Timestamp: ${_formatDateTime(_result!.timestamp)}'),
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
