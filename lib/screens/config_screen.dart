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

  ScannerConfig _config = ScannerConfig();
  bool _isLoading = false;
  String _selectedPreset = 'Default';

  // Define all preset configurations
  final Map<String, ScannerConfig> _presets = {
    'Mobile': ScannerConfig.mobile(),
    'Desktop': ScannerConfig.desktop(),
    'Fast': ScannerConfig.fast(),
    'Thorough': ScannerConfig.thorough(),
    'Emulator': ScannerConfig.emulator(),
    'Default': ScannerConfig(),
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
    return a.threads == b.threads &&
        a.testCount == b.testCount &&
        a.downloadCount == b.downloadCount &&
        a.latencyLimit == b.latencyLimit &&
        a.speedLimit == b.speedLimit &&
        a.disableDownload == b.disableDownload &&
        a.httpingMode == b.httpingMode &&
        a.downloadTestTime == b.downloadTestTime &&
        a.testPort == b.testPort &&
        a.batchSize == b.batchSize &&
        a.targetCleanIPs == b.targetCleanIPs &&
        a.minAcceptableIPs == b.minAcceptableIPs &&
        a.maxTotalIPsToTest == b.maxTotalIPsToTest;
  }

  Future<void> _saveConfig() async {
    final errors = _config.validate();

    if (errors.isNotEmpty) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invalid Configuration'),
          content: Text(errors.join('\n')),
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
    _log.logOk('Scanner configuration saved');

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
    _log.logInfo('Loaded $presetName preset configuration');

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

                    // Important Notice
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
                                    'Goal-Based Scanning',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Scanner automatically tests batches of IPs until your target clean IP goal is met. '
                                    'Set your goal (Target Clean IPs) and safety limits (Max Total IPs to Test), then let the scanner find the best IPs for you!',
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

                    // Configuration Cards
                    Text(
                      'Performance',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildSlider(
                              'Threads',
                              _config.threads.toDouble(),
                              10,
                              500,
                              (value) => _updateConfig(
                                _config.copyWith(threads: value.toInt()),
                              ),
                              'Number of concurrent threads',
                            ),
                            _buildSlider(
                              'Test Count',
                              _config.testCount.toDouble(),
                              1,
                              20,
                              (value) => _updateConfig(
                                _config.copyWith(testCount: value.toInt()),
                              ),
                              'Number of tests per IP',
                            ),
                            _buildSlider(
                              'IPs to Scan for Speed',
                              _config.downloadCount.toDouble(),
                              1,
                              100,
                              (value) => _updateConfig(
                                _config.copyWith(downloadCount: value.toInt()),
                              ),
                              'Number of IPs to test for download speed (after latency filtering)',
                            ),
                            _buildSlider(
                              'Target Clean IPs',
                              _config.targetCleanIPs.toDouble(),
                              1,
                              50,
                              (value) => _updateConfig(
                                _config.copyWith(targetCleanIPs: value.toInt()),
                              ),
                              'Goal: Number of clean IPs to find (with good latency AND downloads)',
                            ),
                            _buildSlider(
                              'Minimum Acceptable IPs',
                              _config.minAcceptableIPs.toDouble(),
                              1,
                              _config.targetCleanIPs
                                  .toDouble(), // Dynamic max: can't exceed target
                              (value) => _updateConfig(
                                _config.copyWith(
                                  minAcceptableIPs: value.toInt(),
                                ),
                              ),
                              'Safety net: Minimum clean IPs to accept partial success',
                            ),
                            _buildSlider(
                              'Batch Size',
                              _config.batchSize.toDouble(),
                              50,
                              500,
                              (value) => _updateConfig(
                                _config.copyWith(batchSize: value.toInt()),
                              ),
                              'IPs per batch (WARNING: high values may crash mobile apps)',
                            ),
                            _buildSlider(
                              'Max Total IPs to Test',
                              _config.maxTotalIPsToTest.toDouble(),
                              100,
                              2000,
                              (value) => _updateConfig(
                                _config.copyWith(
                                  maxTotalIPsToTest: value.toInt(),
                                ),
                              ),
                              'Safety limit: Maximum total IPs across all batches',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'Thresholds',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildSlider(
                              'Latency Limit (ms)',
                              _config.latencyLimit.toDouble(),
                              50,
                              500,
                              (value) => _updateConfig(
                                _config.copyWith(latencyLimit: value.toInt()),
                              ),
                              'Maximum acceptable latency',
                            ),
                            _buildSlider(
                              'Latency Lower Limit (ms)',
                              _config.latencyLowerLimit.toDouble(),
                              10,
                              200,
                              (value) => _updateConfig(
                                _config.copyWith(
                                  latencyLowerLimit: value.toInt(),
                                ),
                              ),
                              'Minimum latency threshold',
                            ),
                            _buildSlider(
                              'Speed Limit (MB/s)',
                              _config.speedLimit.toDouble(),
                              1,
                              50,
                              (value) => _updateConfig(
                                _config.copyWith(speedLimit: value.toInt()),
                              ),
                              'Minimum download speed',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'Advanced',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildSlider(
                              'Download Test Time (sec)',
                              _config.downloadTestTime.toDouble(),
                              2,
                              30,
                              (value) => _updateConfig(
                                _config.copyWith(
                                  downloadTestTime: value.toInt(),
                                ),
                              ),
                              'Download test duration',
                            ),
                            _buildSlider(
                              'Test Port',
                              _config.testPort.toDouble(),
                              80,
                              8443,
                              (value) => _updateConfig(
                                _config.copyWith(testPort: value.toInt()),
                              ),
                              'Port for connectivity tests',
                            ),
                            SwitchListTile(
                              title: const Text('Disable Download Test'),
                              subtitle: const Text('Skip download speed tests'),
                              value: _config.disableDownload,
                              onChanged: (value) => _updateConfig(
                                _config.copyWith(disableDownload: value),
                              ),
                            ),
                            SwitchListTile(
                              title: const Text('HTTPing Mode'),
                              subtitle: const Text(
                                'Use HTTP ping instead of ICMP',
                              ),
                              value: _config.httpingMode,
                              onChanged: (value) => _updateConfig(
                                _config.copyWith(httpingMode: value),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(
              value.toInt().toString(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        Slider(
          value: value,
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
