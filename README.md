# BPB Automation

Cross-platform app for scanning and updating clean Cloudflare IPs for BPB Panel.

## Compatibility (Important)

This app is built for **BPB Worker Panel** by `bia-pain-bache`.

- Supported panel project:
  - [BPB Worker Panel (main)](https://github.com/bia-pain-bache/BPB-Worker-Panel/tree/main)
- BPB Automation follows this panel's subscription/update behavior and routes.
- It is not intended as a generic manager for unrelated panels.

## Overview

BPB Automation tests Cloudflare IPs from your real network and updates your panel with working results.

It supports two update methods:
- **Panel API (default):** panel login/session and panel settings update routes
- **Cloudflare API (fallback):** Workers KV read/modify/write

Recommendation:
- If your network has heavy disturbance, DPI inspection, SNI filtering, or unstable direct access to panel endpoints, use **Cloudflare API mode**.

The scan pipeline uses your real BPB Xray subscription configs and validates actual proxy behavior, not just ping/latency checks.

## Server and Web Status (WIP / Experimental)

Server backend mode and web control flows are currently **WIP / Experimental**.

- Trigger/rollback/history/logs flows may be partially functional depending on environment/setup.
- Web mode depends on backend API/session behavior and is not stable in all environments.
- For reliability, use local app mode on Android/macOS/Linux/Windows.
- VPS and experimental server docs: [docs/vps-deployment.md](docs/vps-deployment.md)

## Navigation Table

| Section | Link |
| --- | --- |
| Overview | [Go to section](#overview) |
| Key Features | [Go to section](#key-features) |
| Supported Platforms | [Go to section](#supported-platforms) |
| Quick Start | [Go to section](#quick-start) |
| Documentation | [Go to section](#documentation) |
| Requirements | [Go to section](#requirements) |
| Testing | [Go to section](#testing) |
| How It Works | [Go to section](#how-it-works) |
| Security and Privacy | [Go to section](#security-and-privacy) |
| Contributing | [Go to section](#contributing) |
| License | [Go to section](#license) |
| Support | [Go to section](#support) |
| Roadmap | [Go to section](#roadmap) |

## Key Features

- **Auto scan scheduling:** app-managed local scheduler with runtime state, next/last run, last result/error, and manual `Run Scheduler Now`
- **Auto upload after scan:** optional auto-apply to BPB after successful scan
- **Multiple panel update methods:** Panel API (default) or Cloudflare API (fallback)
- **Auto ECH update support:** app-side ECH refresh controls in Cloudflare API mode (legacy-compatible)
- **ECH bypass for BPB v4.1.3+:** optional switch to bypass app-side ECH handling when panel reports `panelVersion >= 4.1.3`
- **ECH-only update action:** refresh ECH using clean IP results from the last scan without running a new scan (hidden when bypass switch is enabled)
- **ECH Server Name aware logic:** when `echServerName` exists in panel proxy settings, ECH lookup tries it first, then falls back to panel/subscription host
- **Multiple ECH strategies:** direct DoH, panel DoH, proxy fallback (experimental), cached fallback, optional panel DoH URL override
- **ECH-safe behavior:** respects panel ECH state and surfaces user-facing guidance when ECH is disabled
- **Debugging options for panel routing:** proxy update mode (experimental), proxy diagnostics, and forced clean-IP direct routing
- **Full in-app logs workflow:** filter, copy, export, clear, and persisted log hydration
- **Bundled Xray-core:** no external Xray installation required
- **Real verification scan pipeline:** TCP pre-filter -> TLS test -> live Xray proxy test
- **Subnet-aware IP diversity:** one IPv4 IP per /24 subnet for better routing spread
- **Offline-first local workflow:** no hosting required for standard app mode

## Donations

If this project was beneficial to you, you can support us with a donation:

<a href="https://nowpayments.io/donation?api_key=0968506a-9102-45ad-83ce-f29864982a43" target="_blank" rel="noreferrer noopener">
    <img src="https://nowpayments.io/images/embeds/donation-button-white.svg" alt="Cryptocurrency & Bitcoin donation button by NOWPayments">
</a>

## Supported Platforms

- Android (Primary)
- macOS
- Linux
- Windows
- Web (WIP/Experimental, requires VPS backend)
- iOS (coming soon, not released yet)

## Quick Start

### Installation

Download artifacts from the [latest release](https://github.com/deadman7412/bpb-automation/releases/latest):

#### Android

```text
BPB-Automation-Android-Universal-<version>.apk
```

#### macOS

```text
BPB-Automation-macOS-<version>.dmg
```

#### Linux

```text
BPB-Automation-Linux-x64-<version>.deb
BPB-Automation-Linux-x64-<version>.rpm
BPB-Automation-Linux-x64-<version>.tar.gz
```

#### Windows

```text
BPB-Automation-Windows-x64-<version>.zip
```

#### Experimental VPS/server bundles

```text
BPB-Automation-Server-Linux-x64-<version>.tar.gz
BPB-Automation-Web-<version>.tar.gz
```

For server install/update and troubleshooting, see [docs/vps-deployment.md](docs/vps-deployment.md).

### Setup

1. Install and open the app.
2. In **Configuration**, enter BPB panel subscription URL and save.
3. In **Settings**, choose update method:
   - **Panel API (default)** - [docs/panel-setup.md](docs/panel-setup.md)
   - **Cloudflare API (fallback)** - [docs/cloudflare-setup.md](docs/cloudflare-setup.md)
   - If panel route access is unstable due to DPI/SNI filtering, choose Cloudflare API mode.
4. Add credentials for your chosen method (required only for auto-update).
5. Start scan.
6. Apply with **Update BPB Panel**, or enable auto-apply.

Credentials are not required for scan-only/manual copy usage.

## Documentation

- [User Guide](docs/user-guide.md)
- [Panel Setup](docs/panel-setup.md)
- [Panel API Reference](docs/panel-api-reference.md)
- [Cloudflare Setup](docs/cloudflare-setup.md)
- [Scanner Configuration](docs/scanner-configuration.md)
- [VPS Deployment (WIP/Experimental)](docs/vps-deployment.md)
- [Development Guide](docs/development.md)
- [Deployment Guide](docs/deployment.md)
- [Testing Guide](TESTING_GUIDE.md)
- [Backend README](backend/README.md)

## Requirements

### For users

- Internet connection
- BPB panel subscription URL

For BPB panel updates:
- **Panel API mode:** panel base URL + panel password
- **Cloudflare API mode:** API token + account ID + KV namespace ID

### For developers

- Flutter SDK (stable)
- Platform tools as needed (Android Studio, Xcode, etc.)

## Testing

### Full validation suite

```bash
./scripts/run_validation_suite.sh
```

Includes backend analyzer, Flutter analyzer, Flutter tests, and backend/API smoke checks.

### Standard CI-safe test run

```bash
flutter test --exclude-tags=integration
```

### Integration tests

```bash
flutter test --tags=integration
```

Integration tests depend on real network conditions and can fail in restricted CI environments.

## How It Works

### Step 1: Config fetch

The app fetches BPB Xray subscription configs (with `?app=xray`) and picks a compatible config template.

### Step 2: Candidate IP pool

- Loads Cloudflare IP ranges from bundled lists
- Uses subnet-aware IPv4 sampling for diversity
- Supports IPv6 sampling when enabled

### Step 3: Phase 1 - TCP pre-filter

Fast TCP probes remove clearly unreachable candidates before heavier checks.

### Step 4: Phase 2 - TLS testing (two-pass)

Survivors are TLS-tested with SNI-aware handshake checks and re-validation pass.

### Step 5: Phase 3 - live proxy test

Top candidates are tested through bundled Xray-core. Only true working proxy paths pass.

### Step 6: Apply update (and optional ECH update)

- Panel API mode writes via panel endpoints
- Cloudflare API mode updates Workers KV proxy settings
- ECH-only update can use the latest saved scan results and keeps persisted `cleanIPs` unchanged
- ECH update respects `echServerName` first (when configured), then follows configured fallback strategy options
- If **Bypass app ECH handling** is enabled, bypass mode applies only when `panelVersion >= 4.1.3`
- For older or unknown panel versions, app keeps legacy app-side ECH handling for compatibility

## Security and Privacy

- Credentials stored with secure platform storage
- No analytics/tracking
- No cloud relay service required for normal local usage
- Network calls limited to subscription/update endpoints and scan targets
- Logs include redaction safeguards for sensitive local path/token leakage

## Contributing

Contributions are welcome. Start with [docs/development.md](docs/development.md).

## License

[MIT](LICENSE)

## Credits

- [BPB-Worker-Panel](https://github.com/bia-pain-bache/BPB-Worker-Panel)
- Cloudflare official IP ranges

## Support

- [User Guide](docs/user-guide.md)
- [Troubleshooting](docs/user-guide.md#troubleshooting)
- In-app logs screen
- [GitHub Issues](https://github.com/deadman7412/bpb-automation/issues)

## Roadmap

- [x] Config-based multi-phase scanning with Xray verification
- [x] Panel API + Cloudflare API update modes
- [x] Local scheduler with runtime status and manual trigger
- [x] Auto-apply and scheduler notifications on mobile
- [ ] iOS public release
- [ ] Server/web stabilization (currently experimental)
- [ ] Multi-account support
- [ ] Custom IP list support
