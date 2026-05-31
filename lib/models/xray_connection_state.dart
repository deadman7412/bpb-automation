enum XrayConnectionStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

class XrayConnectionState {
  final XrayConnectionStatus status;
  final String? activeIP;
  final String? configName;
  final DateTime? connectedAt;
  final String? errorMessage;
  final int? socksPort;
  final int? httpPort;
  final String? bindAddress;

  const XrayConnectionState({
    required this.status,
    this.activeIP,
    this.configName,
    this.connectedAt,
    this.errorMessage,
    this.socksPort,
    this.httpPort,
    this.bindAddress,
  });

  factory XrayConnectionState.disconnected() =>
      const XrayConnectionState(status: XrayConnectionStatus.disconnected);

  factory XrayConnectionState.connecting({required String ip}) =>
      XrayConnectionState(
        status: XrayConnectionStatus.connecting,
        activeIP: ip,
      );

  factory XrayConnectionState.connected({
    required String ip,
    required String? configName,
    required int socksPort,
    int? httpPort,
    required String bindAddress,
  }) => XrayConnectionState(
    status: XrayConnectionStatus.connected,
    activeIP: ip,
    configName: configName,
    connectedAt: DateTime.now(),
    socksPort: socksPort,
    httpPort: httpPort,
    bindAddress: bindAddress,
  );

  factory XrayConnectionState.disconnecting() =>
      const XrayConnectionState(status: XrayConnectionStatus.disconnecting);

  factory XrayConnectionState.error({required String message}) =>
      XrayConnectionState(
        status: XrayConnectionStatus.error,
        errorMessage: message,
      );

  bool get isConnected => status == XrayConnectionStatus.connected;
  bool get isDisconnected => status == XrayConnectionStatus.disconnected;
  bool get isBusy =>
      status == XrayConnectionStatus.connecting ||
      status == XrayConnectionStatus.disconnecting;
  bool get isActive =>
      status != XrayConnectionStatus.disconnected &&
      status != XrayConnectionStatus.error;

  String get statusLabel {
    switch (status) {
      case XrayConnectionStatus.disconnected:
        return 'Disconnected';
      case XrayConnectionStatus.connecting:
        return 'Connecting...';
      case XrayConnectionStatus.connected:
        return 'Connected';
      case XrayConnectionStatus.disconnecting:
        return 'Disconnecting...';
      case XrayConnectionStatus.error:
        return 'Error';
    }
  }

  String get displayAddress {
    if (bindAddress == null || socksPort == null) return '';
    final display = bindAddress == '0.0.0.0' ? '<your-ip>' : '127.0.0.1';
    return '$display:$socksPort';
  }
}
