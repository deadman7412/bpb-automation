# BPB Automation

Cross-platform application for automatically scanning and updating clean Cloudflare IPs in BPB Panel.

## Overview

BPB Automation helps you find the fastest Cloudflare IPs for your network and automatically updates your BPB Panel configuration via Cloudflare Workers KV API.

## Key Features

- **Pure Dart IP scanner** - Native implementation, no binary dependencies
- Scan for clean Cloudflare IPs from your actual network
- TCP latency testing + HTTP/HTTPS download speed testing
- Automatic BPB Panel settings update via API
- Cross-platform support: Android, iOS, macOS, Linux, Windows, Web
- Offline-first design (no hosting required)
- No sandboxing issues (works on all platforms including macOS)
- Secure credential storage
- User-friendly interface (no terminal needed)
- Real-time progress tracking with detailed statistics
- Advanced scanner configuration options

## Supported Platforms

- Android (Primary)
- macOS
- Linux
- Windows
- Web (requires VPS backend)
- iOS (coming soon)

## Quick Start

### Installation

Download the appropriate version for your platform:
- Android: `bpb-automation.apk`
- macOS: `bpb-automation.dmg`
- Linux: `bpb-automation.AppImage` or `.deb`
- Windows: `bpb-automation-setup.exe`

### Setup

1. Install the app
2. Run your first scan (no credentials needed for scanning)
3. Get your Cloudflare credentials (see [Cloudflare Setup Guide](docs/cloudflare-setup.md))
4. Enter credentials in app settings
5. Update BPB Panel with clean IPs

**Note:** Cloudflare credentials are only required for updating BPB Panel. You can scan and view clean IPs without credentials.

## Documentation

- [User Guide](docs/user-guide.md) - Complete usage instructions
- [Cloudflare Setup](docs/cloudflare-setup.md) - How to get credentials
- [Scanner Configuration](docs/scanner-configuration.md) - Scanner parameters explained
- [Development Guide](docs/development.md) - For developers
- [Deployment Guide](docs/deployment.md) - Building and distributing

## Requirements

### For Users
- Internet connection

**For Scanning Only:**
- No additional requirements

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
# Run unit tests only (excludes integration tests)
flutter test --exclude-tags=integration
```

### Run Specific Test Suites
```bash
# Run only model tests
flutter test test/models/

# Run only service tests
flutter test test/services/

# Run integration tests (requires network access)
flutter test --tags=integration
```

### Test Categories
- **Unit Tests** - Fast, isolated tests for models and services (338 tests)
- **Integration Tests** - Slow, network-dependent tests against real Cloudflare IPs
  - Tagged with `@Tags(['integration'])`
  - May fail in CI due to rate limiting or network restrictions
  - Should be run manually or in separate CI job with proper network access

**Note:** Integration tests use real network requests to Cloudflare and may be rate-limited (HTTP 429). For reliable CI/CD, always use `--exclude-tags=integration`.

## How It Works

1. Loads Cloudflare IP ranges and expands CIDR notation
2. Tests TCP latency for all IPs concurrently
3. Tests download speed for top performers
4. Calculates quality scores (latency + speed)
5. Updates BPB Panel's Workers KV via Cloudflare API
6. Your proxy connection uses the new clean IPs

**Technical Implementation:**
- Pure Dart - no external binaries or sandboxing issues
- TCP socket connections for latency measurement
- Raw HTTPS with manual HTTP protocol for speed testing
- Configurable concurrency (1-1000 threads)
- Quality-based sorting algorithm

## Why Use This App

- No VPS required - runs on your device
- Tests from your actual network (mobile ISP, WiFi)
- Clean IPs specific to your location and ISP
- Automated updates - no manual CSV editing
- Secure - all data stays local

## Security & Privacy

- Credentials encrypted with platform keychain
- No cloud storage or third-party services
- No analytics or tracking
- Only connects to Cloudflare API
- All network requests user-initiated

## Contributing

Contributions welcome. Please follow the guidelines in [Development Guide](docs/development.md).

## License

To be determined.

## Credits

- [Cloudflare-Clean-IP-Scanner](https://github.com/bia-pain-bache/Cloudflare-Clean-IP-Scanner) - Scanner algorithm inspiration
- [BPB-Worker-Panel](https://github.com/bia-pain-bache/BPB-Worker-Panel) - Panel software
- IP lists sourced from Cloudflare's official IP ranges

## Support

For issues and questions:
- Check [User Guide](docs/user-guide.md)
- Review [Troubleshooting](docs/user-guide.md#troubleshooting)
- See logs in app (Settings > View Logs)

## Roadmap

- [x] Core scanning functionality
- [x] Cloudflare API integration
- [x] Multi-platform support
- [ ] Scheduled auto-scans
- [ ] Multi-account support
- [ ] Custom IP lists
- [ ] Cloud backup (optional)
- [ ] In-app updates

## Version

Current: 1.0.0 (Initial Release)

See CHANGELOG.md for version history.

