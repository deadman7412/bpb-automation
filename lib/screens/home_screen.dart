import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';
import '../widgets/logs_action_button.dart';
import '../widgets/theme_mode_action_button.dart';
import '../services/dart_scanner_service.dart';
import '../services/server_backend_service.dart';

/// Main home screen with navigation menu
///
/// Provides quick access to:
/// - Start Scan (launches scan progress screen)
/// - Settings (app preferences)
/// - Configuration (scan parameters and subscription URL)
/// - Results (view last scan results)
/// - Logs (view scan logs)
/// - About (app info)
/// - Debug (developer tools)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final StorageService _storage = StorageService.instance;
  final DartScannerService _scanner = DartScannerService.instance;
  final ServerBackendService _serverApi = ServerBackendService.instance;

  DateTime? _lastScanTime;
  String? _subscriptionUrl;
  bool _useServerBackend = false;
  bool _startingServerRun = false;
  bool _webHasServerConfig = false;
  bool _webHasSession = false;
  Timer? _scanStatusTimer;

  @override
  void initState() {
    super.initState();
    _loadInfo();
    // Periodically refresh so the button reacts to scan state changes
    _scanStatusTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _scanStatusTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    final lastScan = await _storage.getLastScanTime();
    final url = await _storage.getSubscriptionUrl();
    final useServerBackend = await _storage.getUseServerBackend();
    final serverBaseUrl =
        (await _storage.getServerBackendBaseUrl())?.trim() ?? '';
    final serverJwt = (await _storage.getServerBackendJwt())?.trim() ?? '';
    final serverToken = (await _storage.getServerBackendToken())?.trim() ?? '';
    final serverAuthToken = kIsWeb
        ? serverJwt
        : (serverToken.isNotEmpty ? serverToken : serverJwt);

    if (kIsWeb && !useServerBackend) {
      await _storage.saveUseServerBackend(true);
    }

    DateTime? effectiveLastScan = lastScan;
    final effectiveUseServerBackend = kIsWeb ? true : useServerBackend;
    final canQueryServerHistory = kIsWeb
        ? serverJwt.isNotEmpty
        : serverAuthToken.isNotEmpty;
    if (effectiveUseServerBackend &&
        serverBaseUrl.isNotEmpty &&
        canQueryServerHistory) {
      try {
        final runs = await _serverApi.getResults(
          baseUrl: serverBaseUrl,
          page: 1,
          pageSize: 1,
          authToken: serverAuthToken,
        );
        if (runs.isNotEmpty) {
          final latestServerScan = _parseServerScanTime(runs.first);
          if (latestServerScan != null &&
              (effectiveLastScan == null ||
                  latestServerScan.isAfter(effectiveLastScan))) {
            effectiveLastScan = latestServerScan;
          }
        }
      } catch (_) {
        // Keep local last scan fallback when server history is unavailable.
      }
    }

    setState(() {
      _lastScanTime = effectiveLastScan;
      _subscriptionUrl = url;
      _useServerBackend = effectiveUseServerBackend;
      _webHasServerConfig = serverBaseUrl.isNotEmpty;
      _webHasSession = serverJwt.isNotEmpty;
    });
  }

  DateTime? _parseServerScanTime(Map<String, dynamic> run) {
    final candidates = [
      run['finished_at'],
      run['started_at'],
      run['created_at'],
    ];
    for (final value in candidates) {
      final raw = value?.toString().trim();
      if (raw == null || raw.isEmpty) continue;
      try {
        return DateTime.parse(raw);
      } catch (_) {}
    }
    return null;
  }

  Future<void> _startScan() async {
    if (_useServerBackend) {
      if (_startingServerRun) return;
      final baseUrl = (await _storage.getServerBackendBaseUrl())?.trim() ?? '';
      final token = kIsWeb
          ? (await _storage.getServerBackendJwt())?.trim() ?? ''
          : (await _storage.getServerBackendToken())?.trim() ?? '';
      if (baseUrl.isEmpty || token.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Set server backend URL and login/token in Settings first.',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pushNamed(context, '/settings').then((_) => _loadInfo());
        return;
      }

      setState(() => _startingServerRun = true);
      try {
        await _serverApi.triggerRun(
          baseUrl: baseUrl,
          token: token,
          trigger: 'mobile',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Server run started. You can lock the phone; scan continues on the server.',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushNamed(
          context,
          '/server-history',
        ).then((_) => _loadInfo());
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start server run: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) {
          setState(() => _startingServerRun = false);
        }
      }
      return;
    }

    // If scan is running, just navigate to it (will attach, not start new)
    if (_scanner.isScanning) {
      Navigator.pushNamed(context, '/scan-progress').then((_) => _loadInfo());
      return;
    }

    // Check if subscription URL is configured
    if (_subscriptionUrl == null || _subscriptionUrl!.isEmpty) {
      _showConfigNeeded();
      return;
    }

    // Navigate to scan progress screen
    Navigator.pushNamed(context, '/scan-progress').then((_) {
      _loadInfo();
    });
  }

  void _showConfigNeeded() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configuration Required'),
        content: const Text(
          'Please configure your BPB Panel subscription URL in Configuration before starting a scan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Navigator.pushNamed(context, '/config');
              // Reload info when returning from config
              _loadInfo();
            },
            child: const Text('Configure Now'),
          ),
        ],
      ),
    );
  }

  String _getTimeSinceLastScan() {
    if (_lastScanTime == null) return 'Never';

    final now = DateTime.now();
    final difference = now.difference(_lastScanTime!);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${(difference.inDays / 7).floor()}w ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final webAuthBlocked = kIsWeb && (!_webHasServerConfig || !_webHasSession);
    final missingConfig =
        !_useServerBackend &&
        (_subscriptionUrl == null || _subscriptionUrl!.isEmpty);
    final needsSetupNotice = missingConfig || webAuthBlocked;
    return Scaffold(
      appBar: AppBar(
        title: const Text('BPB Automation'),
        centerTitle: true,
        actions: const [
          ThemeModeActionButton(),
          LogsActionButton(currentRoute: '/'),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Title & Description
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_done,
                            size: 64,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Clean IP Scanner',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Find working Cloudflare IPs for your BPB Panel',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Start Scan / View Current Scan Button
                  SizedBox(
                    height: 64,
                    child: ElevatedButton.icon(
                      onPressed: (_startingServerRun || webAuthBlocked)
                          ? null
                          : _startScan,
                      icon: Icon(
                        _useServerBackend
                            ? (_startingServerRun
                                  ? Icons.hourglass_top
                                  : Icons.cloud_upload)
                            : (_scanner.isScanning
                                  ? Icons.visibility
                                  : Icons.play_arrow),
                        size: 28,
                      ),
                      label: Text(
                        webAuthBlocked
                            ? 'Sign In Required'
                            : _useServerBackend
                            ? (_startingServerRun
                                  ? 'Starting Server Scan...'
                                  : 'Start Server Scan')
                            : (_scanner.isScanning
                                  ? 'View Current Scan'
                                  : 'Start Scan'),
                        style: const TextStyle(fontSize: 20),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _useServerBackend
                            ? Colors.indigo
                            : (_scanner.isScanning
                                  ? Colors.blue
                                  : Colors.green),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),

                  if (webAuthBlocked) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Colors.orange.withValues(alpha: 0.12),
                      child: ListTile(
                        leading: const Icon(
                          Icons.lock_outline,
                          color: Colors.orange,
                        ),
                        title: const Text('Web access is locked'),
                        subtitle: Text(
                          _webHasServerConfig
                              ? 'Sign in from Settings to continue.'
                              : 'Configure server backend URL and sign in from Settings.',
                        ),
                        trailing: TextButton(
                          onPressed: () => Navigator.pushNamed(
                            context,
                            '/settings',
                          ).then((_) => _loadInfo()),
                          child: const Text('Open Settings'),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Status Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Status',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                _useServerBackend
                                    ? Icons.cloud
                                    : (_scanner.isScanning
                                          ? Icons.sync
                                          : (_subscriptionUrl != null &&
                                                    _subscriptionUrl!.isNotEmpty
                                                ? Icons.check_circle
                                                : Icons.warning)),
                                color: _useServerBackend
                                    ? Colors.indigo
                                    : (_scanner.isScanning
                                          ? Colors.blue
                                          : (_subscriptionUrl != null &&
                                                    _subscriptionUrl!.isNotEmpty
                                                ? Colors.green
                                                : Colors.orange)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _useServerBackend
                                      ? (webAuthBlocked
                                            ? 'Authentication required'
                                            : 'Server backend mode enabled')
                                      : (_scanner.isScanning
                                            ? 'Scan in progress'
                                            : (_subscriptionUrl != null &&
                                                      _subscriptionUrl!
                                                          .isNotEmpty
                                                  ? 'Ready to scan'
                                                  : 'Configuration needed')),
                                  style: TextStyle(
                                    color: _useServerBackend
                                        ? (webAuthBlocked
                                              ? Colors.orange[700]
                                              : Colors.indigo[700])
                                        : (_scanner.isScanning
                                              ? Colors.blue[700]
                                              : (_subscriptionUrl != null &&
                                                        _subscriptionUrl!
                                                            .isNotEmpty
                                                    ? Colors.green[700]
                                                    : Colors.orange[700])),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (!_useServerBackend && _scanner.isScanning)
                                TextButton(
                                  onPressed: () => Navigator.pushNamed(
                                    context,
                                    '/scan-progress',
                                  ).then((_) => _loadInfo()),
                                  child: const Text('View'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Last scan:',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              Text(
                                _getTimeSinceLastScan(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          if (needsSetupNotice) ...[
                            const SizedBox(height: 12),
                            Card(
                              color: Colors.orange.withValues(alpha: 0.1),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Action needed: update Configuration and Settings.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        TextButton(
                                          onPressed: () => Navigator.pushNamed(
                                            context,
                                            '/config',
                                          ).then((_) => _loadInfo()),
                                          child: const Text(
                                            'Update Configuration',
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pushNamed(
                                            context,
                                            '/settings',
                                          ).then((_) => _loadInfo()),
                                          child: const Text('Open Settings'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Quick Actions Grid
                  Text(
                    'Quick Actions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),

                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.9,
                    children: [
                      _buildActionCard(
                        context,
                        'Configuration',
                        Icons.tune,
                        Colors.blue,
                        () async {
                          await Navigator.pushNamed(context, '/config');
                          // Reload info when returning from config
                          _loadInfo();
                        },
                      ),
                      _buildActionCard(
                        context,
                        'Settings',
                        Icons.settings,
                        Colors.orange,
                        () => Navigator.pushNamed(context, '/settings'),
                      ),
                      _buildActionCard(
                        context,
                        _useServerBackend ? 'Run History' : 'Results',
                        Icons.list_alt,
                        Colors.green,
                        () => Navigator.pushNamed(
                          context,
                          _useServerBackend ? '/server-history' : '/results',
                        ),
                      ),
                      _buildActionCard(
                        context,
                        'Logs',
                        Icons.assignment,
                        Colors.purple,
                        () => Navigator.pushNamed(context, '/logs'),
                      ),
                      _buildActionCard(
                        context,
                        'About',
                        Icons.info,
                        Colors.teal,
                        () => Navigator.pushNamed(context, '/about'),
                      ),
                      _buildActionCard(
                        context,
                        'Debug',
                        Icons.bug_report,
                        Colors.red,
                        () => Navigator.pushNamed(context, '/debug'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
