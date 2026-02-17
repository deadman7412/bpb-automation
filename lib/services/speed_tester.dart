import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:bpb_automation/models/speed_result.dart';
import 'package:bpb_automation/utils/ewma.dart';
import 'log_service.dart';

/// Service for testing download speed
///
/// Uses raw sockets to connect directly to specific IPs
/// and sends HTTP/HTTPS requests manually for accurate testing.
class SpeedTester {
  final LogService _logService = LogService.instance;

  /// Default Cloudflare speed test URL
  static const String defaultSpeedTestUrl =
      'https://speed.cloudflare.com/__down?bytes=';

  /// Test download speed for a single IP
  ///
  /// Downloads data from [testUrl] using [ip] and measures speed.
  /// Optionally accepts [isCancelled] callback to check for cancellation.
  Future<SpeedResult> testSpeed({
    required String ip,
    required int port,
    String testUrl = defaultSpeedTestUrl,
    int downloadBytes = 10000000, // 10 MB default
    Duration timeout = const Duration(seconds: 10),
    bool Function()? isCancelled,
  }) async {
    // Construct URL with bytes parameter
    final fullUrl = testUrl.endsWith('=')
        ? '$testUrl$downloadBytes'
        : testUrl.contains('?bytes=')
        ? testUrl.replaceAll(RegExp(r'\?bytes=\d*'), '?bytes=$downloadBytes')
        : '$testUrl?bytes=$downloadBytes';

    _logService.logInfo(
      '[INFO] Download test START: $ip:$port (${downloadBytes ~/ 1000000} MB, timeout: ${timeout.inSeconds}s)',
    );

    Socket? socket;
    SecureSocket? secureSocket;

    try {
      final uri = Uri.parse(fullUrl);
      final isHttps = uri.scheme == 'https';
      final host = uri.host;
      final path = uri.path + (uri.query.isNotEmpty ? '?${uri.query}' : '');

      _logService.logInfo(
        '[INFO] Connecting to $ip:$port (host: $host, https: $isHttps)',
      );

      final stopwatch = Stopwatch()..start();
      int totalBytes = 0;

      // Connect to the specific IP
      socket = await Socket.connect(ip, port, timeout: timeout);
      _logService.logInfo('[INFO] Socket connected to $ip:$port');

      // If HTTPS, upgrade to secure socket
      if (isHttps) {
        _logService.logInfo('[INFO] Upgrading to secure socket for $ip');
        secureSocket = await SecureSocket.secure(
          socket,
          host: host,
          onBadCertificate: (cert) =>
              true, // Accept any certificate for testing
        ).timeout(timeout);
        _logService.logInfo('[INFO] Secure socket established for $ip');
      }

      final activeSocket = secureSocket ?? socket;

      // Send HTTP GET request
      final request =
          'GET $path HTTP/1.1\r\n'
          'Host: $host\r\n'
          'User-Agent: BPB-Automation/1.0\r\n'
          'Accept: */*\r\n'
          'Connection: close\r\n'
          '\r\n';

      _logService.logInfo('[INFO] Sending HTTP request to $ip: GET $path');
      activeSocket.write(request);
      await activeSocket.flush();

      // Read response with EWMA speed sampling
      bool headersParsed = false;
      int statusCode = 0;
      final buffer = BytesBuilder();

      // EWMA for tracking sustained throughput quality
      final ewma = EWMA(0.2); // Match Go scanner's default
      int lastBytesRead = 0;
      final sampleInterval = Duration(
        milliseconds: timeout.inMilliseconds ~/ 100,
      ); // 100 samples
      Duration lastSampleTime = Duration.zero;

      _logService.logInfo('[INFO] Waiting for response from $ip...');
      await for (final chunk in activeSocket.timeout(timeout)) {
        // Check for cancellation
        if (isCancelled?.call() == true) {
          _logService.logWarn('[WARN] Download test CANCELLED: $ip');
          await activeSocket.close();
          return SpeedResult.failed(
            ip: ip,
            testUrl: fullUrl,
            error: 'Cancelled by user',
          );
        }

        buffer.add(chunk);

        if (!headersParsed) {
          // Try to parse headers
          final data = buffer.toBytes();
          final headerEnd = _findHeaderEnd(data);

          if (headerEnd != -1) {
            // Parse status code
            final headersStr = utf8.decode(data.sublist(0, headerEnd));
            final lines = headersStr.split('\r\n');
            if (lines.isNotEmpty) {
              final statusLine = lines[0];
              final parts = statusLine.split(' ');
              if (parts.length >= 2) {
                statusCode = int.tryParse(parts[1]) ?? 0;
              }
            }

            _logService.logInfo(
              '[INFO] HTTP response from $ip: Status $statusCode',
            );

            // Start counting bytes after headers
            totalBytes = data.length - headerEnd - 4; // -4 for \r\n\r\n
            headersParsed = true;
            lastBytesRead = totalBytes;
            lastSampleTime = stopwatch.elapsed;
          }
        } else {
          totalBytes += chunk.length;

          // Sample speed periodically using EWMA
          final currentTime = stopwatch.elapsed;
          final elapsed = currentTime - lastSampleTime;

          if (elapsed >= sampleInterval) {
            final bytesInInterval = totalBytes - lastBytesRead;
            ewma.add(bytesInInterval.toDouble());
            lastBytesRead = totalBytes;
            lastSampleTime = currentTime;
          }
        }
      }

      stopwatch.stop();

      _logService.logInfo(
        '[INFO] Download complete from $ip: $totalBytes bytes in ${stopwatch.elapsedMilliseconds}ms',
      );

      if (statusCode != 200) {
        throw Exception('HTTP $statusCode');
      }

      if (totalBytes == 0) {
        throw Exception('No data received');
      }

      final durationSeconds = stopwatch.elapsedMicroseconds / 1000000.0;

      // Calculate quality score using EWMA (matches Go scanner)
      // Apply normalization factor: / (timeout.inSeconds / 120)
      final normalizationFactor = timeout.inSeconds / 120;
      double qualityScore = 0.0;

      if (ewma.isInitialized && normalizationFactor > 0) {
        qualityScore = ewma.value / normalizationFactor;
      } else {
        // Fallback to simple average if EWMA wasn't sampled
        qualityScore = (totalBytes / durationSeconds) / normalizationFactor;
      }

      final result = SpeedResult.success(
        ip: ip,
        testUrl: fullUrl,
        bytesDownloaded: totalBytes,
        durationSeconds: durationSeconds,
        qualityScore: qualityScore,
      );

      _logService.logOk(
        '[OK] Download test SUCCESS: $ip - '
        'Quality: ${result.qualityScore.toStringAsFixed(2)} '
        '($totalBytes bytes in ${durationSeconds.toStringAsFixed(2)}s)',
      );

      return result;
    } on SocketException catch (e) {
      _logService.logWarn(
        '[WARN] Download test FAILED (SocketException): $ip - ${e.message}',
      );
      return SpeedResult.failed(
        ip: ip,
        testUrl: fullUrl,
        error: 'Connection failed: ${e.message}',
      );
    } on TimeoutException {
      _logService.logWarn(
        '[WARN] Download test FAILED (Timeout): $ip - timeout after ${timeout.inSeconds}s',
      );
      return SpeedResult.failed(
        ip: ip,
        testUrl: fullUrl,
        error: 'Timeout after ${timeout.inSeconds}s',
      );
    } catch (e) {
      _logService.logWarn('Speed test error for $ip: $e');
      return SpeedResult.failed(ip: ip, testUrl: fullUrl, error: e.toString());
    } finally {
      secureSocket?.destroy();
      socket?.destroy();
    }
  }

  /// Find the end of HTTP headers (\\r\\n\\r\\n)
  int _findHeaderEnd(Uint8List data) {
    for (var i = 0; i < data.length - 3; i++) {
      if (data[i] == 13 &&
          data[i + 1] == 10 &&
          data[i + 2] == 13 &&
          data[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  /// Test multiple IPs concurrently with limited parallelism
  Stream<SpeedResult> testMultiple({
    required List<String> ips,
    required int port,
    String testUrl = defaultSpeedTestUrl,
    int downloadBytes = 10000000,
    Duration timeout = const Duration(seconds: 10),
    int maxConcurrent = 5,
    bool Function()? isCancelled,
  }) async* {
    _logService.logInfo(
      'Testing download speed for ${ips.length} IPs with max $maxConcurrent concurrent',
    );

    var completed = 0;
    var started = 0;
    final pending = <String, Future<SpeedResult>>{};

    while (started < ips.length || pending.isNotEmpty) {
      // Check for cancellation
      if (isCancelled?.call() == true) {
        _logService.logWarn('[WARN] Speed test batch cancelled');
        return;
      }

      // Start new tasks up to max concurrent
      while (started < ips.length && pending.length < maxConcurrent) {
        final ip = ips[started];
        started++;

        final task = testSpeed(
          ip: ip,
          port: port,
          testUrl: testUrl,
          downloadBytes: downloadBytes,
          timeout: timeout,
          isCancelled: isCancelled,
        );

        pending[ip] = task;
      }

      // Wait for at least one to complete
      if (pending.isNotEmpty) {
        final result = await Future.any(pending.values);

        // Remove completed task from pending
        pending.remove(result.ip);

        completed++;
        _logService.logInfo('Speed test progress: $completed/${ips.length}');

        yield result;
      }
    }

    _logService.logOk('All speed tests completed: $completed results');
  }

  /// Test IPs in batch and collect all results
  Future<List<SpeedResult>> testBatch({
    required List<String> ips,
    required int port,
    String testUrl = defaultSpeedTestUrl,
    int downloadBytes = 10000000,
    Duration timeout = const Duration(seconds: 10),
    int maxConcurrent = 5,
    bool Function()? isCancelled,
  }) async {
    _logService.logInfo('Starting batch speed test for ${ips.length} IPs');

    final results = <SpeedResult>[];

    await for (final result in testMultiple(
      ips: ips,
      port: port,
      testUrl: testUrl,
      downloadBytes: downloadBytes,
      timeout: timeout,
      maxConcurrent: maxConcurrent,
      isCancelled: isCancelled,
    )) {
      results.add(result);
    }

    // Sort by speed (fastest first)
    results.sort((a, b) {
      // Successful results come first
      if (a.isSuccessful != b.isSuccessful) {
        return a.isSuccessful ? -1 : 1;
      }
      // Among successful, higher speed is better (reverse comparison)
      return b.speedMbps.compareTo(a.speedMbps);
    });

    _logService.logOk('Batch speed test complete: ${results.length} results');

    return results;
  }
}
