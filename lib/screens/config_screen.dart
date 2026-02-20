import 'package:flutter/material.dart';
import '../models/xray_config.dart';
import '../services/storage_service.dart';
import '../services/log_service.dart';
import '../services/subscription_service.dart';
import '../widgets/logs_action_button.dart';

/// Simple configuration screen - just the essentials
///
/// User enters their BPB Panel URL and adjusts scan settings.
/// Config fetching/caching happens automatically during scan.
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final StorageService _storage = StorageService.instance;
  final LogService _log = LogService.instance;
  final SubscriptionService _subscription = SubscriptionService.instance;
  final TextEditingController _urlController = TextEditingController();

  bool _isLoading = false;
  bool _saveUrl = false;
  int _desiredIPCount = 5;
  int _phase2TestDepth = 50;
  bool _enableIPv6 = false; // Default to OFF
  bool _fullScan = false; // Default: use depth slider, not all survivors
  int _ipPoolSize = 1000; // default: 1000 IPs total
  int _batchSize = 200; // default: 200 concurrent connections
  List<XrayConfig>? _cachedConfigs;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);

    final url = await _storage.getSubscriptionUrl();
    final params = await _storage.getScanParameters();
    final fullScan = await _storage.getFullScan();
    final cachedConfigsJson = await _storage.getCachedConfigs();

    // Convert JSON to XrayConfig objects
    List<XrayConfig>? configs;
    if (cachedConfigsJson != null) {
      configs = cachedConfigsJson
          .map((json) => XrayConfig.fromJson(json as Map<String, dynamic>))
          .toList();
    }

    setState(() {
      if (url != null && url.isNotEmpty) {
        _urlController.text = url;
        _saveUrl = true;
      }
      _desiredIPCount = params['desiredIPCount'] ?? 5;
      _phase2TestDepth = params['phase2TestDepth'] ?? 50;
      _enableIPv6 = params['enableIPv6'] == 1; // 1 = true, 0/null = false
      _ipPoolSize = params['ipPoolSize'] ?? 1000;
      _batchSize = params['scanBatchSize'] ?? 200;
      _fullScan = fullScan;
      _cachedConfigs = configs;
      _isLoading = false;
    });
  }

  Future<void> _testAndCacheConfigs() async {
    final url = _urlController.text.trim();

    if (url.isEmpty) {
      _showError('Please enter a subscription URL first');
      return;
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      _showError('URL must start with http:// or https://');
      return;
    }

    setState(() => _isLoading = true);

    try {
      _log.logInfo('Testing connection to subscription URL...');

      final configs = await _subscription.fetchConfigs(url);

      if (configs.isEmpty) {
        setState(() => _isLoading = false);
        _showError(
          'No valid configs found in the subscription.\n\nPlease check your URL.',
        );
        return;
      }

      // Cache the configs
      await _storage.saveCachedConfigs(configs);

      // Auto-save the URL since it's working
      await _storage.saveSubscriptionUrl(url);

      setState(() {
        _cachedConfigs = configs;
        _saveUrl = true; // Auto-check "Remember this URL"
        _isLoading = false;
      });

      _log.logOk('Successfully fetched and cached ${configs.length} configs');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Success! Cached ${configs.length} configs'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      _log.logError('Failed to fetch configs: $e');
      setState(() => _isLoading = false);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('Connection Failed'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Could not fetch configs from the URL.'),
              const SizedBox(height: 12),
              Text(
                'Error: $e',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please check:\n'
                '• Your internet connection\n'
                '• The URL is correct\n'
                '• The URL is accessible',
              ),
            ],
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
  }

  Future<void> _saveConfig() async {
    final url = _urlController.text.trim();

    // Validate URL format if provided
    if (url.isNotEmpty &&
        !url.startsWith('http://') &&
        !url.startsWith('https://')) {
      _showError('URL must start with http:// or https://');
      return;
    }

    // Warn if no URL provided
    if (url.isEmpty) {
      final shouldContinue = await _showConfirmDialog(
        'No Subscription URL',
        'You haven\'t entered a subscription URL. You won\'t be able to scan without it.\n\nContinue anyway?',
      );
      if (!shouldContinue) return;
    }

    // Save subscription URL only if checkbox is checked
    if (_saveUrl && url.isNotEmpty) {
      await _storage.saveSubscriptionUrl(url);
      _log.logInfo('Saved subscription URL');
    }
    // Note: We don't clear the URL if checkbox is unchecked
    // This allows users to keep their saved URL even if they
    // temporarily uncheck the box

    // Save scan parameters
    await _storage.saveScanParameters(
      desiredIPCount: _desiredIPCount,
      phase2TestDepth: _phase2TestDepth,
      enableIPv6: _enableIPv6 ? 1 : 0,
      ipPoolSize: _ipPoolSize,
      scanBatchSize: _batchSize,
      fullScan: _fullScan,
    );

    _log.logOk('Configuration saved successfully');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuration saved'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invalid Input'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showConfirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showHelp(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _viewCachedConfigs() {
    if (_cachedConfigs == null || _cachedConfigs!.isEmpty) return;

    // Count configs by type
    final Map<String, int> typeCounts = {};
    final List<String> endpoints = [];

    for (final config in _cachedConfigs!) {
      // Count by type
      final type = config.getProtocol()?.toUpperCase() ?? 'Unknown';
      typeCounts[type] = (typeCounts[type] ?? 0) + 1;

      // Get first 5 endpoints as examples
      if (endpoints.length < 5) {
        final address = config.getServerAddress() ?? 'unknown';
        final port = config.getServerPort()?.toString() ?? '?';
        endpoints.add('$address:$port');
      }
    }

    // Build type summary
    final typeSummary = typeCounts.entries
        .map((e) => '${e.value} ${e.key}')
        .join(', ');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.storage, color: Colors.green),
            SizedBox(width: 8),
            Text('Cached Configs'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total: ${_cachedConfigs!.length} configs',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Text('Types: $typeSummary', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              const Text(
                'Sample endpoints:',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ...endpoints.map(
                (endpoint) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text(
                    '• $endpoint',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
              if (_cachedConfigs!.length > 5)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text(
                    '... and ${_cachedConfigs!.length - 5} more',
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuration'),
        actions: [
          const LogsActionButton(),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save',
            onPressed: _saveConfig,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // BPB Panel URL Section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.link, color: Colors.blue),
                                const SizedBox(width: 8),
                                Text(
                                  'BPB Panel URL',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _urlController,
                              decoration: const InputDecoration(
                                hintText: 'https://your-bpb-panel.com/sub/...',
                                border: OutlineInputBorder(),
                                labelText: 'Subscription URL',
                                helperText:
                                    'Your BPB Panel subscription link. Auto-populated when Panel API settings are saved.',
                                helperMaxLines: 2,
                              ),
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              maxLines: 3,
                              minLines: 1,
                            ),
                            const SizedBox(height: 16),

                            // Test Connection Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _isLoading
                                    ? null
                                    : _testAndCacheConfigs,
                                icon: _isLoading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.cloud_download),
                                label: Text(
                                  _isLoading
                                      ? 'Testing...'
                                      : 'Test & Cache Configs',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Cache status indicator
                            if (_cachedConfigs != null)
                              Builder(
                                builder: (context) {
                                  final cs = Theme.of(context).colorScheme;
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: cs.secondaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: cs.secondary,
                                        width: 1,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.check_circle,
                                              color: cs.onSecondaryContainer,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Cached: ${_cachedConfigs!.length} configs ready to use',
                                                style: TextStyle(
                                                  color:
                                                      cs.onSecondaryContainer,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: double.infinity,
                                          child: TextButton.icon(
                                            onPressed: _viewCachedConfigs,
                                            icon: const Icon(
                                              Icons.visibility,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              'View Cached Configs',
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor:
                                                  cs.onSecondaryContainer,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),

                            const SizedBox(height: 12),
                            CheckboxListTile(
                              value: _saveUrl,
                              onChanged: (value) {
                                setState(() => _saveUrl = value ?? false);
                              },
                              title: const Text('Remember this URL'),
                              subtitle: const Text('Save for next time'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Scan Settings Section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.tune, color: Colors.green),
                                const SizedBox(width: 8),
                                Text(
                                  'Scan Settings',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // How many working IPs to find
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Working IPs to find',
                                  style: TextStyle(fontSize: 16),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$_desiredIPCount',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                    ),
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
                              onChanged: (value) {
                                setState(() => _desiredIPCount = value.round());
                              },
                            ),
                            Text(
                              'Scan stops after finding this many working IPs',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 24),

                            // How thorough the scan should be
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Scan depth',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.help_outline,
                                        size: 20,
                                      ),
                                      onPressed: () => _showHelp(
                                        'What is Scan Depth?',
                                        'The scanner works in 2 phases:\n\n'
                                            'Phase 1: Quick TLS test on hundreds of IPs (finds candidates)\n\n'
                                            'Phase 2: Deep proxy test on top candidates (finds working IPs)\n\n'
                                            'Scan depth controls how many candidates from Phase 1 get tested in Phase 2.\n\n'
                                            'Higher = more thorough but slower\n'
                                            'Lower = faster but might miss working IPs',
                                      ),
                                      tooltip: 'What is this?',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _fullScan ? 'All' : '$_phase2TestDepth',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              value: _phase2TestDepth.toDouble(),
                              min: 20,
                              max: 100,
                              divisions: 8,
                              label: '$_phase2TestDepth candidates',
                              onChanged: _fullScan
                                  ? null
                                  : (value) {
                                      setState(
                                        () => _phase2TestDepth = value.round(),
                                      );
                                    },
                            ),
                            Text(
                              _fullScan
                                  ? 'Full scan — tests all Phase 1 survivors in Phase 2'
                                  : _phase2TestDepth < 40
                                  ? 'Fast scan (may miss some working IPs)'
                                  : _phase2TestDepth < 70
                                  ? 'Balanced (recommended)'
                                  : 'Thorough scan (slower but more reliable)',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              value: _fullScan,
                              onChanged: (value) {
                                setState(() => _fullScan = value ?? false);
                              },
                              title: const Text('Full scan mode'),
                              subtitle: Text(
                                _fullScan
                                    ? 'Tests every Phase 1 survivor in Phase 2 (most thorough, slower)'
                                    : 'Enable to test all Phase 1 IPs instead of capping at depth slider',
                              ),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            const SizedBox(height: 24),

                            // IP Pool Size
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'IP pool size',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.help_outline,
                                        size: 20,
                                      ),
                                      onPressed: () => _showHelp(
                                        'IP Pool Size',
                                        'Exactly how many Cloudflare IP addresses are loaded and tested in Phase 0 and Phase 1.\n\n'
                                            'IPs are distributed proportionally across all Cloudflare CIDR ranges — larger ranges receive more IPs.\n\n'
                                            'Higher = better chance of finding clean IPs, but Phase 1 takes longer.\n\n'
                                            'Default: 1000 IPs\n'
                                            'Recommended range: 500–2000',
                                      ),
                                      tooltip: 'What is this?',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$_ipPoolSize IPs',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              value: _ipPoolSize.toDouble(),
                              min: 100,
                              max: 5000,
                              divisions: 49,
                              label: '$_ipPoolSize IPs',
                              onChanged: (value) {
                                setState(() => _ipPoolSize = value.round());
                              },
                            ),
                            Text(
                              _ipPoolSize <= 300
                                  ? 'Minimal — very fast, best for slow networks'
                                  : _ipPoolSize <= 800
                                  ? 'Small pool — fast scan, good for testing'
                                  : _ipPoolSize <= 1500
                                  ? 'Medium pool — balanced (recommended)'
                                  : _ipPoolSize <= 3000
                                  ? 'Large pool — thorough, slower on mobile'
                                  : 'Maximum pool — comprehensive, use on desktop',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            const SizedBox(height: 24),

                            // Batch Size (concurrency)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Scan concurrency',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.help_outline,
                                        size: 20,
                                      ),
                                      onPressed: () => _showHelp(
                                        'Scan Concurrency',
                                        'How many IPs are tested simultaneously in Phase 0 (TCP) and Phase 1 (TLS).\n\n'
                                            'Higher = faster scan on good networks.\n'
                                            'Lower = better for slow or congested networks.\n\n'
                                            'Default: 200 concurrent connections',
                                      ),
                                      tooltip: 'What is this?',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$_batchSize',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              value: _batchSize.toDouble(),
                              min: 50,
                              max: 500,
                              divisions: 9,
                              label: '$_batchSize concurrent',
                              onChanged: (value) {
                                setState(() => _batchSize = value.round());
                              },
                            ),
                            Text(
                              _batchSize <= 50
                                  ? 'Conservative — for slow or very noisy networks'
                                  : _batchSize <= 150
                                  ? 'Low — suitable for limited-bandwidth connections'
                                  : _batchSize <= 250
                                  ? 'Default — good balance for most networks'
                                  : _batchSize <= 350
                                  ? 'High — for fast connections and strong hardware'
                                  : 'Maximum — for desktop on high-speed connections',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            const SizedBox(height: 24),

                            // IPv6 Toggle
                            Builder(
                              builder: (context) {
                                final cs = Theme.of(context).colorScheme;
                                return Container(
                                  decoration: BoxDecoration(
                                    color: _enableIPv6
                                        ? cs.primaryContainer
                                        : cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _enableIPv6
                                          ? cs.primary
                                          : cs.outlineVariant,
                                      width: 2,
                                    ),
                                  ),
                                  child: CheckboxListTile(
                                    value: _enableIPv6,
                                    onChanged: (value) {
                                      setState(
                                        () => _enableIPv6 = value ?? false,
                                      );
                                    },
                                    title: Row(
                                      children: [
                                        const Text(
                                          'Include IPv6 addresses',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.help_outline,
                                            size: 20,
                                          ),
                                          onPressed: () => _showHelp(
                                            'IPv6 Scanning',
                                            'Controls whether to include IPv6 addresses in the scan.\n\n'
                                                'OFF (Recommended): Only scan IPv4 addresses\n'
                                                '  - Faster scan (~700 IPs)\n'
                                                '  - Works for most users\n'
                                                '  - Sufficient for typical networks\n\n'
                                                'ON: Scan both IPv4 and IPv6 addresses\n'
                                                '  - Slower scan (~2100 IPs)\n'
                                                '  - More comprehensive\n'
                                                '  - Only needed if your network supports IPv6',
                                          ),
                                          tooltip: 'What is this?',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ],
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        _enableIPv6
                                            ? 'Comprehensive scan (IPv4 + IPv6, ~2100 IPs, slower)'
                                            : 'Fast scan (IPv4 only, ~700 IPs, recommended)',
                                        style: TextStyle(
                                          color: _enableIPv6
                                              ? cs.onPrimaryContainer
                                              : cs.onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Save Button
                    SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _saveConfig,
                        icon: const Icon(Icons.save),
                        label: const Text(
                          'Save Configuration',
                          style: TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
