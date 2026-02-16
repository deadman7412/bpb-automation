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
      _isLoading = false;
    });
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

  void _usePreset(ScannerConfig preset, String name) {
    setState(() => _config = preset);
    _log.logInfo('Loaded $name preset configuration');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name preset loaded')),
    );
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildPresetButton(
                          'Mobile',
                          Icons.phone_android,
                          () => _usePreset(ScannerConfig.mobile(), 'Mobile'),
                        ),
                        _buildPresetButton(
                          'Desktop',
                          Icons.computer,
                          () => _usePreset(ScannerConfig.desktop(), 'Desktop'),
                        ),
                        _buildPresetButton(
                          'Fast',
                          Icons.speed,
                          () => _usePreset(ScannerConfig.fast(), 'Fast'),
                        ),
                        _buildPresetButton(
                          'Thorough',
                          Icons.security,
                          () => _usePreset(ScannerConfig.thorough(), 'Thorough'),
                        ),
                        _buildPresetButton(
                          'Default',
                          Icons.restore,
                          () => _usePreset(ScannerConfig(), 'Default'),
                        ),
                      ],
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
                              (value) => setState(() => _config = _config.copyWith(threads: value.toInt())),
                              'Number of concurrent threads',
                            ),
                            _buildSlider(
                              'Test Count',
                              _config.testCount.toDouble(),
                              1,
                              20,
                              (value) => setState(() => _config = _config.copyWith(testCount: value.toInt())),
                              'Number of tests per IP',
                            ),
                            _buildSlider(
                              'IPs to Scan for Speed',
                              _config.downloadCount.toDouble(),
                              1,
                              100,
                              (value) => setState(() => _config = _config.copyWith(downloadCount: value.toInt())),
                              'Number of IPs to test for download speed (after latency filtering)',
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
                              (value) => setState(() => _config = _config.copyWith(latencyLimit: value.toInt())),
                              'Maximum acceptable latency',
                            ),
                            _buildSlider(
                              'Latency Lower Limit (ms)',
                              _config.latencyLowerLimit.toDouble(),
                              10,
                              200,
                              (value) => setState(() => _config = _config.copyWith(latencyLowerLimit: value.toInt())),
                              'Minimum latency threshold',
                            ),
                            _buildSlider(
                              'Speed Limit (MB/s)',
                              _config.speedLimit.toDouble(),
                              1,
                              50,
                              (value) => setState(() => _config = _config.copyWith(speedLimit: value.toInt())),
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
                              (value) => setState(() => _config = _config.copyWith(downloadTestTime: value.toInt())),
                              'Download test duration',
                            ),
                            _buildSlider(
                              'Test Port',
                              _config.testPort.toDouble(),
                              80,
                              8443,
                              (value) => setState(() => _config = _config.copyWith(testPort: value.toInt())),
                              'Port for connectivity tests',
                            ),
                            SwitchListTile(
                              title: const Text('Disable Download Test'),
                              subtitle: const Text('Skip download speed tests'),
                              value: _config.disableDownload,
                              onChanged: (value) => setState(() => _config = _config.copyWith(disableDownload: value)),
                            ),
                            SwitchListTile(
                              title: const Text('HTTPing Mode'),
                              subtitle: const Text('Use HTTP ping instead of ICMP'),
                              value: _config.httpingMode,
                              onChanged: (value) => setState(() => _config = _config.copyWith(httpingMode: value)),
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

  Widget _buildPresetButton(String label, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            Text(
              value.toInt().toString(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min).toInt(),
          onChanged: onChanged,
        ),
        Text(
          helperText,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
