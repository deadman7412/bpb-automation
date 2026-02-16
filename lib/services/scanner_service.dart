import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/clean_ip.dart';
import '../models/scanner_config.dart';
import 'log_service.dart';

/// Service for managing the scanner binary extraction and execution
class ScannerService {
  static final ScannerService _instance = ScannerService._internal();
  static ScannerService get instance => _instance;

  ScannerService._internal();

  final LogService _logService = LogService.instance;

  /// Current scanner version from binary name
  static const String scannerVersion = '2.2.5';

  /// Version file to track extracted binary version
  static const String versionFileName = '.scanner_version';

  String? _extractedBinaryPath;
  String? _ipListPath;
  String? _ipv6ListPath;

  /// Get the platform-specific binary directory name
  String _getPlatformBinaryDir() {
    if (Platform.isAndroid) {
      // Android uses arm64 architecture
      return 'android-arm64';
    } else if (Platform.isMacOS) {
      // Detect macOS architecture
      final arch = Platform.version.contains('arm64') ? 'arm64' : 'amd64';
      return 'darwin-$arch';
    } else if (Platform.isLinux) {
      return 'linux-amd64';
    } else if (Platform.isWindows) {
      return 'windows-amd64';
    } else if (Platform.isIOS) {
      return 'ios-arm64';
    } else {
      throw UnsupportedError('Platform ${Platform.operatingSystem} is not supported');
    }
  }

  /// Get the binary filename based on platform
  String _getBinaryName() {
    return Platform.isWindows ? 'CloudflareScanner.exe' : 'CloudflareScanner';
  }

  /// Get the asset path for the binary
  String _getAssetBinaryPath() {
    final platformDir = _getPlatformBinaryDir();
    final binaryName = _getBinaryName();
    return 'assets/binaries/$platformDir/$binaryName';
  }

  /// Get the asset path for IP list
  String _getAssetIpListPath() {
    final platformDir = _getPlatformBinaryDir();
    return 'assets/binaries/$platformDir/ip.txt';
  }

  /// Get the asset path for IPv6 list
  String _getAssetIpv6ListPath() {
    final platformDir = _getPlatformBinaryDir();
    return 'assets/binaries/$platformDir/ipv6.txt';
  }

  /// Get the application directory for extracting binaries
  Future<Directory> _getAppDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // Use app support directory for mobile
      return await getApplicationSupportDirectory();
    } else {
      // Use app documents directory for desktop
      return await getApplicationDocumentsDirectory();
    }
  }

  /// Check if binary needs extraction (first run or version changed)
  Future<bool> _needsExtraction() async {
    try {
      final appDir = await _getAppDirectory();
      final versionFile = File('${appDir.path}/$versionFileName');

      if (!await versionFile.exists()) {
        _logService.logInfo('No version file found, extraction needed');
        return true;
      }

      final extractedVersion = await versionFile.readAsString();
      if (extractedVersion.trim() != scannerVersion) {
        _logService.logInfo(
            'Version mismatch: extracted=$extractedVersion, current=$scannerVersion');
        return true;
      }

      final binaryPath = '${appDir.path}/${_getBinaryName()}';
      if (!await File(binaryPath).exists()) {
        _logService.logInfo('Binary file missing, extraction needed');
        return true;
      }

      _logService.logInfo('Binary already extracted (version $scannerVersion)');
      return false;
    } catch (e, stackTrace) {
      _logService.logError('Error checking extraction status', e, stackTrace);
      return true;
    }
  }

  /// Calculate checksum of a file for verification
  Future<String> _calculateChecksum(List<int> bytes) async {
    // Simple checksum: sum of all bytes modulo a large prime
    int sum = 0;
    for (var byte in bytes) {
      sum = (sum + byte) % 2147483647;
    }
    return sum.toString();
  }

  /// Extract binary from assets to app directory
  Future<void> _extractBinary() async {
    try {
      _logService.logInfo('Starting binary extraction');

      final appDir = await _getAppDirectory();
      final binaryPath = '${appDir.path}/${_getBinaryName()}';
      final ipListPath = '${appDir.path}/ip.txt';
      final ipv6ListPath = '${appDir.path}/ipv6.txt';
      final versionFilePath = '${appDir.path}/$versionFileName';

      // Load binary from assets
      _logService.logInfo('Loading binary from ${_getAssetBinaryPath()}');
      final binaryData = await rootBundle.load(_getAssetBinaryPath());
      final binaryBytes = binaryData.buffer.asUint8List();

      // Calculate checksum
      final checksum = await _calculateChecksum(binaryBytes);
      _logService.logInfo('Binary checksum: $checksum');

      // Write binary to app directory
      _logService.logInfo('Writing binary to $binaryPath');
      final binaryFile = File(binaryPath);
      await binaryFile.writeAsBytes(binaryBytes);

      // Load and write IP lists
      _logService.logInfo('Extracting IP lists');
      final ipListData = await rootBundle.loadString(_getAssetIpListPath());
      await File(ipListPath).writeAsString(ipListData);

      final ipv6ListData = await rootBundle.loadString(_getAssetIpv6ListPath());
      await File(ipv6ListPath).writeAsString(ipv6ListData);

      // Set execute permissions on Unix systems
      if (!Platform.isWindows) {
        _logService.logInfo('Setting execute permissions');
        final result = await Process.run('chmod', ['+x', binaryPath]);
        if (result.exitCode != 0) {
          throw Exception('Failed to set execute permissions: ${result.stderr}');
        }
      }

      // Write version file
      await File(versionFilePath).writeAsString(scannerVersion);

      // Store paths
      _extractedBinaryPath = binaryPath;
      _ipListPath = ipListPath;
      _ipv6ListPath = ipv6ListPath;

      _logService.logOk('Binary extraction completed successfully');
    } catch (e, stackTrace) {
      _logService.logError('Failed to extract binary', e, stackTrace);
      rethrow;
    }
  }

  /// Initialize the scanner service (extracts binary if needed)
  Future<void> initialize() async {
    try {
      _logService.logInfo('Initializing ScannerService');

      final needsExtraction = await _needsExtraction();

      if (needsExtraction) {
        await _extractBinary();
      } else {
        // Binary already extracted, just set paths
        final appDir = await _getAppDirectory();
        _extractedBinaryPath = '${appDir.path}/${_getBinaryName()}';
        _ipListPath = '${appDir.path}/ip.txt';
        _ipv6ListPath = '${appDir.path}/ipv6.txt';

        // Ensure execute permissions on Unix systems
        if (!Platform.isWindows) {
          _logService.logInfo('Ensuring execute permissions on existing binary');
          final result = await Process.run('chmod', ['+x', _extractedBinaryPath!]);
          if (result.exitCode != 0) {
            _logService.logError('Failed to set execute permissions: ${result.stderr}');
          }
        }
      }

      _logService.logOk('ScannerService initialized successfully');
    } catch (e, stackTrace) {
      _logService.logError('Failed to initialize ScannerService', e, stackTrace);
      rethrow;
    }
  }

  /// Get the path to the extracted binary
  String? get binaryPath => _extractedBinaryPath;

  /// Get the path to the IP list file
  String? get ipListPath => _ipListPath;

  /// Get the path to the IPv6 list file
  String? get ipv6ListPath => _ipv6ListPath;

  /// Check if service is initialized
  bool get isInitialized =>
      _extractedBinaryPath != null &&
      _ipListPath != null &&
      _ipv6ListPath != null;

  /// Execute scanner with given configuration
  /// Returns Stream of output lines for real-time updates
  Stream<String> executeScan(ScannerConfig config) async* {
    if (!isInitialized) {
      throw StateError('ScannerService not initialized. Call initialize() first.');
    }

    _logService.logInfo('Starting scanner execution');

    try {
      // Build command-line arguments
      final args = config.toCommandLineArgs();

      _logService.logInfo('Scanner command: $_extractedBinaryPath ${args.join(" ")}');

      // Start the process
      final process = await Process.start(
        _extractedBinaryPath!,
        args,
        workingDirectory: Directory(_extractedBinaryPath!).parent.path,
      );

      _logService.logInfo('Scanner process started (PID: ${process.pid})');

      // Stream stdout
      await for (final line in process.stdout.transform(SystemEncoding().decoder)) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          _logService.logInfo('Scanner: $trimmed');
          yield trimmed;
        }
      }

      // Stream stderr
      await for (final line in process.stderr.transform(SystemEncoding().decoder)) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          _logService.logWarn('Scanner stderr: $trimmed');
          yield '[STDERR] $trimmed';
        }
      }

      // Wait for process to complete
      final exitCode = await process.exitCode;

      if (exitCode == 0) {
        _logService.logOk('Scanner completed successfully (exit code: $exitCode)');
      } else {
        _logService.logError('Scanner exited with code: $exitCode');
        throw Exception('Scanner failed with exit code: $exitCode');
      }
    } catch (e, stackTrace) {
      _logService.logError('Scanner execution failed', e, stackTrace);
      rethrow;
    }
  }

  /// Parse scanner CSV output and return list of CleanIP results
  Future<List<CleanIP>> parseScannerOutput(String outputPath) async {
    try {
      _logService.logInfo('Parsing scanner output from: $outputPath');

      final file = File(outputPath);
      if (!await file.exists()) {
        throw Exception('Output file not found: $outputPath');
      }

      final lines = await file.readAsLines();

      if (lines.isEmpty) {
        _logService.logWarn('Output file is empty');
        return [];
      }

      final results = <CleanIP>[];
      var lineNumber = 0;

      for (final line in lines) {
        lineNumber++;

        // Skip empty lines
        if (line.trim().isEmpty) {
          continue;
        }

        // Skip header line (if present)
        if (line.toLowerCase().contains('ip') &&
            line.toLowerCase().contains('sent') &&
            lineNumber == 1) {
          _logService.logInfo('Skipping header line');
          continue;
        }

        try {
          // Parse CSV line
          final parts = line.split(',');
          final cleanIp = CleanIP.fromCsvRow(parts);
          results.add(cleanIp);
        } catch (e) {
          _logService.logWarn('Failed to parse line $lineNumber: $line', e);
          // Continue parsing other lines
        }
      }

      _logService.logOk('Parsed ${results.length} results from scanner output');

      // Sort by quality (best first)
      results.sort((a, b) => a.compareQuality(b));

      return results;
    } catch (e, stackTrace) {
      _logService.logError('Failed to parse scanner output', e, stackTrace);
      rethrow;
    }
  }

  /// Get top N clean IPs from results
  List<String> getTopCleanIPs(List<CleanIP> results, int count) {
    _logService.logInfo('Selecting top $count clean IPs from ${results.length} results');

    final acceptable = results.where((ip) => ip.isAcceptable()).toList();

    if (acceptable.isEmpty) {
      _logService.logWarn('No acceptable IPs found in results');
      return [];
    }

    // Sort by quality (best first) after filtering
    acceptable.sort((a, b) => a.compareQuality(b));

    final topCount = count.clamp(0, acceptable.length);
    final topIps = acceptable.take(topCount).map((ip) => ip.ip).toList();

    _logService.logOk('Selected ${topIps.length} clean IPs');

    return topIps;
  }
}

