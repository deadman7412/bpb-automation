import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:bpb_automation/services/log_service.dart';

/// SOCKS5 protocol helper for connecting through proxy
///
/// Implements SOCKS5 protocol as specified in RFC 1928:
/// https://www.rfc-editor.org/rfc/rfc1928
///
/// Usage:
/// ```dart
/// final socket = await Socks5Helper.connectViaSocks5(
///   socksHost: '127.0.0.1',
///   socksPort: 10808,
///   targetHost: 'www.gstatic.com',
///   targetPort: 80,
///   timeout: 5,
/// );
/// ```
class Socks5Helper {
  static final LogService _logService = LogService.instance;

  /// SOCKS5 protocol version
  static const int socks5Version = 0x05;

  /// Authentication methods
  static const int authNoAuth = 0x00;
  static const int authNoAcceptable = 0xFF;

  /// SOCKS5 commands
  static const int cmdConnect = 0x01;

  /// Address types
  static const int atypIPv4 = 0x01;
  static const int atypDomainName = 0x03;
  static const int atypIPv6 = 0x04;

  /// Reply codes
  static const int repSuccess = 0x00;
  static const int repGeneralFailure = 0x01;
  static const int repConnectionNotAllowed = 0x02;
  static const int repNetworkUnreachable = 0x03;
  static const int repHostUnreachable = 0x04;
  static const int repConnectionRefused = 0x05;
  static const int repTTLExpired = 0x06;
  static const int repCommandNotSupported = 0x07;
  static const int repAddressTypeNotSupported = 0x08;

  /// Connect to target host through SOCKS5 proxy
  ///
  /// Returns a connected socket on success.
  /// Throws SocketException or Socks5Exception on failure.
  static Future<Socket> connectViaSocks5({
    required String socksHost,
    required int socksPort,
    required String targetHost,
    required int targetPort,
    required int timeout,
  }) async {
    Socket? socket;

    try {
      _logService.logInfo(
        'Connecting to SOCKS5 proxy at $socksHost:$socksPort',
      );

      // Connect to SOCKS5 proxy
      socket = await Socket.connect(
        socksHost,
        socksPort,
        timeout: Duration(seconds: timeout),
      );

      _logService.logInfo('Connected to SOCKS5 proxy');

      // Perform SOCKS5 handshake
      await _performHandshake(socket, timeout);

      // Send connect request
      await _sendConnectRequest(socket, targetHost, targetPort, timeout);

      _logService.logOk(
        '[OK] SOCKS5 connection established to $targetHost:$targetPort',
      );

      return socket;
    } catch (e) {
      _logService.logError('SOCKS5 connection failed: $e');
      await socket?.close();
      rethrow;
    }
  }

  /// Perform SOCKS5 handshake (greeting and authentication)
  static Future<void> _performHandshake(Socket socket, int timeout) async {
    // Send greeting: [version, nmethods, methods...]
    // We only support no authentication (0x00)
    final greeting = Uint8List.fromList([
      socks5Version, // SOCKS version 5
      0x01, // 1 authentication method
      authNoAuth, // No authentication required
    ]);

    socket.add(greeting);
    await socket.flush();

    _logService.logInfo('Sent SOCKS5 greeting');

    // Receive server response: [version, method]
    final response = await _readBytes(socket, 2, timeout);

    if (response[0] != socks5Version) {
      throw Socks5Exception(
        'Invalid SOCKS version in response: ${response[0]}',
      );
    }

    if (response[1] == authNoAcceptable) {
      throw Socks5Exception('No acceptable authentication method');
    }

    if (response[1] != authNoAuth) {
      throw Socks5Exception(
        'Server requested unsupported authentication method: ${response[1]}',
      );
    }

    _logService.logInfo('SOCKS5 handshake successful (no auth)');
  }

  /// Send SOCKS5 connect request
  static Future<void> _sendConnectRequest(
    Socket socket,
    String targetHost,
    int targetPort,
    int timeout,
  ) async {
    // Build connect request
    final request = <int>[
      socks5Version, // SOCKS version 5
      cmdConnect, // CONNECT command
      0x00, // Reserved
    ];

    // Add target address
    final ipv4 = _parseIPv4(targetHost);
    if (ipv4 != null) {
      // IPv4 address
      request.add(atypIPv4);
      request.addAll(ipv4);
    } else {
      // Domain name
      request.add(atypDomainName);
      request.add(targetHost.length);
      request.addAll(targetHost.codeUnits);
    }

    // Add target port (big-endian)
    request.add((targetPort >> 8) & 0xFF);
    request.add(targetPort & 0xFF);

    socket.add(Uint8List.fromList(request));
    await socket.flush();

    _logService.logInfo(
      '[INFO] Sent CONNECT request for $targetHost:$targetPort',
    );

    // Read response: [version, reply, reserved, atyp, addr, port]
    final header = await _readBytes(socket, 4, timeout);

    if (header[0] != socks5Version) {
      throw Socks5Exception(
        'Invalid SOCKS version in connect response: ${header[0]}',
      );
    }

    final reply = header[1];
    if (reply != repSuccess) {
      throw Socks5Exception(
        'SOCKS5 connect failed: ${_getReplyMessage(reply)} (code: $reply)',
      );
    }

    final atyp = header[3];

    // Read bound address based on type
    int addressLength;
    if (atyp == atypIPv4) {
      addressLength = 4;
    } else if (atyp == atypIPv6) {
      addressLength = 16;
    } else if (atyp == atypDomainName) {
      final domainLengthBytes = await _readBytes(socket, 1, timeout);
      addressLength = domainLengthBytes[0];
    } else {
      throw Socks5Exception('Unsupported address type: $atyp');
    }

    // Read bound address and port
    await _readBytes(socket, addressLength + 2, timeout);

    _logService.logOk('SOCKS5 CONNECT successful');
  }

  /// Parse IPv4 address string to bytes
  ///
  /// Returns null if not a valid IPv4 address.
  static List<int>? _parseIPv4(String address) {
    final parts = address.split('.');
    if (parts.length != 4) return null;

    try {
      final bytes = parts.map((p) => int.parse(p)).toList();
      if (bytes.any((b) => b < 0 || b > 255)) return null;
      return bytes;
    } catch (e) {
      return null;
    }
  }

  /// Read exact number of bytes from socket with timeout
  static Future<Uint8List> _readBytes(
    Socket socket,
    int count,
    int timeout,
  ) async {
    final buffer = <int>[];
    final completer = Completer<Uint8List>();
    StreamSubscription<Uint8List>? subscription;

    final timer = Timer(Duration(seconds: timeout), () {
      subscription?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('SOCKS5 read timeout', Duration(seconds: timeout)),
        );
      }
    });

    subscription = socket.listen(
      (data) {
        buffer.addAll(data);
        if (buffer.length >= count) {
          timer.cancel();
          subscription?.cancel();
          if (!completer.isCompleted) {
            completer.complete(Uint8List.fromList(buffer.sublist(0, count)));
          }
        }
      },
      onError: (error) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            Socks5Exception('Socket closed before receiving all data'),
          );
        }
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  /// Get human-readable message for SOCKS5 reply code
  static String _getReplyMessage(int replyCode) {
    switch (replyCode) {
      case repSuccess:
        return 'Success';
      case repGeneralFailure:
        return 'General SOCKS server failure';
      case repConnectionNotAllowed:
        return 'Connection not allowed by ruleset';
      case repNetworkUnreachable:
        return 'Network unreachable';
      case repHostUnreachable:
        return 'Host unreachable';
      case repConnectionRefused:
        return 'Connection refused';
      case repTTLExpired:
        return 'TTL expired';
      case repCommandNotSupported:
        return 'Command not supported';
      case repAddressTypeNotSupported:
        return 'Address type not supported';
      default:
        return 'Unknown error';
    }
  }
}

/// Exception thrown by SOCKS5 operations
class Socks5Exception implements Exception {
  final String message;

  Socks5Exception(this.message);

  @override
  String toString() => 'Socks5Exception: $message';
}
