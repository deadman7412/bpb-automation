import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:bpb_automation/services/log_service.dart';

/// Buffered reader over a single socket subscription.
///
/// Dart's [Socket] is a single-subscription stream — calling listen() more
/// than once (or after cancel()) is not reliable. This class listens exactly
/// once and accumulates incoming bytes into an internal buffer. Sequential
/// reads are served from the buffer, waiting for more data when necessary.
class _SocketReader {
  final List<int> _buffer = [];
  Completer<void>? _dataAvailable;
  StreamSubscription<List<int>>? _subscription;
  Object? _error;
  bool _done = false;

  _SocketReader(Socket socket) {
    _subscription = socket.listen(
      (data) {
        _buffer.addAll(data);
        // Wake up any waiting read.
        _dataAvailable?.complete();
        _dataAvailable = null;
      },
      onError: (Object error) {
        _error = error;
        _dataAvailable?.completeError(error);
        _dataAvailable = null;
      },
      onDone: () {
        _done = true;
        // Wake up waiting reads so they can detect EOF.
        _dataAvailable?.complete();
        _dataAvailable = null;
      },
      cancelOnError: true,
    );
  }

  /// Read exactly [count] bytes, waiting for data if necessary.
  Future<Uint8List> readBytes(int count, int timeoutSeconds) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));

    while (_buffer.length < count) {
      if (_error != null) throw _error!;
      if (_done) {
        throw Socks5Exception(
          'Socket closed before receiving $count bytes '
          '(buffered: ${_buffer.length})',
        );
      }

      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        throw TimeoutException(
          'SOCKS5 read timeout after ${timeoutSeconds}s',
          Duration(seconds: timeoutSeconds),
        );
      }

      _dataAvailable = Completer<void>();
      await _dataAvailable!.future.timeout(
        remaining,
        onTimeout: () {
          throw TimeoutException(
            'SOCKS5 read timeout after ${timeoutSeconds}s',
            Duration(seconds: timeoutSeconds),
          );
        },
      );
    }

    final bytes = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return bytes;
  }

  /// Read whatever bytes are currently buffered, waiting for at least 1 byte.
  ///
  /// Returns an empty list if the socket is closed with nothing buffered.
  Future<List<int>> readAvailable(int timeoutSeconds) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));

    while (_buffer.isEmpty) {
      if (_error != null) throw _error!;
      if (_done) return const [];

      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        throw TimeoutException(
          'Read timeout after ${timeoutSeconds}s',
          Duration(seconds: timeoutSeconds),
        );
      }

      _dataAvailable = Completer<void>();
      await _dataAvailable!.future.timeout(
        remaining,
        onTimeout: () {
          throw TimeoutException(
            'Read timeout after ${timeoutSeconds}s',
            Duration(seconds: timeoutSeconds),
          );
        },
      );
    }

    final available = List<int>.from(_buffer);
    _buffer.clear();
    return available;
  }

  void cancel() {
    _subscription?.cancel();
    _subscription = null;
  }
}

/// A live SOCKS5 proxy connection ready for data exchange.
///
/// Returned by [Socks5Helper.connectViaSocks5] after the SOCKS5 handshake
/// completes. The underlying socket stream is kept alive (single subscription,
/// no re-listen), so the caller can read HTTP responses via [readAvailable]
/// after writing an HTTP request via [write] + [flush].
class Socks5Connection {
  final Socket _socket;
  final _SocketReader _reader;

  Socks5Connection._(this._socket, this._reader);

  /// Write bytes to the connection (buffered; call [flush] to send).
  void write(List<int> data) => _socket.add(data);

  /// Flush any buffered write data.
  Future<void> flush() => _socket.flush();

  /// Read exactly [count] bytes (blocks until available or timeout).
  Future<Uint8List> readBytes(int count, int timeoutSeconds) =>
      _reader.readBytes(count, timeoutSeconds);

  /// Read whatever bytes are available (waits for at least 1 byte).
  Future<List<int>> readAvailable(int timeoutSeconds) =>
      _reader.readAvailable(timeoutSeconds);

  /// Close the connection and release resources.
  Future<void> close() async {
    _reader.cancel();
    await _socket.close();
  }
}

/// SOCKS5 protocol helper for connecting through a local proxy.
///
/// Implements SOCKS5 as per RFC 1928. Uses [_SocketReader] so the socket
/// stream is listened to exactly once for the lifetime of the connection,
/// enabling sequential handshake reads followed by arbitrary data exchange
/// on the same connection.
class Socks5Helper {
  static final LogService _logService = LogService.instance;

  // Protocol constants
  static const int _version = 0x05;
  static const int _authNoAuth = 0x00;
  static const int _authNoAcceptable = 0xFF;
  static const int _cmdConnect = 0x01;
  static const int _atypIPv4 = 0x01;
  static const int _atypDomainName = 0x03;
  static const int _atypIPv6 = 0x04;
  static const int _repSuccess = 0x00;

  /// Connect to [targetHost]:[targetPort] through the SOCKS5 proxy at
  /// [socksHost]:[socksPort].
  ///
  /// Returns a [Socks5Connection] on success. The SOCKS5 handshake is fully
  /// complete; the caller can immediately start writing application data
  /// (e.g., an HTTP request) and reading the response via [readAvailable].
  ///
  /// Throws [SocketException], [TimeoutException], or [Socks5Exception] on
  /// failure.
  static Future<Socks5Connection> connectViaSocks5({
    required String socksHost,
    required int socksPort,
    required String targetHost,
    required int targetPort,
    required int timeout,
  }) async {
    Socket? socket;
    try {
      _logService.logInfo(
        'Connecting to SOCKS5 at $socksHost:$socksPort',
      );

      socket = await Socket.connect(
        socksHost,
        socksPort,
        timeout: Duration(seconds: timeout),
      );

      // Create exactly one subscription for the entire connection lifetime.
      final reader = _SocketReader(socket);
      final conn = Socks5Connection._(socket, reader);

      await _handshake(conn, timeout);
      await _connect(conn, targetHost, targetPort, timeout);

      _logService.logOk(
        'SOCKS5 connection established to $targetHost:$targetPort',
      );
      return conn;
    } catch (e) {
      _logService.logError('SOCKS5 connection failed: $e');
      await socket?.close();
      rethrow;
    }
  }

  // --- Internal helpers ---

  static Future<void> _handshake(Socks5Connection conn, int timeout) async {
    // Greeting: VER=5, NMETHODS=1, METHOD=NO_AUTH
    conn.write([_version, 0x01, _authNoAuth]);
    await conn.flush();

    final resp = await conn.readBytes(2, timeout);
    if (resp[0] != _version) {
      throw Socks5Exception('Unexpected SOCKS version: ${resp[0]}');
    }
    if (resp[1] == _authNoAcceptable) {
      throw Socks5Exception('No acceptable authentication method');
    }
    if (resp[1] != _authNoAuth) {
      throw Socks5Exception(
        'Server requires unsupported auth method: ${resp[1]}',
      );
    }
  }

  static Future<void> _connect(
    Socks5Connection conn,
    String host,
    int port,
    int timeout,
  ) async {
    final req = <int>[_version, _cmdConnect, 0x00];

    final ipv4 = _parseIPv4(host);
    if (ipv4 != null) {
      req.add(_atypIPv4);
      req.addAll(ipv4);
    } else {
      req.add(_atypDomainName);
      req.add(host.length);
      req.addAll(host.codeUnits);
    }
    req.add((port >> 8) & 0xFF);
    req.add(port & 0xFF);

    conn.write(req);
    await conn.flush();

    // Read [VER, REP, RSV, ATYP]
    final hdr = await conn.readBytes(4, timeout);
    if (hdr[0] != _version) {
      throw Socks5Exception(
        'Unexpected SOCKS version in CONNECT reply: ${hdr[0]}',
      );
    }
    if (hdr[1] != _repSuccess) {
      throw Socks5Exception(
        'SOCKS5 CONNECT rejected: ${_replyMsg(hdr[1])} (${hdr[1]})',
      );
    }

    // Consume bound address (we don't use it)
    final atyp = hdr[3];
    int addrLen;
    if (atyp == _atypIPv4) {
      addrLen = 4;
    } else if (atyp == _atypIPv6) {
      addrLen = 16;
    } else if (atyp == _atypDomainName) {
      final lb = await conn.readBytes(1, timeout);
      addrLen = lb[0];
    } else {
      throw Socks5Exception('Unknown address type in reply: $atyp');
    }
    await conn.readBytes(addrLen + 2, timeout); // addr + port
  }

  static List<int>? _parseIPv4(String addr) {
    final parts = addr.split('.');
    if (parts.length != 4) return null;
    try {
      final bytes = parts.map(int.parse).toList();
      if (bytes.any((b) => b < 0 || b > 255)) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static String _replyMsg(int code) {
    const msgs = {
      0x00: 'Success',
      0x01: 'General SOCKS server failure',
      0x02: 'Connection not allowed by ruleset',
      0x03: 'Network unreachable',
      0x04: 'Host unreachable',
      0x05: 'Connection refused',
      0x06: 'TTL expired',
      0x07: 'Command not supported',
      0x08: 'Address type not supported',
    };
    return msgs[code] ?? 'Unknown ($code)';
  }
}

/// Exception thrown by SOCKS5 protocol errors.
class Socks5Exception implements Exception {
  final String message;
  const Socks5Exception(this.message);

  @override
  String toString() => 'Socks5Exception: $message';
}
