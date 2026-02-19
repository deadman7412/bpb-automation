import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:bpb_automation/services/log_service.dart';
import 'package:bpb_automation/models/xray_config.dart';
import 'package:bpb_automation/models/config_test_result.dart';
import 'package:bpb_automation/utils/socks5_helper.dart';

/// Service for managing Xray-core binary and proxy testing
///
/// Handles:
/// - Platform detection
/// - Binary extraction from assets to app directory
/// - Version tracking
/// - Binary lifecycle management
class XrayService {
  static final XrayService _instance = XrayService._internal();
  static XrayService get instance => _instance;

  XrayService._internal();

  final LogService _logService = LogService.instance;

  /// Current Xray-core version bundled in the app
  static const String xrayVersion = 'v26.2.6';

  /// External non-Cloudflare target used in Phase 2 to verify the BPB Worker
  /// can reach the real internet. Must NOT be a Cloudflare-hosted domain —
  /// Cloudflare Workers can always reach other Cloudflare services via internal
  /// routing, so a Cloudflare target (e.g. cp.cloudflare.com) would pass even
  /// when the Worker has no real outbound internet access.
  ///
  /// connectivitycheck.gstatic.com is Google's dedicated connectivity probe:
  /// - Returns HTTP 204 at /generate_204 — no body, fast response
  /// - Not hosted on Cloudflare — forces a real TCP connection to the internet
  /// - Globally distributed and highly available
  static const String _phase2TestHost = 'connectivitycheck.gstatic.com';
  static const String _phase2TestPath = '/generate_204';
  static const int _phase2TestPort = 80;

  /// Version file name for tracking extracted binary version
  static const String versionFileName = '.xray_version';

  /// Binary file name (platform-specific)
  String get binaryFileName => Platform.isWindows ? 'xray.exe' : 'xray';

  /// Path to extracted binary (null if not initialized)
  String? _binaryPath;

  /// Whether the service has been initialized
  bool _isInitialized = false;

  /// Get the path to the extracted binary
  String? get binaryPath => _binaryPath;

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;

  /// Initialize the Xray service
  ///
  /// On Android, uses the binary installed by the package manager into
  /// nativeLibraryDir (the only executable location on modern Android).
  /// On other platforms, extracts the binary from assets if needed.
  /// Safe to call multiple times - will skip if already initialized.
  ///
  /// Returns true if initialization successful, false otherwise.
  Future<bool> initialize() async {
    if (_isInitialized) {
      _logService.logInfo('XrayService already initialized');
      return true;
    }

    try {
      _logService.logInfo('Initializing XrayService...');
      _logService.logInfo('Platform: ${Platform.operatingSystem}');

      // Android: execute from nativeLibraryDir (the only exec-allowed path).
      // All app-writable dirs (app_flutter, cache, files) are mounted noexec
      // on Android 10+, so asset extraction + chmod cannot work there.
      if (Platform.isAndroid) {
        return await _initializeAndroid();
      }

      // Detect platform and get asset path for non-Android platforms
      final assetPath = _getAssetPath();
      if (assetPath == null) {
        _logService.logError(
          '[ERROR] Unsupported platform: ${Platform.operatingSystem}',
        );
        return false;
      }

      _logService.logInfo('Asset path: $assetPath');

      // Get app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final xrayDir = Directory(path.join(appDir.path, 'xray'));

      // Create directory if it doesn't exist
      if (!await xrayDir.exists()) {
        await xrayDir.create(recursive: true);
        _logService.logInfo('Created Xray directory: ${xrayDir.path}');
      }

      final binaryPath = path.join(xrayDir.path, binaryFileName);
      final versionFilePath = path.join(xrayDir.path, versionFileName);

      // Check if extraction is needed
      final needsExtraction = await _needsExtraction(
        binaryPath,
        versionFilePath,
      );

      if (needsExtraction) {
        _logService.logInfo('Extracting Xray binary...');
        await _extractBinary(assetPath, binaryPath);
        await _writeVersionFile(versionFilePath);
        _logService.logOk('Xray binary extracted successfully');
      } else {
        _logService.logInfo('Xray binary already up to date');
      }

      // Always ensure execute permissions (and remove quarantine on macOS)
      await _setExecutePermissions(binaryPath);

      _binaryPath = binaryPath;
      _isInitialized = true;

      _logService.logOk(
        '[OK] XrayService initialized successfully (version: $xrayVersion)',
      );
      return true;
    } catch (e, stackTrace) {
      _logService.logError('Failed to initialize XrayService: $e');
      _logService.logError('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Android-specific initialization using nativeLibraryDir.
  ///
  /// The xray binary is packaged as libxray.so in jniLibs/arm64-v8a/.
  /// Android extracts it to nativeLibraryDir at install time, which is
  /// an exec-enabled filesystem location (unlike all app-writable dirs).
  Future<bool> _initializeAndroid() async {
    try {
      const channel = MethodChannel('com.bpb.bpb_automation/native');
      final nativeLibDir =
          await channel.invokeMethod<String>('getNativeLibraryDir');

      if (nativeLibDir == null || nativeLibDir.isEmpty) {
        _logService.logError(
          '[ERROR] Could not determine Android native library directory',
        );
        return false;
      }

      _logService.logInfo('Native library dir: $nativeLibDir');

      final binaryPath = path.join(nativeLibDir, 'libxray.so');
      final binaryFile = File(binaryPath);

      if (!await binaryFile.exists()) {
        _logService.logError(
          '[ERROR] libxray.so not found at: $binaryPath',
        );
        _logService.logError(
          '[ERROR] Reinstall the app to restore the binary',
        );
        return false;
      }

      final stat = await binaryFile.stat();
      _logService.logInfo(
        'Binary size: ${(stat.size / 1024 / 1024).toStringAsFixed(1)}MB',
      );

      // chmod is harmless here and ensures x bit is set just in case
      await _setExecutePermissions(binaryPath);

      _binaryPath = binaryPath;
      _isInitialized = true;

      _logService.logOk(
        '[OK] XrayService initialized (Android nativeLibraryDir)',
      );
      return true;
    } catch (e, stackTrace) {
      _logService.logError('Android initialization failed: $e');
      _logService.logError('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Detect platform and return the appropriate asset path
  String? _getAssetPath() {
    if (Platform.isAndroid) {
      return 'assets/xray-binaries/android-arm64/$binaryFileName';
    } else if (Platform.isMacOS) {
      // Detect macOS architecture
      final arch = _getMacOSArchitecture();
      return 'assets/xray-binaries/$arch/$binaryFileName';
    } else if (Platform.isLinux) {
      return 'assets/xray-binaries/linux-amd64/$binaryFileName';
    } else if (Platform.isWindows) {
      return 'assets/xray-binaries/windows-amd64/$binaryFileName';
    }
    return null;
  }

  /// Detect macOS architecture (darwin-amd64 or darwin-arm64)
  String _getMacOSArchitecture() {
    // Try to detect Apple Silicon vs Intel
    try {
      final result = Process.runSync('uname', ['-m']);
      final arch = (result.stdout as String).trim();

      if (arch == 'arm64') {
        return 'darwin-arm64';
      }
      return 'darwin-amd64';
    } catch (e) {
      _logService.logWarn(
        '[WARN] Failed to detect macOS architecture, defaulting to amd64: $e',
      );
      return 'darwin-amd64';
    }
  }

  /// Check if binary extraction is needed
  Future<bool> _needsExtraction(
    String binaryPath,
    String versionFilePath,
  ) async {
    // Check if binary exists
    final binaryFile = File(binaryPath);
    if (!await binaryFile.exists()) {
      _logService.logInfo('Binary not found, extraction needed');
      return true;
    }

    // Check version file
    final versionFile = File(versionFilePath);
    if (!await versionFile.exists()) {
      _logService.logInfo('Version file not found, extraction needed');
      return true;
    }

    // Compare versions
    final installedVersion = await versionFile.readAsString();
    if (installedVersion.trim() != xrayVersion) {
      _logService.logInfo(
        '[INFO] Version mismatch (installed: ${installedVersion.trim()}, '
        'bundled: $xrayVersion), extraction needed',
      );
      return true;
    }

    return false;
  }

  /// Extract binary from assets to app directory
  Future<void> _extractBinary(String assetPath, String targetPath) async {
    try {
      // Load binary from assets
      final byteData = await rootBundle.load(assetPath);
      final buffer = byteData.buffer;

      // Write to file
      final file = File(targetPath);
      await file.writeAsBytes(
        buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
      );

      _logService.logOk(
        '[OK] Binary extracted: ${(buffer.lengthInBytes / 1024 / 1024).toStringAsFixed(1)} MB',
      );
    } catch (e) {
      _logService.logError('Failed to extract binary: $e');
      rethrow;
    }
  }

  /// Write version file to track installed version
  Future<void> _writeVersionFile(String versionFilePath) async {
    final file = File(versionFilePath);
    await file.writeAsString(xrayVersion);
    _logService.logInfo('Version file written: $xrayVersion');
  }

  /// Set execute permissions on Unix-based systems
  Future<void> _setExecutePermissions(String binaryPath) async {
    if (Platform.isWindows) {
      // Windows doesn't need execute permissions
      return;
    }

    try {
      final result = await Process.run('chmod', ['+x', binaryPath]);
      if (result.exitCode == 0) {
        _logService.logOk('Execute permissions set');
      } else {
        _logService.logWarn(
          'Failed to set execute permissions: ${result.stderr}',
        );
      }
    } catch (e) {
      _logService.logWarn('Failed to set execute permissions: $e');
    }

    // On macOS, remove quarantine attribute that blocks execution of
    // binaries written by sandboxed apps
    if (Platform.isMacOS) {
      try {
        await Process.run('xattr', [
          '-d',
          'com.apple.quarantine',
          binaryPath,
        ]);
        _logService.logInfo('Quarantine attribute removed');
      } catch (_) {
        // Attribute may not exist - ignore
      }
    }
  }

  /// Get Xray version from binary
  ///
  /// Returns the version string or null if unable to determine.
  Future<String?> getBinaryVersion() async {
    if (_binaryPath == null) {
      _logService.logWarn('Binary path not set, cannot get version');
      return null;
    }

    try {
      final result = await Process.run(_binaryPath!, ['version']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        // Extract version from output (format: "Xray 1.8.x (Xray, Penetrates Everything.) ...")
        final versionMatch = RegExp(r'Xray\s+([\d.]+)').firstMatch(output);
        if (versionMatch != null) {
          return versionMatch.group(1);
        }
      }
      return null;
    } catch (e) {
      _logService.logWarn('Failed to get binary version: $e');
      return null;
    }
  }

  /// Test IP with proxy (Phase 2 testing)
  ///
  /// This is the main method for Phase 2 proxy testing:
  /// 1. Replace address in config with candidate IP
  /// 2. Write config to temp file
  /// 3. Start Xray process
  /// 4. Wait for initialization
  /// 5. Test via SOCKS5
  /// 6. Measure latency and verify response
  /// 7. Kill process and cleanup
  ///
  /// Returns ConfigTestResult with proxy test results.
  Future<ConfigTestResult> testIPWithProxy({
    required XrayConfig config,
    required String candidateIP,
    required int timeoutSeconds,
  }) async {
    if (!_isInitialized) {
      _logService.logError(
        '[ERROR] XrayService not initialized. Call initialize() first.',
      );
      return ConfigTestResult(
        ip: candidateIP,
        config: config,
        proxyTestResult: ProxyTestResult.failure(
          error: 'XrayService not initialized',
        ),
        qualityScore: 0,
        timestamp: DateTime.now(),
      );
    }

    final xrayStartTime = DateTime.now();
    Process? xrayProcess;
    String? configPath;

    try {
      _logService.logInfo('Testing $candidateIP with Xray proxy...');

      // Replace address in config
      final testConfig = config.copyWithAddress(candidateIP);

      // Add test inbound (SOCKS5 on 127.0.0.1:10808)
      final configWithInbound = testConfig.withTestInbound();

      // Write config to temp file
      configPath = await _writeConfigToTempFile(configWithInbound);
      _logService.logInfo('Config written to: $configPath');

      // Start Xray process
      xrayProcess = await _startXrayProcess(configPath);
      _logService.logInfo(
        'Xray process started (PID: ${xrayProcess.pid})',
      );

      // Poll until Xray binds port 10808 (up to 8 s)
      // Replaces fixed 2 s delay — Xray with ECH + fragmentation takes 3-5 s
      final xrayReady = await _waitForXrayPort(10808, maxWaitSeconds: 8);
      if (!xrayReady) {
        _logService.logError('Xray did not bind port 10808 within 8 seconds');
        return ConfigTestResult(
          ip: candidateIP,
          config: config,
          proxyTestResult: ProxyTestResult.failure(
            error: 'Xray startup timeout (port 10808 never opened)',
          ),
          qualityScore: 0,
          timestamp: xrayStartTime,
        );
      }

      final xrayReadyTime = DateTime.now();
      final xrayStartupMs =
          xrayReadyTime.difference(xrayStartTime).inMilliseconds;
      _logService.logInfo(
        'Xray ready on port 10808 (startup: ${xrayStartupMs}ms)',
      );

      // Compute remaining HTTP test budget after startup.
      // Cap at a minimum so very slow starts don't leave zero time for the test.
      const minHttpTimeoutSeconds = 5;
      final httpTimeoutSeconds =
          (timeoutSeconds - (xrayStartupMs / 1000).ceil())
              .clamp(minHttpTimeoutSeconds, timeoutSeconds);
      _logService.logInfo(
        'HTTP test timeout: ${httpTimeoutSeconds}s '
        '(${timeoutSeconds}s total - ${(xrayStartupMs / 1000).ceil()}s startup)',
      );

      // Log the worker host for debugging only — the actual test uses an
      // external host to confirm the Worker can reach the broader internet.
      final workerHost = config.getSni() ?? '';
      _logService.logInfo(
        'Worker: $workerHost — testing outbound via $_phase2TestHost',
      );

      final proxyResult = await _testProxyConnection(
        socksPort: 10808,
        httpTimeoutSeconds: httpTimeoutSeconds,
      );

      // Measure latency from Xray-ready to HTTP response. This isolates actual
      // network round-trip from process startup time (logged separately above).
      final proxyLatency = DateTime.now()
          .difference(xrayReadyTime)
          .inMilliseconds
          .toDouble();

      _logService.logOk(
        'Proxy test for $candidateIP: '
        '${proxyResult.success ? "SUCCESS" : "FAILED"} '
        '(proxy: ${proxyLatency.toStringAsFixed(0)}ms, '
        'startup: ${xrayStartupMs}ms)',
      );

      // Create result with latency measured from Xray-ready (not wall-clock).
      final updatedProxyResult = ProxyTestResult(
        success: proxyResult.success,
        latencyMs: proxyLatency,
        error: proxyResult.error,
        statusCode: proxyResult.statusCode,
        speedMbps: proxyResult.speedMbps,
      );

      return ConfigTestResult.fromBothTests(
        ip: candidateIP,
        config: testConfig,
        tlsTestResult: TlsTestResult.success(latencyMs: 0),
        proxyTestResult: updatedProxyResult,
      );
    } catch (e, stackTrace) {
      _logService.logError('Proxy test failed for $candidateIP: $e');
      _logService.logError('Stack trace: $stackTrace');

      return ConfigTestResult(
        ip: candidateIP,
        config: config,
        proxyTestResult: ProxyTestResult.failure(error: e.toString()),
        qualityScore: 0,
        timestamp: xrayStartTime,
      );
    } finally {
      // Always cleanup: kill process and delete temp file
      await _cleanupProxyTest(xrayProcess, configPath);
    }
  }

  /// Start Xray process with config file
  Future<Process> _startXrayProcess(String configPath) async {
    try {
      final process = await Process.start(_binaryPath!, [
        'run',
        '-c',
        configPath,
      ]);

      // Listen to stdout/stderr for debugging (don't wait for completion)
      process.stdout.listen((data) {
        _logService.logInfo('Xray stdout: ${utf8.decode(data).trim()}');
      });

      process.stderr.listen((data) {
        _logService.logWarn('Xray stderr: ${utf8.decode(data).trim()}');
      });

      return process;
    } catch (e) {
      _logService.logError('Failed to start Xray process: $e');
      rethrow;
    }
  }

  /// Poll until Xray binds [port] or [maxWaitSeconds] elapses.
  ///
  /// Returns true if the port is open, false if it never opened in time.
  Future<bool> _waitForXrayPort(int port, {required int maxWaitSeconds}) async {
    final deadline = DateTime.now().add(Duration(seconds: maxWaitSeconds));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final s = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 300),
        );
        await s.close();
        return true;
      } catch (_) {
        // Not ready yet — brief pause before retry
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    return false;
  }

  /// Test proxy connection via SOCKS5 against a non-Cloudflare external host.
  ///
  /// Flow:
  ///   1. SOCKS5 CONNECT to [_phase2TestHost]:[_phase2TestPort] through Xray
  ///   2. Send HTTP GET [_phase2TestPath]
  ///   3. Read response chunks until an HTTP status line is received or timeout
  ///   4. HTTP 2xx or 3xx = success; 4xx/5xx = failure
  ///
  /// Why non-Cloudflare:
  ///   Cloudflare Workers can always reach other Cloudflare services (e.g.
  ///   cp.cloudflare.com) via Cloudflare's internal network fabric. A test
  ///   against a Cloudflare host passes even when the Worker has no real
  ///   outbound internet access — exactly the false-positive case we need to
  ///   avoid. [_phase2TestHost] is a non-Cloudflare Google connectivity probe.
  ///
  /// Xray fast-accepts SOCKS5 CONNECT before the outbound is established,
  /// so we must wait for the actual HTTP response to confirm end-to-end
  /// connectivity through the Cloudflare → Worker → real internet chain.
  Future<ProxyTestResult> _testProxyConnection({
    required int socksPort,
    required int httpTimeoutSeconds,
  }) async {
    Socks5Connection? conn;

    try {
      conn = await Socks5Helper.connectViaSocks5(
        socksHost: '127.0.0.1',
        socksPort: socksPort,
        targetHost: _phase2TestHost,
        targetPort: _phase2TestPort,
        timeout: httpTimeoutSeconds,
      );

      _logService.logInfo(
        'SOCKS5 connected to $_phase2TestHost:$_phase2TestPort, '
        'sending HTTP GET $_phase2TestPath...',
      );

      // HTTP/1.1 requires CRLF (\r\n). Note: Dart string \r\n = 2 bytes.
      conn.write(utf8.encode(
        'GET $_phase2TestPath HTTP/1.1\r\n'
        'Host: $_phase2TestHost\r\n'
        'Connection: close\r\n'
        '\r\n',
      ));
      await conn.flush();

      // Read response chunks until we find the HTTP status line or timeout.
      // Xray establishes the outbound (ECH + VLESS + Cloudflare) after
      // accepting SOCKS5, so this may take several seconds.
      final buf = StringBuffer();
      final httpStart = DateTime.now();
      final deadline =
          DateTime.now().add(Duration(seconds: httpTimeoutSeconds));

      while (DateTime.now().isBefore(deadline)) {
        final remaining = deadline.difference(DateTime.now()).inSeconds;
        if (remaining <= 0) break;

        List<int> chunk;
        try {
          chunk = await conn.readAvailable(remaining);
        } on TimeoutException {
          break;
        }

        if (chunk.isEmpty) break; // Socket closed cleanly

        buf.write(utf8.decode(chunk, allowMalformed: true));
        final response = buf.toString();

        if (response.contains('\r\n')) {
          final status = _extractHttpStatus(response);
          if (status != null) {
            // Only 2xx/3xx confirm a healthy outbound connection.
            // 4xx/5xx (e.g. 530 Worker Error) indicate Cloudflare or Worker
            // problems — the proxy chain technically works but the Worker
            // cannot serve requests, so these do not count as success.
            if (status >= 200 && status < 400) {
              _logService.logOk(
                'HTTP $status from $_phase2TestHost — outbound internet OK',
              );
              return ProxyTestResult.success(
                latencyMs: 0, // Updated by caller with Xray-ready-relative time
                statusCode: status,
              );
            } else {
              _logService.logWarn(
                'HTTP $status from $_phase2TestHost — not counting as success',
              );
              return ProxyTestResult.failure(
                error: 'HTTP $status',
                statusCode: status,
              );
            }
          }
        }

        if (buf.length > 4096) break;
      }

      final elapsedMs =
          DateTime.now().difference(httpStart).inMilliseconds;
      // Distinguish between actual timeout (elapsedMs ≈ budget) and early
      // socket close (elapsedMs << budget, meaning Xray gave up on outbound).
      final closedEarly = elapsedMs < (httpTimeoutSeconds - 1) * 1000;
      if (closedEarly) {
        _logService.logWarn(
          'Connection closed after ${elapsedMs}ms without HTTP response '
          '(outbound failed — budget was ${httpTimeoutSeconds}s)',
        );
        return ProxyTestResult.failure(
          error: 'Connection closed after ${elapsedMs}ms (no response)',
        );
      } else {
        _logService.logWarn(
          'No HTTP response after ${elapsedMs}ms '
          '(timeout: ${httpTimeoutSeconds}s)',
        );
        return ProxyTestResult.failure(
          error: 'HTTP response timeout after ${httpTimeoutSeconds}s',
        );
      }
    } on TimeoutException catch (e) {
      _logService.logError('Proxy connection timeout: $e');
      return ProxyTestResult.failure(error: 'Connection timeout');
    } on Socks5Exception catch (e) {
      _logService.logError('SOCKS5 error: $e');
      return ProxyTestResult.failure(error: 'SOCKS5 error: ${e.message}');
    } catch (e) {
      _logService.logError('Proxy connection failed: $e');
      return ProxyTestResult.failure(error: e.toString());
    } finally {
      await conn?.close();
    }
  }

  /// Extract HTTP status code from a response string.
  int? _extractHttpStatus(String response) {
    final m = RegExp(r'HTTP/\S+\s+(\d+)').firstMatch(response);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  /// Write Xray config to temporary file
  Future<String> _writeConfigToTempFile(XrayConfig config) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final configPath = path.join(tempDir.path, 'xray_test_$timestamp.json');

    final configJson = json.encode(config.toJson());
    final file = File(configPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(configJson);

    return configPath;
  }

  /// Cleanup after proxy test
  Future<void> _cleanupProxyTest(Process? process, String? configPath) async {
    // Kill Xray process
    if (process != null) {
      try {
        process.kill();
        _logService.logInfo('Xray process killed');
      } catch (e) {
        _logService.logWarn('Failed to kill Xray process: $e');
      }
    }

    // Delete temp config file
    if (configPath != null) {
      try {
        final file = File(configPath);
        if (await file.exists()) {
          await file.delete();
          _logService.logInfo('Temp config file deleted');
        }
      } catch (e) {
        _logService.logWarn('Failed to delete temp config: $e');
      }
    }
  }

  /// Clean up extracted binary and version file
  ///
  /// Useful for testing or forcing re-extraction.
  Future<void> cleanup() async {
    try {
      if (_binaryPath != null) {
        final binaryFile = File(_binaryPath!);
        final binaryDir = binaryFile.parent;

        if (await binaryDir.exists()) {
          await binaryDir.delete(recursive: true);
          _logService.logOk('Xray directory cleaned up');
        }
      }

      _binaryPath = null;
      _isInitialized = false;
    } catch (e) {
      _logService.logError('Failed to cleanup: $e');
    }
  }
}
