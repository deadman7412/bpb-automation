import 'package:flutter/material.dart';
import '../models/scanner_config.dart';
import '../services/storage_service.dart';
import '../services/log_service.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final StorageService _storage = StorageService.instance;
  final LogService _log = LogService.instance;

  ScannerConfig _config = const ScannerConfig();
  bool _isLoading = false;
  String _selectedPreset = 'Default';

  // Define all preset configurations
  final Map<String, ScannerConfig> _presets = {
    'Mobile': ScannerConfig.mobile,
    'Desktop': ScannerConfig.desktop,
    'Fast': ScannerConfig.fast,
    'Balanced': ScannerConfig.balanced,
    'Quality': ScannerConfig.quality,
    'Default': const ScannerConfig(),
  };

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);

    final config = await _storage.getScannerConfig();

    setState(() {
      _config = config;
      _selectedPreset = _detectPreset(config);
      _isLoading = false;
    });
  }

  /// Detect which preset matches the current config, or return "Custom"
  String _detectPreset(ScannerConfig config) {
    for (final entry in _presets.entries) {
      if (_configsEqual(config, entry.value)) {
        return entry.key;
      }
    }
    return 'Custom';
  }

  /// Compare two configs for equality
  bool _configsEqual(ScannerConfig a, ScannerConfig b) {
    return a.targetCleanIPs == b.targetCleanIPs &&
        a.threads == b.threads &&
        a.maxLatency == b.maxLatency &&
        a.maxLossRate == b.maxLossRate &&
        a.minDownloadSpeed == b.minDownloadSpeed &&
        a.testCount == b.testCount &&
        a.testPort == b.testPort &&
        a.downloadTestTime == b.downloadTestTime &&
        a.downloadBytes == b.downloadBytes &&
        a.httpingMode == b.httpingMode &&
        a.maxIPsToTest == b.maxIPsToTest &&
        a.testAllIPs == b.testAllIPs;
  }

  Future<void> _saveConfig() async {
    final error = _config.validate();

    if (error != null) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invalid Configuration'),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    await _storage.saveScannerConfig(_config);
    _log.logOk('[OK] Scanner configuration saved');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuration saved successfully'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _usePreset(String presetName) {
    final preset = _presets[presetName];
    if (preset == null) return;

    setState(() {
      _config = preset;
      _selectedPreset = presetName;
    });
    _log.logInfo('[INFO] Loaded $presetName preset configuration');

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$presetName preset loaded')));
  }

  void _updateConfig(ScannerConfig newConfig) {
    setState(() {
      _config = newConfig;
      _selectedPreset = _detectPreset(newConfig);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner Configuration'),
        actions: [
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
                    // Presets Section
                    Text(
                      'Presets',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.tune),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DropdownButton<String>(
                                value: _selectedPreset,
                                isExpanded: true,
                                underline: const SizedBox(),
                                items: [
                                  ..._presets.keys.map(
                                    (name) => DropdownMenuItem(
                                      value: name,
                                      child: Text(name),
                                    ),
                                  ),
                                  const DropdownMenuItem(
                                    value: 'Custom',
                                    child: Text(
                                      'Custom',
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null && value != 'Custom') {
                                    _usePreset(value);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Algorithm Notice
                    Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.blue.shade700,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Go Scanner Algorithm',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'This scanner uses the proven algorithm from the Go scanner: '
                                    '(1) Load IPs, (2) Test all for latency, (3) Filter by loss/latency, '
                                    '(4) Test downloads serially with early exit, (5) Sort by speed. '
                                    'Set your target clean IPs and quality filters, then let it find the best IPs for you!',
                                    style: TextStyle(
                                      color: Colors.blue.shade900,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Essential Settings
                    Text(
                      'Essential Settings',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildSlider(
                              'Target Clean IPs',
                              _config.targetCleanIPs.toDouble(),
                              1,
                              50,
                              (value) => _updateConfig(
                                _config.copyWith(targetCleanIPs: value.toInt()),
                              ),
                              'Number of clean IPs to find (scanner stops when reached)',
                            ),
                            _buildSlider(
                              'Threads',
                              _config.threads.toDouble(),
                              50,
                              500,
                              (value) => _updateConfig(
                                _config.copyWith(threads: value.toInt()),
                              ),
                              'Concurrent threads for latency testing (higher = faster)',
                            ),
                            _buildSlider(
                              'Max Latency (ms)',
                              _config.maxLatency.toDouble(),
                              50,
                              9999,
                              (value) => _updateConfig(
                                ScannerConfig(
                                  targetCleanIPs: _config.targetCleanIPs,
                                  threads: _config.threads,
                                  maxLatency: value.toInt(),
                                  maxLossRate: _config.maxLossRate,
                                  minDownloadSpeed: _config.minDownloadSpeed,
                                  testCount: _config.testCount,
                                  testPort: _config.testPort,
                                  downloadTestTime: _config.downloadTestTime,
                                  downloadBytes: _config.downloadBytes,
                                  testUrl: _config.testUrl,
                                  httpingMode: _config.httpingMode,
                                  maxIPsToTest: _config.maxIPsToTest,
                                  testAllIPs: _config.testAllIPs,
                                ),
                              ),
                              'Maximum acceptable latency (IPs above this are filtered out)',
                            ),
                            _buildSlider(
                              'Max Loss Rate (%)',
                              (_config.maxLossRate * 100).toDouble(),
                              0,
                              100,
                              (value) => _updateConfig(
                                ScannerConfig(
                                  targetCleanIPs: _config.targetCleanIPs,
                                  threads: _config.threads,
                                  maxLatency: _config.maxLatency,
                                  maxLossRate: value / 100.0,
                                  minDownloadSpeed: _config.minDownloadSpeed,
                                  testCount: _config.testCount,
                                  testPort: _config.testPort,
                                  downloadTestTime: _config.downloadTestTime,
                                  downloadBytes: _config.downloadBytes,
                                  testUrl: _config.testUrl,
                                  httpingMode: _config.httpingMode,
                                  maxIPsToTest: _config.maxIPsToTest,
                                  testAllIPs: _config.testAllIPs,
                                ),
                              ),
                              'Maximum acceptable packet loss (0% = no loss, 100% = any loss)',
                            ),
                            _buildSlider(
                              'Min Download Speed (MB/s)',
                              _config.minDownloadSpeed,
                              0,
                              100,
                              (value) => _updateConfig(
                                ScannerConfig(
                                  targetCleanIPs: _config.targetCleanIPs,
                                  threads: _config.threads,
                                  maxLatency: _config.maxLatency,
                                  maxLossRate: _config.maxLossRate,
                                  minDownloadSpeed: value,
                                  testCount: _config.testCount,
                                  testPort: _config.testPort,
                                  downloadTestTime: _config.downloadTestTime,
                                  downloadBytes: _config.downloadBytes,
                                  testUrl: _config.testUrl,
                                  httpingMode: _config.httpingMode,
                                  maxIPsToTest: _config.maxIPsToTest,
                                  testAllIPs: _config.testAllIPs,
                                ),
                              ),
                              'Minimum download speed required (0 = no minimum)',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Advanced Settings
                    Text(
                      'Advanced Settings',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildSlider(
                              'Test Count',
                              _config.testCount.toDouble(),
                              1,
                              10,
                              (value) => _updateConfig(
                                ScannerConfig(
                                  targetCleanIPs: _config.targetCleanIPs,
                                  threads: _config.threads,
                                  maxLatency: _config.maxLatency,
                                  maxLossRate: _config.maxLossRate,
                                  minDownloadSpeed: _config.minDownloadSpeed,
                                  testCount: value.toInt(),
                                  testPort: _config.testPort,
                                  downloadTestTime: _config.downloadTestTime,
                                  downloadBytes: _config.downloadBytes,
                                  testUrl: _config.testUrl,
                                  httpingMode: _config.httpingMode,
                                  maxIPsToTest: _config.maxIPsToTest,
                                  testAllIPs: _config.testAllIPs,
                                ),
                              ),
                              'Number of latency tests per IP (more = more accurate)',
                            ),
                            _buildSlider(
                              'Download Test Time (sec)',
                              _config.downloadTestTime.toDouble(),
                              5,
                              60,
                              (value) => _updateConfig(
                                ScannerConfig(
                                  targetCleanIPs: _config.targetCleanIPs,
                                  threads: _config.threads,
                                  maxLatency: _config.maxLatency,
                                  maxLossRate: _config.maxLossRate,
                                  minDownloadSpeed: _config.minDownloadSpeed,
                                  testCount: _config.testCount,
                                  testPort: _config.testPort,
                                  downloadTestTime: value.toInt(),
                                  downloadBytes: _config.downloadBytes,
                                  testUrl: _config.testUrl,
                                  httpingMode: _config.httpingMode,
                                  maxIPsToTest: _config.maxIPsToTest,
                                  testAllIPs: _config.testAllIPs,
                                ),
                              ),
                              'Timeout for each download test',
                            ),
                            _buildSlider(
                              'Max IPs to Test',
                              _config.maxIPsToTest.toDouble(),
                              1000,
                              20000,
                              (value) => _updateConfig(
                                ScannerConfig(
                                  targetCleanIPs: _config.targetCleanIPs,
                                  threads: _config.threads,
                                  maxLatency: _config.maxLatency,
                                  maxLossRate: _config.maxLossRate,
                                  minDownloadSpeed: _config.minDownloadSpeed,
                                  testCount: _config.testCount,
                                  testPort: _config.testPort,
                                  downloadTestTime: _config.downloadTestTime,
                                  downloadBytes: _config.downloadBytes,
                                  testUrl: _config.testUrl,
                                  httpingMode: _config.httpingMode,
                                  maxIPsToTest: value.toInt(),
                                  testAllIPs: _config.testAllIPs,
                                ),
                              ),
                              'Safety limit: Maximum total IPs to test (prevents infinite scanning)',
                            ),
                            _buildSlider(
                              'Test Port',
                              _config.testPort.toDouble(),
                              80,
                              8443,
                              (value) => _updateConfig(
                                ScannerConfig(
                                  targetCleanIPs: _config.targetCleanIPs,
                                  threads: _config.threads,
                                  maxLatency: _config.maxLatency,
                                  maxLossRate: _config.maxLossRate,
                                  minDownloadSpeed: _config.minDownloadSpeed,
                                  testCount: _config.testCount,
                                  testPort: value.toInt(),
                                  downloadTestTime: _config.downloadTestTime,
                                  downloadBytes: _config.downloadBytes,
                                  testUrl: _config.testUrl,
                                  httpingMode: _config.httpingMode,
                                  maxIPsToTest: _config.maxIPsToTest,
                                  testAllIPs: _config.testAllIPs,
                                ),
                              ),
                              'Port for connectivity tests (443 = HTTPS, 80 = HTTP)',
                            ),
                            SwitchListTile(
                              title: const Text('HTTPing Mode'),
                              subtitle: const Text(
                                'Use HTTP ping instead of TCP (slower but more accurate)',
                              ),
                              value: _config.httpingMode,
                              onChanged: (value) => _updateConfig(
                                ScannerConfig(
                                  targetCleanIPs: _config.targetCleanIPs,
                                  threads: _config.threads,
                                  maxLatency: _config.maxLatency,
                                  maxLossRate: _config.maxLossRate,
                                  minDownloadSpeed: _config.minDownloadSpeed,
                                  testCount: _config.testCount,
                                  testPort: _config.testPort,
                                  downloadTestTime: _config.downloadTestTime,
                                  downloadBytes: _config.downloadBytes,
                                  testUrl: _config.testUrl,
                                  httpingMode: value,
                                  maxIPsToTest: _config.maxIPsToTest,
                                  testAllIPs: _config.testAllIPs,
                                ),
                              ),
                            ),
                            SwitchListTile(
                              title: const Text('Test All IPs'),
                              subtitle: const Text(
                                'Test all ~5956 IPs (slower, ~4 min) vs default ~696 IPs (faster, ~30 sec). '
                                'Default tests 1 random IP per /24 subnet, which is statistically valid due to Cloudflare Anycast.',
                              ),
                              value: _config.testAllIPs,
                              onChanged: (value) => _updateConfig(
                                ScannerConfig(
                                  targetCleanIPs: _config.targetCleanIPs,
                                  threads: _config.threads,
                                  maxLatency: _config.maxLatency,
                                  maxLossRate: _config.maxLossRate,
                                  minDownloadSpeed: _config.minDownloadSpeed,
                                  testCount: _config.testCount,
                                  testPort: _config.testPort,
                                  downloadTestTime: _config.downloadTestTime,
                                  downloadBytes: _config.downloadBytes,
                                  testUrl: _config.testUrl,
                                  httpingMode: _config.httpingMode,
                                  maxIPsToTest: _config.maxIPsToTest,
                                  testAllIPs: value,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    ElevatedButton.icon(
                      onPressed: _saveConfig,
                      icon: const Icon(Icons.save),
                      label: const Text('Save Configuration'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    String helperText,
  ) {
    // Calculate divisions safely - ensure it's positive
    final divisionCount = (max - min).toInt();
    final divisions = divisionCount > 0 ? divisionCount : null;

    // Format value display based on type
    String valueDisplay;
    if (label.contains('%')) {
      valueDisplay = '${value.toInt()}%';
    } else if (label.contains('MB/s')) {
      valueDisplay = '${value.toStringAsFixed(1)} MB/s';
    } else {
      valueDisplay = value.toInt().toString();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(
              valueDisplay,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
        Text(
          helperText,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
