import 'package:flutter/material.dart';
import 'dart:async';
import '../services/storage_service.dart';
import '../widgets/logs_action_button.dart';
import '../services/dart_scanner_service.dart';

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

  DateTime? _lastScanTime;
  String? _subscriptionUrl;
  bool _useServerBackend = false;
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

    setState(() {
      _lastScanTime = lastScan;
      _subscriptionUrl = url;
      _useServerBackend = useServerBackend;
    });
  }

  void _startScan() {
    if (_useServerBackend) {
      Navigator.pushNamed(context, '/server-history').then((_) => _loadInfo());
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('BPB Clean IP Scanner'),
        centerTitle: true,
        actions: const [LogsActionButton()],
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
                      onPressed: _startScan,
                      icon: Icon(
                        _useServerBackend
                            ? Icons.history
                            : (_scanner.isScanning
                                  ? Icons.visibility
                                  : Icons.play_arrow),
                        size: 28,
                      ),
                      label: Text(
                        _useServerBackend
                            ? 'Open Server Runs'
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
                                      ? 'Server backend mode enabled'
                                      : (_scanner.isScanning
                                            ? 'Scan in progress'
                                            : (_subscriptionUrl != null &&
                                                      _subscriptionUrl!
                                                          .isNotEmpty
                                                  ? 'Ready to scan'
                                                  : 'Configuration needed')),
                                  style: TextStyle(
                                    color: _useServerBackend
                                        ? Colors.indigo[700]
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
