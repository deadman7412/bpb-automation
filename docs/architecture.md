# Technical Architecture

## Overview

BPB Automation is a Flutter application with a **pure Dart IP scanner implementation** that provides automated clean IP discovery and BPB Panel updates via Cloudflare Workers KV API.

**Key Design Decision:** The app uses a native Dart scanner instead of external binaries to avoid platform sandboxing issues (especially on macOS) and ensure true cross-platform compatibility.

## Architecture Diagram

```
┌─────────────────────────────────────────────┐
│         Flutter Application UI              │
├─────────────────────────────────────────────┤
│  Screens:                                   │
│  - Home Screen (Scan + Progress)            │
│  - Settings Screen (Credentials + Config)   │
│  - Results Screen (IP List + Stats)         │
│  - Config Screen (Scanner Parameters)       │
│  - Logs Screen (Real-time logs)             │
└──────────────┬──────────────────────────────┘
               │
┌──────────────▼──────────────────────────────┐
│         Service Layer                       │
├─────────────────────────────────────────────┤
│  - DartScannerService (singleton)           │
│    ├─ IPLoader (CIDR expansion)            │
│    ├─ LatencyTester (TCP sockets)          │
│    ├─ SpeedTester (HTTPS download)         │
│    └─ Progress streaming                   │
│  - CloudflareApiService                     │
│    └─ Workers KV read/write                │
│  - StorageService                           │
│    └─ Secure credential storage            │
│  - LogService                               │
│    └─ [OK] [INFO] [WARN] [ERROR] tags      │
└──────────────┬──────────────────────────────┘
               │
┌──────────────▼──────────────────────────────┐
│         External Components                 │
├─────────────────────────────────────────────┤
│  - Cloudflare Workers KV API                │
│  - flutter_secure_storage                   │
│  - IP lists (bundled assets)                │
└─────────────────────────────────────────────┘
```

## Component Details

### 1. DartScannerService

Pure Dart implementation of the IP scanner (no external binaries).

**Responsibilities:**
- Orchestrate complete scan workflow
- Load and expand CIDR IP ranges
- Coordinate latency and speed testing
- Stream real-time progress updates
- Calculate quality scores
- Sort and return results

**Key Methods:**
```dart
Future<DartScanResult> executeScan(ScannerConfig config)
Stream<ScanProgress> startProgressStream()
void stopProgressStream()
bool get isAvailable  // Always true for Dart scanner
String get version    // Returns '1.0.0-dart'
```

**Scan Workflow:**
1. Load IP addresses from bundled assets
2. Expand CIDR ranges to individual IPs (random sampling)
3. Test latency for ALL IPs concurrently
4. Filter successful results
5. Test download speed for top N IPs (from config.downloadCount)
6. Calculate quality scores (60% latency + 40% speed)
7. Sort by quality and return

**Sub-services:**
- **IPLoader**: CIDR expansion and random sampling
- **LatencyTester**: TCP socket-based latency measurement
- **SpeedTester**: Raw socket HTTPS download testing

### 2. CloudflareApiService

Handles all Cloudflare API interactions.

**Responsibilities:**
- Authenticate with API token
- Read current proxySettings from Workers KV
- Update only cleanIPs field (preserve other settings)
- Write updated settings back to KV
- Error handling and retries

**API Endpoints:**
```
GET  /accounts/{account_id}/storage/kv/namespaces/{namespace_id}/values/proxySettings
PUT  /accounts/{account_id}/storage/kv/namespaces/{namespace_id}/values/proxySettings
```

**Key Methods:**
```dart
Future<ProxySettings> getProxySettings()
Future<bool> updateCleanIPs(List<String> ips)
Future<bool> validateCredentials()
```

**Data Flow:**
1. Fetch current proxySettings JSON
2. Parse to ProxySettings model
3. Update cleanIPs array
4. Serialize back to JSON
5. PUT to Cloudflare API

### 3. StorageService

Manages local storage of credentials and app state.

**Storage Strategy:**
- **Sensitive data** (API tokens): flutter_secure_storage (encrypted)
- **App state** (last scan time, settings): shared_preferences

**Stored Data:**
```dart
// Secure storage (encrypted)
- cf_api_token: String
- cf_account_id: String
- cf_kv_namespace_id: String

// Preferences
- scanner_threads: int
- scanner_latency_limit: int
- num_ips_to_use: int
- last_scan_timestamp: DateTime
- auto_update_enabled: bool
- auto_update_interval: int (hours)
```

**Key Methods:**
```dart
Future<void> saveCredentials(Credentials creds)
Future<Credentials?> getCredentials()
Future<void> clearCredentials()
Future<void> saveScannerConfig(ScannerConfig config)
```

### 4. LogService

Centralized logging with tagged output.

**Log Levels:**
- `[OK]` - Success messages
- `[INFO]` - Informational messages
- `[WARN]` - Warnings
- `[ERROR]` - Error messages

**Features:**
- Console output (debug mode)
- File logging (persistent)
- UI display (in-app log viewer)
- Automatic log rotation

**Format:**
```
[2025-02-15 14:30:45] [INFO] Starting IP scan...
[2025-02-15 14:31:12] [OK] Scan completed, found 10 clean IPs
[2025-02-15 14:31:15] [INFO] Updating Cloudflare KV...
[2025-02-15 14:31:18] [OK] Clean IPs updated successfully
```

## Data Models

### LatencyResult
```dart
class LatencyResult {
  final String ip;
  final int port;
  final int successCount;
  final int totalAttempts;
  final double averageLatencyMs;
  final double minLatencyMs;
  final double maxLatencyMs;
  final List<double> latencies;
  final String? error;

  double get successRate;
  bool get isSuccessful;
}
```

### SpeedResult
```dart
class SpeedResult {
  final String ip;
  final String testUrl;
  final int bytesDownloaded;
  final double durationSeconds;
  final double speedMbps;
  final String? error;

  bool get isSuccessful;
  double get speedKbps;
  double get speedMBps;
}
```

### ScanResult
```dart
class ScanResult {
  final String ip;
  final LatencyResult latencyResult;
  final SpeedResult? speedResult;
  final double qualityScore;
  final DateTime timestamp;

  int compareQuality(ScanResult other);
}
```

### ScanProgress
```dart
class ScanProgress {
  final int totalIPs;
  final int processedIPs;
  final int successfulIPs;
  final int failedIPs;
  final String? currentIP;
  final ScanStage stage;
  final String? message;

  double get progress;
  double get progressPercent;
}

enum ScanStage {
  initializing, loadingIPs, latencyTesting,
  speedTesting, sorting, completed, failed
}
```

### CleanIP
```dart
class CleanIP {
  final String ip;
  final int packetsSent;
  final int packetsReceived;
  final double lossRate;
  final double avgLatency;
  final double downloadSpeed;
}
```

### ProxySettings
```dart
class ProxySettings {
  final String remoteDNS;
  final Map<String, dynamic> remoteDnsHost;
  final String localDNS;
  final List<String> cleanIPs;  // This is what we update
  final List<String> proxyIPs;
  final Map<String, dynamic> outProxyParams;
  // ... other fields preserved as-is
}
```

### ScannerConfig
```dart
class ScannerConfig {
  final int threads;
  final int testCount;
  final int downloadCount;
  final int latencyLimit;
  final int latencyLowerLimit;
  final int speedLimit;
  final bool disableDownload;
  final bool httpingMode;
}
```

### Credentials
```dart
class Credentials {
  final String apiToken;
  final String accountId;
  final String kvNamespaceId;
}
```

## Security Architecture

### Credential Storage
- All sensitive data encrypted at rest
- flutter_secure_storage uses:
  - **Android**: Android Keystore
  - **iOS**: iOS Keychain
  - **Desktop**: Platform-specific secure storage

### Network Security
- HTTPS only for Cloudflare API
- Certificate pinning (optional)
- No third-party analytics or tracking
- All network requests user-initiated

### Scanner Security
- Pure Dart implementation - no binary execution
- No sandboxing issues or permission requirements
- All network operations using standard Dart libraries
- TCP/HTTPS connections with proper error handling
- Accept any certificate for speed testing (IP-based connections)

## Error Handling

### Error Types
1. **Network Errors**: Cloudflare API unreachable
2. **Auth Errors**: Invalid API token
3. **Scanner Errors**: Binary execution failed
4. **Parse Errors**: Invalid CSV output
5. **Storage Errors**: Failed to save/load credentials

### Error Recovery
```dart
// Retry logic with exponential backoff
Future<T> retryWithBackoff<T>(
  Future<T> Function() operation,
  {int maxAttempts = 3, Duration initialDelay = Duration(seconds: 1)}
)

// User-friendly error messages
String getUserFriendlyError(Exception e) {
  if (e is NetworkException) return "Network unreachable. Check connection.";
  if (e is AuthException) return "Invalid credentials. Check API token.";
  // ...
}
```

## Platform-Specific Considerations

### Android
- No special permissions needed (only internet)
- Background execution: WorkManager for scheduled scans
- Distribution: APK sideloading or Play Store
- Works without sandboxing restrictions

### iOS
- Code signing: Developer account required
- Background execution: Background fetch API
- Distribution: TestFlight or App Store
- No binary execution issues

### Desktop (macOS/Linux/Windows)
- No binary extraction or permissions needed
- **macOS**: No sandboxing issues with pure Dart
- Tray icon: System tray integration (optional)
- Auto-start: Platform-specific (plist/systemd/registry)
- Universal compatibility across all desktop platforms

### Web
- **Pure Dart scanner works in browser** (with CORS considerations)
- Alternative: VPS deployment with backend
- Frontend: Flutter web UI
- Deployment: Cloudflare Pages, Netlify, or VPS

## Performance Considerations

### IP Loading & CIDR Expansion
- CIDR ranges randomly sampled (max 200 IPs per range)
- Avoids expanding millions of IPs into memory
- Typical load: ~3000 IPs from 15 CIDR ranges
- Loading time: < 1 second

### Concurrent Testing
- Configurable parallelism (default: 200 threads)
- Asynchronous stream-based processing
- Map-based pending task tracking
- Automatic rate limiting via maxConcurrent parameter

### Memory Management
- Stream-based result processing (not batch)
- Real-time progress updates via broadcast stream
- Proper StreamController disposal
- Socket cleanup in finally blocks

### Network Efficiency
- Single API call to update KV (not multiple)
- Gzip compression on API requests
- Raw socket connections (lower overhead than HTTP client)
- Connection reuse within test batches

## Future Enhancements

- Multi-account support
- Scan history and analytics
- Export/import settings
- Custom IP ranges
- Notification system
- Background scheduled scans
- Cloud backup of settings (optional)
