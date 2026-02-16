import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../services/log_service.dart';
import '../services/storage_service.dart';
import '../services/cloudflare_api_service.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final LogService _log = LogService.instance;
  final StorageService _storage = StorageService.instance;
  final CloudflareApiService _cloudflareAPI = CloudflareApiService.instance;

  bool _isRunningTest = false;
  final List<String> _testResults = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug & Diagnostics'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // System Info Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'System Information',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow('Platform', Platform.operatingSystem),
                      _buildInfoRow('OS Version', Platform.operatingSystemVersion),
                      _buildInfoRow('Locale', Platform.localeName),
                      _buildInfoRow('Number of Processors', Platform.numberOfProcessors.toString()),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Network Diagnostics Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.network_check, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            'Network Diagnostics',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _isRunningTest ? null : _testDNSResolution,
                        icon: const Icon(Icons.dns),
                        label: const Text('Test DNS Resolution'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _isRunningTest ? null : _testCloudflareAPI,
                        icon: const Icon(Icons.cloud),
                        label: const Text('Test Cloudflare API'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _isRunningTest ? null : _testNetworkConnectivity,
                        icon: const Icon(Icons.wifi_find),
                        label: const Text('Full Network Test'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Test Results Card
              if (_testResults.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Test Results',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy),
                              tooltip: 'Copy to clipboard',
                              onPressed: _copyResultsToClipboard,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _testResults
                                .map((result) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4.0),
                                      child: Text(
                                        result,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          color: _getResultColor(result),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _clearResults,
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear Results'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Storage Debug Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.storage, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(
                            'Storage Debug',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _testCredentialsStorage,
                        icon: const Icon(Icons.key),
                        label: const Text('Test Credentials Storage'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _showStorageInfo,
                        icon: const Icon(Icons.info),
                        label: const Text('Show Storage Info'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Quick Actions Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Quick Actions',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pushNamed(context, '/logs'),
                        icon: const Icon(Icons.assignment),
                        label: const Text('View Full Logs'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _exportDebugInfo,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('Export Debug Info'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Color _getResultColor(String result) {
    if (result.contains('[OK]') || result.contains('✓') || result.contains('Success')) {
      return Colors.green;
    } else if (result.contains('[ERROR]') || result.contains('✗') || result.contains('Failed')) {
      return Colors.red;
    } else if (result.contains('[WARN]') || result.contains('Warning')) {
      return Colors.orange;
    } else {
      return Colors.white70;
    }
  }

  Future<void> _testDNSResolution() async {
    setState(() {
      _isRunningTest = true;
      _testResults.clear();
      _testResults.add('[INFO] Testing DNS resolution...');
    });

    final testDomains = [
      'api.cloudflare.com',
      'google.com',
      '1.1.1.1',
    ];

    for (final domain in testDomains) {
      try {
        final addresses = await InternetAddress.lookup(domain);
        setState(() {
          _testResults.add('[OK] $domain resolved to: ${addresses.first.address}');
        });
      } catch (e) {
        setState(() {
          _testResults.add('[ERROR] Failed to resolve $domain: $e');
        });
      }
    }

    setState(() {
      _testResults.add('[INFO] DNS test completed');
      _isRunningTest = false;
    });
  }

  Future<void> _testCloudflareAPI() async {
    setState(() {
      _isRunningTest = true;
      _testResults.clear();
      _testResults.add('[INFO] Testing Cloudflare API...');
    });

    try {
      // Check if credentials exist
      final hasCredentials = await _storage.hasCredentials();
      setState(() {
        _testResults.add('[INFO] Has credentials: $hasCredentials');
      });

      if (!hasCredentials) {
        setState(() {
          _testResults.add('[WARN] No credentials stored. Please configure in Settings.');
          _isRunningTest = false;
        });
        return;
      }

      // Get credentials
      final credentials = await _storage.getCredentials();
      setState(() {
        _testResults.add('[INFO] Account ID: ${credentials?.accountId ?? "null"}');
        _testResults.add('[INFO] KV Namespace ID: ${credentials?.kvNamespaceId ?? "null"}');
        _testResults.add('[INFO] API Token length: ${credentials?.apiToken.length ?? 0}');
      });

      // Test API connectivity
      if (credentials != null) {
        setState(() {
          _testResults.add('[INFO] Attempting to validate credentials...');
        });

        final isValid = await _cloudflareAPI.validateCredentials(credentials);
        if (isValid) {
          setState(() {
            _testResults.add('[OK] ✓ Cloudflare API is reachable');
            _testResults.add('[OK] ✓ Credentials are valid');
          });
        } else {
          setState(() {
            _testResults.add('[ERROR] ✗ Credentials validation failed');
          });
        }
      }
    } catch (e, stackTrace) {
      setState(() {
        _testResults.add('[ERROR] Cloudflare API test failed: $e');
        _testResults.add('[ERROR] Stack: ${stackTrace.toString().split('\n').take(3).join('\n')}');
      });
    }

    setState(() {
      _testResults.add('[INFO] Cloudflare API test completed');
      _isRunningTest = false;
    });
  }

  Future<void> _testNetworkConnectivity() async {
    setState(() {
      _isRunningTest = true;
      _testResults.clear();
      _testResults.add('[INFO] Running full network diagnostics...');
    });

    // Test 1: DNS Resolution
    _testResults.add('\n[INFO] === Test 1: DNS Resolution ===');
    await _testDNSResolution();

    // Test 2: HTTP/HTTPS Connectivity
    setState(() {
      _testResults.add('\n[INFO] === Test 2: HTTP/HTTPS Connectivity ===');
    });

    final testUrls = [
      'https://api.cloudflare.com',
      'https://www.google.com',
      'https://1.1.1.1',
    ];

    for (final url in testUrls) {
      try {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(url));
        request.headers.add('User-Agent', 'BPB-Automation/1.0');
        final response = await request.close().timeout(const Duration(seconds: 5));

        setState(() {
          _testResults.add('[OK] $url: HTTP ${response.statusCode}');
        });

        await response.drain();
        client.close();
      } catch (e) {
        setState(() {
          _testResults.add('[ERROR] $url: $e');
        });
      }
    }

    // Test 3: Cloudflare API
    setState(() {
      _testResults.add('\n[INFO] === Test 3: Cloudflare API ===');
    });
    await _testCloudflareAPI();

    setState(() {
      _testResults.add('\n[INFO] === Full network test completed ===');
      _isRunningTest = false;
    });
  }

  Future<void> _testCredentialsStorage() async {
    setState(() {
      _testResults.clear();
      _testResults.add('[INFO] Testing credentials storage...');
    });

    try {
      final hasCredentials = await _storage.hasCredentials();
      setState(() {
        _testResults.add('[INFO] Has credentials: $hasCredentials');
      });

      if (hasCredentials) {
        final credentials = await _storage.getCredentials();
        setState(() {
          _testResults.add('[OK] Successfully retrieved credentials');
          _testResults.add('[INFO] Account ID: ${credentials?.accountId}');
          _testResults.add('[INFO] KV Namespace ID: ${credentials?.kvNamespaceId}');
          _testResults.add('[INFO] API Token length: ${credentials?.apiToken.length}');
        });
      } else {
        setState(() {
          _testResults.add('[WARN] No credentials stored');
        });
      }
    } catch (e) {
      setState(() {
        _testResults.add('[ERROR] Failed to test credentials: $e');
      });
    }
  }

  Future<void> _showStorageInfo() async {
    setState(() {
      _testResults.clear();
      _testResults.add('[INFO] Storage Information:');
    });

    try {
      final isInitialized = _storage.isInitialized;
      final hasCredentials = await _storage.hasCredentials();
      final lastScanTime = await _storage.getLastScanTime();
      final autoUpdateEnabled = await _storage.getAutoUpdateEnabled();
      final autoUpdateInterval = await _storage.getAutoUpdateInterval();
      final numIpsToUse = await _storage.getNumIpsToUse();

      setState(() {
        _testResults.add('[INFO] Storage initialized: $isInitialized');
        _testResults.add('[INFO] Has credentials: $hasCredentials');
        _testResults.add('[INFO] Last scan: ${lastScanTime ?? "Never"}');
        _testResults.add('[INFO] Auto-update enabled: $autoUpdateEnabled');
        _testResults.add('[INFO] Auto-update interval: $autoUpdateInterval hours');
        _testResults.add('[INFO] Number of IPs to use: $numIpsToUse');
      });
    } catch (e) {
      setState(() {
        _testResults.add('[ERROR] Failed to get storage info: $e');
      });
    }
  }

  void _clearResults() {
    setState(() {
      _testResults.clear();
    });
  }

  Future<void> _copyResultsToClipboard() async {
    final text = _testResults.join('\n');
    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Results copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _exportDebugInfo() async {
    final debugInfo = StringBuffer();
    debugInfo.writeln('=== BPB Automation Debug Info ===');
    debugInfo.writeln('Generated: ${DateTime.now()}');
    debugInfo.writeln('\n=== System Info ===');
    debugInfo.writeln('Platform: ${Platform.operatingSystem}');
    debugInfo.writeln('OS Version: ${Platform.operatingSystemVersion}');
    debugInfo.writeln('Locale: ${Platform.localeName}');
    debugInfo.writeln('Processors: ${Platform.numberOfProcessors}');

    debugInfo.writeln('\n=== Storage Info ===');
    debugInfo.writeln('Initialized: ${_storage.isInitialized}');
    debugInfo.writeln('Has credentials: ${await _storage.hasCredentials()}');
    debugInfo.writeln('Last scan: ${await _storage.getLastScanTime()}');

    debugInfo.writeln('\n=== Test Results ===');
    if (_testResults.isNotEmpty) {
      debugInfo.writeln(_testResults.join('\n'));
    } else {
      debugInfo.writeln('No tests run yet');
    }

    debugInfo.writeln('\n=== Recent Logs ===');
    final logs = _log.getLogs();
    for (final log in logs) {
      debugInfo.writeln(log.format());
    }

    await Clipboard.setData(ClipboardData(text: debugInfo.toString()));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Debug info copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
