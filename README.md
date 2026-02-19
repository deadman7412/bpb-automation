# BPB Automation

Cross-platform application for automatically scanning and updating clean Cloudflare IPs in BPB Panel.

## Overview

BPB Automation helps you find working Cloudflare IPs for your network and automatically updates your BPB Panel configuration via Cloudflare Workers KV API.

The app fetches your BPB Panel's Xray subscription configs, then runs a 3-phase scan to find IPs that actually work as a proxy on your network.

## Key Features

- **Config-based scanning** - Uses your actual BPB Panel Xray configs to test real proxy connectivity
- **3-phase verification** - TCP pre-filter, TLS handshake, and live Xray proxy test
- **Subnet-aware IP selection** - One IP per /24 subnet for maximum routing diversity
- **Bundled Xray-core** - No external installation required; binary is bundled per platform
- Scan from your actual network (mobile ISP, home internet, etc.)
- Automatic BPB Panel settings update via Cloudflare Workers KV API
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

#### Windows
```
Download and extract:
BPB-Automation-Windows-x64.zip
```

### Setup

1. Install the app
2. Open **Configuration** and enter your BPB Panel subscription URL
3. (Optional) Get your Cloudflare credentials — see [Cloudflare Setup Guide](docs/cloudflare-setup.md)
4. Enter credentials in **Settings** (only needed for the auto-update feature)
5. Tap **Start Scan**
6. After scan completes, tap **Update BPB Panel** to apply the results

**Note:** Cloudflare credentials are only required for updating BPB Panel. You can scan and copy IPs without credentials.

## Documentation

- [User Guide](docs/user-guide.md) - Complete usage instructions
- [Cloudflare Setup](docs/cloudflare-setup.md) - How to get credentials
- [Scanner Configuration](docs/scanner-configuration.md) - Scan parameters explained
- [Development Guide](docs/development.md) - For developers
- [Deployment Guide](docs/deployment.md) - Building and distributing

## Requirements

### For Users
- Internet connection
- BPB Panel subscription URL (for scanning)

**For BPB Panel Updates:**
- Cloudflare account with BPB Panel installed
- API token with Workers KV Edit permission
- Account ID and KV Namespace ID

### For Developers
- Flutter SDK (latest stable)
- Platform-specific tools (Android Studio, Xcode, etc.)
- See [Development Guide](docs/development.md)

## Testing

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

The top working IPs are written to your BPB Panel's Workers KV `cleanIPs` field via the Cloudflare API. All other KV settings are preserved.

### Why This Approach

- **Real-world verification**: Phase 2 uses actual Xray proxy connections, not just latency pings — an IP must actually work as a proxy to pass
- **Subnet diversity**: /24 subnet-aware IPv4 selection ensures IPs route through different Cloudflare edge servers, giving better redundancy
- **Network-specific**: Testing happens on your device from your network, so results are optimal for your ISP

## Security & Privacy

- Credentials encrypted with platform keychain (Android Keystore, iOS Keychain, etc.)
- No cloud storage or third-party services
- No analytics or tracking
- Only connects to Cloudflare API and your BPB Panel subscription URL
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
- [x] Multi-platform support
- [x] Config-based 3-phase Xray scanning
- [ ] Scheduled auto-scans
- [ ] Multi-account support
- [ ] Custom IP lists
- [ ] In-app updates

## Version

Current: 4.1.0

See CHANGELOG.md for version history.
