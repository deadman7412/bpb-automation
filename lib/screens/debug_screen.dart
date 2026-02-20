import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../services/log_service.dart';
import '../services/storage_service.dart';
import '../services/cloudflare_api_service.dart';
import '../services/xray_service.dart';
import '../widgets/logs_action_button.dart';

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
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _resultsKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToResults() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _resultsKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug & Diagnostics'),
        actions: const [LogsActionButton()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
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
                      _buildInfoRow('Processors', Platform.numberOfProcessors.toString()),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Xray Binary Diagnostics Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.terminal, color: Colors.purple),
                          const SizedBox(width: 8),
                          Text(
                            'Xray Binary Diagnostics',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _isRunningTest ? null : _testXrayBinary,
                        icon: const Icon(Icons.search),
                        label: const Text('Check Xray Setup'),
                      ),
                      const SizedBox(height: 8),
                      if (Platform.isMacOS || Platform.isLinux)
                        ElevatedButton.icon(
                          onPressed: _isRunningTest ? null : _fixXrayBinary,
                          icon: const Icon(Icons.build),
                          label: const Text('Fix Xray Permissions'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
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

              // Test Results Card
              if (_testResults.isNotEmpty)
                Card(
                  key: _resultsKey,
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
                          width: double.infinity,
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
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Color _getResultColor(String result) {
    if (result.contains('[OK]') || result.contains('Success')) {
      return Colors.green;
    } else if (result.contains('[ERROR]') || result.contains('Failed')) {
      return Colors.red;
    } else if (result.contains('[WARN]') || result.contains('Warning')) {
      return Colors.orange;
    } else {
      return Colors.white70;
    }
  }

  /// Run all async work, collect results in a local list, then single setState.
  Future<void> _testDNSResolution() async {
    setState(() {
      _isRunningTest = true;
      _testResults.clear();
    });

    final results = <String>['[INFO] Testing DNS resolution...'];

    for (final domain in ['api.cloudflare.com', 'google.com', '1.1.1.1']) {
      try {
        final addresses = await InternetAddress.lookup(domain);
        results.add('[OK] $domain -> ${addresses.first.address}');
      } catch (e) {
        results.add('[ERROR] Failed to resolve $domain: $e');
      }
    }

    results.add('[INFO] DNS test complete');

    setState(() {
      _testResults.addAll(results);
      _isRunningTest = false;
    });
    _scrollToResults();
  }

  Future<void> _testCloudflareAPI() async {
    setState(() {
      _isRunningTest = true;
      _testResults.clear();
    });

    final results = <String>['[INFO] Testing Cloudflare API...'];

    try {
      final hasCredentials = await _storage.hasCredentials();
      results.add('[INFO] Has credentials: $hasCredentials');

      if (!hasCredentials) {
        results.add('[WARN] No credentials stored - configure in Settings');
        setState(() {
          _testResults.addAll(results);
          _isRunningTest = false;
        });
        _scrollToResults();
        return;
      }

      final credentials = await _storage.getCredentials();
      results.add(
        '[INFO] Account ID length: ${credentials?.accountId.length ?? 0}',
      );
      results.add(
        '[INFO] KV Namespace ID length: ${credentials?.kvNamespaceId.length ?? 0}',
      );
      results.add('[INFO] API Token length: ${credentials?.apiToken.length ?? 0}');

      if (credentials != null) {
        results.add('[INFO] Validating credentials...');
        final isValid = await _cloudflareAPI.validateCredentials(credentials);
        if (isValid) {
          results.add('[OK] Cloudflare API reachable');
          results.add('[OK] Credentials are valid');
        } else {
          results.add('[ERROR] Credentials validation failed');
        }
      }
    } catch (e, stackTrace) {
      results.add('[ERROR] Cloudflare API test failed: $e');
      results.add('[ERROR] ${stackTrace.toString().split('\n').take(2).join(' ')}');
    }

    results.add('[INFO] Cloudflare API test complete');

    setState(() {
      _testResults.addAll(results);
      _isRunningTest = false;
    });
    _scrollToResults();
  }

  Future<void> _testNetworkConnectivity() async {
    setState(() {
      _isRunningTest = true;
      _testResults.clear();
    });

    final results = <String>['[INFO] Running full network diagnostics...'];

    // DNS
    results.add('[INFO] === Test 1: DNS Resolution ===');
    for (final domain in ['api.cloudflare.com', 'google.com', '1.1.1.1']) {
      try {
        final addresses = await InternetAddress.lookup(domain);
        results.add('[OK] $domain -> ${addresses.first.address}');
      } catch (e) {
        results.add('[ERROR] $domain: $e');
      }
    }

    // HTTP
    results.add('[INFO] === Test 2: HTTP Connectivity ===');
    for (final url in ['https://api.cloudflare.com', 'https://www.google.com']) {
      try {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(url));
        request.headers.add('User-Agent', 'BPB-Automation/1.0');
        final response = await request.close().timeout(const Duration(seconds: 5));
        results.add('[OK] $url: HTTP ${response.statusCode}');
        await response.drain();
        client.close();
      } catch (e) {
        results.add('[ERROR] $url: $e');
      }
    }

    // Cloudflare API
    results.add('[INFO] === Test 3: Cloudflare API ===');
    try {
      final hasCredentials = await _storage.hasCredentials();
      if (hasCredentials) {
        final credentials = await _storage.getCredentials();
        if (credentials != null) {
          final isValid = await _cloudflareAPI.validateCredentials(credentials);
          results.add(isValid
              ? '[OK] Credentials valid'
              : '[ERROR] Credentials invalid');
        }
      } else {
        results.add('[WARN] No credentials stored');
      }
    } catch (e) {
      results.add('[ERROR] API test failed: $e');
    }

    results.add('[INFO] === Full network test complete ===');

    setState(() {
      _testResults.addAll(results);
      _isRunningTest = false;
    });
    _scrollToResults();
  }

  Future<void> _testCredentialsStorage() async {
    final results = <String>['[INFO] Testing credentials storage...'];

    try {
      final hasCredentials = await _storage.hasCredentials();
      results.add('[INFO] Has credentials: $hasCredentials');

      if (hasCredentials) {
        final credentials = await _storage.getCredentials();
        results.add('[OK] Successfully retrieved credentials');
        results.add(
          '[INFO] Account ID length: ${credentials?.accountId.length ?? 0}',
        );
        results.add(
          '[INFO] KV Namespace ID length: ${credentials?.kvNamespaceId.length ?? 0}',
        );
        results.add('[INFO] API Token length: ${credentials?.apiToken.length}');
      } else {
        results.add('[WARN] No credentials stored');
      }
    } catch (e) {
      results.add('[ERROR] Failed to test credentials: $e');
    }

    setState(() {
      _testResults
        ..clear()
        ..addAll(results);
    });
    _scrollToResults();
  }

  Future<void> _showStorageInfo() async {
    final results = <String>['[INFO] Storage Information:'];

    try {
      final isInitialized = _storage.isInitialized;
      final hasCredentials = await _storage.hasCredentials();
      final lastScanTime = await _storage.getLastScanTime();
      final autoUpdateEnabled = await _storage.getAutoUpdateEnabled();
      final autoUpdateInterval = await _storage.getAutoUpdateInterval();
      final numIpsToUse = await _storage.getNumIpsToUse();

      results.add('[INFO] Storage initialized: $isInitialized');
      results.add('[INFO] Has credentials: $hasCredentials');
      results.add('[INFO] Last scan: ${lastScanTime ?? "Never"}');
      results.add('[INFO] Auto-update enabled: $autoUpdateEnabled');
      results.add('[INFO] Auto-update interval: $autoUpdateInterval hours');
      results.add('[INFO] IPs to use: $numIpsToUse');
    } catch (e) {
      results.add('[ERROR] Failed to get storage info: $e');
    }

    setState(() {
      _testResults
        ..clear()
        ..addAll(results);
    });
    _scrollToResults();
  }

  Future<String> _getXrayBinaryPath() async {
    // On Android, the binary lives in nativeLibraryDir (installed by the OS).
    // App-writable dirs are mounted noexec on Android 10+ so we cannot use them.
    if (Platform.isAndroid) {
      // Prefer the path already resolved by XrayService
      final servicePath = XrayService.instance.binaryPath;
      if (servicePath != null) return servicePath;

      // Fallback: ask Android for the directory directly
      try {
        const channel = MethodChannel('com.bpb.bpb_automation/native');
        final nativeLibDir =
            await channel.invokeMethod<String>('getNativeLibraryDir');
        if (nativeLibDir != null && nativeLibDir.isNotEmpty) {
          return path.join(nativeLibDir, 'libxray.so');
        }
      } catch (_) {}
    }

    final appDir = await getApplicationDocumentsDirectory();
    final binaryFileName = Platform.isWindows ? 'xray.exe' : 'xray';
    return path.join(appDir.path, 'xray', binaryFileName);
  }

  Future<void> _testXrayBinary() async {
    setState(() {
      _isRunningTest = true;
      _testResults.clear();
    });

    final results = <String>['[INFO] === Xray Binary Diagnostics ==='];

    try {
      final binaryPath = await _getXrayBinaryPath();
      results.add('[INFO] Path: $binaryPath');

      // 1. File exists
      final binaryFile = File(binaryPath);
      final exists = await binaryFile.exists();
      if (!exists) {
        results.add('[ERROR] Binary not found - run a scan to extract it');
        setState(() {
          _testResults.addAll(results);
          _isRunningTest = false;
        });
        _scrollToResults();
        return;
      }
      results.add('[OK] Binary file exists');

      // 2. File size
      final stat = await binaryFile.stat();
      final sizeMb = (stat.size / 1024 / 1024).toStringAsFixed(1);
      results.add('[INFO] Size: ${sizeMb}MB');
      if (stat.size < 1024 * 1024) {
        results.add('[WARN] Binary seems too small - may be corrupt');
      }

      // 3. Execute permissions
      if (!Platform.isWindows) {
        final lsResult = await Process.run('ls', ['-la', binaryPath]);
        if (lsResult.exitCode == 0) {
          final perms = (lsResult.stdout as String).split(' ').first;
          results.add('[INFO] Permissions: $perms');
          results.add(perms.contains('x')
              ? '[OK] Execute permission set'
              : '[ERROR] Execute permission NOT set - use Fix button');
        }
      }

      // 4. Quarantine attribute (macOS)
      if (Platform.isMacOS) {
        final xattrResult = await Process.run('xattr', ['-l', binaryPath]);
        final xattrOutput = xattrResult.stdout as String;
        if (xattrOutput.contains('com.apple.quarantine')) {
          results.add('[ERROR] Quarantine attribute detected - blocks execution');
          results.add('[INFO] Use the Fix button to remove it');
        } else {
          results.add('[OK] No quarantine attribute');
        }
      }

      // 5. Run binary
      results.add('[INFO] Testing binary execution...');
      try {
        final versionResult = await Process.run(binaryPath, ['version'])
            .timeout(const Duration(seconds: 5));
        if (versionResult.exitCode == 0) {
          results.add('[OK] Binary executes successfully');
          final versionLine = (versionResult.stdout as String)
              .split('\n')
              .firstWhere((l) => l.contains('Xray'), orElse: () => '');
          if (versionLine.isNotEmpty) {
            results.add('[OK] ${versionLine.trim()}');
          }
        } else {
          results.add('[ERROR] Binary exited with code ${versionResult.exitCode}');
          final stderr = (versionResult.stderr as String).trim();
          if (stderr.isNotEmpty) results.add('[INFO] stderr: $stderr');
        }
      } catch (e) {
        results.add('[ERROR] Failed to run binary: $e');
        if (Platform.isMacOS) {
          results.add('[INFO] Use the Fix button to remove quarantine and set permissions');
        }
      }

      // 6. Version file
      final appDir = await getApplicationDocumentsDirectory();
      final versionFilePath = path.join(appDir.path, 'xray', '.xray_version');
      final versionFile = File(versionFilePath);
      if (await versionFile.exists()) {
        final installedVersion = (await versionFile.readAsString()).trim();
        results.add('[INFO] Installed: $installedVersion  Bundled: ${XrayService.xrayVersion}');
        results.add(installedVersion == XrayService.xrayVersion
            ? '[OK] Version up to date'
            : '[WARN] Version mismatch - will re-extract on next scan');
      } else {
        results.add('[WARN] Version file not found');
      }
    } catch (e) {
      results.add('[ERROR] Diagnostics failed: $e');
    }

    results.add('[INFO] === Xray diagnostics complete ===');

    setState(() {
      _testResults.addAll(results);
      _isRunningTest = false;
    });
    _scrollToResults();
  }

  Future<void> _fixXrayBinary() async {
    setState(() {
      _isRunningTest = true;
      _testResults.clear();
    });

    final results = <String>['[INFO] === Fixing Xray Binary ==='];

    try {
      final binaryPath = await _getXrayBinaryPath();
      final binaryFile = File(binaryPath);

      if (!await binaryFile.exists()) {
        results.add('[ERROR] Binary not found at: $binaryPath');
        results.add('[INFO] Run a scan first to extract the binary');
        setState(() {
          _testResults.addAll(results);
          _isRunningTest = false;
        });
        _scrollToResults();
        return;
      }

      // Fix execute permissions
      if (!Platform.isWindows) {
        final chmodResult = await Process.run('chmod', ['+x', binaryPath]);
        results.add(chmodResult.exitCode == 0
            ? '[OK] Execute permissions set (chmod +x)'
            : '[ERROR] chmod failed: ${chmodResult.stderr}');
      }

      // Remove quarantine attribute on macOS
      if (Platform.isMacOS) {
        final xattrResult = await Process.run('xattr', [
          '-d', 'com.apple.quarantine', binaryPath,
        ]);
        if (xattrResult.exitCode == 0) {
          results.add('[OK] Quarantine attribute removed');
        } else {
          final stderr = (xattrResult.stderr as String).trim();
          results.add(stderr.isEmpty
              ? '[INFO] Quarantine attribute was not present'
              : '[WARN] xattr: $stderr');
        }
      }

      // Verify
      results.add('[INFO] Verifying fix...');
      try {
        final versionResult = await Process.run(binaryPath, ['version'])
            .timeout(const Duration(seconds: 5));
        if (versionResult.exitCode == 0) {
          results.add('[OK] Binary executes successfully');
        } else {
          results.add('[ERROR] Binary still fails (exit ${versionResult.exitCode})');
          results.add('[INFO] stderr: ${(versionResult.stderr as String).trim()}');
        }
      } catch (e) {
        results.add('[ERROR] Binary still fails: $e');
        results.add('[INFO] Try running the app again - the fix takes effect on restart');
      }
    } catch (e) {
      results.add('[ERROR] Fix failed: $e');
    }

    results.add('[INFO] === Fix complete ===');

    setState(() {
      _testResults.addAll(results);
      _isRunningTest = false;
    });
    _scrollToResults();
  }

  void _clearResults() {
    setState(() => _testResults.clear());
  }

  Future<void> _copyResultsToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _testResults.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Results copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
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
    debugInfo.writeln(_testResults.isEmpty ? 'No tests run yet' : _testResults.join('\n'));
    debugInfo.writeln('\n=== Recent Logs ===');
    for (final log in _log.getLogs()) {
      debugInfo.writeln(log.format());
    }

    await Clipboard.setData(ClipboardData(text: debugInfo.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Debug info copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
