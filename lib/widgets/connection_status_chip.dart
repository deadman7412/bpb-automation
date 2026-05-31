import 'package:flutter/material.dart';

import '../models/xray_connection_state.dart';
import '../services/connection_service.dart';

class ConnectionStatusChip extends StatelessWidget {
  const ConnectionStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<XrayConnectionState>(
      stream: ConnectionService.instance.stateStream,
      initialData: ConnectionService.instance.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? XrayConnectionState.disconnected();
        if (state.isDisconnected) return const SizedBox.shrink();

        final (color, label) = switch (state.status) {
          XrayConnectionStatus.connecting => (Colors.orange, 'Connecting...'),
          XrayConnectionStatus.connected => (
            Colors.green,
            'Proxy: ${state.activeIP ?? ""}'
          ),
          XrayConnectionStatus.disconnecting => (Colors.orange, 'Disconnecting...'),
          XrayConnectionStatus.error => (Colors.red, 'Proxy error'),
          XrayConnectionStatus.disconnected => (Colors.grey, 'Disconnected'),
        };

        return GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/connection'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
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
          ),
        );
      },
    );
  }
}
