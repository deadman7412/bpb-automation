import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/config_scan_result.dart';
import '../models/connection_config.dart';
import '../models/connection_test_result.dart';
import '../models/xray_connection_state.dart';
import '../models/xray_traffic_stats.dart';
import '../services/connection_service.dart';
import '../services/lan_share_service.dart';
import '../services/log_service.dart';
import '../services/storage_service.dart';
import '../services/xray_stats_service.dart';
import '../widgets/logs_action_button.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final ConnectionService _conn = ConnectionService.instance;
  final LanShareService _lanShare = LanShareService.instance;
  final LogService _log = LogService.instance;

  late StreamSubscription<XrayConnectionState> _stateSub;
  Timer? _uptimeTimer;

  XrayConnectionState _state = ConnectionService.instance.currentState;
  ConnectionConfig _config = const ConnectionConfig();
  ConfigScanResult? _scanResult;
  String? _selectedIP;
  String? _lanIP;
  bool _loadingResult = true;
  ConnectionTestResult? _testResult;
  bool _isTesting = false;

  final _socksPortController = TextEditingController(text: '10808');
  final _httpPortController = TextEditingController(text: '8080');

  @override
  void initState() {
    super.initState();
    _state = _conn.currentState;
    _stateSub = _conn.stateStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _state = s;
        if (s.isDisconnected) {
          _testResult = null;
          _isTesting = false;
        }
      });
      if (s.isConnected) {
        _startUptimeTimer();
      } else {
        _uptimeTimer?.cancel();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _stateSub.cancel();
    _uptimeTimer?.cancel();
    _socksPortController.dispose();
    _httpPortController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is ConfigScanResult && args.workingIPs.isNotEmpty) {
      setState(() {
        _scanResult = args;
        _selectedIP = args.workingIPs.first;
        _loadingResult = false;
      });
    } else {
      await _loadLastResult();
    }
    _detectLanIP();
  }

  Future<void> _loadLastResult() async {
    try {
      final resultJson = await StorageService.instance.getLastScanResult();
      if (resultJson != null) {
        final result = ConfigScanResult.fromJson(resultJson);
        if (result.workingIPs.isNotEmpty) {
          if (mounted) {
            setState(() {
              _scanResult = result;
              _selectedIP = result.workingIPs.first;
            });
          }
        }
      }
    } catch (e) {
      _log.logWarn('[Proxy] Failed to load last scan result: $e');
    } finally {
      if (mounted) setState(() => _loadingResult = false);
    }
  }

  Future<void> _detectLanIP() async {
    final ip = await _lanShare.getLocalNetworkIPv4();
    if (mounted) setState(() => _lanIP = ip);
  }

  void _startUptimeTimer() {
    _uptimeTimer?.cancel();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _connect() async {
    final result = _scanResult;
    final ip = _selectedIP;
    if (result == null || ip == null) return;

    final socksPort = int.tryParse(_socksPortController.text.trim()) ?? 10808;
    final httpPortText = _httpPortController.text.trim();
    final httpPort = httpPortText.isEmpty ? null : int.tryParse(httpPortText);

    final connConfig = _config.copyWith(
      socksPort: socksPort,
      httpPort: httpPort,
    );

    try {
      await _conn.connect(
        templateConfig: result.templateConfig,
        ip: ip,
        connConfig: connConfig,
      );
      setState(() => _config = connConfig);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Connection failed: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _disconnect() async {
    await _conn.disconnect();
  }

  Future<void> _runConnectionTest() async {
    if (_isTesting) return;
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    try {
      final result = await _conn.testConnection();
      if (mounted) setState(() => _testResult = result);
    } catch (e) {
      if (mounted) {
        setState(() => _testResult = ConnectionTestResult(
          success: false,
          error: e.toString(),
          testedAt: DateTime.now(),
        ));
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  String _formatUptime() {
    final connectedAt = _state.connectedAt;
    if (connectedAt == null) return '';
    final d = DateTime.now().difference(connectedAt);
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60).toString().padLeft(2, '0')}m';
    }
    return '${d.inMinutes.toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Copied: $text'),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  bool get _isUnsupported => kIsWeb || (Platform.isIOS);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proxy Connection'),
        actions: const [LogsActionButton(currentRoute: '/connection')],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_isUnsupported) ...[
                  _buildUnsupportedCard(),
                ] else if (_loadingResult) ...[
                  const Center(child: CircularProgressIndicator()),
                ] else ...[
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  if (_state.isConnected) ...[
                    _buildConnectionDetailsCard(),
                    const SizedBox(height: 16),
                    _buildTestCard(),
                    const SizedBox(height: 16),
                    _buildTrafficStatsCard(),
                    const SizedBox(height: 16),
                    _buildLanSharingCard(),
                    const SizedBox(height: 16),
                  ],
                  if (!_state.isConnected && !_state.isBusy) ...[
                    _buildIPSelectorCard(),
                    const SizedBox(height: 16),
                    _buildSettingsCard(),
                    const SizedBox(height: 16),
                  ],
                  _buildConnectButton(),
                  if (!_state.isConnected) ...[
                    const SizedBox(height: 16),
                    _buildModeCard(),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnsupportedCard() {
    return Card(
      color: Colors.orange.withValues(alpha: 0.12),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.info_outline, size: 48, color: Colors.orange),
            SizedBox(height: 12),
            Text(
              'Not available on this platform',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'The built-in proxy requires running the Xray binary, '
              'which is not supported on iOS or web. '
              'Use Android, macOS, Linux, or Windows.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final (icon, color, title, subtitle) = switch (_state.status) {
      XrayConnectionStatus.disconnected => (
        Icons.power_off,
        Colors.grey,
        'Disconnected',
        _scanResult == null
            ? 'Run a scan first to find working IPs'
            : 'Ready to connect via ${_selectedIP ?? ""}',
      ),
      XrayConnectionStatus.connecting => (
        Icons.sync,
        Colors.orange,
        'Connecting...',
        'Starting Xray proxy for ${_state.activeIP ?? ""}',
      ),
      XrayConnectionStatus.connected => (
        Icons.shield,
        Colors.green,
        'Connected',
        'Via ${_state.activeIP ?? ""}  |  ${_formatUptime()}',
      ),
      XrayConnectionStatus.disconnecting => (
        Icons.sync,
        Colors.orange,
        'Disconnecting...',
        'Stopping proxy',
      ),
      XrayConnectionStatus.error => (
        Icons.error_outline,
        Colors.red,
        'Connection error',
        _state.errorMessage ?? 'Unknown error',
      ),
    };

    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionDetailsCard() {
    final state = _state;
    if (!state.isConnected) return const SizedBox.shrink();

    final bindAddr = state.bindAddress == '0.0.0.0'
        ? (_lanIP ?? '0.0.0.0')
        : '127.0.0.1';
    final socksAddr = '$bindAddr:${state.socksPort}';
    final httpAddr = state.httpPort != null ? '$bindAddr:${state.httpPort}' : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Proxy Addresses', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildAddressRow(
              label: 'SOCKS5',
              address: socksAddr,
              protocol: 'socks5://$socksAddr',
            ),
            if (httpAddr != null) ...[
              const SizedBox(height: 8),
              _buildAddressRow(
                label: 'HTTP',
                address: httpAddr,
                protocol: 'http://$httpAddr',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAddressRow({
    required String label,
    required String address,
    required String protocol,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          ),
        ),
        TextButton.icon(
          onPressed: () => _copy(address),
          icon: const Icon(Icons.copy, size: 14),
          label: const Text('host:port', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        TextButton.icon(
          onPressed: () => _copy(protocol),
          icon: const Icon(Icons.copy, size: 14),
          label: const Text('URL', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildTestCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.network_check, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Test Connection',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: _isTesting ? null : _runConnectionTest,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow, size: 18),
                    label: Text(
                      _isTesting ? 'Testing...' : (_testResult == null ? 'Run Test' : 'Retest'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
            if (_testResult == null && !_isTesting) ...[
              const SizedBox(height: 8),
              Text(
                'Sends a request through the proxy to check your external IP. '
                'A successful result confirms traffic is routing correctly.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_isTesting) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Connecting to api.ipify.org through proxy...'),
                ],
              ),
            ],
            if (_testResult != null) ...[
              const SizedBox(height: 12),
              _buildTestResult(_testResult!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTestResult(ConnectionTestResult r) {
    if (r.success) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Connection working',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (r.latencyMs != null) ...[
                  const Spacer(),
                  Text(
                    '${r.latencyMs} ms',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.green[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'External IP:  ',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: Text(
                    r.externalIP ?? '',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: 'Copy IP',
                  onPressed: () => _copy(r.externalIP ?? ''),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Traffic is routing through the proxy. The IP above belongs to Cloudflare, confirming your connection is correct.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Failure
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Test failed',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  r.error ?? 'Unknown error',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  'The proxy is running but could not reach the test endpoint. '
                  'Check that apps are using SOCKS5 127.0.0.1:${_state.socksPort ?? 10808}.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrafficStatsCard() {
    return StreamBuilder<XrayTrafficStats>(
      stream: XrayStatsService.instance.statsStream,
      initialData: XrayStatsService.instance.lastStats,
      builder: (context, snapshot) {
        final stats = snapshot.data;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.swap_vert, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Traffic',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    if (stats == null)
                      Text(
                        'Waiting for data...',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (stats == null) ...[
                  Text(
                    'Stats will appear once traffic flows through the proxy.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: _buildTrafficTile(
                          icon: Icons.arrow_downward,
                          color: Colors.blue,
                          label: 'Download',
                          total: stats.formattedDownload,
                          speed: stats.formattedDownloadSpeed,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTrafficTile(
                          icon: Icons.arrow_upward,
                          color: Colors.green,
                          label: 'Upload',
                          total: stats.formattedUpload,
                          speed: stats.formattedUploadSpeed,
                        ),
                      ),
                    ],
                  ),
                  if (stats.uplinkBytes == 0 && stats.downlinkBytes == 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'No traffic yet — send a request through the proxy to confirm it works.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrafficTile({
    required IconData icon,
    required Color color,
    required String label,
    required String total,
    required String speed,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            total,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (speed.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              speed,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLanSharingCard() {
    final isLanEnabled = _state.bindAddress == '0.0.0.0';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi, size: 20),
                const SizedBox(width: 8),
                Text('LAN Sharing', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            if (isLanEnabled) ...[
              Text(
                'Proxy is accessible on your local network.',
                style: TextStyle(color: Colors.green[700]),
              ),
              if (_lanIP != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Your LAN IP: $_lanIP',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 4),
                Text(
                  'Other devices: set SOCKS5 proxy to $_lanIP:${_state.socksPort}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ] else ...[
              Text(
                'Proxy is only accessible from this device (127.0.0.1).',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'To share with other LAN devices, disconnect and reconnect with LAN sharing enabled.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIPSelectorCard() {
    final result = _scanResult;
    if (result == null) {
      return Card(
        color: Colors.orange.withValues(alpha: 0.1),
        child: const ListTile(
          leading: Icon(Icons.info_outline, color: Colors.orange),
          title: Text('No scan results'),
          subtitle: Text('Run a scan first to find working IPs, then connect.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('IP to connect', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedIP,
                  isExpanded: true,
                  items: result.workingIPs
                      .map((ip) {
                        final testResult = result.getResultForIP(ip);
                        final latency = testResult?.proxyTestResult?.latencyMs;
                        return DropdownMenuItem(
                          value: ip,
                          child: Text(
                            latency != null
                                ? '$ip  (${latency.toStringAsFixed(0)} ms)'
                                : ip,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        );
                      })
                      .toList(),
                  onChanged: (v) => setState(() => _selectedIP = v),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Config: ${result.templateConfig.getDescription()}',
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Proxy Settings', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _socksPortController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'SOCKS5 port',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _httpPortController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'HTTP port (optional)',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              value: _config.lanSharingEnabled,
              onChanged: (v) => setState(() => _config = _config.copyWith(lanSharingEnabled: v)),
              title: const Text('LAN sharing'),
              subtitle: const Text(
                'Bind on 0.0.0.0 so other devices on your network can use this proxy',
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectButton() {
    final hasResult = _scanResult != null && _selectedIP != null;
    final isConnected = _state.isConnected;
    final isBusy = _state.isBusy;

    if (isConnected) {
      return ElevatedButton.icon(
        onPressed: isBusy ? null : _disconnect,
        icon: isBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.power_off),
        label: Text(isBusy ? 'Disconnecting...' : 'Disconnect'),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: (hasResult && !isBusy) ? _connect : null,
      icon: isBusy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.power),
      label: Text(
        isBusy
            ? 'Connecting...'
            : hasResult
            ? 'Connect via ${_selectedIP ?? ""}'
            : 'Run a scan first',
      ),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildModeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connection Mode', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.router, color: Colors.blue),
              title: const Text('Proxy mode'),
              subtitle: const Text(
                'SOCKS5 + HTTP proxy. Apps need to be configured manually.',
              ),
              trailing: const Icon(Icons.check_circle, color: Colors.blue),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: Icon(Icons.vpn_lock, color: Colors.grey[400]),
              title: Text('VPN tunnel', style: TextStyle(color: Colors.grey[500])),
              subtitle: const Text('Full device tunnel. Coming soon.'),
              trailing: Chip(
                label: const Text('Soon'),
                labelStyle: const TextStyle(fontSize: 11),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}
