import 'connection_mode.dart';

class ConnectionConfig {
  final ConnectionMode mode;
  final int socksPort;
  final int? httpPort;
  final bool lanSharingEnabled;

  const ConnectionConfig({
    this.mode = ConnectionMode.proxy,
    this.socksPort = 10808,
    this.httpPort = 8080,
    this.lanSharingEnabled = false,
  });

  String get effectiveBindAddress => lanSharingEnabled ? '0.0.0.0' : '127.0.0.1';

  ConnectionConfig copyWith({
    ConnectionMode? mode,
    int? socksPort,
    int? httpPort,
    bool? lanSharingEnabled,
  }) {
    return ConnectionConfig(
      mode: mode ?? this.mode,
      socksPort: socksPort ?? this.socksPort,
      httpPort: httpPort ?? this.httpPort,
      lanSharingEnabled: lanSharingEnabled ?? this.lanSharingEnabled,
    );
  }
}
