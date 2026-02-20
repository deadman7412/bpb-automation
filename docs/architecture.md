# Technical Architecture

## Overview

BPB Automation is a Flutter application that uses a **config-based, Xray-powered IP scanner** to find working Cloudflare IPs for BPB Panel and update them with selectable update methods.

The scanner fetches the user's BPB Panel Xray subscription, tests candidate IPs through three verification phases (TCP, TLS, live proxy), and writes the best results back to the panel.

## Architecture Diagram

```
┌─────────────────────────────────────────────────┐
│           Flutter Application UI                │
├─────────────────────────────────────────────────┤
│  Screens:                                       │
│  - Home Screen (start scan / status)            │
│  - Config Screen (subscription URL + params)    │
│  - Settings Screen (update method + credentials)│
│  - Scan Progress Screen (live progress)         │
│  - Config Scan Results Screen (results + IPs)   │
│  - Logs Screen (real-time log viewer)           │
│  - Debug Screen (developer tools)               │
└──────────────┬──────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────┐
│           Service Layer                         │
├─────────────────────────────────────────────────┤
│  DartScannerService (singleton)                 │
│    ├─ SubscriptionService  (config fetch)       │
│    ├─ IPLoader             (CIDR expansion)     │
│    ├─ ConfigTesterService  (Phase 0+1: TCP+TLS) │
│    ├─ XrayService          (Phase 2: proxy test)│
│    └─ ConfigExportService  (JSON export)        │
│                                                 │
│  CloudflareApiService                           │
│    └─ Workers KV read/write                     │
│                                                 │
│  PanelApiService                                │
│    └─ /login + /panel/settings + update-settings│
│                                                 │
│  StorageService                                 │
│    └─ Secure credential + settings storage      │
│                                                 │
│  LogService                                     │
│    └─ [OK] [INFO] [WARN] [ERROR] tagged output  │
└──────────────┬──────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────┐
│           External Components                   │
├─────────────────────────────────────────────────┤
│  - Xray-core binary (bundled, platform-specific)│
│  - Cloudflare Workers KV API                    │
│  - BPB Panel API endpoints                      │
│  - BPB Panel subscription endpoint             │
│  - flutter_secure_storage                       │
│  - IP lists (bundled assets: ip.txt, ipv6.txt)  │
└─────────────────────────────────────────────────┘
```

## Component Details

### 1. DartScannerService

Orchestrates the full scan workflow. Singleton — the scan keeps running even if the user navigates away, and screens can attach/detach to its progress streams.

**Responsibilities:**
- Coordinate subscription fetch, IP loading, Phase 1 TLS testing, Phase 2 proxy testing
- Stream Phase 2 real-time progress
- Broadcast final `ConfigScanResult` on completion
- Handle cancellation

**Key Methods:**
```dart
Future<void> executeConfigScan({
  required XrayConfig templateConfig,
  required String subscriptionUrl,
  int desiredIPCount,
  int phase2TestDepth,
  bool enableIPv6,
  int maxSamplesPerCIDR,
  int batchSize,
})

Stream<Phase2Progress> get phase2ProgressStream
Stream<ConfigScanResult> get completionStream
bool get isScanning
void cancelScan()
```

**Scan Workflow:**
1. Fetch/validate subscription URL → select template config
2. Load IP candidates (CIDR expansion with subnet-aware sampling)
3. Phase 1: TLS handshake test all candidates concurrently
4. Sort Phase 1 results by TLS latency, take top `phase2TestDepth`
5. Phase 2: Live Xray proxy test each candidate sequentially
6. Sort Phase 2 results by proxy latency, take top `desiredIPCount`
7. Emit `ConfigScanResult` on completion stream

### 2. SubscriptionService

Fetches and parses the BPB Panel Xray subscription.

**Responsibilities:**
- Fetch `{url}?app=xray` with retry (3 attempts, exponential backoff, 30s timeout)
- Parse JSON array of Xray config objects
- Filter to IP-based configs (domain-based excluded from TLS testing)
- Select best template config (VLESS/WebSocket preferred)

**Key Methods:**
```dart
Future<List<XrayConfig>> fetchConfigs(String subscriptionUrl)
XrayConfig? selectBestConfig(List<XrayConfig> configs)
```

### 3. IPLoader

Generates the candidate IP pool from bundled CIDR lists.

**Responsibilities:**
- Load IPv4 ranges from `assets/ip_lists/ip.txt`
- Load IPv6 ranges from `assets/ip_lists/ipv6.txt` (when enabled)
- Expand CIDRs using subnet-aware sampling

**IP Selection Strategy:**

**IPv4 (Subnet-Aware):**
- For each CIDR range, group host IPs by /24 subnet
- Select one random IP from each /24 subnet, up to `maxSamplesPerCIDR` per CIDR
- Ensures IPs route through different Cloudflare edge servers
- Example: `104.16.0.0/13` → samples from up to 100 different /24 subnets

**IPv6 (Pure Random):**
- Randomize the host portion of each IPv6 CIDR
- No subnet grouping; pure random sampling

**Key Methods:**
```dart
Future<List<String>> loadIPv4({int maxSamplesPerCIDR})
Future<List<String>> loadIPv6({int maxSamplesPerCIDR})
Future<List<String>> loadAll({bool enableIPv6, int maxSamplesPerCIDR})
```

### 4. ConfigTesterService

Runs Phase 0 (TCP pre-filter) and Phase 1 (two-pass TLS) against all candidate IPs.

**Phase 0 — Two-Probe TCP Filter:**
- Two sequential TCP connections to `ip:443` (1 s each, 100 ms gap)
- Both probes must succeed — eliminates IPs with >50% packet loss
- Survivors sorted by average TCP latency ascending

**Phase 1a + 1b — Two-Pass TLS:**
- Phase 1a: full TLS handshake on all Phase 0 survivors (concurrently)
- Phase 1b: re-tests Phase 1a survivors only (verifies stability)
- Only IPs that pass BOTH passes are kept
- Sort key: `avg(1a, 1b) + |1a - 1b| * 0.5` (penalises jitter)
- Uses `RawSocket`/`RawSecureSocket` to avoid file descriptor leaks

**Key Methods:**
```dart
Future<List<ConfigTestResult>> testIPsWithTLS({
  required List<String> candidateIPs,
  required XrayConfig template,
  int tlsTimeoutSeconds,
  int maxConcurrency,
})

Stream<TlsTestProgress> get progressStream
void cancel()
```

### 5. XrayService

Manages the bundled Xray-core binary and runs Phase 2: live proxy tests.

**Responsibilities:**
- Extract platform-specific Xray binary from app assets
- Launch Xray process with a modified config (IP substituted into outbound)
- Route HTTP test request through SOCKS5 proxy Xray creates
- Test `http://[worker-hostname]/cdn-cgi/trace` — any HTTP status = success
- Terminate Xray process after test, clean up ports

**Why the worker hostname (not gstatic.com):**
Testing gstatic.com confirms Cloudflare CDN connectivity but not that the
BPB Worker zone is reachable via the candidate IP. `/cdn-cgi/trace` is
available on every Cloudflare zone; a 301 redirect still proves routing.

**Binary Assets:**
```
assets/xray-binaries/
├── android-arm64/xray
├── darwin-amd64/xray
├── darwin-arm64/xray
├── linux-amd64/xray
└── windows-amd64/xray.exe
```

**Test Logic:**
1. Write temp Xray config JSON (outbound address = candidate IP)
2. Start Xray process (`xray run -config <path>`)
3. Poll until SOCKS5 proxy opens on localhost:10808 (up to 8 s)
4. HTTP GET `/cdn-cgi/trace` via SOCKS5 to `[worker-hostname]:80`
5. Any HTTP status code = success; record wall-clock latency
6. Kill Xray process, delete temp files

**Key Methods:**
```dart
Future<ProxyTestResult> testIPWithProxy({
  required String ip,
  required XrayConfig templateConfig,
  int timeoutSeconds,
})

Future<bool> get isAvailable
String get binaryPath
```

### 6. ConfigExportService

Builds Xray-compatible config files from scan results for import into VPN apps.

**Responsibilities:**
- Substitute each working IP into the template config
- Drop DNS section and strip geo routing rules (no geo data files bundled)
- Preserve original inbounds, TLS/ECH/fragmentation settings
- Serialize as JSON array (all IPs) or single best-IP JSON object

**Key Methods:**
```dart
List<XrayConfig> buildExportConfigs(ConfigScanResult result)
String exportToJsonArray(ConfigScanResult result)   // all working IPs
String? exportBestConfig(ConfigScanResult result)   // lowest-latency IP only
```

### 7. CloudflareApiService

Handles all Cloudflare Workers KV API interactions.

**Responsibilities:**
- Read current `proxySettings` from Workers KV
- Update only the `cleanIPs` array (all other fields preserved)
- Write updated settings back to KV
- Validate credentials

**API Endpoints:**
```
GET  /accounts/{account_id}/storage/kv/namespaces/{namespace_id}/values/proxySettings
PUT  /accounts/{account_id}/storage/kv/namespaces/{namespace_id}/values/proxySettings
```

**Key Methods:**
```dart
Future<void> updateCleanIPs(Credentials credentials, List<String> ips)
Future<bool> validateCredentials(Credentials credentials)
```

**Data Flow:**
1. Fetch current `proxySettings` JSON from KV
2. Decode JSON, replace `cleanIPs` array
3. Re-encode JSON, PUT back to KV

### 7b. PanelApiService

Handles panel login/session and panel settings update endpoints.

**Responsibilities:**
- Authenticate using panel password
- Read current panel settings (`proxySettings`)
- Update only `cleanIPs` while preserving all other settings fields
- Handle expired session (`401`) by re-auth + retry once

**API Endpoints:**
```
POST /login/authenticate
GET  /panel/settings
PUT  /panel/update-settings
```

**Key Methods:**
```dart
Future<bool> validateCredentials(PanelCredentials credentials)
Future<bool> updateCleanIPs(PanelCredentials credentials, List<String> ips)
```

### 8. StorageService

Manages local storage for credentials and app state.

**Storage Strategy:**
- **Sensitive data** (API tokens): `flutter_secure_storage` (platform keychain)
- **App state** (scan params, last scan time): `shared_preferences`
- **Scan results** (last scan JSON): `shared_preferences`
- **Cached configs** (Xray subscription): `shared_preferences`

**Stored Data:**
```dart
// Secure storage (encrypted)
- cf_api_token
- cf_account_id
- cf_kv_namespace_id
- panel_base_url
- panel_password

// Preferences
- update_mode: String (panel_api | cloudflare_api)
- subscription_url: String
- scan_params: Map (desiredIPCount, phase2TestDepth, enableIPv6, maxSamplesPerCIDR, scanBatchSize)
- last_scan_timestamp: String (ISO 8601)
- last_scan_result: String (JSON)
- cached_configs: String (JSON)
```

### 9. LogService

Centralized logging with tagged output.

**Log Tags:**
- `[OK]` — Success messages
- `[INFO]` — Informational messages
- `[WARN]` — Warnings
- `[ERROR]` — Errors

**Log Format:**
```
[2026-01-15 14:30:45] [INFO] Starting IP scan...
[2026-01-15 14:31:12] [OK] Phase 1 complete: 47 IPs passed TLS
[2026-01-15 14:31:15] [INFO] Starting Phase 2 proxy tests...
[2026-01-15 14:31:58] [OK] Phase 2 complete: 5 working IPs found
```

## Data Models

### XrayConfig
```dart
class XrayConfig {
  // Parsed Xray outbound configuration
  // Contains protocol (vless/vmess/trojan), network, SNI, etc.
  String? getProtocol()
  String? getOutboundAddress()   // hostname or IP
  int? getOutboundPort()
  bool isSecure()                // true for TLS/Reality
  XrayConfig withIP(String ip)   // returns copy with IP substituted
  Map<String, dynamic> toJson()
  factory XrayConfig.fromJson(Map<String, dynamic>)
}
```

### ConfigTestResult
```dart
class ConfigTestResult {
  final String ip;
  final TlsTestResult? tlsTestResult;      // Phase 1 result
  final ProxyTestResult? proxyTestResult;  // Phase 2 result
}

class TlsTestResult {
  final bool success;
  final double latencyMs;
  final String? error;
}

class ProxyTestResult {
  final bool success;
  final double latencyMs;
  final int? statusCode;   // 204 = working
  final String? error;
}
```

### ConfigScanResult
```dart
class ConfigScanResult {
  final int totalTested;       // Phase 1 candidates
  final int phase1Passed;      // TLS handshake successes
  final int phase2Tested;      // IPs tested in Phase 2
  final int workingIPCount;    // HTTP 204 successes
  final List<String> workingIPs;        // sorted by proxy latency
  final List<ConfigTestResult> allResults;
  final Duration scanDuration;
  final XrayConfig templateConfig;
  final DateTime timestamp;

  factory ConfigScanResult.success({...})
  factory ConfigScanResult.failure({...})
  factory ConfigScanResult.fromJson(Map<String, dynamic>)
  Map<String, dynamic> toJson()
}
```

### Phase2Progress
```dart
class Phase2Progress {
  final int totalIPs;
  final int testedIPs;
  final int workingIPs;
  final String? currentIP;

  double get progress;
  double get progressPercent;
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
- All API tokens encrypted at rest via `flutter_secure_storage`
  - **Android**: Android Keystore
  - **iOS**: iOS Keychain
  - **Desktop**: Platform-specific secure storage (libsecret, Keychain, DPAPI)

### Network Security
- HTTPS only for API calls
- No third-party analytics or tracking
- No data sent anywhere except selected update API (panel and/or Cloudflare) and the user's BPB Panel URL

### Binary Execution
- Xray binary is extracted to app-private temp directory before use
- Execute permission is set programmatically (POSIX platforms)
- Process is killed and temp files deleted after each Phase 2 test
- Binary is verified to exist before scan starts

## Error Handling

### Error Types
1. **Subscription Errors**: Unable to fetch or parse BPB Panel configs
2. **Network Errors**: Selected update API unreachable
3. **Auth Errors**: Invalid panel password or Cloudflare API token
4. **Binary Errors**: Xray binary missing or failed to execute
5. **Storage Errors**: Failed to save/load credentials or results

### Error Recovery
- Subscription fetch: 3 retries with exponential backoff (1s, 2s, 4s), 30s timeout
- Phase 2 proxy test: per-IP timeout (configurable), Xray process killed on failure
- Cloudflare API: retry with exponential backoff, then show detailed error
- Panel API: if session expired (401), auto re-authenticate and retry once

## Platform-Specific Considerations

### Android
- Xray binary: `android-arm64/xray` (ELF 64-bit ARM, linked against Android linker)
- Only arm64-v8a devices supported (covers all modern Android phones)
- Internet permission only (no storage permission required)
- Distribution: APK sideloading

### macOS
- Xray binary: `darwin-arm64/xray` or `darwin-amd64/xray` (selected at runtime)
- Requires network entitlement (`com.apple.security.network.client`)
- Sandbox entitlement allows outgoing connections only

### Linux / Windows
- Xray binary: `linux-amd64/xray` or `windows-amd64/xray.exe`
- No special permissions required

### Web
- Xray binary cannot run in browser; Phase 2 proxy testing unavailable
- Falls back to Phase 1 TLS results only
- Config download available as an alternative to auto-update
- For full Phase 1 + Phase 2 scanning with web UI, deploy browser frontend with a Linux backend worker and scheduler adapter
- Scheduler integration should be adapter-based per platform (cron/systemd/Task Scheduler/WorkManager), all invoking the same headless "run once" workflow

## Performance Considerations

### Phase 1 (TLS Testing)
- Concurrent: up to `batchSize` (default 200) simultaneous sockets
- Each test: TCP connect + TLS handshake (1s timeout)
- Typical duration: 10–30 seconds for 500–1000 IPs

### Phase 2 (Proxy Testing)
- Sequential (one Xray process at a time)
- Each test: Xray startup + HTTP request via SOCKS5
- Typical duration: 5–15 seconds per IP
- For `phase2TestDepth = 50`, expect 5–10 minutes total

### Memory
- IP list loaded once into memory (~few thousand strings)
- Scan results kept in memory, serialized to storage on completion
- Xray binary extracted once per scan to temp directory

## Future Enhancements

- Multi-account support
- Scan history and analytics (server-side persisted run history)
- Export/import settings
- Custom IP range input
- Notification system
- Background/scheduled scans across platforms via scheduler adapters
- Server log lifecycle management (rotation + 7-day retention)
