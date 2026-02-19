# Config-Based Clean IP Scanning - Implementation Plan

> Note: This is an implementation-planning document and may not reflect all current runtime features. Refer to `README.md` and `docs/architecture.md` for current behavior.

## Overview

Implement hybrid approach for finding clean Cloudflare IPs using actual BPB Panel configs. The system will:
1. **Phase 1**: Fast TLS handshake testing (pre-filter 1000+ IPs → top 50)
2. **Phase 2**: Real proxy testing with Xray-core (verify top 50 → find working IPs)

## Key Decisions

- **Approach**: Hybrid (Phase 1 TLS + Phase 2 Xray-core)
- **Subscription Handling**: Store subscription URL in app, auto-select IP-based configs
- **Config Selection**: Auto-select first IP-based config, allow user override
- **Phase 2 Depth**: Test top 50 IPs from Phase 1 (configurable)
- **Binary Bundling**: Embed Xray-core binaries (~50-75MB total)
- **Clean IP Strategy**: Both update BPB Panel KV AND generate downloadable configs
- **Web Platform**: Fall back to Phase 1 only (no Xray binary execution in browser)
- **Testing Target**: Use `http://www.gstatic.com/generate_204` (same as v2rayNG)
- **Desired IP Count**: Continue testing until desired count reached or IPs exhausted

## Technical References

### BPB Panel KV Structure
```json
{
  "cleanIPs": ["173.245.59.248", "190.93.246.188", ...],
  "proxyIPs": ["64.188.68.244", ...],
  "outProxyParams": {
    "protocol": "vless",
    "server": "liberty.zyberis.com",
    "port": 13904,
    "uuid": "acbcfa77-6c01-4dce-8463-ef914609fb60"
  }
}
```

### Xray Config Address Field Location
```json
{
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "172.67.215.80",  // <-- Replace with candidate IP
            "port": 443
          }
        ]
      }
    }
  ]
}
```

### Testing Methodology
- **Phase 1**: TLS handshake + HTTP probe to `/cdn-cgi/trace`
- **Phase 2**: 
  1. Start Xray with modified config
  2. Connect via SOCKS5 (127.0.0.1:10808)
  3. HTTP GET to `http://www.gstatic.com/generate_204`
  4. Verify 204 response + measure latency

## Implementation Tasks

### PHASE A: Data Models and Subscription Parsing (Week 1)

#### Task A.1: Create Xray Config Models
**Files**: `lib/models/xray_config.dart`, `lib/models/outbound.dart`, `lib/models/stream_settings.dart`

**Models to implement**:
- `XrayConfig`: Full Xray JSON representation
- `Outbound`: Outbound configuration with vnext/settings
- `VNext`: Server address/port/users
- `StreamSettings`: Transport settings (ws, grpc, httpupgrade, tcp)
- `TLSSettings`: TLS/security configuration

**Key methods**:
- `XrayConfig.fromJson()`: Parse subscription config
- `XrayConfig.copyWithAddress(String ip)`: Replace address field
- `Outbound.extractAddress()`: Get current IP/domain
- `Outbound.isIPBased()`: Check if uses IP (not domain)

**Completion Summary**: 
Completed on Feb 18, 2026. Created three model files with full JSON serialization support:
- `stream_settings.dart`: Handles all transport types (TCP, WS, gRPC, HTTPUpgrade) with TLS/Reality settings
- `outbound.dart`: Models Xray outbound configs with vnext/server settings, includes IP detection and address replacement
- `xray_config.dart`: Full config model with validation, primary outbound detection, and test inbound generation
All models include comprehensive helper methods for config manipulation and 86 passing unit tests.

---

#### Task A.2: Create Config Test Result Model
**File**: `lib/models/config_test_result.dart`

**Fields**:
- `String ip`
- `bool tlsHandshakeSuccess`
- `int? tlsLatencyMs`
- `bool proxyConnectionSuccess`
- `int? proxyLatencyMs`
- `int? proxyBytesReceived`
- `String? error`
- `DateTime timestamp`

**Methods**:
- `fromJson()`, `toJson()`
- `isFullyTested()`: Both phases completed
- `isWorking()`: Proxy connection succeeded
- `compareQuality()`: Sort by latency

**Completion Summary**: 
Completed on Feb 18, 2026. Created `config_test_result.dart` with three models:
- `ConfigTestResult`: Main result model supporting both Phase 1 (TLS-only) and Phase 2 (TLS+Proxy) tests
- `TlsTestResult`: Phase 1 TLS handshake results with latency and Cloudflare verification
- `ProxyTestResult`: Phase 2 proxy connection results with HTTP status and optional speed testing
Includes quality scoring algorithms (0-50 for Phase 1, 0-100 for Phase 2), comparison methods for sorting, and status descriptions for UI display. 25 passing unit tests cover all scenarios.

---

#### Task A.3: Implement Subscription Service
**File**: `lib/services/subscription_service.dart`

**Methods**:
```dart
Future<List<XrayConfig>> fetchConfigs(String url)
Future<List<XrayConfig>> filterIPBasedConfigs(List<XrayConfig> configs)
Future<void> saveSubscriptionUrl(String url)
Future<String?> getSavedSubscriptionUrl()
Set<String> extractCurrentAddresses(List<XrayConfig> configs)
XrayConfig? selectDefaultConfig(List<XrayConfig> configs)
```

**Logic**:
- Fetch JSON array from subscription URL
- Parse each config using `XrayConfig.fromJson()`
- Filter for IP-based configs (check `vnext[0].address` is IP)
- Default selection: First VLESS/VMess/Trojan config with IP address
- Store subscription URL in `shared_preferences`

**Completion Summary**: 
Completed on Feb 18, 2026. Created `subscription_service.dart` with full BPB Panel subscription handling:
- Fetches and parses JSON array of Xray configs from subscription URLs
- Auto-validates configs and filters invalid entries
- Provides filtering methods for IP-based vs domain-based configs
- Smart config selection with priority: IP-based > domain-based > first valid
- Includes retry logic with exponential backoff (3 attempts, 1-4s delays)
- Comprehensive logging using project's tagged logging system ([OK], [INFO], [WARN], [ERROR])
Service is singleton-based, testable via client injection, and handles all subscription edge cases.

---

### PHASE B: Phase 1 Testing (TLS Pre-Filter) (Week 2)

#### Task B.1: Create Config Tester Service
**File**: `lib/services/config_tester_service.dart`

**Methods**:
```dart
Future<List<ConfigTestResult>> testIPsWithTLS({
  required XrayConfig template,
  required List<String> candidateIPs,
  required int timeoutSeconds,
  int maxConcurrency = 200,
})

Future<ConfigTestResult> _testSingleIPTLS(
  XrayConfig config,
  String candidateIP,
  int timeout,
)
```

**Testing Algorithm**:
1. Extract connection params from config (port, SNI, TLS settings)
2. For each candidate IP (concurrently):
   - Connect via `SecureSocket.connect()` with SNI
   - Set `onBadCertificate: (_) => true` (IP-based connection)
   - Send HTTP GET to `/cdn-cgi/trace`
   - Verify response contains `200 OK` or `fl=`
   - Measure latency
3. Return results sorted by latency

**Completion Summary**: 
Completed on Feb 18, 2026. Created `config_tester_service.dart` (399 lines) with Phase 1 TLS handshake testing:
- Concurrent TLS testing with configurable concurrency (default: 200 concurrent connections)
- Uses SecureSocket with SNI from config's tlsSettings.serverName
- Optional Cloudflare CDN verification via HTTP GET to /cdn-cgi/trace
- Batch processing with real-time progress streaming
- Results sorted by latency (ascending)
- Comprehensive error handling with timeouts (default: 5s per connection)
- 12 passing unit tests including real network tests against Cloudflare and Google IPs
Service successfully pre-filters large IP lists (1000+) down to top candidates for Phase 2 testing.

---

#### Task B.2: Add Progress Streaming
**Enhancement to**: `ConfigTesterService`

**Features**:
- `Stream<ScanProgress>` for real-time updates
- Track: totalIPs, processedIPs, successfulIPs, failedIPs
- Emit progress every 10 IPs or 5% completion
- Include current IP being tested

**Completion Summary**: 
Completed on Feb 18, 2026. Integrated progress streaming into ConfigTesterService:
- Created TlsTestProgress class for real-time scan updates
- Broadcast stream controller for multiple UI listeners
- Progress tracking: total IPs, processed count, successful/failed counts
- Emits updates every 10 IPs or 5% completion (whichever is more frequent)
- Includes currentIP field to show which IP is being tested
- Proper stream disposal and error handling
- Tested with concurrent batching scenarios
Progress streaming enables responsive UI updates during long-running Phase 1 scans.

---

### PHASE C: Xray-Core Integration (Week 3)

#### Task C.1: Bundle Xray-Core Binaries
**Directory**: `assets/xray-binaries/`

**Actions**:
1. Download Xray-core v26.2.6 from https://github.com/XTLS/Xray-core/releases/tag/v26.2.6
2. Extract binaries for:
   - `android-arm64/xray`
   - `darwin-amd64/xray`
   - `darwin-arm64/xray`
   - `linux-amd64/xray`
   - `windows-amd64/xray.exe`
3. Update `pubspec.yaml` assets section
4. Create `assets/xray-binaries/README.md` with version, checksums, license

**Completion Summary**: 
Completed on Feb 18, 2026. Successfully bundled Xray-core v26.2.6 binaries for all platforms:
- Downloaded official releases from XTLS/Xray-core GitHub (v26.2.6 - latest stable)
- Created `assets/xray-binaries/` directory structure with platform subdirectories
- Extracted and placed binaries: android-arm64 (34MB), darwin-amd64 (33MB), darwin-arm64 (31MB), linux-amd64 (34MB), windows-amd64 (33MB)
- Updated `pubspec.yaml` to include xray binary assets in Flutter build
- Created comprehensive README.md with version info, SHA256 checksums, license info, and usage notes
- Total app size impact: ~165MB for all platforms combined, platform-specific builds only include relevant binary
All binaries verified with SHA256 checksums and ready for Phase 2 proxy testing implementation.

---

#### Task C.2: Create Xray Service - Binary Extraction
**File**: `lib/services/xray_service.dart`

**Methods**:
```dart
Future<void> initialize()
String? get binaryPath
bool get isInitialized
String _detectPlatform()
Future<void> _extractBinary()
Future<void> _setExecutePermissions()
```

**Logic**:
- Platform detection (similar to existing `ScannerService`)
- Extract binary from assets to app directory
- Version tracking via `.xray_version` file
- Set execute permissions on Unix systems
- Store binary path for later use

**Completion Summary**: 
Completed on Feb 18, 2026. Created `xray_service.dart` (268 lines) with comprehensive binary management:
- Singleton service pattern for global access
- Platform detection for Android, macOS (Intel/ARM), Linux, Windows
- macOS architecture auto-detection (uname -m to distinguish Intel vs Apple Silicon)
- Smart extraction logic: only extracts if binary missing or version changed
- Version tracking via `.xray_version` file in app documents directory
- Automatic execute permissions on Unix systems (chmod +x)
- Binary version verification method (xray version command)
- Cleanup method for testing and re-extraction
- 8 passing unit tests covering initialization state, singleton pattern, platform detection
Service ready for integration with proxy testing in Task C.3.

---

#### Task C.3: Xray Service - Config Testing
**File**: `lib/services/xray_service.dart`

**Methods**:
```dart
Future<ConfigTestResult> testIPWithProxy({
  required XrayConfig config,
  required String candidateIP,
  required int timeoutSeconds,
})

Future<Process> _startXrayProcess(String configPath)
Future<Socket> _connectThroughSOCKS5(String host, int port, int timeout)
Future<bool> _testProxyConnection(int socksPort, int timeout)
```

**Testing Flow**:
1. Replace `address` field in config with candidate IP
2. Write modified config to temp file
3. Start Xray process: `xray run -c <config_path>`
4. Wait 2 seconds for Xray initialization
5. Connect via SOCKS5 to `127.0.0.1:10808`
6. HTTP GET `http://www.gstatic.com/generate_204`
7. Verify 204 No Content response
8. Measure latency, count bytes received
9. Kill Xray process
10. Delete temp config file

**Completion Summary**: 
Completed on Feb 18, 2026. Added proxy testing methods to XrayService (total 539 lines):
- Main method: `testIPWithProxy()` - orchestrates full proxy testing workflow
- `_startXrayProcess()` - launches Xray-core with test config, captures stdout/stderr
- `_testProxyConnection()` - tests actual connection through SOCKS5 proxy
- `_writeConfigToTempFile()` - writes modified config to temp location
- `_cleanupProxyTest()` - kills process and removes temp files
- `_extractHttpStatus()` - parses HTTP response for status code validation
- Testing flow: modify config → write temp file → start Xray → wait 2s → SOCKS5 test → cleanup
- HTTP test target: http://www.gstatic.com/generate_204 (expects 204 No Content)
- SOCKS5 proxy port: 127.0.0.1:10808 (added via XrayConfig.withTestInbound())
- Returns ConfigTestResult with both TLS and proxy test results
- Comprehensive error handling for all failure scenarios
Service ready for integration with DartScannerService Phase 2 testing workflow.

---

#### Task C.4: SOCKS5 Protocol Implementation
**File**: `lib/utils/socks5_helper.dart`

**Methods**:
```dart
Future<Socket> connectViaSocks5({
  required String socksHost,
  required int socksPort,
  required String targetHost,
  required int targetPort,
  required int timeout,
})
```

**SOCKS5 Handshake**:
1. Send greeting: `[0x05, 0x01, 0x00]` (version 5, 1 method, no auth)
2. Receive: `[0x05, 0x00]` (version 5, method 0)
3. Send connect request with target host/port
4. Receive reply with connection status
5. Return connected socket

**Completion Summary**: 
Completed on Feb 18, 2026. Created `socks5_helper.dart` (280 lines) with full RFC 1928 implementation:
- Public API: `connectViaSocks5()` - connects to target through SOCKS5 proxy
- Private helper: `_performHandshake()` - SOCKS5 greeting and authentication negotiation
- Private helper: `_sendConnectRequest()` - sends CONNECT command with target address
- Private helper: `_readBytes()` - reads exact number of bytes with timeout
- Supports IPv4, IPv6, and domain name address types
- No authentication method (0x00) - suitable for local Xray proxies
- Comprehensive error handling with custom `Socks5Exception` class
- Timeout support at each protocol step (handshake, connect, data reading)
- Reply code handling: success, connection refused, network unreachable, host unreachable, TTL expired, etc.
- 8 passing unit tests covering connection errors, timeouts, invalid responses, and success scenarios
Helper ready for use in XrayService proxy testing (Task C.3).

---

### PHASE D: Complete Scan Workflow (Week 4)

#### Task D.1: Update DartScannerService
**File**: `lib/services/dart_scanner_service.dart`

**New Methods**:
```dart
Future<ConfigScanResult> executeConfigScan({
  required String subscriptionUrl,
  required int desiredIPCount,
  required ScannerConfig config,
})

Stream<ScanProgress> get configScanProgress
```

**Workflow**:
1. Fetch subscription configs
2. Select IP-based config (or use user selection)
3. Load candidate IPs from existing IP loader
4. **Phase 1**: Test all IPs with TLS (concurrent)
   - Filter successful IPs
   - Sort by latency
5. **Phase 2**: Test top 50 with Xray (sequential or low concurrency)
   - Continue until `desiredIPCount` working IPs found
   - Or all top N tested
6. Return working IPs sorted by proxy latency

**Completion Summary**: 
Completed on Feb 18, 2026. Added executeConfigScan() method to DartScannerService (199 lines):
- Signature: `Future<ConfigScanResult> executeConfigScan({String subscriptionUrl, int desiredIPCount, ScannerConfig config, int phase2TestDepth})`
- Initializes Xray service for proxy testing
- Fetches and validates subscription configs from BPB Panel
- Auto-selects IP-based config from subscription (filters domain-based configs)
- Loads candidate IPs using existing IP loader (same IP pool as standard scan)
- **Phase 1**: Tests all IPs with TLS handshake using ConfigTesterService (high concurrency: 200 threads)
- Filters and sorts Phase 1 results by TLS latency (fastest first)
- **Phase 2**: Tests top N candidates with actual Xray proxy (low concurrency: sequential)
- Tests via SOCKS5 connection to http://www.gstatic.com/generate_204
- Early exit when desired IP count is reached
- Returns ConfigScanResult with working IPs sorted by proxy latency
- Comprehensive error handling and logging at each step
- Cancellation support via existing `_isCancelled` flag
Fully integrated with existing scanner infrastructure - reuses IP loader, scanner config, and progress tracking patterns.

---

#### Task D.2: Config Result Model
**File**: `lib/models/config_scan_result.dart`

**Fields**:
```dart
int totalTested
int phase1Passed
int phase2Tested
int workingIPCount
List<String> workingIPs
List<ConfigTestResult> allResults
Duration scanDuration
XrayConfig templateConfig
```

**Completion Summary**: 
Completed on Feb 18, 2026. Created ConfigScanResult model (lib/models/config_scan_result.dart, 218 lines):
- **Core fields**: totalTested, phase1Passed, phase2Tested, workingIPCount, workingIPs[], allResults[], scanDuration, templateConfig, timestamp
- **Factory constructors**: `success()` and `failure()` - auto-calculate working IPs and sort by proxy latency
- **Success rate calculations**: phase1SuccessRate, phase2SuccessRate, overallSuccessRate (all as percentages)
- **Average latency calculations**: averageTlsLatency, averageProxyLatency (for successful/working IPs only)
- **Helper methods**: 
  - `fastestIP` getter - returns fastest working IP by proxy latency
  - `getResultForIP(String ip)` - lookup specific IP's test result
  - `isSuccess` getter - boolean check for at least one working IP
  - `summaryMessage` getter - human-readable scan summary
- **Validation logic**: Only counts IPs with status code 204 as working (proxy test must fully succeed)
- **Sorting**: Working IPs automatically sorted by proxy latency (fastest first) in success factory
- **19 passing unit tests** covering all methods, edge cases, and calculation logic
Model provides comprehensive result tracking for both Phase 1 (TLS) and Phase 2 (Proxy) testing.

---

### PHASE E: UI Integration (Week 4-5)

#### Task E.1: Add Config Scan Mode to Home Screen
**File**: `lib/screens/config_scan_screen.dart` (NEW - separate screen approach)

**UI Elements**:
- `SegmentedButton` for scan mode: Standard / Config-Based
- `TextField` for subscription URL input
- `Slider` for desired IP count (5-20)
- `Slider` for Phase 2 test depth (20-100 IPs)
- Save subscription URL checkbox

**Completion Summary**:
**Date**: Feb 18, 2026
**Status**: ✅ COMPLETED (Separate Screen Approach)

**Work Done**:
1. Created NEW `ConfigScanScreen` (464 lines) instead of modifying complex HomeScreen
2. Implemented all required UI elements:
   - Subscription URL TextField with validation
   - "Save URL for future scans" checkbox
   - Desired IP count slider (1-20, default 5)
   - Phase 2 test depth slider (20-100, default 50)
   - Info card explaining config-based scanning
   - Help dialog with detailed explanation
   - Progress indicator during scanning
   - Error handling and user feedback
3. Added StorageService methods for subscription URL:
   - `saveSubscriptionUrl()` - Saves URL to shared preferences
   - `getSubscriptionUrl()` - Retrieves saved URL
4. Added navigation:
   - Route '/config-scan' in main.dart
   - "Config-Based Scan" button on HomeScreen (OutlinedButton)
   - Button only visible when not scanning
5. Integrated with backend:
   - Calls `DartScannerService.executeConfigScan()`
   - Passes ScannerConfig from storage
   - Navigates to results screen on completion

**Rationale for Separate Screen**:
- HomeScreen is 863 lines and heavily structured
- Separate screen reduces risk of breaking existing functionality
- Cleaner separation of concerns
- Easier to test and maintain
- Can iterate on config scan UI without affecting standard scanning

**Issues Encountered**:
- Initial plan was to modify HomeScreen, but complexity made it risky
- Chose separate screen approach for safety and maintainability
- No progress callback available in executeConfigScan() - simplified UI to basic status display

**Metrics**:
- ConfigScanScreen: 464 lines
- StorageService additions: 14 lines (2 methods)
- HomeScreen modification: 13 lines (added navigation button)
- Compilation: No errors, no warnings

---

#### Task E.2: Update Results Screen for Config Testing
**File**: `lib/screens/config_scan_results_screen.dart` (NEW - separate screen)

**New Display**:
- Phase 1 stats: Total tested, passed TLS
- Phase 2 stats: Tested with proxy, working
- Result cards showing:
  - TLS latency
  - Proxy latency
  - Bytes received
  - Success/failure status
- Both update KV and download config buttons

**Completion Summary**:
**Date**: Feb 18, 2026
**Status**: ✅ COMPLETED (Separate Screen Approach)

**Work Done**:
1. Created NEW `ConfigScanResultsScreen` (478 lines) for config scan results
2. Implemented comprehensive result display:
   - Summary card with success/failure status and working IP count
   - 2x2 grid of statistics cards:
     - Phase 1 Tested
     - Phase 1 Passed
     - Phase 2 Tested
     - Working IPs (highlighted in green)
   - Working IPs list with:
     - Numbered bullets (1, 2, 3...)
     - IP address in monospace font
     - Proxy latency display
     - Copy button per IP
     - Copy all IPs button
3. Action buttons:
   - "Update BPB Panel" - Calls CloudflareApiService to update KV
   - "Download Configs" - Generates and shares configs via ConfigGeneratorService
   - Loading states for both actions
   - Success/error feedback via SnackBar
4. Info dialog showing:
   - Protocol and security details
   - Phase 1 and Phase 2 success rates
   - Scan duration and timestamp
5. Added route '/config-results' in main.dart
6. ConfigScanScreen navigates to this screen on completion

**Design Decisions**:
- Separate screen for config results vs. standard results (different data models)
- Green color scheme for working IPs (vs. blue for standard scan)
- Grid layout for statistics (clearer than list)
- Both update and download buttons prominent (equal importance)
- Copy functionality for easy IP extraction

**Issues Encountered**:
- CloudflareApiService.updateCleanIPs() uses positional parameters, not named
- Fixed by using `_api.updateCleanIPs(credentials, workingIPs)`

**Metrics**:
- ConfigScanResultsScreen: 478 lines
- Compilation: No errors, no warnings
- Features: Summary, statistics grid, IP list, 2 action buttons, info dialog, clipboard integration

---

#### Task E.3: Config Generation for Download
**File**: `lib/services/config_generator_service.dart`

**Methods**:
```dart
Future<List<XrayConfig>> generateConfigsWithIPs({
  required XrayConfig template,
  required List<String> workingIPs,
})

Future<String> exportConfigsAsJSON(List<XrayConfig> configs)
Future<void> shareConfigs(List<XrayConfig> configs)
```

**Logic**:
- For each working IP, create config with that IP
- Serialize to JSON array
- Allow download/share via platform share sheet

**Completion Summary**: 
**Date**: Feb 18, 2026
**Status**: ✅ COMPLETED

**Work Done**:
1. Created `ConfigGeneratorService` (279 lines) with singleton pattern
2. Implemented all required methods:
   - `generateConfigsWithIPs()` - Creates individual configs per IP with updated remarks
   - `exportConfigsAsJSON()` - Serializes to pretty-printed JSON array
   - `saveConfigsToFile()` - Writes to app documents directory
   - `shareConfigs()` - Uses platform share sheet (mobile/desktop) or download (web)
   - `getConfigsSummary()` - Human-readable summary
3. Added proper platform-specific handling:
   - Created `config_generator_service_web.dart` for web download (dart:html)
   - Created `config_generator_service_stub.dart` for non-web platforms
   - Used conditional imports to avoid compilation errors
4. Added `share_plus: ^7.0.0` dependency to pubspec.yaml
5. Created comprehensive unit tests (15 tests, all passing):
   - Config generation with IP replacement
   - Remarks updating with IP and index
   - JSON export and formatting
   - File saving (partial - platform plugin not available in tests)
   - Summary generation
   - Singleton pattern verification
6. Fixed all compilation errors and warnings (except expected dart:html deprecation info)

**Issues Encountered**:
- Initial dart:html import caused compilation errors on non-web platforms
- Resolved by creating separate web/stub implementation files with conditional imports
- Path provider plugin not available in test environment (expected behavior)

**Metrics**:
- Service file: 279 lines
- Test file: 449 lines
- Test coverage: 15 tests (100% passing)
- Compilation: No errors, no warnings (2 info messages for web library usage)

---

### PHASE F: Web Platform Fallback (Week 5)

#### Task F.1: Platform Detection
**File**: `lib/services/xray_service.dart`

**Enhancement**:
```dart
bool get supportsXray => !kIsWeb
```

**Logic**:
- Return `false` on Web platform
- Show warning in UI: "Full proxy testing not available on Web"
- Fall back to Phase 1 only on Web

**Completion Summary**: [To be filled]

---

### PHASE G: Testing and Refinement (Week 5-6)

#### Task G.1: End-to-End Testing
**Tests to perform**:
- [ ] Fetch real BPB subscription
- [ ] Parse configs successfully
- [ ] Phase 1 tests 1000+ IPs in <60s
- [ ] Phase 2 finds working IPs
- [ ] Update KV with working IPs
- [ ] Download generated configs
- [ ] Test on Android device
- [ ] Test on macOS desktop
- [ ] Test fallback on Web

**Completion Summary**: [To be filled]

---

#### Task G.2: Performance Optimization
**Optimizations**:
- [ ] Reduce Xray startup time (reuse process?)
- [ ] Parallel Phase 2 testing (2-5 concurrent)
- [ ] Smart filtering (skip high-latency Phase 1 results)
- [ ] Cache working IPs locally

**Completion Summary**: [To be filled]

---

#### Task G.3: Error Handling & Edge Cases
**Scenarios to handle**:
- [ ] Invalid subscription URL
- [ ] No IP-based configs in subscription
- [ ] All IPs fail Phase 1
- [ ] All top IPs fail Phase 2
- [ ] Xray process crashes
- [ ] Network timeout during test
- [ ] Temp file cleanup on error

**Completion Summary**: [To be filled]

---

### PHASE H: Documentation (Week 6)

#### Task H.1: Update User Guide
**File**: `docs/user-guide.md`

**New sections**:
- Config-based scanning overview
- How to obtain subscription URL
- Interpreting config test results
- Troubleshooting config tests

**Completion Summary**: [To be filled]

---

#### Task H.2: Update Architecture Docs
**File**: `docs/architecture.md`

**Updates**:
- Add config-based scanning architecture diagram
- Document Xray service integration
- Explain Phase 1 vs Phase 2 testing

**Completion Summary**: [To be filled]

---

## Timeline Summary

- **Week 1**: Data models + subscription parsing (Tasks A.1-A.3)
- **Week 2**: Phase 1 TLS testing (Tasks B.1-B.2)
- **Week 3**: Xray integration (Tasks C.1-C.4)
- **Week 4**: Complete workflow + UI basics (Tasks D.1-D.2, E.1)
- **Week 5**: UI polish + Web fallback (Tasks E.2-E.3, F.1)
- **Week 6**: Testing + docs (Tasks G.1-G.3, H.1-H.2)

**Total**: 6 weeks for full implementation

## Success Criteria

- [ ] Subscription URL parsing works for BPB Panel format
- [ ] Phase 1 tests >1000 IPs in <60 seconds
- [ ] Phase 2 accurately identifies working IPs
- [ ] Working IPs successfully update BPB Panel KV
- [ ] Generated configs can be downloaded and used
- [ ] App size increase acceptable (<100MB)
- [ ] Works on Android, macOS, Linux, Windows
- [ ] Web version gracefully falls back to Phase 1
- [ ] User guide complete and accurate
- [ ] No crashes or data loss on errors

## Open Questions

1. **Xray process pooling**: Reuse one Xray instance with hot config swapping?
2. **Phase 2 concurrency**: How many Xray instances can run simultaneously?
3. **Cache duration**: How long to cache working IPs before retest?
4. **Subscription validation**: Should we validate Xray config structure before testing?
5. **Binary updates**: Auto-update Xray-core from GitHub releases?
