# BPB Automation

Cross-platform application for automatically scanning and updating clean Cloudflare IPs in BPB Panel.

## Overview

BPB Automation helps you find working Cloudflare IPs for your network and automatically updates your BPB Panel configuration.

It supports two update methods:
- **Panel API (default)** — Login to panel and update settings via panel endpoints
- **Cloudflare API (fallback)** — Direct Workers KV read/modify/write

The app fetches your BPB Panel's Xray subscription configs, then runs a 3-phase scan to find IPs that actually work as a proxy on your network.

## Key Features

- **Config-based scanning** - Uses your actual BPB Panel Xray configs to test real proxy connectivity
- **3-phase verification** - TCP pre-filter, TLS handshake, and live Xray proxy test
- **Subnet-aware IP selection** - One IP per /24 subnet for maximum routing diversity
- **Bundled Xray-core** - No external installation required; binary is bundled per platform
- Scan from your actual network (mobile ISP, home internet, etc.)
- Automatic BPB Panel settings update (Panel API or Cloudflare API)
- Cross-platform support: Android, iOS, macOS, Linux, Windows, Web
- Offline-first design (no hosting required)
- Secure credential storage
- User-friendly interface (no terminal needed)
- Real-time scan progress tracking

## Supported Platforms

- Android (Primary)
- macOS
- Linux
- Windows
- Web (requires VPS backend)
- iOS (coming soon)

## Quick Start

### Installation

Download the appropriate version for your platform from the [latest release](https://github.com/YOUR_USERNAME/bpb-automation/releases/latest):

#### Android
```
Download and install APK:
BPB-Automation-Android-arm64.apk
```

#### macOS
```
Download and mount DMG:
BPB-Automation-macOS.dmg
```

#### Linux

**Ubuntu/Debian (.deb package)**
```bash
sudo dpkg -i BPB-Automation-Linux-x64.deb
sudo apt-get install -f   # fix any dependency issues
```

**Manual Installation (tar.gz)**
```bash
tar -xzf BPB-Automation-Linux-x64.tar.gz
cd bundle
./bpb_automation
```

#### Linux VPS (Server Package, Recommended)
One-command installer/update on Ubuntu:
```bash
curl -fsSL https://raw.githubusercontent.com/deadman7412/bpb-automation/main/backend/deploy/vps/install_or_update_server.sh \
  | sudo bash -s -- --domain scan.example.com --email admin@example.com
```
What it does:
- Downloads latest `BPB-Automation-Server-Linux-x64` from GitHub Releases
- Installs/updates backend binaries under `/opt/bpb-automation/server`
- Creates and enables systemd services/timer (auto-start on reboot)
- Detects nginx/caddy and configures reverse proxy for your domain
- Tries automatic TLS provisioning (nginx+certbot or caddy native TLS)
- Blocks `/internal/*` endpoints at proxy layer (public internet cannot reach trigger/rollback routes)

#### Windows
```
Download and extract:
BPB-Automation-Windows-x64.zip
```

### Setup

1. Install the app
2. Open **Configuration** and enter your BPB Panel subscription URL
3. Open **Settings** and choose update method:
   - **Panel API (default)** — see [Panel Setup Guide](docs/panel-setup.md)
   - **Cloudflare API (fallback)** — see [Cloudflare Setup Guide](docs/cloudflare-setup.md)
4. Enter credentials for the selected method (only needed for auto-update)
5. Tap **Start Scan**
6. After scan completes, tap **Update BPB Panel** to apply the results

**Note:** Credentials are only required for auto-update. You can always scan and copy IPs manually without credentials.

## Documentation

- [User Guide](docs/user-guide.md) - Complete usage instructions
- [Panel Setup](docs/panel-setup.md) - Configure Panel API update mode
- [Panel API Reference](docs/panel-api-reference.md) - Full BPB panel route and API reference
- [Cloudflare Setup](docs/cloudflare-setup.md) - How to get credentials
- [Scanner Configuration](docs/scanner-configuration.md) - Scan parameters explained
- [Development Guide](docs/development.md) - For developers
- [Deployment Guide](docs/deployment.md) - Building and distributing

## Web + VPS Scheduler (Ubuntu)

Use this mode when you want:
- Web dashboard access from any device
- Server-side scheduled scans
- Automatic apply from a Linux host (for example Ubuntu LTS VPS)

Architecture:
1. Flutter app/web UI talks to backend API
2. Backend runs `run-once` worker
3. Scheduler (cron/systemd) triggers backend runs
4. Backend stores run history/logs and serves dashboard endpoints

### Ubuntu Quick Start (Backend)

```bash
sudo apt update
sudo apt install -y curl jq ca-certificates

# Example working dirs
sudo mkdir -p /opt/bpb-automation/backend /var/lib/bpb-automation /var/log/bpb-automation
```

Run backend API manually (advanced/debug path):

```bash
cd /opt/bpb-automation/backend
dart run bin/bpb_api.dart \
  --host 127.0.0.1 \
  --port 8787 \
  --state-dir /var/lib/bpb-automation \
  --log-dir /var/log/bpb-automation \
  --internal-token "CHANGE_ME" \
  --allowed-trigger-ips "127.0.0.1,::1" \
  --scan-cmd "YOUR_REAL_SCAN_COMMAND" \
  --apply \
  --apply-cmd "YOUR_REAL_APPLY_COMMAND"
```

For production, prefer the installer command above.

### Scheduler Options

Linux scheduler adapters are included under:

`backend/deploy/schedulers/`

- `cron/` template
- `systemd/` service + timer + env example
- `windows/` task scheduler helpers
- `macos/` launchd adapter scripts
- `android/` WorkManager integration notes

For production hardening:
- Keep backend bound to localhost
- Put Nginx reverse proxy in front
- Restrict internal trigger endpoints to trusted source IPs only
- Use a strong internal token

## Requirements

### For Users
- Internet connection
- BPB Panel subscription URL (for scanning)

**For BPB Panel Updates:**
- **Panel API mode (default):** Panel base URL + panel password
- **Cloudflare API mode (fallback):** API token + account ID + KV namespace ID

### For Developers
- Flutter SDK (latest stable)
- Platform-specific tools (Android Studio, Xcode, etc.)
- See [Development Guide](docs/development.md)

## Testing

### Full Validation Script (Recommended)

```bash
./scripts/run_validation_suite.sh
```

This runs:
- `backend` analyzer
- Flutter analyzer
- Flutter test suite
- Isolated backend/API smoke checks (path traversal guard, trigger race conflict, CORS default deny)

### Run All Tests (Recommended for CI)
```bash
flutter test --exclude-tags=integration
```

### Run Specific Test Suites
```bash
# Model tests
flutter test test/models/

# Service tests
flutter test test/services/

# Integration tests (requires network access)
flutter test --tags=integration
```

### Test Categories
- **Unit Tests** - Fast, isolated tests for models and services
- **Integration Tests** - Network-dependent tests against real Cloudflare IPs
  - Tagged with `@Tags(['integration'])`
  - May fail in CI due to network restrictions
  - Should be run manually or in a separate CI job

**Note:** For reliable CI/CD, always use `--exclude-tags=integration`.

## How It Works

### Scan Algorithm (v3)

#### Step 1: Config Fetch

The app fetches your BPB Panel's Xray subscription URL (with `?app=xray`) and parses the JSON list of Xray configs. One config is selected as the template for testing (VLESS/WebSocket configs are preferred). The SNI hostname and port are extracted from the config.

#### Step 2: IP Pool Generation

- Loads Cloudflare IP ranges from bundled `ip.txt` (and `ipv6.txt` if IPv6 is enabled)
- **IPv4**: Subnet-aware sampling — one random IP per /24 subnet, up to `maxSamplesPerCIDR` per CIDR range
- **IPv6**: Pure random sampling across the CIDR host portion
- Result: A diverse set of candidate IPs connecting through different Cloudflare edge nodes

#### Step 3: Phase 1 — TLS Handshake Test

Each candidate IP is tested for a working TLS connection:

1. TCP connection to port 443 (1-second timeout)
2. TLS handshake using the SNI hostname from the config
3. IPs that complete a successful handshake pass Phase 1
4. Results sorted by TLS latency (fastest first)
5. Top `phase2TestDepth` IPs advance to Phase 2

This phase runs concurrently (`batchSize` connections at a time, default 200).

#### Step 4: Phase 2 — Live Proxy Test

Each Phase 1 candidate is tested with a real Xray proxy connection:

1. The bundled Xray-core binary is started with a config substituting the candidate IP
2. An HTTP request is made through the SOCKS5 proxy to `connectivitycheck.gstatic.com/generate_204`
3. Only **HTTP 204** responses count as a working IP
4. Results sorted by proxy latency (fastest first)
5. Top `desiredIPCount` working IPs are saved

This phase tests actual proxy connectivity on your network, so results are specific to your ISP and location.

#### Step 5: BPB Panel Update

The top working IPs are written to your BPB Panel's `cleanIPs` field using the selected update method:
- **Panel API mode:** `/login/authenticate` + `/panel/settings` + `/panel/update-settings`
- **Cloudflare API mode:** direct Workers KV API (`proxySettings` read/modify/write)

### Why This Approach

- **Real-world verification**: Phase 2 uses actual Xray proxy connections, not just latency pings — an IP must actually work as a proxy to pass
- **Subnet diversity**: /24 subnet-aware IPv4 selection ensures IPs route through different Cloudflare edge servers, giving better redundancy
- **Network-specific**: Testing happens on your device from your network, so results are optimal for your ISP

## Security & Privacy

- Credentials encrypted with platform keychain (Android Keystore, iOS Keychain, etc.)
- No cloud storage or third-party services
- No analytics or tracking
- Only connects to your BPB Panel subscription URL and selected update endpoints (panel API and/or Cloudflare API)
- All network requests are user-initiated

## Contributing

Contributions welcome. Please follow the guidelines in [Development Guide](docs/development.md).

## License

To be determined.

## Credits

- [BPB-Worker-Panel](https://github.com/bia-pain-bache/BPB-Worker-Panel) - Panel software
- IP lists sourced from Cloudflare's official IP ranges

## Support

For issues and questions:
- Check [User Guide](docs/user-guide.md)
- Review [Troubleshooting](docs/user-guide.md#troubleshooting)
- See logs in app (Logs screen)

## Roadmap

- [x] Core scanning functionality
- [x] Cloudflare API integration
- [x] Panel API integration
- [x] Multi-platform support
- [x] Config-based 3-phase Xray scanning
- [x] Scheduled auto-scans (Linux backend worker + scheduler adapters)
- [ ] Multi-account support
- [ ] Custom IP lists
- [ ] In-app updates

## Version

Current: 4.2.3

See CHANGELOG.md for version history.
