import 'package:flutter/material.dart';

import '../models/xray_connection_state.dart';
import '../models/xray_traffic_stats.dart';
import '../services/connection_service.dart';
import '../services/xray_stats_service.dart';

class ConnectionStatusCard extends StatelessWidget {
  const ConnectionStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<XrayConnectionState>(
      stream: ConnectionService.instance.stateStream,
      initialData: ConnectionService.instance.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? XrayConnectionState.disconnected();
        return _buildCard(context, state);
      },
    );
  }

  Widget _buildCard(BuildContext context, XrayConnectionState state) {
    final Color? bg = switch (state.status) {
      XrayConnectionStatus.connected => Colors.green.withValues(alpha: 0.09),
      XrayConnectionStatus.error => Colors.red.withValues(alpha: 0.08),
      _ => null,
    };

    return Card(
      color: bg,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pushNamed(context, '/connection'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: switch (state.status) {
            XrayConnectionStatus.connected => _buildConnected(context, state),
            XrayConnectionStatus.connecting ||
            XrayConnectionStatus.disconnecting =>
              _buildBusy(context, state),
            XrayConnectionStatus.error => _buildError(context, state),
            XrayConnectionStatus.disconnected => _buildDisconnected(context),
          },
        ),
      ),
    );
  }

  // ── Connected ──────────────────────────────────────────────────────────────

  Widget _buildConnected(BuildContext context, XrayConnectionState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: icon + IP + Disconnect button
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 22, color: Colors.green[700]),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Proxy Active',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    '${state.activeIP ?? ""}  ·  ${_connectedSince(state.connectedAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => ConnectionService.instance.disconnect(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red[700],
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Disconnect'),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Stats + address row
        StreamBuilder<XrayTrafficStats>(
          stream: XrayStatsService.instance.statsStream,
          initialData: XrayStatsService.instance.lastStats,
          builder: (context, snap) {
            final stats = snap.data;
            return Row(
              children: [
                if (stats != null) ...[
                  _statItem(
                    context,
                    Icons.arrow_downward,
                    Colors.blue,
                    stats.formattedDownload,
                    stats.formattedDownloadSpeed,
                  ),
                  const SizedBox(width: 20),
                  _statItem(
                    context,
                    Icons.arrow_upward,
                    Colors.green[600]!,
                    stats.formattedUpload,
                    stats.formattedUploadSpeed,
                  ),
                  const Spacer(),
                ] else ...[
                  const Spacer(),
                ],
                Text(
                  'SOCKS5  :${state.socksPort ?? 10808}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _statItem(
    BuildContext context,
    IconData icon,
    Color color,
    String total,
    String speed,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(total, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        if (speed.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            speed,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  // ── Disconnected ───────────────────────────────────────────────────────────

  Widget _buildDisconnected(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.power_off_outlined, size: 20, color: Colors.grey[500]),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Proxy Connection',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'Tap to connect after scanning',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
      ],
    );
  }

  // ── Busy (connecting / disconnecting) ──────────────────────────────────────

  Widget _buildBusy(BuildContext context, XrayConnectionState state) {
    return Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(
          state.statusLabel,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  // ── Error ──────────────────────────────────────────────────────────────────

  Widget _buildError(BuildContext context, XrayConnectionState state) {
    return Row(
      children: [
        const Icon(Icons.error_outline, size: 20, color: Colors.red),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            state.errorMessage ?? 'Proxy error',
            style: const TextStyle(color: Colors.red, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: () {
            ConnectionService.instance.disconnect();
          },
          style: TextButton.styleFrom(
            foregroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Dismiss'),
        ),
        Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _connectedSince(DateTime? at) {
    if (at == null) return '';
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return 'since $h:$m';
  }
}
