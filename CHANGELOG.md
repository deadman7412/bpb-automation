# Changelog

All notable changes to BPB Automation will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.5.3] - 2026-02-22

### Changed
- ECH refresh in Cloudflare API mode now prioritizes `echServerName` (when configured) and falls back to panel/subscription hostname if the preferred domain fails.
- Added a Cloudflare API settings notice for BPB Panel `v4.1.3+` explaining client-side ECH handling and recommended fallback behavior.
- Version bump to `4.5.3+16` across Flutter, iOS, macOS, and documentation metadata.

---

## [4.5.2] - 2026-02-22

### Added
- **Update ECH** action on the scan results screen (under **Update BPB Panel**) for Cloudflare API mode.
- Results-screen notice when panel `proxySettings.enableECH` is disabled:
  - shows that ECH is turned off in panel settings
  - guides user to enable ECH before running ECH-only updates.

### Changed
- Version bump to 4.5.2+15 across Flutter, iOS, macOS, and documentation metadata.
- ECH-only update now uses Cloudflare ECH strategy settings exactly as configured in Settings:
  - direct DoH toggle
  - panel DoH toggle
  - proxy fallback toggle
  - cached fallback behavior.
- ECH-only update keeps persisted `cleanIPs` unchanged while refreshing ECH-derived fields.
- Home AppBar title updated from `BPB Clean IP Scanner` to `BPB Automation`.
- Global AppBar quick actions simplified to prioritize **Logs** and reduce header clutter.
- Theme mode switcher (System / Light / Dark) added to Home AppBar and persisted between app restarts.
- Results statistics cards were compacted (smaller visual weight and spacing) for cleaner desktop/mobile layout.
- Results statistics grid layout now enforces consistent sizing with only **2 or 4 cards per row** (no 3-card rows).
- Results screen no longer uses a separate scan-details header button; related details are embedded directly in statistics cards.

### Fixed
- Removed duplicate success log line after ECH-only update completion.
- ECH-only update now handles `enableECH=false` explicitly and returns a clear user-facing message instead of reporting success.
- Home status card now shows clear action notice with direct links to both **Configuration** and **Settings** when setup is incomplete.
- Home `Last scan` now correctly resolves latest server-run timestamps in server-backend mode (instead of incorrectly showing `Never`).
- Server-backend `Last scan` lookup now supports all app targets (web, Android, macOS, Windows, Linux) with platform-appropriate auth token selection.
- Improved dark-mode readability on Results summary card and statistics section.

---

## [4.2.3] - 2026-02-20

### Added
- Global Logs quick-access icon in AppBar across major screens.

### Changed
- Logging service now hydrates app-visible logs from persisted file on startup.
- In-memory log retention increased for better history visibility.
- Log export now prefers file-backed history (with line cap) for more complete exports.

### Fixed
- Improved consistency between terminal/runtime logs and in-app Logs screen output.

---

## [4.2.2] - 2026-02-20

### Added
- **Auto apply after scan** setting in Settings to automatically push working IPs to BPB after scan completion.
- **Persistent auto-apply status** on Results screen (success/failure/skipped) so users can return later and see what happened.

### Changed
- **Scan timer persistence improved**:
  - elapsed timer now survives navigation away/back while a scan is in progress
  - final elapsed duration is saved and shown on Results screen.
- **Pre-scan config refresh resilience**:
  - leaving Scan screen during config refresh no longer stops the underlying scan flow.
- **Results UI polish for dark mode**:
  - auto-apply status card now uses theme-aware colors
  - stat icons/text contrast improved on dark backgrounds
  - update button label now shows `Already Applied - Apply Again` when auto-apply already succeeded.

### Fixed
- Prevented scan interruption during early refresh phase when user navigates away.
- Improved post-scan visibility for long-running automatic update operations.

---

## [4.2.1] - 2026-02-20

### Added
- Settings notices for reliability guidance:
  - Panel API: if panel is unreachable without VPN or under disturbed network, use Cloudflare API mode.
  - Cloudflare API: updates may take up to ~60 seconds to take effect (KV propagation).
- Panel-unreachable guidance dialog on Results update flow with direct navigation to Settings and step-by-step fallback instructions.

### Changed
- Scan progress labels renumbered for users:
  - Phase 1 = TCP pre-filter
  - Phase 2 = TLS testing
  - Phase 3 = Proxy testing
- Subscription config handling is now refresh-first on each scan:
  - Attempt to fetch latest configs every run.
  - If refresh fails, fallback to cached configs with warning.

### Fixed
- Prevented infinite "updating" spinner on panel update failures by:
  - adding a hard timeout to panel update calls
  - always clearing update state via `finally`, including timeout/error paths.

---

## [4.2.0] - 2026-02-20

### Added
- **Panel API update mode** with full login/session flow:
  - `POST /login/authenticate`
  - `GET /panel/settings`
  - `PUT /panel/update-settings`
- **Update method selector in Settings**:
  - Panel API (**default**)
  - Cloudflare API (fallback)
- **Panel credential storage** (base URL + password) with secure storage and SharedPreferences fallback.
- **Automatic panel session recovery** on `401` (re-authenticate and retry once).
- **Panel setup documentation** (`docs/panel-setup.md`) and full docs sync for dual update modes.

### Changed
- **Default update mode** switched from Cloudflare API to Panel API.
- **Panel base URL input normalization** now auto-removes `/panel` when pasted (and `/panel/...` paths).
- Updated `README.md`, `docs/user-guide.md`, and `docs/architecture.md` to reflect current behavior.

### Fixed
- CI failure in `config_tester_service_test.dart` sorting assertion:
  test now validates the current TLS ranking metric (`sortScore = latency + jitter * 0.5`) instead of raw latency-only ordering.

---

## [4.1.2] - 2026-02-20

### Fixed
- **SnackBar overlapping bottom buttons** — all SnackBars now use `SnackBarBehavior.floating` so they float above bottom action buttons instead of covering them.
- **IPv6 addresses rejected by BPB Panel** — IP loader now emits IPv6 addresses in bracketed form `[addr]` as required by the panel's `isIPv6` validator (`^\[...\]$` regex). Plain unbracketed IPv6 was silently dropped during panel validation.
- **Missing `selectRandomIPs` and `filterByType` methods on `IPLoader`** — added the two public methods referenced in tests, resolving `flutter analyze` errors in CI.

### Added
- **KV propagation notice after panel update** — success message now reminds the user to wait ~60 seconds for Cloudflare KV to propagate globally before refreshing their subscription. Duration extended to 6 seconds so the message is readable.

---

## [4.1.1] - 2026-02-19

### Fixed
- **EMFILE (FD exhaustion) in Phase 0 TCP pre-filter** — TCP probe sockets were closed with `await s.close()` (graceful half-close), which left sockets in CLOSE_WAIT and held OS file descriptors until GC ran. With large IP pools (5000+ IPs) this exhausted the FD limit before Phase 1 TLS even started, causing every TLS connection to fail instantly with `[24] Connection failed`. Fixed by replacing both probe closes with `s.destroy()`, which issues an immediate RST and releases the FD right away.

### Added
- **Copy Configs button** on the scan results page — exports generated Xray configs as JSON directly to the clipboard, alongside the existing Download Configs button.

### Changed
- **Exact IP pool size** — `ipPoolSize` now controls the exact number of candidate IPs loaded for scanning (previously `maxSamplesPerCIDR` was a per-range cap). IPs are allocated proportionally across all Cloudflare CIDR ranges weighted by /24 subnet count, with cap-and-redistribute to honour range sizes.
- Slider label on the Config screen now shows the exact IP count (e.g. `1000 IPs`) instead of an approximate formula.

---

## [1.0.0] - 2026-02-16

### Initial Release

#### Added
- **Pure Dart IP Scanner** - Native implementation without binary dependencies
  - TCP-based latency testing (TCPing)
  - HTTP/HTTPS download speed testing with raw sockets
  - CIDR range expansion for Cloudflare IP lists
  - Concurrent testing with configurable parallelism
  - Real-time progress streaming
  - Quality-based result scoring
- Automatic BPB Panel configuration update via Cloudflare API
- Secure credential storage (platform-specific encryption)
- Real-time scan progress tracking with detailed statistics
- Clean IP results display with sorting options
- Comprehensive logging system with export functionality
- Advanced scanner configuration options
- Support for multiple platforms:
  - Android (tested on API 36)
  - macOS (tested on Apple Silicon) - **No sandboxing issues**
  - Linux (build-ready)
  - Windows (build-ready)

#### Features

**Core Functionality:**
- Scan network for clean Cloudflare IPs
- Parse and rank IPs by latency and speed
- Update BPB Panel Workers KV settings
- No credentials required for scanning (only for BPB updates)
- Configurable number of IPs to use

**User Interface:**
- Material 3 design with light/dark theme support
- Home screen with scan status and last scan info
- Results screen with IP list and statistics
- Settings screen for Cloudflare credentials
- Configuration screen for scanner parameters
- Logs screen with filtering and export

**Scanner Configuration:**
- Threads: 1-16 (default: 4)
- Test count: 1-20 (default: 10)
- IP limit: 1-100 (default: 10)
- Download timeout: 1-10 seconds (default: 2)

**Security:**
- Credentials encrypted using platform keychain
  - Android: Android Keystore
  - iOS: iOS Keychain
  - macOS: macOS Keychain
- No telemetry or analytics
- All data stored locally
- Only connects to Cloudflare API

**Logging:**
- Four log levels: OK, INFO, WARN, ERROR
- Real-time log streaming
- Filter by log level
- Export logs to clipboard
- Persistent log storage
- Auto-scroll to latest entries

#### Technical Details
- Built with Flutter 3.38.5
- **Pure Dart scanner implementation** - no external binaries required
- TCP socket-based latency measurement
- Raw Socket + SecureSocket for HTTPS speed testing
- Manual HTTP protocol handling for accurate speed measurement
- CIDR to IP expansion with random sampling (max 200 IPs per range)
- Singleton service architecture for state management
- Broadcast stream for real-time progress updates
- Retry logic with exponential backoff for API calls
- Quality scoring algorithm (60% latency, 40% speed)

#### Platform-Specific

**Android:**
- Debug APK: 186 MB
- Release APK: 64.5 MB
- Minimum SDK: API 21
- Target SDK: API 36

**macOS:**
- Release build: 78.7 MB
- Native Apple Silicon support
- Universal binary ready

#### Known Limitations
- Linux and Windows builds require respective host platforms
- Web platform not yet implemented
- iOS support pending TestFlight setup
- No scheduled auto-scan functionality
- Single account support only

#### Fixed Issues During Development
- **macOS sandboxing blocking binary execution** - Replaced with pure Dart implementation
- CIDR range handling in IP lists
- ScannerConfig compatibility with DartScannerService
- SecureSocket.secure() timeout parameter handling
- StorageService initialization before app start
- Slider crash on Results page when no IPs available
- Removed mandatory credentials for scanning
- Improved logs screen visibility in dark mode
- BuildContext usage across async gaps

### Dependencies
- flutter: >=3.0.0
- flutter_secure_storage: ^9.2.2
- shared_preferences: ^2.3.3
- path_provider: ^2.1.5
- http: ^1.2.2
- csv: ^6.0.0

---

## Release Notes

### What's New in 1.0.0

This is the initial release of BPB Automation, a cross-platform tool for finding and updating clean Cloudflare IPs in your BPB Panel.

**Key Highlights:**
- Scan from your actual device (mobile/desktop) - no VPS needed
- Find IPs optimized for your network and location
- One-tap update to BPB Panel configuration
- Beautiful Material 3 interface with dark mode
- Comprehensive logging for troubleshooting
- Secure credential storage
- Works offline (after credentials configured)

**Getting Started:**
1. Download the app for your platform
2. (Optional) Configure Cloudflare credentials for auto-updates
3. Run a scan to find clean IPs
4. View results and optionally update BPB Panel

For detailed instructions, see the [User Guide](docs/user-guide.md).

### Upgrade Notes

This is the initial release - no upgrades applicable.

### Breaking Changes

None - initial release.

---

## Future Roadmap

Planned for future releases:
- Scheduled automatic scans
- Multi-account support
- Custom IP range configuration
- Cloud backup (optional)
- In-app update mechanism
- iOS App Store distribution
- Web version with cronjob support

---

[1.0.0]: https://github.com/your-repo/bpb-automation/releases/tag/v1.0.0
