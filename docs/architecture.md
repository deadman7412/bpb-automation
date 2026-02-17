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
2. Expand CIDR ranges with **subnet-aware sampling** (see IP Selection Strategy below)
3. Test latency for ALL IPs concurrently
4. Filter successful results, sort by **loss rate first, then latency**
5. Test download speed for top N IPs (from config.downloadCount)
6. Calculate **EWMA-based quality scores** (see Speed Testing Algorithm below)
7. Sort by quality (loss rate → latency → quality score) and return

**Sub-services:**
- **IPLoader**: CIDR expansion with subnet-aware IPv4 selection
- **LatencyTester**: TCP socket-based latency measurement (1s timeout)
- **SpeedTester**: Raw socket HTTPS download with EWMA quality scoring
- **EWMA**: Exponentially Weighted Moving Average for sustained throughput quality

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
  final double qualityScore;  // EWMA-based dimensionless quality metric
  final String? error;

  bool get isSuccessful;
  double get speedMbps;  // Computed from qualityScore (backward compat)
  double get speedKbps;
  double get speedMBps;
}
```

**Note:** Primary metric is now `qualityScore` (EWMA-based), not raw speed in Mbps.

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

## Scanner Algorithm Details

### IP Selection Strategy (Routing Diversity)

**Goal:** Maximize routing diversity to ensure IPs connect through different Cloudflare PoPs (Points of Presence).

**IPv4 Selection (Subnet-Aware):**
- Large CIDR ranges (> /24): Select **one random IP per /24 subnet**
  - Example: `104.16.0.0/13` (524,288 IPs) → Sample from 2,048 different /24 subnets
  - Each /24 subnet typically routes through different paths to your ISP
  - Prevents clustering IPs in the same network segment
- Small CIDR ranges (≤ /24): Random sampling within subnet

**Implementation:**
```dart
// For IPv4 CIDR like 104.16.0.0/13:
1. Calculate number of /24 subnets in range
2. Randomly select N subnets to sample
3. For each selected subnet:
   - Generate random IP within that /24
   - Randomize last octet only (xxx.xxx.xxx.0-255)
4. Result: N IPs from N different /24 subnets
```

**IPv6 Selection (Pure Random):**
- Sample randomly across entire /32 range
- No subnet-based logic (matches Go scanner behavior)
- Randomize last 2 bytes completely

**Why This Matters:**
- Different /24 subnets connect to different Cloudflare edge servers
- Edge servers have different routing paths to your ISP
- Result: IPs with better routing quality for BPB Panel, even if raw speed metrics are similar

### Speed Testing Algorithm (EWMA Quality Score)

**Goal:** Measure sustained throughput quality, not just peak speed.

**EWMA (Exponentially Weighted Moving Average):**
- Library equivalent: `github.com/VividCortex/ewma` (Go)
- Alpha coefficient: **0.2** (20% weight to new samples, 80% to historical average)
- Favors sustained performance over brief bursts

**Sampling Process:**
```dart
1. Start download from speed.cloudflare.com
2. Every 100ms during download:
   - Calculate bytes received since last sample
   - Add to EWMA: ewma.add(bytesInInterval)
3. After download completes:
   - Apply normalization: qualityScore = ewma.value / (timeout / 120)
   - Store qualityScore (dimensionless metric)
```

**Normalization Factor:**
- Formula: `timeout_seconds / 120`
- Example: 10s timeout → factor = 10/120 = 0.0833
- Aligns quality scores across different timeout durations
- Matches Go scanner's download quality calculation

**Quality Score vs Speed Mbps:**
- `qualityScore`: EWMA-based sustained throughput quality (primary metric)
- `speedMbps`: Computed as `(bytesDownloaded * 8) / (durationSeconds * 1000000)` (backward compatibility)
- Quality score is more reliable for BPB Panel performance

### Latency Testing Algorithm

**TCP Socket Connection Test:**
```dart
1. Connect to IP:443 via raw TCP socket
2. Timeout: 1 second (aggressive, matches Go scanner)
3. Measure connection establishment time
4. Repeat 2 times per IP
5. Calculate average latency from successful attempts
```

**Success Criteria:**
- At least 1 successful connection out of 2 attempts
- Connection established within 1s timeout
- Valid TCP handshake completed

**Loss Rate Calculation:**
```dart
lossRate = 1.0 - (successCount / totalAttempts)
// Example: 1 success out of 2 attempts = 50% loss rate
```

### Sorting Algorithm (Multi-Criteria)

**Priority Order:**
1. **Loss Rate** (lower is better) - PRIMARY
2. **Latency** (lower is better) - SECONDARY
3. **Quality Score** (higher is better) - TERTIARY

**Implementation:**
```dart
int compareQuality(ScanResult a, ScanResult b) {
  // Compare loss rates first
  if (a.lossRate != b.lossRate) {
    return a.lossRate.compareTo(b.lossRate);  // Lower wins
  }
  
  // If tied, compare latency
  if (a.latency != b.latency) {
    return a.latency.compareTo(b.latency);  // Lower wins
  }
  
  // If still tied, compare quality score
  return b.qualityScore.compareTo(a.qualityScore);  // Higher wins
}
```

**Why Loss Rate First:**
- 0% packet loss is critical for stable BPB Panel connections
- Low latency with packet loss = unstable connection
- Matches Go scanner's `PingDelaySet.Less()` behavior

## Performance Considerations

### IP Loading & CIDR Expansion
- CIDR ranges use **subnet-aware sampling** for IPv4 (one IP per /24 subnet)
- IPv6 uses pure random sampling across /32 ranges
- Max samples configurable per CIDR (default: 200 IPs)
- Avoids expanding millions of IPs into memory
- Typical load: ~3000 IPs from 15 CIDR ranges
- Loading time: < 1 second

**Routing Diversity:**
- IPv4: 100 samples from /13 range = 100 different /24 subnets
- Result: 100 IPs connecting through different network paths
- Significantly improves BPB Panel IP quality vs random sampling

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
