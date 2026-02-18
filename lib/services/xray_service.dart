import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
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
  /// Extracts the binary from assets if needed and sets up for use.
  /// Safe to call multiple times - will skip if already initialized.
  ///
  /// Returns true if initialization successful, false otherwise.
  Future<bool> initialize() async {
    if (_isInitialized) {
      _logService.logInfo('[INFO] XrayService already initialized');
      return true;
    }

    try {
      _logService.logInfo('[INFO] Initializing XrayService...');

      // Detect platform and get asset path
      final assetPath = _getAssetPath();
      if (assetPath == null) {
        _logService.logError(
          '[ERROR] Unsupported platform: ${Platform.operatingSystem}',
        );
        return false;
      }

      _logService.logInfo('[INFO] Platform: ${Platform.operatingSystem}');
      _logService.logInfo('[INFO] Asset path: $assetPath');

      // Get app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final xrayDir = Directory(path.join(appDir.path, 'xray'));

      // Create directory if it doesn't exist
      if (!await xrayDir.exists()) {
        await xrayDir.create(recursive: true);
        _logService.logInfo('[INFO] Created Xray directory: ${xrayDir.path}');
      }

      final binaryPath = path.join(xrayDir.path, binaryFileName);
      final versionFilePath = path.join(xrayDir.path, versionFileName);

      // Check if extraction is needed
      final needsExtraction = await _needsExtraction(
        binaryPath,
        versionFilePath,
      );

      if (needsExtraction) {
        _logService.logInfo('[INFO] Extracting Xray binary...');
        await _extractBinary(assetPath, binaryPath);
        await _writeVersionFile(versionFilePath);
        await _setExecutePermissions(binaryPath);
        _logService.logOk('[OK] Xray binary extracted successfully');
      } else {
        _logService.logInfo('[INFO] Xray binary already up to date');
      }

      _binaryPath = binaryPath;
      _isInitialized = true;

      _logService.logOk(
        '[OK] XrayService initialized successfully (version: $xrayVersion)',
      );
      return true;
    } catch (e, stackTrace) {
      _logService.logError('[ERROR] Failed to initialize XrayService: $e');
      _logService.logError('[ERROR] Stack trace: $stackTrace');
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
      _logService.logInfo('[INFO] Binary not found, extraction needed');
      return true;
    }

    // Check version file
    final versionFile = File(versionFilePath);
    if (!await versionFile.exists()) {
      _logService.logInfo('[INFO] Version file not found, extraction needed');
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
      _logService.logError('[ERROR] Failed to extract binary: $e');
      rethrow;
    }
  }

  /// Write version file to track installed version
  Future<void> _writeVersionFile(String versionFilePath) async {
    final file = File(versionFilePath);
    await file.writeAsString(xrayVersion);
    _logService.logInfo('[INFO] Version file written: $xrayVersion');
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
        _logService.logOk('[OK] Execute permissions set');
      } else {
        _logService.logWarn(
          '[WARN] Failed to set execute permissions: ${result.stderr}',
        );
      }
    } catch (e) {
      _logService.logWarn('[WARN] Failed to set execute permissions: $e');
    }
  }

  /// Get Xray version from binary
  ///
  /// Returns the version string or null if unable to determine.
  Future<String?> getBinaryVersion() async {
    if (_binaryPath == null) {
      _logService.logWarn('[WARN] Binary path not set, cannot get version');
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
      _logService.logWarn('[WARN] Failed to get binary version: $e');
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

    final startTime = DateTime.now();
    Process? xrayProcess;
    String? configPath;

    try {
      _logService.logInfo('[INFO] Testing \$candidateIP with Xray proxy...');

      // Replace address in config
      final testConfig = config.copyWithAddress(candidateIP);

      // Add test inbound (SOCKS5 on 127.0.0.1:10808)
      final configWithInbound = testConfig.withTestInbound();

      // Write config to temp file
      configPath = await _writeConfigToTempFile(configWithInbound);
      _logService.logInfo('[INFO] Config written to: \$configPath');

      // Start Xray process
      xrayProcess = await _startXrayProcess(configPath);
      _logService.logInfo(
        '[INFO] Xray process started (PID: \${xrayProcess.pid})',
      );

      // Wait for Xray to initialize
      await Future.delayed(const Duration(seconds: 2));

      // Test proxy connection
      final proxyResult = await _testProxyConnection(
        socksPort: 10808,
        timeout: timeoutSeconds,
      );

      final latency = DateTime.now()
          .difference(startTime)
          .inMilliseconds
          .toDouble();

      _logService.logOk(
        '[OK] Proxy test for \$candidateIP: \${proxyResult.success ? "SUCCESS" : "FAILED"} '
        '(\${latency.toStringAsFixed(0)}ms)',
      );

      // Create result with updated latency
      final updatedProxyResult = ProxyTestResult(
        success: proxyResult.success,
        latencyMs: latency,
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
      _logService.logError('[ERROR] Proxy test failed for $candidateIP: $e');
      _logService.logError('[ERROR] Stack trace: $stackTrace');

      return ConfigTestResult(
        ip: candidateIP,
        config: config,
        proxyTestResult: ProxyTestResult.failure(error: e.toString()),
        qualityScore: 0,
        timestamp: startTime,
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
      ], mode: ProcessStartMode.detached);

      // Listen to stdout/stderr for debugging (don't wait for completion)
      process.stdout.listen((data) {
        _logService.logInfo('[INFO] Xray stdout: ${utf8.decode(data).trim()}');
      });

      process.stderr.listen((data) {
        _logService.logWarn('[WARN] Xray stderr: ${utf8.decode(data).trim()}');
      });

      return process;
    } catch (e) {
      _logService.logError('[ERROR] Failed to start Xray process: \$e');
      rethrow;
    }
  }

  /// Test proxy connection via SOCKS5
  ///
  /// Connects to http://www.gstatic.com/generate_204 through the SOCKS5 proxy
  /// and verifies we get a 204 No Content response.
  Future<ProxyTestResult> _testProxyConnection({
    required int socksPort,
    required int timeout,
  }) async {
    Socket? socket;

    try {
      // Connect via SOCKS5 to www.gstatic.com:80
      socket = await Socks5Helper.connectViaSocks5(
        socksHost: '127.0.0.1',
        socksPort: socksPort,
        targetHost: 'www.gstatic.com',
        targetPort: 80,
        timeout: timeout,
      );

      _logService.logInfo('[INFO] SOCKS5 connection established');

      // Send HTTP GET request
      final request =
          'GET /generate_204 HTTP/1.1\\r\\n'
          'Host: www.gstatic.com\\r\\n'
          'Connection: close\\r\\n'
          '\\r\\n';

      socket.write(request);
      await socket.flush();

      _logService.logInfo('[INFO] HTTP request sent');

      // Read response with timeout
      final responseBytes = await socket
          .timeout(Duration(seconds: timeout))
          .toList();
      final response = utf8.decode(responseBytes.expand((x) => x).toList());

      _logService.logInfo(
        '[INFO] HTTP response received: ${response.substring(0, response.length > 100 ? 100 : response.length)}',
      );

      // Check for 204 No Content
      if (response.contains('204') || response.contains('No Content')) {
        _logService.logOk('[OK] Received 204 No Content response');
        return ProxyTestResult.success(
          latencyMs: 0, // Will be updated by caller
          statusCode: 204,
        );
      } else {
        _logService.logWarn(
          '[WARN] Unexpected HTTP response (expected 204): \${response.substring(0, 50)}',
        );
        return ProxyTestResult.failure(
          error: 'Unexpected HTTP status (expected 204)',
          statusCode: _extractHttpStatus(response),
        );
      }
    } on TimeoutException catch (e) {
      _logService.logError('[ERROR] Proxy connection timeout: $e');
      return ProxyTestResult.failure(error: 'Connection timeout');
    } on Socks5Exception catch (e) {
      _logService.logError('[ERROR] SOCKS5 error: $e');
      return ProxyTestResult.failure(error: 'SOCKS5 error: ${e.message}');
    } catch (e) {
      _logService.logError('[ERROR] Proxy connection failed: $e');
      return ProxyTestResult.failure(error: e.toString());
    } finally {
      await socket?.close();
    }
  }

  /// Extract HTTP status code from response
  int? _extractHttpStatus(String response) {
    final match = RegExp(r'HTTP/\d\.\d\s+(\d+)').firstMatch(response);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Write Xray config to temporary file
  Future<String> _writeConfigToTempFile(XrayConfig config) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final configPath = path.join(tempDir.path, 'xray_test_$timestamp.json');

    final configJson = json.encode(config.toJson());
    final file = File(configPath);
    await file.writeAsString(configJson);

    return configPath;
  }

  /// Cleanup after proxy test
  Future<void> _cleanupProxyTest(Process? process, String? configPath) async {
    // Kill Xray process
    if (process != null) {
      try {
        process.kill();
        _logService.logInfo('[INFO] Xray process killed');
      } catch (e) {
        _logService.logWarn('[WARN] Failed to kill Xray process: \$e');
      }
    }

    // Delete temp config file
    if (configPath != null) {
      try {
        final file = File(configPath);
        if (await file.exists()) {
          await file.delete();
          _logService.logInfo('[INFO] Temp config file deleted');
        }
      } catch (e) {
        _logService.logWarn('[WARN] Failed to delete temp config: \$e');
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
          _logService.logOk('[OK] Xray directory cleaned up');
        }
      }

      _binaryPath = null;
      _isInitialized = false;
    } catch (e) {
      _logService.logError('[ERROR] Failed to cleanup: \$e');
    }
  }
}
